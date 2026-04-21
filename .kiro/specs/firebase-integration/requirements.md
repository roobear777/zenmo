# Requirements Document

## Introduction

This feature adds Firebase integration to the Zenmo Flutter web app. Anonymous users who complete all 5 fingerprint questions can submit their party fingerprint to Firestore. Ru and Frankie can access a password-protected admin screen inside the app to view all submissions ordered by most recent first.

The app is already deployed to Firebase Hosting on the `zenmobeta` project and `firebase_options.dart` already exists in the sibling `color_wallet/lib/` project. Firebase Auth, Firestore, and the existing Firestore security rules file (`color_wallet/firestore.rules`) are all part of the same `zenmobeta` project.

## Glossary

- **App**: The Zenmo Flutter web application deployed at `zenmobeta.web.app`
- **Auth_Service**: The component responsible for Firebase Authentication operations (anonymous sign-in and email/password sign-in)
- **Firestore_Service**: The component responsible for reading and writing fingerprint submission documents in Firestore
- **FingerprintState**: The existing ChangeNotifier that holds the 5 `FingerprintAnswer` objects and `currentQuestionIndex`
- **FingerprintAnswer**: An existing model containing `title`, `colors` (List<int>), `hexes` (List<String>), and `swatches` (List<ColorSwatch>)
- **ColorSwatch**: An existing model containing `title`, `color` (Color), `note` (String?), `createdAt` (DateTime), and `creator` (String)
- **Submission**: A single snapshot of a user's completed fingerprint, stored as an element in the `submissions` array on a Firestore document
- **Fingerprint_Document**: The Firestore document at `events/zenmo_party/fingerprints/{uid}` that accumulates all submissions from one anonymous user
- **SummaryScreen**: The existing screen that displays all 5 completed answers; the Submit button is added here
- **InitialLogoScreen**: The existing entry screen where the admin lock icon is placed
- **Admin_Screen**: The new screen accessible only to whitelisted UIDs that displays all fingerprint submissions
- **Whitelisted_UID**: One of the two authorised admin UIDs: `OpWxbjKjOuYSLopBew8uHQlMY1F2` (Ru) or `qjvsPsCL9uZS6ba3x4cqJPWXaSb2` (Frankie)
- **Door_Code**: The client-side access code `zenmo123` required after email/password login before the Admin_Screen is shown
- **Anonymous_User**: A user signed in via Firebase Anonymous Authentication, identified by a stable UID for the duration of the browser session

---

## Requirements

### Requirement 1: Firebase Initialisation and Anonymous Sign-In

**User Story:** As an anonymous user, I want the app to silently authenticate me with Firebase on launch, so that I have a stable identity for submitting my fingerprint without creating an account.

#### Acceptance Criteria

1. THE App SHALL initialise Firebase using the existing `firebase_options.dart` configuration before rendering any screen.
2. WHEN the App starts and no Firebase Auth session exists, THE Auth_Service SHALL sign the user in anonymously without displaying any authentication UI.
3. WHEN the App starts and a Firebase Auth session already exists, THE Auth_Service SHALL reuse the existing session without signing in again.
4. IF Firebase initialisation fails, THEN THE App SHALL log the error and continue to render the UI using local state only.
5. IF anonymous sign-in fails, THEN THE App SHALL log the error and continue to render the UI using local state only.
6. THE App SHALL continue to load and save state via the existing `PersistenceService` (SharedPreferences) regardless of Firebase Auth status.

---

### Requirement 2: Submit Fingerprint to Firestore

**User Story:** As an anonymous user who has completed all 5 questions, I want to submit my party fingerprint, so that Ru and Frankie can see my responses.

#### Acceptance Criteria

1. WHEN all 5 `FingerprintAnswer` objects in `FingerprintState` are valid (non-empty title and at least one color), THE SummaryScreen SHALL display a "Submit" button.
2. WHILE fewer than 5 questions are complete, THE SummaryScreen SHALL NOT display the Submit button.
3. WHEN the user taps the Submit button and the Auth_Service has a valid anonymous UID, THE Firestore_Service SHALL write a new submission object to the `submissions` array on the Firestore_Document at `events/zenmo_party/fingerprints/{uid}`.
4. THE Firestore_Service SHALL use `arrayUnion` (or equivalent append semantics) so that each tap of Submit adds a new submission without overwriting previous submissions from the same user.
5. WHEN writing a submission, THE Firestore_Service SHALL include the following fields in each submission object:
   - `submittedAt`: server timestamp
   - `answers`: an array of 5 objects, each containing:
     - `questionIndex`: integer (0–4)
     - `questionText`: the question string from `kFingerprintQuestions`
     - `colorInts`: List<int> of ARGB color values
     - `hexValues`: List<String> of hex color strings (e.g. `#FF5733`)
     - `titles`: List<String> of swatch titles
     - `notes`: List<String?> of swatch notes (null where absent)
     - `swatchTimestamps`: List<String> of swatch `createdAt` ISO-8601 strings
6. WHEN writing a submission, THE Firestore_Service SHALL also set a top-level `updatedAt` field on the Fingerprint_Document to the server timestamp.
7. WHEN writing a submission, THE Firestore_Service SHALL set a top-level `uid` field on the Fingerprint_Document equal to the anonymous user's UID.
8. WHEN the Firestore write succeeds, THE SummaryScreen SHALL display a confirmation message to the user (e.g. "Fingerprint submitted!").
9. IF the Firestore write fails, THEN THE SummaryScreen SHALL display an error message and allow the user to retry.
10. WHILE a Firestore write is in progress, THE Submit button SHALL be disabled and display a loading indicator.

---

