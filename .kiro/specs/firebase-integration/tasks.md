# Implementation Plan: Firebase Integration

## Overview

Add Firebase to the Zenmo Flutter web app: anonymous sign-in at startup, a Submit button on `SummaryScreen` that writes to Firestore, and a discreet admin flow (lock icon → email/password login → door code → streaming admin screen). Firestore security rules are added to the existing `color_wallet/firestore.rules` file.

## Tasks

- [x] 1. Add Firebase dependencies and copy `firebase_options.dart`
  - Add `firebase_core`, `firebase_auth`, and `cloud_firestore` to `pubspec.yaml` under `dependencies`
  - Copy `color_wallet/lib/firebase_options.dart` verbatim to `lib/firebase_options.dart`
  - _Requirements: 9.1, 9.2_

- [x] 2. Implement `AuthService`
  - [x] 2.1 Create `lib/services/auth_service.dart` with `AuthService` class
    - Implement `currentUser` getter wrapping `FirebaseAuth.instance.currentUser`
    - Implement `isWhitelisted` getter checking UIDs `OpWxbjKjOuYSLopBew8uHQlMY1F2` and `qjvsPsCL9uZS6ba3x4cqJPWXaSb2`
    - Implement `ensureAnonymousSignIn()`: no-op if `currentUser != null`, else calls `signInAnonymously()`, catches and logs errors
    - Implement `signInWithEmailAndPassword(email, password)` delegating to `FirebaseAuth.instance`
    - _Requirements: 1.2, 1.3, 1.5, 4.2, 4.5, 4.6_

  - [ ]* 2.2 Write property test for `isWhitelisted` exactness
    - **Property 5: Whitelist check is exact**
    - **Validates: Requirements 4.5, 4.6**
    - Generate random UID strings (including the two whitelisted UIDs); assert `isWhitelisted` is true iff UID matches one of the two constants

- [x] 3. Implement `FirestoreFingerprintService`
  - [x] 3.1 Create `lib/services/firestore_fingerprint_service.dart`
    - Implement `buildSubmission(FingerprintState state)` returning a map with `submittedAt` (FieldValue.serverTimestamp) and `answers` list of 5 objects each containing `questionIndex`, `questionText`, `colorInts`, `hexValues`, `titles`, `notes`, `swatchTimestamps`
    - Implement `submitFingerprint(FingerprintState state)`: calls `buildSubmission`, then uses `set` with `merge: true` + `FieldValue.arrayUnion([submission])` for `submissions`, `FieldValue.serverTimestamp()` for `updatedAt`, and the user's UID for `uid` on the document at `events/zenmo_party/fingerprints/{uid}`
    - Implement `streamAllSubmissions()` returning a stream of the collection ordered by `updatedAt` descending
    - _Requirements: 2.3, 2.4, 2.5, 2.6, 2.7, 6.1_

  - [ ]* 3.2 Write property test for `buildSubmission` shape correctness
    - **Property 3: Submission document is correctly shaped**
    - **Validates: Requirements 2.5, 2.6, 2.7**
    - Generate valid `FingerprintState` with random swatches; assert returned map has `submittedAt`, `answers` list of exactly 5 elements, each with all required keys, and list lengths matching swatch counts

