# Next Tasks for Zenmo Development

**Last Updated**: March 14, 2026  
**Priority Order**: Follow this sequence for best results

---

## Phase 1: Testing & Validation (1-2 days)

### Task 1.1: Run Full Test Suite
**Status**: Not started  
**Effort**: 30 minutes

```bash
flutter test
```

**What to check:**
- All existing tests pass
- No new errors introduced by refactoring
- Coverage is adequate

**Files involved:**
- `test/phone_frame_compatibility_test.dart`
- `test/state/fingerprint_state_persistence_test.dart`

**Success criteria:**
- ✅ All tests pass
- ✅ No compilation errors
- ✅ No warnings

---

### Task 1.2: Test Web Deployment
**Status**: Not started  
**Effort**: 30 minutes

**What to test:**
1. Visit https://zenmobeta.web.app in private browser window
2. Test landing page loads correctly
3. Click "Try Zenmo 2.0" - should load v2 app
4. Click "Try Zenmo 1.0" - should load v1 app
5. Test complete fingerprint flow on v2
6. Verify state persists after refresh

**Success criteria:**
- ✅ Landing page displays correctly
- ✅ Both versions load without errors
- ✅ Fingerprint flow works end-to-end
- ✅ State persists across page refresh

---

### Task 1.3: Test on iOS Simulator
**Status**: Not started  
**Effort**: 1 hour

```bash
flutter run -d "iPhone 15"
```

**What to test:**
1. App launches without errors
2. All screens render correctly
3. Color picker works smoothly
4. State persists after app restart
5. No platform-specific errors

**Success criteria:**
- ✅ App runs on iOS simulator
- ✅ No crashes or errors
- ✅ All features work as expected

---

## Phase 2: iOS-Specific Implementation (2-3 days)

### Task 2.1: Create iOS Persistence Service
**Status**: Not started  
**Effort**: 2-3 hours

**What to do:**
1. Create `lib/services/ios_persistence_service.dart`
2. Implement iOS Keychain storage using `flutter_secure_storage` package
3. Match `PersistenceService` interface for compatibility
4. Add error handling for iOS-specific issues

**Files to create:**
- `lib/services/ios_persistence_service.dart`

**Files to modify:**
- `pubspec.yaml` - Add `flutter_secure_storage` dependency

**Code structure:**
```dart
class IOSPersistenceService implements PersistenceService {
  // Use Keychain for sensitive data
  // Fallback to UserDefaults for non-sensitive data
}
```

**Success criteria:**
- ✅ Service implements PersistenceService interface
- ✅ Data persists in iOS Keychain
- ✅ Error handling for iOS-specific issues
- ✅ Tests pass on iOS simulator

---

### Task 2.2: Create Platform-Aware Service Factory
**Status**: Not started  
**Effort**: 1-2 hours

**What to do:**
1. Create `lib/services/service_factory.dart`
2. Implement factory that returns correct service based on platform
3. Update `main.dart` to use factory
4. Update `FingerprintState` to accept injected service

**Files to create:**
- `lib/services/service_factory.dart`

**Files to modify:**
- `lib/main.dart` - Use factory to inject correct service
- `lib/state/fingerprint_state.dart` - Already supports injection

**Code structure:**
```dart
class ServiceFactory {
  static PersistenceService createPersistenceService() {
    if (kIsWeb) {
      return PersistenceService(); // SharedPreferences
    } else if (Platform.isIOS) {
      return IOSPersistenceService(); // Keychain
    } else if (Platform.isAndroid) {
      return AndroidPersistenceService(); // EncryptedSharedPreferences
    }
    return PersistenceService(); // Fallback
  }
}
```

**Success criteria:**
- ✅ Factory correctly identifies platform
- ✅ Correct service injected for each platform
- ✅ Tests pass on web, iOS simulator, and Android

---

### Task 2.3: Add Android Persistence Service (Optional)
**Status**: Not started  
**Effort**: 2-3 hours

