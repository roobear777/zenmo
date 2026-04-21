# Design Document: Firebase Integration

## Overview

This design adds Firebase to the Zenmo Flutter web app. The integration has two user-facing surfaces:

1. **Anonymous submission** — when a user completes all 5 fingerprint questions, a "Submit" button appears on `SummaryScreen`. Tapping it writes their answers to Firestore under `events/zenmo_party/fingerprints/{uid}`, accumulating submissions over time.
2. **Admin view** — a discreet lock icon on `InitialLogoScreen` leads through an email/password login gate and a door-code gate to a streaming admin screen that shows all submissions ordered by most recent first.

The app targets Firebase project `zenmobeta`, which is shared with the sibling `color_wallet` app. `firebase_options.dart` already exists in `color_wallet/lib/` and is copied verbatim to `lib/`.

---

## Architecture

```mermaid
graph TD
    subgraph App Startup
        A[main.dart] -->|Firebase.initializeApp| B[Firebase SDK]
        A -->|provide AuthService| C[AuthService]
        C -->|signInAnonymously| D[FirebaseAuth]
    end

    subgraph User Flow
        E[InitialLogoScreen] -->|lock icon tap| F[AdminLoginScreen]
        E -->|Test Questions| G[Question Flow]
        G -->|all 5 complete| H[SummaryScreen]
        H -->|Submit tap| I[FirestoreFingerprintService]
        I -->|arrayUnion write| J[(Firestore\nevents/zenmo_party/fingerprints/{uid})]
    end

    subgraph Admin Flow
        F -->|email+password login| K[AuthService.signInWithEmail]
        K -->|UID whitelisted| L[AdminDoorScreen]
        L -->|correct door code| M[ZenmoAdminScreen]
        M -->|stream| J
    end
```

**Key design decisions:**

- `AuthService` is a thin wrapper around `FirebaseAuth.instance` — it does not extend `ChangeNotifier` because auth state does not need to drive widget rebuilds in this app.
- `FirestoreFingerprintService` is a plain Dart class (not a `ChangeNotifier`) injected via `Provider` as a value. It has no state of its own.
- Firebase initialisation and anonymous sign-in happen in `main()` before `runApp`, with errors caught and swallowed so the app always renders.
- The admin screens are a self-contained subtree under `lib/screens/admin/` and are never reachable from the normal user flow except via the lock icon.

---

## Components and Interfaces

### `AuthService` (`lib/services/auth_service.dart`)

```dart
class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  bool get isWhitelisted {
    final uid = currentUser?.uid;
    return uid == 'OpWxbjKjOuYSLopBew8uHQlMY1F2' ||
           uid == 'qjvsPsCL9uZS6ba3x4cqJPWXaSb2';
  }

  /// Called once at startup. No-ops if already signed in.
  Future<void> ensureAnonymousSignIn() async { ... }

  /// Used by AdminLoginScreen.
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async { ... }
}
```

### `FirestoreFingerprintService` (`lib/services/firestore_fingerprint_service.dart`)

```dart
class FirestoreFingerprintService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Appends a new submission to the user's fingerprint document.
  Future<void> submitFingerprint(FingerprintState state) async { ... }

  /// Streams all fingerprint documents ordered by updatedAt desc.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamAllSubmissions() { ... }

  // Internal helper — public for testability
  Map<String, dynamic> buildSubmission(FingerprintState state) { ... }
}
```

### Admin screens

| File | Responsibility |
|---|---|
| `lib/screens/admin/admin_login_screen.dart` | Email/password form; whitelist check; navigates to door screen on success |
| `lib/screens/admin/admin_door_screen.dart` | Door code entry (`zenmo123`); navigates to admin screen on success |
| `lib/screens/admin/zenmo_admin_screen.dart` | Streams `events/zenmo_party/fingerprints`, expands submissions array, renders cards |

### Modified files