### Requirement 3: Admin Entry Point on InitialLogoScreen

**User Story:** As an admin (Ru or Frankie), I want a discreet entry point on the home screen, so that I can navigate to the admin login without it being obvious to regular users.

#### Acceptance Criteria

1. THE InitialLogoScreen SHALL display a small lock icon in the bottom-right corner of the screen.
2. WHEN the user taps the lock icon, THE App SHALL navigate to the Admin_Login_Screen.

---

### Requirement 4: Admin Email/Password Login

**User Story:** As an admin, I want to log in with my email and password, so that my identity can be verified before I access submission data.

#### Acceptance Criteria

1. THE Admin_Login_Screen SHALL display an email field, a password field, and a "Login" button.
2. WHEN the user taps Login with valid credentials, THE Auth_Service SHALL sign in using Firebase email/password authentication.
3. IF the email or password is empty when Login is tapped, THEN THE Admin_Login_Screen SHALL display a validation message and SHALL NOT attempt sign-in.
4. IF Firebase email/password sign-in fails, THEN THE Admin_Login_Screen SHALL display the error message returned by Firebase and SHALL NOT proceed.
5. WHEN Firebase sign-in succeeds and the authenticated UID is a Whitelisted_UID, THE App SHALL navigate to the Admin_Door_Screen.
6. WHEN Firebase sign-in succeeds and the authenticated UID is NOT a Whitelisted_UID, THE Admin_Login_Screen SHALL display "Not authorized" and SHALL NOT navigate further.
7. WHILE a sign-in request is in progress, THE Login button SHALL be disabled and display a loading indicator.

---

### Requirement 5: Admin Door Code Gate

**User Story:** As an admin, I want to enter a door code after logging in, so that there is a second layer of protection before viewing submissions.

#### Acceptance Criteria

1. THE Admin_Door_Screen SHALL display a text field for the door code and a "Continue" button.
2. WHEN the user enters the correct Door_Code (`zenmo123`) and taps Continue, THE App SHALL navigate to the Admin_Screen.
3. IF the entered code does not match the Door_Code, THEN THE Admin_Door_Screen SHALL display "Incorrect code" and SHALL NOT navigate to the Admin_Screen.
4. THE Admin_Door_Screen SHALL obscure the door code input by default and provide a toggle to reveal it.

---

### Requirement 6: Admin Screen — Submission List

**User Story:** As an admin, I want to see all fingerprint submissions from all anonymous users ordered by most recent first, so that I can review party responses in real time.

#### Acceptance Criteria

1. THE Admin_Screen SHALL stream all documents from the `events/zenmo_party/fingerprints` Firestore collection ordered by `updatedAt` descending.
2. WHEN the Firestore stream emits new data, THE Admin_Screen SHALL update the displayed list without requiring a manual refresh.
3. WHEN the collection is empty, THE Admin_Screen SHALL display a "No submissions yet" message.
4. IF the Firestore stream returns an error, THEN THE Admin_Screen SHALL display the error message.
5. THE Admin_Screen SHALL expand each Fingerprint_Document into one card per submission in the `submissions` array, ordered so that the most recent submission appears first.

---

### Requirement 7: Admin Screen — Submission Card Content

**User Story:** As an admin, I want each submission card to show the user ID, timestamp, and full color details for all 5 questions, so that I can understand each person's fingerprint at a glance.

#### Acceptance Criteria

1. THE Admin_Screen SHALL display the anonymous user UID on each submission card, truncated to 12 characters with an ellipsis if longer.
2. THE Admin_Screen SHALL display the `submittedAt` timestamp on each submission card in a human-readable format (e.g. `dd MMM yyyy HH:mm`).
3. THE Admin_Screen SHALL display all 5 question answers on each submission card.
4. FOR each answer, THE Admin_Screen SHALL display the question text and all color swatches chosen by the user.
5. FOR each color swatch, THE Admin_Screen SHALL display a color square (minimum 18×18 logical pixels) filled with the swatch color, the swatch title, the hex value, and the note (if present).

---

### Requirement 8: Firestore Security Rules

**User Story:** As a system operator, I want Firestore security rules that allow anonymous users to write only their own document and admins to read all documents, so that submission data is protected.

#### Acceptance Criteria

1. THE Firestore_Rules SHALL allow an authenticated user to create the document at `events/zenmo_party/fingerprints/{uid}` only when `request.auth.uid == uid`.
2. THE Firestore_Rules SHALL allow an authenticated user to update the document at `events/zenmo_party/fingerprints/{uid}` only when `request.auth.uid == uid`.
3. THE Firestore_Rules SHALL deny read access to `events/zenmo_party/fingerprints/{uid}` for any user whose UID is not a Whitelisted_UID.
4. THE Firestore_Rules SHALL allow read access to all documents in `events/zenmo_party/fingerprints` for any Whitelisted_UID.
5. THE Firestore_Rules SHALL be added to the existing `color_wallet/firestore.rules` file without removing or modifying any existing rules.
6. THE Firestore_Rules SHALL deny delete access to all documents in `events/zenmo_party/fingerprints` for all users.

---

### Requirement 9: pubspec Dependencies

**User Story:** As a developer, I want the required Firebase packages declared in `pubspec.yaml`, so that the app compiles with Firebase support.

#### Acceptance Criteria

1. THE App SHALL declare `firebase_core`, `firebase_auth`, and `cloud_firestore` as dependencies in `pubspec.yaml` with versions compatible with the existing Flutter SDK constraint (`^3.9.2`).
2. THE App SHALL include `firebase_options.dart` (copied from `color_wallet/lib/`) in `lib/` so that `Firebase.initializeApp` can reference the correct project configuration.
