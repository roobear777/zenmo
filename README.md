# Zenmo

A Flutter app for creating party fingerprints through color selection. Users answer 5 questions by picking colors that represent their feelings/memories.

**Live:** https://zenmobeta.web.app  
**GitHub:** https://github.com/roobear777/zenmo

---

## What's been built

### Core app
- 5-question fingerprint flow with color selection per question
- Animated splash screen, progress indicators, locked question states
- Anonymous feedback survey integration
- Firebase Hosting deployment with landing page (v1 + v2 selector)

### Color picker
The color picker lives in `lib/widgets/color_picker/`. It's a hue/value disc wheel with 10 concentric rings and a neutral grey hub. The design is extracted from the `color_wallet` reference project.

When a user taps the wheel, an immersive full-screen overlay opens — the wheel world is rendered at ~6× the screen size and the user can pan around it to explore colors. A loupe floats above the finger showing a zoomed-in smooth view of the region under the cursor.

**Current status of the immersive picker:** The overlay opens correctly and covers the full screen. The initial pan position (centering on where you clicked) and drag-to-pan are implemented but have not been confirmed working in production yet — this was the last thing being worked on when we stopped.

### Architecture
- Provider-based state management (`FingerprintState`, `ColorCreationState`)
- `PersistenceService` abstraction layer (currently SharedPreferences, ready for Keychain/Firebase)
- Services layer in `lib/services/` for Firebase, auth, etc.
- Clean separation: models / state / services / screens / widgets / config

---

## Known issues / in progress

**Immersive color wheel panning (main open issue)**  
The immersive overlay opens but dragging to pan the wheel world doesn't work reliably on Flutter web with mouse input. Multiple approaches have been tried:
- `GestureDetector` — doesn't fire on web mouse drag
- `Listener` widget — fires but `setState` inside `OverlayEntry` doesn't reliably rebuild on web
- `ValueNotifier` + `ValueListenableBuilder` — rebuild path fixed but events still not reaching handler
- `GestureBinding.instance.pointerRouter.addGlobalRoute` — current approach, catches events at engine level

The latest code also initialises the pan position from the tap location so clicking yellow shows yellow in the center. This hasn't been verified in production yet.

**Deprecation warnings**  
Some `.value` and `.withOpacity()` calls in older files — harmless but worth cleaning up eventually.

---

## Running locally

```bash
flutter pub get
flutter run -d chrome   # web
flutter run             # connected device
```

## Deploying

```bash
flutter build web --release && firebase deploy --only hosting
```

---

## What's next

1. Confirm immersive wheel panning works (or keep debugging — see `.kiro/specs/immersive-wheel-drag/` for the full bug spec)
2. iOS build + TestFlight prep (icons, signing, Keychain persistence)
3. Firebase/Firestore sync for fingerprint data
4. User authentication

---

## Team

- **Ru** — owner, merges to `main`
- **Marc** — designer, works on `marc/starter`
- **Frankie** — developer, works on `frankie/starter`

---

*Last updated: April 2026*