| File | Change |
|---|---|
| `lib/main.dart` | `Firebase.initializeApp`, provide `AuthService` + `FirestoreFingerprintService`, call `ensureAnonymousSignIn` |
| `lib/screens/initial_logo_screen.dart` | Add `Positioned` lock icon in bottom-right via `Stack` |
| `lib/screens/summary_screen.dart` | Add Submit button (conditional on `allQuestionsComplete`), loading/error/success states |
| `pubspec.yaml` | Add `firebase_core`, `firebase_auth`, `cloud_firestore` |
| `color_wallet/firestore.rules` | Add `events/zenmo_party/fingerprints` rules |

---

## Data Models

### Firestore document: `events/zenmo_party/fingerprints/{uid}`

```
{
  uid: string,                    // anonymous UID
  updatedAt: Timestamp,           // server timestamp, updated on every submit
  submissions: [                  // array grows with each submit (arrayUnion)
    {
      submittedAt: Timestamp,
      answers: [
        {
          questionIndex: int,         // 0–4
          questionText: string,       // from kFingerprintQuestions
          colorInts: List<int>,       // ARGB values
          hexValues: List<string>,    // e.g. "#FF5733"
          titles: List<string>,       // swatch titles
          notes: List<string?>,       // null where absent
          swatchTimestamps: List<string>  // ISO-8601 createdAt
        },
        ... (5 total)
      ]
    },
    ...
  ]
}
```

### Dart serialisation (`FirestoreFingerprintService.buildSubmission`)

```dart
Map<String, dynamic> buildSubmission(FingerprintState state) {
  return {
    'submittedAt': FieldValue.serverTimestamp(),
    'answers': List.generate(kFingerprintTotalQuestions, (i) {
      final answer = state.getAnswer(i);
      return {
        'questionIndex': i,
        'questionText': kFingerprintQuestions[i],
        'colorInts': answer.colors,
        'hexValues': answer.hexes,
        'titles': answer.swatches.map((s) => s.title).toList(),
        'notes': answer.swatches.map((s) => s.note).toList(),
        'swatchTimestamps': answer.swatches
            .map((s) => s.createdAt.toIso8601String())
            .toList(),
      };
    }),
  };
}
```

The top-level document write uses `set` with `merge: true` plus `FieldValue.arrayUnion([submission])` for the `submissions` field, and `FieldValue.serverTimestamp()` for `updatedAt` and `uid` for the `uid` field.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: All-complete state shows Submit

*For any* `FingerprintState` where all 5 answers each have at least one swatch with a non-empty title, `allQuestionsComplete` SHALL return `true`.

**Validates: Requirements 2.1**

---

### Property 2: Incomplete state hides Submit

*For any* `FingerprintState` where at least one of the 5 answers has no swatches with a non-empty title, `allQuestionsComplete` SHALL return `false`.

**Validates: Requirements 2.2**

---

### Property 3: Submission document is correctly shaped

*For any* valid `FingerprintState` (all 5 answers complete), `FirestoreFingerprintService.buildSubmission(state)` SHALL return a map containing:
- a `submittedAt` field
- an `answers` list of exactly 5 elements
- each answer element containing `questionIndex`, `questionText`, `colorInts`, `hexValues`, `titles`, `notes`, and `swatchTimestamps`
- `colorInts`, `hexValues`, `titles`, `notes`, and `swatchTimestamps` all having the same length as the number of swatches in the corresponding answer

**Validates: Requirements 2.5, 2.6, 2.7**

---

### Property 4: Submissions accumulate (arrayUnion semantics)

*For any* sequence of N valid submissions from the same anonymous UID, after all N writes complete, the `submissions` array on the Firestore document SHALL contain exactly N elements, one per submit call, in the order they were written.

**Validates: Requirements 2.4**

---

### Property 5: Whitelist check is exact

*For any* UID string, `AuthService.isWhitelisted` SHALL return `true` if and only if the UID is exactly `"OpWxbjKjOuYSLopBew8uHQlMY1F2"` or `"qjvsPsCL9uZS6ba3x4cqJPWXaSb2"`.

**Validates: Requirements 4.5, 4.6**

---

### Property 6: Admin stream is ordered by updatedAt descending

*For any* non-empty set of fingerprint documents with distinct `updatedAt` timestamps, the stream returned by `FirestoreFingerprintService.streamAllSubmissions()` SHALL emit documents in descending `updatedAt` order.

