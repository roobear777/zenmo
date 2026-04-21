# Zenmo Project Status

**Last Updated**: March 14, 2026  
**Current Phase**: Web Deployment Complete + Codebase Refactoring Complete

## Project Overview

Zenmo is a Flutter app for creating party fingerprints through a 5-question flow where users select colors to answer each question. The project is set up for collaborative development with Git/GitHub.

## Team Structure

- **Ru (Owner)**: Overall control, merge authority on `main` branch
- **Marc**: Designer, will customize color picker visuals
- **Frankie**: Developer, feature implementation

## Repository Structure

- **Main branch**: Protected, Ru controls merges
- **marc/starter**: Marc's working branch
- **frankie/starter**: Frankie's working branch

GitHub: https://github.com/roobear777/zenmo

## Current Implementation Status

### ✅ Completed Features

1. **Basic Flutter Project Setup**
   - Phone frame wrapper for web development (iPhone XR size: 414x896)
   - Full screen on mobile devices
   - Git repository initialized and pushed to GitHub

2. **Fingerprint Flow** (5 Questions)
   - Question progression with progress indicator
   - Color selection and management (max 5 colors per question)
   - Title input for each answer
   - Save/resume functionality
   - Summary screen showing all answers
   - Files: `lib/screens/fingerprint_flow_screen.dart`, `lib/config/fingerprint_questions.dart`, `lib/models/fingerprint_answer.dart`

3. **Sophisticated Color Picker** ✅ COMPLETE
   - Hue/Value disc wheel with 10 concentric rings
   - Neutral grey hub (center 11% of radius)
   - Color mosaic screen with 600 variations
   - Two modes: Organized (deterministic grid) and Randomized (masonry layout)
   - Neutral mosaic screen with 240 grey tones
   - Exact mathematical formulas from color_wallet reference
   - Files: `lib/widgets/color_picker/` (5 files)

4. **UI Redesign (Zenmo 2.0)** ✅ COMPLETE & DEPLOYED
   - Animated splash screen with Zenmo text (fade-in, scale animation)
   - Removed "Party Questions" title from question list
   - Visual feedback for locked questions (greyed out, 50% opacity)
   - Anonymous feedback survey integration with Google Forms
   - Custom fonts (OleoScript, Lobster) for branding
   - Deployed to Firebase Hosting at https://zenmobeta.web.app
   - Landing page with version selector (v1 and v2)
   - Files: `lib/screens/initial_logo_screen.dart`, `lib/screens/understand_screen.dart`, `lib/widgets/question_card.dart`

5. **Codebase Refactoring & Audit** ✅ COMPLETE
   - Extracted persistence logic to `PersistenceService` (platform-agnostic)
   - Centralized design constants in `AppConstants`
   - Moved example palettes to `example_palettes.dart` config
   - Removed dead code (HomeScreen, unused imports)
   - Created barrel files for clean imports
   - Established services layer for future integrations
   - Improved separation of concerns
   - See `CODEBASE_AUDIT_REPORT.md` for full details

### 📋 Implementation Details

#### Color Picker Components

**Files Created:**
```
lib/widgets/color_picker/
├── color_picker_widget.dart          # Main widget (replaces simple_color_picker.dart)
├── hue_value_disc_painter.dart       # Wheel rendering with CustomPainter
├── color_mosaic_screen.dart          # Chromatic mosaic with mode switching
├── neutral_mosaic_screen.dart        # Grey mosaic (240 tiles)
└── color_generation_utils.dart       # Color math and generation algorithms
```

**Key Features:**
- Tap colored ring → Opens mosaic with 600 color variations
- Tap neutral hub → Opens neutral mosaic with 240 greys
- Switch between Organized and Randomized modes
- Deterministic color generation (same position = same colors)
- Anti-clumping algorithm for randomized mode
- Cluster-based color distribution (pastel, mid, vivid, ink, neon)

**Mathematical Precision:**
- Ring value display: `pow((ringIndex + 1) / 10, 0.5)`
- Ring value selection: `pow((ringIndex + 1) / 10, 0.1)`
- Angle to hue: `(angleRadians * 180 / π + 360 + 90) % 360`
- Organized mode: gamma curves, ring-based interpolation
- Randomized mode: cluster weights, ring biases, anti-clumping
- Deterministic seed: `hueIndex * 1009 + ringIndex * 9176`

### 🔧 Dependencies