**What to do:**
1. Create `lib/services/android_persistence_service.dart`
2. Use `flutter_secure_storage` for encrypted storage
3. Match `PersistenceService` interface
4. Add error handling for Android-specific issues

**Files to create:**
- `lib/services/android_persistence_service.dart`

**Success criteria:**
- ✅ Service implements PersistenceService interface
- ✅ Data persists in encrypted storage
- ✅ Tests pass on Android emulator

---

## Phase 3: Firebase Integration (3-5 days)

### Task 3.1: Create Firebase Service
**Status**: Not started  
**Effort**: 3-4 hours

**What to do:**
1. Create `lib/services/firebase_service.dart`
2. Implement Firestore sync for fingerprint data
3. Implement user authentication service
4. Add error handling and offline support

**Files to create:**
- `lib/services/firebase_service.dart`

**Files to modify:**
- `pubspec.yaml` - Add Firebase dependencies
- `lib/services/services.dart` - Export new service

**Dependencies to add:**
```yaml
firebase_core: ^latest
cloud_firestore: ^latest
firebase_auth: ^latest
```

**Code structure:**
```dart
class FirebaseService {
  Future<void> syncFingerprint(String userId, FingerprintState state) async {
    // Save to Firestore
  }
  
  Future<FingerprintState?> loadFingerprint(String userId) async {
    // Load from Firestore
  }
}
```

**Success criteria:**
- ✅ Firebase initialized correctly
- ✅ Data syncs to Firestore
- ✅ Data loads from Firestore
- ✅ Offline support works

---

### Task 3.2: Create Authentication Service
**Status**: Not started  
**Effort**: 2-3 hours

**What to do:**
1. Create `lib/services/auth_service.dart`
2. Implement email/password authentication
3. Implement GitHub OAuth (optional)
4. Add user session management

**Files to create:**
- `lib/services/auth_service.dart`

**Code structure:**
```dart
class AuthService {
  Future<User?> signInWithEmail(String email, String password) async {
    // Firebase Auth
  }
  
  Future<User?> signInWithGitHub() async {
    // GitHub OAuth
  }
  
  Future<void> signOut() async {
    // Sign out
  }
}
```

**Success criteria:**
- ✅ Email/password auth works
- ✅ User session persists
- ✅ Sign out clears session

---

## Phase 4: TestFlight Preparation (2-3 days)

### Task 4.1: Update App Icons & Branding
**Status**: Not started  
**Effort**: 1-2 hours

**What to do:**
1. Create app icons for iOS (1024x1024 primary)
2. Update `ios/Runner/Assets.xcassets`
3. Update app name in `ios/Runner/Info.plist`
4. Add app description for TestFlight

**Files to modify:**
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- `ios/Runner/Info.plist`
- `pubspec.yaml` - Update version

**Success criteria:**
- ✅ App icon displays correctly
- ✅ App name is correct
- ✅ No build warnings

---

### Task 4.2: Configure iOS Build Settings
**Status**: Not started  
**Effort**: 1-2 hours

**What to do:**
1. Update iOS deployment target (minimum iOS 12.0)
2. Configure code signing
3. Set up provisioning profiles
4. Update build version and number

**Files to modify:**
- `ios/Podfile`
- `ios/Runner.xcodeproj/project.pbxproj`
- `pubspec.yaml` - Update version

**Success criteria:**
- ✅ iOS deployment target set correctly
- ✅ Code signing configured
- ✅ Build succeeds without warnings

---

### Task 4.3: Create TestFlight Build
**Status**: Not started  
**Effort**: 2-3 hours

**What to do:**
1. Build iOS app for release:
```bash
flutter build ios --release
```

2. Open in Xcode:
```bash
open ios/Runner.xcworkspace
```

3. Archive and upload to TestFlight
4. Add beta testers
5. Create release notes

