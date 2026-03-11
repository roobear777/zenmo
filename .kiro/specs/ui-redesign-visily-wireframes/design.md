# Design Document: UI Redesign Based on Visily Wireframes

## Overview

This design implements a comprehensive UI redesign for the Zenmo Flutter application based on new Visily wireframes. The redesign transforms the existing linear question flow into a more flexible navigation system with an overview screen, detailed palette management, and enhanced color creation workflows.

The core architectural change is moving from a single-screen sequential flow to a multi-screen navigation system with:
- An initial logo/entry screen
- A questions overview screen showing all 5 questions at once
- Individual palette detail screens for each question
- Dedicated screens for color creation and adjustment
- Modal overlays for viewing swatch details

The design maintains backward compatibility with the existing `FingerprintAnswer` data model while introducing new UI components and navigation patterns. The implementation will use Flutter's Material Design 3 widgets with custom styling to match the Visily wireframes.

## Architecture

### Navigation Structure

The application uses a stack-based navigation model with the following screen hierarchy:

```
InitialLogoScreen (root)
  ├─> UnderstandScreen (questions overview)
  │     ├─> PaletteDetailScreen (for each question)
  │     │     ├─> AddColorScreen
  │     │     │     ├─> ColorPickerWidget (existing, modal)
  │     │     │     └─> ColorAdjusterScreen
  │     │     └─> SwatchDetailsScreen (modal overlay)
  │     └─> SummaryScreen (when all complete)
  └─> (Anonymous Feedback Survey - placeholder)
```

### State Management

The application uses a centralized state management approach:

**FingerprintState** (top-level state holder)
- Stores all 5 `FingerprintAnswer` objects
- Tracks current question progress
- Manages completion status for each question
- Persists state across navigation

**ColorCreationState** (scoped to AddColorScreen)
- Manages temporary color selection
- Stores title and note text
- Coordinates between color picker and adjuster
- Validates before saving

### Data Flow

1. **Initialization**: Load existing fingerprint data (if any) into `FingerprintState`
2. **Question Selection**: User navigates from UnderstandScreen to PaletteDetailScreen
3. **Color Creation**: User creates colors via AddColorScreen, which updates the current question's palette
4. **Persistence**: Changes are saved to `FingerprintState` and persisted to storage
5. **Completion**: When all questions have valid answers, enable navigation to SummaryScreen

### Platform Considerations

The design accommodates both web and iOS platforms:

**Web**:
- Renders within `PhoneFrame` wrapper (414x896 iPhone XR dimensions)
- Uses fallback for native share functionality
- Handles touch/mouse input appropriately

**iOS**:
- Full-screen rendering
- Native share sheet integration
- TestFlight distribution support

## Components and Interfaces

### Screen Components

#### 1. InitialLogoScreen

**Purpose**: Entry point and home screen for the application