**pubspec.yaml:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_staggered_grid_view: ^0.7.0  # For masonry grid in randomized mode
```

### 📁 Project Structure

```
zenmo/
├── lib/
│   ├── main.dart                              # App entry point
│   ├── screens/
│   │   └── fingerprint_flow_screen.dart       # Main fingerprint flow
│   ├── widgets/
│   │   ├── phone_frame.dart                   # Phone frame wrapper
│   │   ├── simple_color_picker.dart           # OLD - can be deleted
│   │   └── color_picker/                      # NEW color picker system
│   │       ├── color_picker_widget.dart
│   │       ├── hue_value_disc_painter.dart
│   │       ├── color_mosaic_screen.dart
│   │       ├── neutral_mosaic_screen.dart
│   │       └── color_generation_utils.dart
│   ├── models/
│   │   └── fingerprint_answer.dart            # Data model
│   └── config/
│       └── fingerprint_questions.dart         # 5 questions
├── color_wallet_reference/                    # Reference implementation (DO NOT MODIFY)
├── .kiro/
│   └── specs/
│       └── color-picker-mosaic/               # Complete spec documentation
│           ├── requirements.md                # 15 requirements with formulas
│           ├── design.md                      # Architecture + 36 properties
│           └── tasks.md                       # 17 implementation tasks
├── README.md                                  # Project overview
├── CONTRIBUTING.md                            # Git workflow guide
├── QUICK_START.md                             # Setup instructions
├── MARC_NOTES.md                              # Notes for Marc
└── PROJECT_STATUS.md                          # This file
```

### 🎯 Next Steps

#### Immediate (Optional)
1. **Delete old color picker**: `lib/widgets/simple_color_picker.dart` is no longer needed
2. **Test on device**: Run `flutter run` and test the complete flow
3. **Visual customization**: Marc can modify colors, sizes, animations in color picker files
4. **Verify web deployment**: Test https://zenmobeta.web.app in browser

#### Testing (Not Yet Done)
- Unit tests for new services (PersistenceService)
- Property-based tests for color generation
- Widget tests for all components
- Integration tests for complete flow
- Visual regression testing
- Performance testing

#### iOS/TestFlight Preparation
- Create iOS-specific persistence service (Keychain)
- Implement Firebase integration service
- Add unit tests for all services
- Test on iOS simulator and physical device
- Prepare TestFlight submission

#### Future Features
- User authentication
- Backend sync with Firestore
- Sharing fingerprints
- Additional customization options

### 🚀 Running the Project

**First Time Setup:**
```bash
cd zenmo
flutter pub get
flutter run
```

**For Web Development:**
```bash
flutter run -d chrome
```

**For Mobile:**
```bash
flutter run -d <device-id>
```

### 📝 Git Workflow

**Pulling Latest Changes:**
```bash
git pull origin main
```

**Creating Feature Branch:**
```bash
git checkout -b feature/your-feature-name
```

**Committing Changes:**
```bash
git add .
git commit -m "Description of changes"
git push origin feature/your-feature-name
```

**Switching Branches:**
```bash
git checkout marc/starter    # For Marc
git checkout frankie/starter # For Frankie
git checkout main            # For main branch
```

### 🐛 Known Issues

1. **Deprecation warnings**: The code uses some deprecated Flutter APIs (`.value`, `.withOpacity`) - these still work but may need updating in future Flutter versions
2. **color_wallet_reference errors**: The reference folder has compilation errors - this is OK, we don't use it directly, only as reference
3. **Simple color picker**: Old file still exists at `lib/widgets/simple_color_picker.dart` - can be safely deleted

### 📚 Documentation

- **Spec Files**: `.kiro/specs/color-picker-mosaic/` contains complete requirements, design, and tasks
- **Code Comments**: All color picker files have detailed comments explaining formulas
- **MARC_NOTES.md**: Instructions for Marc on customizing the color picker
- **QUICK_START.md**: Setup guide for new developers
- **CONTRIBUTING.md**: Git workflow and collaboration guidelines

### 🔍 Important Notes

1. **color_wallet_reference folder**: This is the original implementation we extracted the color picker from. DO NOT modify it - it's for reference only.

2. **Exact formulas**: The color picker uses precise mathematical formulas from the reference. If modifying, be careful to maintain the math accuracy.

3. **Phone frame**: The app shows in a phone-sized frame on web (414x896) but full screen on mobile devices.

4. **Git branches**: Marc and Frankie have their own starter branches. Ru controls merges to main.

5. **Testing**: Core implementation is complete but comprehensive testing (Tasks 11-16) is not yet done.

### 💡 For the Next Session

When you open this project on another computer:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/roobear777/zenmo.git
   cd zenmo
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Check this file** (`PROJECT_STATUS.md`) to understand current state

4. **Review spec files** in `.kiro/specs/color-picker-mosaic/` for detailed documentation

5. **Run the app:**
   ```bash
   flutter run
   ```

### 📊 Task Completion Status

From `.kiro/specs/color-picker-mosaic/tasks.md`:

- ✅ Task 10: Package dependencies added
- ✅ Task 1: Color generation utilities created
- ✅ Task 2: Hue/Value disc painter implemented
- ✅ Task 3: Organized mode color generation
- ✅ Task 4: Randomized mode color generation
- ✅ Task 5: Tile height assignment
- ✅ Task 6: ColorPickerWidget created
- ✅ Task 7: ColorMosaicScreen created
- ✅ Task 8: NeutralMosaicScreen created
- ✅ Task 9: Integration into fingerprint flow
- ⏳ Task 11-17: Testing and documentation (not started)

**Estimated completion**: Core implementation 100%, Testing 0%

---

## Recent Milestones (March 2026)

### UI Redesign & Web Deployment
- ✅ Implemented animated splash screen with Zenmo branding
- ✅ Redesigned question list with visual feedback for locked questions
- ✅ Integrated anonymous feedback survey
- ✅ Added custom fonts (OleoScript, Lobster)
- ✅ Deployed to Firebase Hosting
- ✅ Created landing page with version selector

### Codebase Refactoring
- ✅ Extracted persistence to service layer
- ✅ Centralized design constants
- ✅ Removed dead code
- ✅ Created barrel files for clean imports
- ✅ Improved architecture for iOS transition
- ✅ See `CODEBASE_AUDIT_REPORT.md` for full details

---