**Success criteria:**
- ✅ Build succeeds
- ✅ Archive uploads to TestFlight
- ✅ Beta testers can download
- ✅ App runs on physical device

---

## Phase 5: Testing & Refinement (1-2 days)

### Task 5.1: Beta Testing on Physical Device
**Status**: Not started  
**Effort**: 2-3 hours

**What to test:**
1. Download from TestFlight on physical iPhone
2. Test complete fingerprint flow
3. Test state persistence
4. Test all screens and interactions
5. Check for crashes or errors
6. Verify performance

**Success criteria:**
- ✅ App runs smoothly on device
- ✅ No crashes
- ✅ All features work correctly
- ✅ Performance is acceptable

---

### Task 5.2: Gather Feedback & Fix Issues
**Status**: Not started  
**Effort**: Variable

**What to do:**
1. Collect feedback from beta testers
2. Prioritize issues
3. Fix critical bugs
4. Make UX improvements
5. Re-test and re-deploy

**Success criteria:**
- ✅ All critical bugs fixed
- ✅ UX improvements implemented
- ✅ Beta testers satisfied

---

## Phase 6: App Store Submission (1 day)

### Task 6.1: Prepare App Store Listing
**Status**: Not started  
**Effort**: 2-3 hours

**What to do:**
1. Create app description
2. Write release notes
3. Create screenshots for App Store
4. Set up pricing and availability
5. Configure app categories and keywords

**Success criteria:**
- ✅ App Store listing complete
- ✅ Screenshots look professional
- ✅ Description is clear and compelling

---

### Task 6.2: Submit to App Store
**Status**: Not started  
**Effort**: 1-2 hours

**What to do:**
1. Build final release version
2. Upload to App Store Connect
3. Fill out review information
4. Submit for review
5. Monitor review status

**Success criteria:**
- ✅ App submitted for review
- ✅ Review status tracked
- ✅ Ready for approval

---

## Quick Reference: Priority Order

**Week 1 (Testing & Validation):**
1. Run full test suite
2. Test web deployment
3. Test on iOS simulator

**Week 2 (iOS Implementation):**
4. Create iOS persistence service
5. Create platform-aware factory
6. Add Android persistence (optional)

**Week 3 (Firebase):**
7. Create Firebase service
8. Create authentication service

**Week 4 (TestFlight):**
9. Update app icons & branding
10. Configure iOS build settings
11. Create TestFlight build

**Week 5 (Testing & Refinement):**
12. Beta testing on physical device
13. Gather feedback & fix issues

**Week 6 (App Store):**
14. Prepare App Store listing
15. Submit to App Store

---

## Estimated Timeline

- **Phase 1**: 1-2 days
- **Phase 2**: 2-3 days
- **Phase 3**: 3-5 days
- **Phase 4**: 2-3 days
- **Phase 5**: 1-2 days
- **Phase 6**: 1 day

**Total**: 10-16 days (2-3 weeks)

---

## Dependencies to Add

```yaml
# iOS/Android Persistence
flutter_secure_storage: ^9.0.0

# Firebase
firebase_core: ^2.24.0
cloud_firestore: ^4.13.0
firebase_auth: ^4.10.0

# Platform detection
platform: ^3.1.0
```

---

## Important Notes

1. **Test after each phase** - Don't skip testing
2. **Commit frequently** - Use meaningful commit messages
3. **Keep documentation updated** - Update README as you go
4. **Ask for help** - Don't get stuck, reach out to Ru
5. **Follow the order** - Each phase builds on the previous one

---

## Success Criteria for Full Release

- ✅ All tests pass
- ✅ App works on iOS simulator and physical device
- ✅ Firebase integration complete
- ✅ Authentication working
- ✅ State persists correctly
- ✅ No crashes or critical bugs
- ✅ Performance acceptable
- ✅ App Store submission approved

---

**Ready to start?** Begin with Phase 1, Task 1.1!