**UI Elements**:
- Centered "zenmo" text logo
- "Test Questions" button (primary action, #6366F1)
- "Anonymous Feedback Survey" link (bottom, placeholder)
- Home icon (not shown on this screen)

**Navigation**:
- "Test Questions" → UnderstandScreen
- "Anonymous Feedback Survey" → No action (placeholder)

**State Dependencies**: None

#### 2. UnderstandScreen

**Purpose**: Overview of all 5 questions with expandable cards

**UI Elements**:
- Back button (top left, purple chevron)
- "Party Questions" label (top center)
- 5 QuestionCard widgets (expandable/collapsible)
- Chevron down icon (bottom)
- Home icon (bottom center)

**Navigation**:
- Back button → InitialLogoScreen
- Home icon → InitialLogoScreen
- Tap expanded QuestionCard → PaletteDetailScreen for that question
- When all complete → Enable navigation to SummaryScreen

**State Dependencies**:
- `FingerprintState` to determine which questions are complete
- Current question index to determine which card is expanded

**QuestionCard Component**:
```dart
class QuestionCard extends StatelessWidget {
  final int questionIndex;
  final String questionText;
  final bool isExpanded;
  final bool isCompleted;
  final List<Color> palettePreview; // Up to 4 colors
  final VoidCallback onTap;
}
```

#### 3. PaletteDetailScreen

**Purpose**: Display and manage colors for a specific question

**UI Elements**:
- Back button (top left)
- Question text (top)
- Color palette grid (selected colors, max 5, displayed as squares in a row)
- "+ Add a color" button (primary action)
- Saved palettes grid (3 columns, example placeholders when empty)
- "+" tile for adding new palettes
- Home icon (bottom)

**Navigation**:
- Back button → UnderstandScreen
- "+ Add a color" → AddColorScreen
- Tap color square → SwatchDetailsScreen (modal)
- Home icon → InitialLogoScreen

**State Dependencies**:
- Current question's `FingerprintAnswer`
- List of selected colors
- Example palettes visibility (hidden when user has added colors)

**Saved Palette Display Logic**:
- When palette is empty: Show 6 example tiles ("Need more sleep", "Passsssion", etc.)
- When palette has ≥1 color: Hide all example tiles
- Example palettes are non-interactive

#### 4. AddColorScreen

**Purpose**: Create a new color with title and note

**UI Elements**:
- Back button (top left)
- "Adding a Color" title
- "Title (required)" text input
- Two-column layout:
  - Left: Color preview square with "PREVIEW" label and "Tap to fine tune your color" text
  - Right: Color wheel placeholder with "Color Wheel" label and "Drag to Select" text
- "Note to Self (Optional/ for your eyes only)" text area
- "SAVE" button (full width, primary action)
- Home icon (bottom)

**Navigation**:
- Back button → PaletteDetailScreen (discard changes)
- Tap color preview → ColorAdjusterScreen
- Tap color wheel area → Open ColorPickerWidget (existing modal)
- "SAVE" → Validate and save to PaletteDetailScreen
- Home icon → InitialLogoScreen (preserve draft state)

**State Dependencies**:
- `ColorCreationState` (title, note, selected color)
- Current question index

**Validation**:
- Title is required (show error on save if empty)
- Color must be selected (default to initial color)
- Note is optional

#### 5. ColorAdjusterScreen

**Purpose**: Fine-tune color using HSB sliders

**UI Elements**:
- Back button (top left)
- "ADJUST: [Title]" header
- Large color preview square
- Three sliders: Hue, Saturation, Brightness
- "DONE" button (primary action)
- Home icon (bottom)

**Navigation**:
- Back button → AddColorScreen (save changes)
- "DONE" → AddColorScreen (save changes)
- Home icon → InitialLogoScreen

**State Dependencies**:
- `ColorCreationState.selectedColor`
- HSB values derived from current color

**Real-time Updates**:
- Slider changes immediately update preview square
- Changes are saved to `ColorCreationState` on navigation back

#### 6. SwatchDetailsScreen

**Purpose**: Display full details of a saved color (modal overlay)

**UI Elements**:
- Back button (top left)
- "Swatch Details" title
- Large color display (full width)
- Color title
- Created date and creator info (purple box)
- Note text (if provided)
- "Keepsake" button (dark gray)
- "Share" button (dark gray, with share icon)
- Home icon (bottom)

**Navigation**:
- Back button → Close modal, return to PaletteDetailScreen
- "Share" → Trigger native share sheet
- Home icon → InitialLogoScreen

**State Dependencies**:
- Selected color data (title, color value, note, created date)

**Share Functionality**:
- Format: "[Title]\n[Hex Value]\n[Note]"
- Use platform share sheet (iOS native, web fallback)

#### 7. SummaryScreen

**Purpose**: Display all completed answers

**UI Elements**:
- All 5 questions with their color palettes
- "Done" button

**Navigation**:
- "Done" → InitialLogoScreen

**State Dependencies**:
- All 5 `FingerprintAnswer` objects from `FingerprintState`

### Reusable Widget Components

#### NavigationButton

```dart
class NavigationButton extends StatelessWidget {
  final NavigationButtonType type; // back, home
  final VoidCallback onPressed;
}
```

Renders purple chevron left for back, purple outlined house for home.

#### ColorSquare

```dart
class ColorSquare extends StatelessWidget {
  final Color color;
  final double size;
  final VoidCallback? onTap;
  final bool showBorder;
}
```

Displays a color with rounded corners, optional tap handler.

#### PrimaryButton

```dart
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final IconData? icon;
}
```

Blue/purple (#6366F1) button with rounded corners, consistent styling.

#### SavedPaletteCard

```dart
class SavedPaletteCard extends StatelessWidget {
  final String title;
  final List<Color> colors;
  final bool isPlaceholder; // For "+" tile
  final VoidCallback? onTap;
}
```

Large square tile displaying a palette with title overlay.

### Existing Components (Reused)

#### PhoneFrame

Wraps the entire app on web, provides iPhone XR dimensions (414x896).

#### ColorPickerWidget

Existing color picker with hue/value disc and mosaic screens. Opened as modal from AddColorScreen.

## Data Models

### Enhanced FingerprintAnswer

The existing `FingerprintAnswer` model is extended to support the new UI requirements:

```dart
class FingerprintAnswer {
  final String title;           // Question answer title (existing)
  final List<int> colors;       // Color values as integers (existing)
  final List<String> hexes;     // Hex strings (existing)
  final List<ColorSwatch> swatches; // NEW: Individual color details
  
  // Existing methods remain unchanged
  bool get isValid => title.trim().isNotEmpty && colors.isNotEmpty;
}
```

### ColorSwatch (New Model)

Represents an individual color with metadata:

```dart
class ColorSwatch {
  final String title;           // Color title (required)
  final Color color;            // Color value
  final String? note;           // Optional note
  final DateTime createdAt;     // Creation timestamp
  final String creator;         // Creator identifier
  
  String get hexValue => '#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  
  Map<String, dynamic> toMap();
  factory ColorSwatch.fromMap(Map<String, dynamic> map);
}
```

### FingerprintState (New State Model)

Manages the overall fingerprint creation state:

```dart
class FingerprintState extends ChangeNotifier {
  List<FingerprintAnswer> _answers;
  int _currentQuestionIndex;
  
  FingerprintAnswer getAnswer(int index);
  void updateAnswer(int index, FingerprintAnswer answer);
  bool isQuestionComplete(int index);
  bool get allQuestionsComplete;
  int get nextIncompleteQuestion;
  
  void addColorToQuestion(int questionIndex, ColorSwatch swatch);
  void removeColorFromQuestion(int questionIndex, int colorIndex);
  
  Future<void> save();
  Future<void> load();
}
```

### ColorCreationState (New State Model)

Manages temporary state during color creation:

```dart
class ColorCreationState extends ChangeNotifier {
  Color _selectedColor;
  String _title;
  String _note;
  
  Color get selectedColor;
  void updateColor(Color color);
  void updateFromHSB(double hue, double saturation, double brightness);
  
  String get title;
  void updateTitle(String title);
  
  String get note;
  void updateNote(String note);
  
  bool get isValid => _title.trim().isNotEmpty;
  
  ColorSwatch toColorSwatch();
  void reset();
}
```

### SavedPalette (Example Data)

Static example palettes shown when a question has no colors:

```dart
class SavedPalette {
  final String title;
  final List<Color> colors;
  
  static List<SavedPalette> get examples => [
    SavedPalette('Need more sleep', [/* colors */]),
    SavedPalette('Passsssion', [/* colors */]),
    SavedPalette('No thanks gran...', [/* colors */]),
    SavedPalette('Spring Blooms A...', [/* colors */]),
    SavedPalette('Deserunt ut ut dui', [/* colors */]),
  ];
}
```

### Navigation State

Sequential question answering is enforced through:

```dart
class QuestionProgressTracker {
  final FingerprintState fingerprintState;
  
  bool canAccessQuestion(int index) {
    if (index == 0) return true;
    return fingerprintState.isQuestionComplete(index - 1);
  }
  
  int getNextAvailableQuestion() {
    for (int i = 0; i < kFingerprintTotalQuestions; i++) {
      if (!fingerprintState.isQuestionComplete(i)) return i;
    }
    return kFingerprintTotalQuestions; // All complete
  }
}
```


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property Reflection

After analyzing all acceptance criteria, I identified the following redundancies:
- Criteria 3.5 is redundant with 3.1 (both enforce sequential access)
- Criteria 16.4 is redundant with 4.6 (both test saved palette rendering)
- Criteria 17.1 is redundant with 1.3 (both test feedback survey link display)
- Criteria 19.1 is redundant with 8.2 (both test color picker synchronization)
- Criteria 19.2 is redundant with 7.7 (both test slider synchronization)

The remaining properties focus on:
1. Sequential question access enforcement
2. Data validation and constraints (max colors, required fields)
3. State preservation across navigation
4. UI synchronization between components
5. Data serialization round-trips
6. Visual consistency rules

### Property 1: Sequential Question Access Enforcement

*For any* question index N where N > 0, if question N-1 is not completed (does not have at least one color with a valid title), then attempting to navigate to question N should be prevented.

**Validates: Requirements 3.1, 3.5**

### Property 2: Question Completion Enables Next Question

*For any* question index N where N < 5, when question N is completed (has at least one color with a valid title), then question N+1 should become accessible for interaction.

**Validates: Requirements 3.3**

### Property 3: Maximum Colors Per Palette

*For any* color palette displayed on the Palette_Detail_Screen, the number of colors shown should never exceed 5.

**Validates: Requirements 4.3**

### Property 4: Saved Palette Rendering

*For any* saved palette (example or user-created), when rendered as a tile, the display should include both the palette colors and the title text.

**Validates: Requirements 4.6**

### Property 5: Empty Title Validation

*For any* string that is empty or contains only whitespace characters, attempting to save a color with that title should display a validation error and prevent the save operation.

**Validates: Requirements 6.1**

### Property 6: Valid Color Save

*For any* color with a non-empty title and a selected color value, saving should successfully add the color to the current question's palette.

**Validates: Requirements 6.2**

### Property 7: Color Title Display in Adjuster

*For any* color being adjusted, the Color_Adjuster_Screen header should display "ADJUST: [Title]" where [Title] is the color's title.

**Validates: Requirements 7.2**

### Property 8: Real-time Slider Synchronization

*For any* HSB slider adjustment on the Color_Adjuster_Screen, the color preview square should update to reflect the new color value immediately.

**Validates: Requirements 7.7**

### Property 9: Color Picker to Preview Synchronization

*For any* color selected from the Color_Picker widget, the Add_Color_Screen preview square should update to display that selected color.

**Validates: Requirements 8.2**

### Property 10: HSB Color Model Round-trip

*For any* color value, converting it to HSB slider values and then back to a color should produce an equivalent color (within acceptable floating-point precision).

**Validates: Requirements 8.4**

### Property 11: Swatch Title Display

*For any* color swatch displayed on the Swatch_Details_Screen, the swatch's title should be visible below the color display.

**Validates: Requirements 9.5**

### Property 12: Conditional Note Display

*For any* color swatch that has a non-empty note field, the Swatch_Details_Screen should display that note text.

**Validates: Requirements 9.7**

### Property 13: Share Content Completeness

*For any* color swatch being shared, the share content should include the color title, hex value, and note text (if present).

**Validates: Requirements 10.2**

### Property 14: Share Content Formatting

*For any* color swatch being shared, the share content should be formatted as human-readable text with clear separation between title, hex value, and note.

**Validates: Requirements 10.4**

### Property 15: Primary Button Color Consistency

*For any* primary action button in the application, the button color should be #6366F1 (blue/purple).

**Validates: Requirements 12.1**

### Property 16: Button Rounded Corners

*For any* button widget in the application, the button should have rounded corners.

**Validates: Requirements 12.2**

### Property 17: Back Button Styling Consistency

*For any* back button in the application, it should display as a purple chevron left icon.

**Validates: Requirements 12.5**

### Property 18: Color Square Rounded Corners

*For any* color square displayed in the application (palette grid, preview, etc.), the square should have rounded corners.

**Validates: Requirements 12.8**

### Property 19: Screen Background Consistency

*For any* screen in the application, the background color should be white.

**Validates: Requirements 12.9**

### Property 20: FingerprintAnswer Serialization Round-trip

*For any* FingerprintAnswer object with color palette data, serializing it to a map and then deserializing back should produce an equivalent FingerprintAnswer with all fields preserved.

**Validates: Requirements 14.2, 14.3**

### Property 21: Question Completion Logic

*For any* question that has at least one color with a non-empty title in its palette, the question should be marked as completed on the Understand_Screen.

**Validates: Requirements 15.1**

### Property 22: Completed Question Visual Distinction

*For any* completed question on the Understand_Screen, it should have visually distinct styling compared to incomplete questions.

**Validates: Requirements 15.2**

### Property 23: Invalid Question Not Completed

*For any* question that has colors but no valid title (empty or whitespace-only), the question should not be marked as completed.

**Validates: Requirements 15.5**

### Property 24: Example Palettes Hidden When User Has Colors

*For any* question palette that contains at least one user-added color, the Palette_Detail_Screen should hide all example saved palettes.

**Validates: Requirements 16.2**

### Property 25: State Preservation on Home Navigation

*For any* screen with user-entered data (titles, notes, selected colors), navigating to the home screen via the Home_Icon should preserve all that data.

**Validates: Requirements 18.1**

### Property 26: Completion State Preservation

*For any* set of completed questions, navigating away from the Understand_Screen and returning should display the same completion state.

**Validates: Requirements 18.2**

### Property 27: Palette State Preservation

*For any* question palette with added colors, navigating away from the Palette_Detail_Screen and returning should display all the same colors.

**Validates: Requirements 18.3**

## Error Handling

### Validation Errors

**Empty Title Validation**:
- When: User attempts to save a color with empty or whitespace-only title
- Action: Display error message "Title is required"
- Recovery: User must enter a valid title to proceed

**Maximum Colors Reached**:
- When: User attempts to add a 6th color to a palette
- Action: Disable "+ Add a color" button
- Recovery: User must remove a color before adding another

**Sequential Access Violation**:
- When: User attempts to access question N before completing question N-1
- Action: Prevent navigation, keep question card disabled
- Recovery: User must complete previous question first

### Navigation Errors

**Invalid Question Index**:
- When: Navigation requested to question index < 0 or > 4
- Action: Log error, prevent navigation
- Recovery: Stay on current screen

**Missing State Data**:
- When: Screen requires data that is not available (e.g., swatch details for non-existent color)
- Action: Log error, show error message, navigate back
- Recovery: Return to previous screen

### Platform-Specific Errors

**Share Functionality Unavailable**:
- When: Native share is not available on platform
- Action: Show error message "Sharing not available"
- Recovery: User can copy content manually (future enhancement)

**Color Picker Initialization Failure**:
- When: Color picker widget fails to initialize
- Action: Log error, use fallback color selection
- Recovery: Provide simple color input as fallback

### Data Persistence Errors

**Save Failure**:
- When: Saving fingerprint data fails
- Action: Show error message, retain data in memory
- Recovery: Retry save operation

**Load Failure**:
- When: Loading existing fingerprint data fails
- Action: Log error, start with empty state
- Recovery: User can create new fingerprint

### State Synchronization Errors

**Color Value Mismatch**:
- When: Color values between picker and preview become desynchronized
- Action: Log warning, use most recent value
- Recovery: User can re-select color

**HSB Conversion Error**:
- When: Converting between color formats produces invalid values
- Action: Clamp values to valid ranges (H: 0-360, S: 0-1, B: 0-1)
- Recovery: Use clamped values

## Testing Strategy

### Dual Testing Approach

This feature requires both unit tests and property-based tests for comprehensive coverage:

**Unit Tests** focus on:
- Specific UI examples (screen layouts, button presence)
- Navigation flows (tap button → navigate to screen)
- Edge cases (exactly 5 colors, empty palettes)
- Platform-specific behavior (web vs iOS)
- Integration points (color picker integration)

**Property-Based Tests** focus on:
- Universal properties across all inputs
- Data validation rules
- State preservation guarantees
- Visual consistency rules
- Serialization round-trips

### Property-Based Testing Configuration

**Framework**: Use the `test` package with custom property-based testing utilities, or integrate a Dart property-based testing library like `dartz` or implement a simple generator-based approach.

**Test Configuration**:
- Minimum 100 iterations per property test
- Each test tagged with: **Feature: ui-redesign-visily-wireframes, Property {number}: {property_text}**
- Use random generators for:
  - Color values (full RGB range)
  - String inputs (titles, notes) including edge cases (empty, whitespace, very long)
  - Question indices (0-4 and invalid values)
  - Palette sizes (0-5 colors)

**Example Property Test Structure**:
```dart
// Feature: ui-redesign-visily-wireframes, Property 1: Sequential Question Access Enforcement
test('Property 1: Sequential access enforcement', () {
  for (int i = 0; i < 100; i++) {
    final questionIndex = random.nextInt(5); // 0-4
    final state = generateRandomFingerprintState();
    
    // Ensure question N-1 is incomplete
    if (questionIndex > 0) {
      state.answers[questionIndex - 1] = FingerprintAnswer.empty();
    }
    
    final canAccess = QuestionProgressTracker(state).canAccessQuestion(questionIndex);
    
    if (questionIndex == 0) {
      expect(canAccess, isTrue, reason: 'First question should always be accessible');
    } else {
      expect(canAccess, isFalse, reason: 'Question $questionIndex should not be accessible when previous is incomplete');
    }
  }
});
```

### Unit Test Coverage

**Screen-Level Tests**:
- InitialLogoScreen: Verify UI elements, navigation
- UnderstandScreen: Verify 5 question cards, expansion state, navigation
- PaletteDetailScreen: Verify color grid, add button, saved palettes
- AddColorScreen: Verify input fields, preview, color wheel, save validation
- ColorAdjusterScreen: Verify sliders, preview updates, save behavior
- SwatchDetailsScreen: Verify modal display, share functionality
- SummaryScreen: Verify all questions displayed, done button

**Component-Level Tests**:
- QuestionCard: Verify expanded/collapsed states, completion indicators
- ColorSquare: Verify rendering, tap handling
- NavigationButton: Verify back/home button rendering
- PrimaryButton: Verify styling, disabled states
- SavedPaletteCard: Verify tile rendering, placeholder handling

**State Management Tests**:
- FingerprintState: Verify answer updates, completion tracking, persistence
- ColorCreationState: Verify color updates, validation, reset
- QuestionProgressTracker: Verify sequential access logic

**Integration Tests**:
- Full flow: Initial screen → Questions → Add colors → Summary → Done
- Navigation preservation: Home icon from various screens
- Color picker integration: Select color → Preview updates
- Share functionality: Generate share content, trigger platform share

### Widget Testing

Use Flutter's widget testing framework for UI verification:

```dart
testWidgets('InitialLogoScreen displays required elements', (tester) async {
  await tester.pumpWidget(MaterialApp(home: InitialLogoScreen()));
  
  expect(find.text('zenmo'), findsOneWidget);
  expect(find.text('Test Questions'), findsOneWidget);
  expect(find.text('Anonymous Feedback Survey'), findsOneWidget);
});
```

### Platform-Specific Testing

**Web Tests**:
- Verify PhoneFrame wrapper is applied
- Verify dimensions are 414x896
- Verify share fallback behavior

**iOS Tests**:
- Verify full-screen rendering
- Verify native share sheet integration
- Verify TestFlight compatibility

### Performance Testing

While not part of unit/property tests, monitor:
- Color preview update latency (< 100ms target)
- Screen navigation transitions
- State persistence operations
- Large palette rendering (5 colors × 5 questions)

### Regression Testing

Maintain tests for:
- Backward compatibility with existing FingerprintAnswer data
- Existing ColorPickerWidget functionality
- PhoneFrame wrapper behavior
- Navigation stack management

### Test Organization

```
test/
├── unit/
│   ├── models/
│   │   ├── fingerprint_answer_test.dart
│   │   ├── color_swatch_test.dart
│   │   └── fingerprint_state_test.dart
│   ├── screens/
│   │   ├── initial_logo_screen_test.dart
│   │   ├── understand_screen_test.dart
│   │   ├── palette_detail_screen_test.dart
│   │   ├── add_color_screen_test.dart
│   │   ├── color_adjuster_screen_test.dart
│   │   ├── swatch_details_screen_test.dart
│   │   └── summary_screen_test.dart
│   └── widgets/
│       ├── question_card_test.dart
│       ├── color_square_test.dart
│       └── navigation_button_test.dart
├── property/
│   ├── sequential_access_properties_test.dart
│   ├── validation_properties_test.dart
│   ├── state_preservation_properties_test.dart
│   ├── synchronization_properties_test.dart
│   └── visual_consistency_properties_test.dart
├── integration/
│   ├── full_flow_test.dart
│   ├── navigation_test.dart
│   └── color_picker_integration_test.dart
└── widget/
    ├── screen_layouts_test.dart
    └── component_rendering_test.dart
```

### Continuous Testing

- Run unit tests on every commit
- Run property tests (100 iterations) on every PR
- Run integration tests before release
- Run platform-specific tests on target platforms
- Monitor test coverage (target: >80% for new code)