**Validates: Requirements 6.1**

---

### Property 7: Submission card displays all required fields

*For any* submission map (with valid `submittedAt`, `uid`, and 5 answer objects), the rendered submission card widget SHALL display the truncated UID, the formatted timestamp, and for each of the 5 answers: the question text, and for each swatch: a color square, the swatch title, the hex value, and the note (when present).

**Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5**

---

## Error Handling

| Scenario | Handling |
|---|---|
| `Firebase.initializeApp` throws | Caught in `main()`; error logged via `debugPrint`; `runApp` proceeds normally |
| `signInAnonymously` throws | Caught in `AuthService.ensureAnonymousSignIn()`; error logged; app continues with `currentUser == null` |
| `submitFingerprint` throws | `SummaryScreen` catches the `Future` error; shows error snackbar/message; re-enables Submit button |
| Admin email/password sign-in fails | `AdminLoginScreen` catches `FirebaseAuthException`; displays `e.message` to user |
| Incorrect door code | `AdminDoorScreen` shows "Incorrect code" inline; does not navigate |
| Non-whitelisted UID after login | `AdminLoginScreen` shows "Not authorized"; does not navigate |
| Firestore stream error | `ZenmoAdminScreen` `StreamBuilder` error branch displays `snap.error.toString()` |
| No submissions in collection | `ZenmoAdminScreen` shows "No submissions yet" |

All Firebase errors are treated as non-fatal. The app degrades gracefully to local-only operation when Firebase is unavailable.

---

## Testing Strategy

### Unit tests (example-based)

- `AuthService.ensureAnonymousSignIn()` calls `signInAnonymously` when no current user (mock `FirebaseAuth`)
- `AuthService.ensureAnonymousSignIn()` skips sign-in when current user exists
- `AdminLoginScreen` shows validation error when email or password is empty
- `AdminLoginScreen` shows Firebase error message on failed sign-in
- `AdminDoorScreen` shows "Incorrect code" for wrong input
- `AdminDoorScreen` navigates to `ZenmoAdminScreen` for correct code
- `SummaryScreen` shows confirmation message after successful submit
- `SummaryScreen` shows error message and re-enables button after failed submit
- `SummaryScreen` disables button and shows loading indicator during submit

### Property-based tests

Using [`dart_test`](https://pub.dev/packages/test) with [`fast_check`](https://pub.dev/packages/fast_check) (or equivalent Dart PBT library). Each property test runs a minimum of 100 iterations.

| Property | Generator | Assertion |
|---|---|---|
| P1: allQuestionsComplete true | Generate 5 valid `FingerprintAnswer` objects (non-empty title, ≥1 swatch) | `allQuestionsComplete == true` |
| P2: allQuestionsComplete false | Generate FingerprintState with 0–4 valid answers, rest empty | `allQuestionsComplete == false` |
| P3: buildSubmission shape | Generate valid `FingerprintState` with random swatches | All required fields present; list lengths match swatch counts |
| P4: submissions accumulate | Generate N (1–5) random submissions, write to Firestore emulator | `submissions.length == N` |
| P5: whitelist exactness | Generate random UID strings (including the two whitelisted UIDs) | `isWhitelisted` true iff UID matches one of the two constants |
| P6: stream ordering | Generate random documents with random timestamps, insert to emulator | Emitted docs in descending `updatedAt` order |
| P7: card renders all fields | Generate random submission map | Card widget tree contains UID prefix, timestamp, all 5 question texts, all swatch details |

Tag format for each property test:
```dart
// Feature: firebase-integration, Property N: <property_text>
```

### Integration tests (Firebase emulator)

- Anonymous user can create their own fingerprint document (rules allow)
- Anonymous user cannot read another user's document (rules deny)
- Anonymous user cannot delete their document (rules deny)
- Whitelisted UID can read all documents in the collection
- Non-whitelisted authenticated user cannot read the collection
- `updatedAt` and `uid` fields are set correctly on the top-level document after submit

### Smoke tests

- `Firebase.apps` is non-empty after app startup (Firebase initialised)
- `firebase_core`, `firebase_auth`, `cloud_firestore` are declared in `pubspec.yaml`