- [x] 4. Wire Firebase into `main.dart`
  - Update `main()` to be `async`, call `WidgetsFlutterBinding.ensureInitialized()`, then `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` wrapped in try/catch (log error, continue)
  - Instantiate `AuthService` and call `ensureAnonymousSignIn()` (errors caught and swallowed)
  - Wrap the widget tree with `MultiProvider` providing `AuthService` via `Provider<AuthService>.value` and `FirestoreFingerprintService` via `Provider<FirestoreFingerprintService>.value`, alongside the existing `ChangeNotifierProvider<FingerprintState>`
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [x] 5. Add Submit button to `SummaryScreen`
  - [x] 5.1 Add submit state management to `SummaryScreen`
    - Convert `SummaryScreen` to `StatefulWidget`
    - Add `_isSubmitting` and `_submitError` and `_submitSuccess` local state fields
    - _Requirements: 2.10_

  - [x] 5.2 Render Submit button conditionally and handle submission
    - Read `fingerprintState.allQuestionsComplete` from `Consumer<FingerprintState>`
    - When `allQuestionsComplete` is true, show a "Submit" button above the existing "Done" button
    - While `_isSubmitting` is true, disable the button and show a `CircularProgressIndicator` in place of the label
    - On tap, call `context.read<FirestoreFingerprintService>().submitFingerprint(fingerprintState)`, set `_isSubmitting = true` before and `false` after
    - On success, set `_submitSuccess = true` and show a confirmation message (e.g. "Fingerprint submitted!")
    - On error, set `_submitError` to the error string and show an error message; re-enable the button
    - _Requirements: 2.1, 2.2, 2.8, 2.9, 2.10_

  - [ ]* 5.3 Write property tests for `allQuestionsComplete`
    - **Property 1: All-complete state shows Submit**
    - **Validates: Requirements 2.1**
    - Generate 5 valid `FingerprintAnswer` objects (non-empty title, ≥1 swatch); assert `allQuestionsComplete == true`
    - **Property 2: Incomplete state hides Submit**
    - **Validates: Requirements 2.2**
    - Generate `FingerprintState` with 0–4 valid answers, rest empty; assert `allQuestionsComplete == false`

- [x] 6. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Add lock icon to `InitialLogoScreen`
  - Wrap the existing `Padding` body in a `Stack`
  - Add a `Positioned(bottom: 16, right: 16, ...)` child containing an `IconButton` with `Icons.lock_outline` that navigates to `AdminLoginScreen`
  - _Requirements: 3.1, 3.2_

- [x] 8. Implement admin screens
  - [x] 8.1 Create `lib/screens/admin/admin_login_screen.dart`
    - Email `TextField`, password `TextField` (obscured), and "Login" `ElevatedButton`
    - Validate that neither field is empty before attempting sign-in; show inline validation message if empty
    - On tap, call `context.read<AuthService>().signInWithEmailAndPassword(email, password)` inside try/catch
    - While in-flight, disable button and show loading indicator
    - On `FirebaseAuthException`, display `e.message` inline
    - After successful sign-in, check `context.read<AuthService>().isWhitelisted`; if true navigate to `AdminDoorScreen`, else show "Not authorized" inline
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_

  - [x] 8.2 Create `lib/screens/admin/admin_door_screen.dart`
    - Door code `TextField` (obscured by default) with a visibility toggle `IconButton`
    - "Continue" `ElevatedButton`
    - On tap, compare trimmed input to `'zenmo123'`; if match navigate to `ZenmoAdminScreen`, else show "Incorrect code" inline
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 8.3 Create `lib/screens/admin/zenmo_admin_screen.dart`
    - Use `StreamBuilder` on `context.read<FirestoreFingerprintService>().streamAllSubmissions()`
    - Show `CircularProgressIndicator` while waiting
    - Show error string if `snap.hasError`
    - Show "No submissions yet" if collection is empty
    - For each document, expand the `submissions` array (most recent first) and render a submission card per entry
    - Each card shows: UID truncated to 12 chars + ellipsis, `submittedAt` formatted with `DateFormat('dd MMM yyyy HH:mm')`, and for each of the 5 answers: question text and per-swatch row with a 18×18 color `Container`, swatch title, hex value, and note (if non-null)
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 7.1, 7.2, 7.3, 7.4, 7.5_

- [x] 9. Add Firestore security rules
  - Open `color_wallet/firestore.rules` and append a new `match /events/zenmo_party/fingerprints/{uid}` block
  - Allow `create` and `update` only when `request.auth != null && request.auth.uid == uid`
  - Allow `read` only when `request.auth.uid == 'OpWxbjKjOuYSLopBew8uHQlMY1F2' || request.auth.uid == 'qjvsPsCL9uZS6ba3x4cqJPWXaSb2'`
  - Deny `delete` for all users (no delete rule)
  - Do not modify any existing rules
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

- [x] 10. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- `AuthService` and `FirestoreFingerprintService` are plain Dart classes (not `ChangeNotifier`), provided via `Provider.value`
- Firebase init and anon sign-in happen in `main()` before `runApp`; errors are caught and swallowed so the app always renders
- Property tests use the existing `test` package; add `fast_check` (or equivalent) to `dev_dependencies` if not present
- The `intl` package is already in `pubspec.yaml` — use `DateFormat` for timestamp formatting in the admin screen
