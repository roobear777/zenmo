# Implementation Plan: UI Redesign Based on Visily Wireframes

## Overview

This implementation plan transforms the Zenmo Flutter application from a linear question flow to a flexible multi-screen navigation system based on Visily wireframes. The redesign introduces an overview screen showing all 5 questions, individual palette detail screens, dedicated color creation/adjustment workflows, and modal swatch details.

The implementation maintains backward compatibility with the existing `FingerprintAnswer` data model while introducing new screens, state management, and navigation patterns using Flutter's Material Design 3 widgets.

## Tasks

- [x] 1. Set up data models and state management
  - [x] 1.1 Create ColorSwatch model with serialization
    - Implement ColorSwatch class with title, color, note, createdAt, creator fields
    - Add hexValue getter for color hex string conversion
    - Implement toMap() and fromMap() methods for persistence
    - _Requirements: 14.2, 14.3_
  
  - [ ]* 1.2 Write property test for ColorSwatch serialization
    - **Property 20: FingerprintAnswer Serialization Round-trip**
    - **Validates: Requirements 14.2, 14.3**
  
  - [x] 1.3 Extend FingerprintAnswer model to support ColorSwatch list
    - Add swatches field to FingerprintAnswer
    - Update serialization methods to handle swatches
    - Maintain backward compatibility with existing data
    - _Requirements: 14.1, 14.2, 14.3_
  
  - [x] 1.4 Create FingerprintState for centralized state management
    - Implement FingerprintState with ChangeNotifier
    - Add methods: getAnswer, updateAnswer, isQuestionComplete, allQuestionsComplete
    - Add methods: addColorToQuestion, removeColorFromQuestion
    - Implement save() and load() for persistence
    - _Requirements: 18.1, 18.2, 18.3_
  
  - [x] 1.5 Create ColorCreationState for color creation workflow
    - Implement ColorCreationState with ChangeNotifier
    - Add fields: selectedColor, title, note
    - Add methods: updateColor, updateFromHSB, updateTitle, updateNote
    - Add isValid getter and toColorSwatch() method
    - _Requirements: 5.3, 5.7, 6.1_
  
  - [x] 1.6 Create QuestionProgressTracker for sequential access logic
    - Implement canAccessQuestion method enforcing sequential access
    - Implement getNextAvailableQuestion method
    - _Requirements: 3.1, 3.3, 3.5_
  
  - [ ]* 1.7 Write property tests for sequential access enforcement
    - **Property 1: Sequential Question Access Enforcement**
    - **Validates: Requirements 3.1, 3.5**
    - **Property 2: Question Completion Enables Next Question**
    - **Validates: Requirements 3.3**

- [x] 2. Create reusable widget components
  - [x] 2.1 Implement NavigationButton widget
    - Create NavigationButton with back and home button types
    - Style back button as purple chevron left
    - Style home button as purple outlined house icon
    - _Requirements: 12.5, 12.4_
  
  - [ ]* 2.2 Write property test for back button styling
    - **Property 17: Back Button Styling Consistency**
    - **Validates: Requirements 12.5**
  
  - [x] 2.3 Implement ColorSquare widget
    - Create ColorSquare with color, size, onTap, showBorder parameters
    - Apply rounded corners to all color squares
    - _Requirements: 12.8_
  
  - [ ]* 2.4 Write property test for color square rounded corners
    - **Property 18: Color Square Rounded Corners**
    - **Validates: Requirements 12.8**
  
  - [x] 2.5 Implement PrimaryButton widget
    - Create PrimaryButton with label, onPressed, fullWidth, icon parameters
    - Apply #6366F1 color to all primary buttons
    - Apply rounded corners to all buttons
    - _Requirements: 12.1, 12.2, 12.3_
  
  - [ ]* 2.6 Write property tests for button styling
    - **Property 15: Primary Button Color Consistency**
    - **Validates: Requirements 12.1**
    - **Property 16: Button Rounded Corners**
    - **Validates: Requirements 12.2**
  
  - [x] 2.7 Implement SavedPaletteCard widget
    - Create SavedPaletteCard with title, colors, isPlaceholder, onTap parameters
    - Render as large square tile with colors and title overlay
    - Support "+" placeholder tile
    - _Requirements: 4.6, 4.7_

- [x] 3. Implement InitialLogoScreen
  - [x] 3.1 Create InitialLogoScreen layout
    - Display centered "zenmo" text logo
    - Display "Test Questions" button with PrimaryButton widget
    - Display "Anonymous Feedback Survey" link at bottom
    - Apply white background
    - _Requirements: 1.1, 1.2, 1.3, 12.9, 17.1_
  
  - [x] 3.2 Implement navigation from InitialLogoScreen
    - Navigate to UnderstandScreen on "Test Questions" tap
    - No action on "Anonymous Feedback Survey" tap (placeholder)
    - _Requirements: 1.4, 17.2_
  
  - [ ]* 3.3 Write unit tests for InitialLogoScreen
    - Test UI elements presence
    - Test navigation behavior
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 4. Implement QuestionCard component
  - [x] 4.1 Create QuestionCard widget
    - Display question text
    - Support expanded/collapsed states
    - Show palette preview (up to 4 colored squares) when expanded
    - Show completion indicator for completed questions
    - _Requirements: 2.3, 2.4, 2.5, 15.2_
  
  - [ ]* 4.2 Write property test for completed question visual distinction
    - **Property 22: Completed Question Visual Distinction**
    - **Validates: Requirements 15.2**
  
  - [ ]* 4.3 Write unit tests for QuestionCard
    - Test expanded/collapsed rendering
    - Test palette preview display
    - Test completion indicator
    - _Requirements: 2.3, 2.4, 2.5_

- [x] 5. Implement UnderstandScreen
  - [x] 5.1 Create UnderstandScreen layout
    - Display Back_Button in top left
    - Display "Party Questions" label at top center
    - Display 5 QuestionCard widgets
    - Display first card expanded, others collapsed
    - Display chevron down icon at bottom
    - Display Home_Icon at bottom center
    - Apply white background
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 12.9_
  
  - [x] 5.2 Implement question completion logic
    - Mark question as completed when it has at least one color with valid title
    - Do not mark question as completed if colors have no title
    - Display current question in expanded state on return
    - _Requirements: 15.1, 15.3, 15.5_
  
  - [ ]* 5.3 Write property tests for question completion
    - **Property 21: Question Completion Logic**
    - **Validates: Requirements 15.1**
    - **Property 23: Invalid Question Not Completed**
    - **Validates: Requirements 15.5**
  
  - [x] 5.4 Implement navigation from UnderstandScreen
    - Navigate to InitialLogoScreen on Back_Button tap
    - Navigate to InitialLogoScreen on Home_Icon tap
    - Navigate to PaletteDetailScreen on expanded QuestionCard tap
    - Enable navigation to SummaryScreen when all questions complete
    - _Requirements: 2.8, 2.9, 3.2, 3.4_
  
  - [ ]* 5.5 Write unit tests for UnderstandScreen
    - Test UI elements presence
    - Test question card states
    - Test navigation behavior
    - _Requirements: 2.1, 2.2, 2.3, 2.8, 2.9_

- [x] 6. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement PaletteDetailScreen
  - [x] 7.1 Create PaletteDetailScreen layout
    - Display Back_Button in top left
    - Display question text at top
    - Display color palette grid (selected colors as squares in a row, max 5)
    - Display "+ Add a color" button with PrimaryButton widget
    - Display 3-column grid of SavedPaletteCard widgets
    - Display "+" tile for adding new palettes
    - Display Home_Icon at bottom
    - Apply white background
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 12.9_
  
  - [x] 7.2 Implement saved palettes display logic
    - Show 6 example palettes when question palette is empty
    - Hide all example palettes when user has added at least one color
    - Example palettes: "Need more sleep", "Passsssion", "No thanks gran...", "Spring Blooms A...", "Deserunt ut ut dui", "[add an answer]"
    - Make example palettes non-interactive
    - _Requirements: 16.1, 16.2, 16.3, 16.5_
  
  - [ ]* 7.3 Write property tests for saved palettes
    - **Property 3: Maximum Colors Per Palette**
    - **Validates: Requirements 4.3**
    - **Property 4: Saved Palette Rendering**
    - **Validates: Requirements 4.6**
    - **Property 24: Example Palettes Hidden When User Has Colors**
    - **Validates: Requirements 16.2**
  
  - [x] 7.4 Implement "+ Add a color" button state
    - Disable button when palette contains 5 colors
    - Enable button when palette has fewer than 5 colors
    - _Requirements: 6.4_
  
  - [x] 7.5 Implement navigation from PaletteDetailScreen
    - Navigate to UnderstandScreen on Back_Button tap
    - Navigate to AddColorScreen on "+ Add a color" tap
    - Navigate to SwatchDetailsScreen modal on color square tap
    - Navigate to InitialLogoScreen on Home_Icon tap
    - _Requirements: 4.9, 4.10, 4.11, 9.1_
  
  - [ ]* 7.6 Write unit tests for PaletteDetailScreen
    - Test UI elements presence
    - Test saved palettes visibility logic
    - Test add button disabled state
    - Test navigation behavior
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 16.1, 16.2_

- [x] 8. Implement AddColorScreen
  - [x] 8.1 Create AddColorScreen layout
    - Display Back_Button in top left
    - Display "Adding a Color" title
    - Display "Title (required)" text input field
    - Display two-column layout with color preview (left) and color wheel (right)
    - Display color preview square with "PREVIEW" label and "Tap to fine tune your color" text
    - Display color wheel placeholder with "Color Wheel" label and "Drag to Select" text
    - Display "Note to Self (Optional/ for your eyes only)" text area
    - Display "SAVE" button with PrimaryButton widget (full width)
    - Display Home_Icon at bottom
    - Apply white background
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 12.9_
  
  - [x] 8.2 Integrate ColorCreationState with AddColorScreen
    - Bind title input to ColorCreationState.title
    - Bind note input to ColorCreationState.note
    - Bind color preview to ColorCreationState.selectedColor
    - _Requirements: 5.3, 5.7_
  
  - [x] 8.3 Implement color picker integration
    - Open existing ColorPickerWidget modal on color wheel area tap
    - Update ColorCreationState.selectedColor when color is selected
    - Update color preview square to display selected color
    - _Requirements: 8.1, 8.2, 8.3, 8.5_
  
  - [ ]* 8.4 Write property test for color picker synchronization
    - **Property 9: Color Picker to Preview Synchronization**
    - **Validates: Requirements 8.2**
  
  - [x] 8.5 Implement save validation
    - Show "Title is required" error when saving with empty title
    - Save color to current question's palette when title is valid
    - Navigate to PaletteDetailScreen after successful save
    - _Requirements: 6.1, 6.2, 6.3_
  
  - [ ]* 8.6 Write property tests for validation
    - **Property 5: Empty Title Validation**
    - **Validates: Requirements 6.1**
    - **Property 6: Valid Color Save**
    - **Validates: Requirements 6.2**
  
  - [x] 8.7 Implement navigation from AddColorScreen
    - Navigate to PaletteDetailScreen on Back_Button tap (discard changes)
    - Navigate to ColorAdjusterScreen on color preview tap
    - Navigate to InitialLogoScreen on Home_Icon tap (preserve draft state)
    - _Requirements: 5.10, 5.11, 5.12, 18.4_
  
  - [ ]* 8.8 Write unit tests for AddColorScreen
    - Test UI elements presence
    - Test validation behavior
    - Test navigation behavior
    - _Requirements: 5.1, 5.2, 5.3, 6.1, 6.2_

- [x] 9. Implement ColorAdjusterScreen
  - [x] 9.1 Create ColorAdjusterScreen layout
    - Display Back_Button in top left
    - Display "ADJUST: [Title]" header with color title
    - Display large color preview square
    - Display three sliders labeled "Hue", "Saturation", "Brightness"
    - Display "DONE" button with PrimaryButton widget
    - Display Home_Icon at bottom
    - Apply white background
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 12.9_
  
  - [ ]* 9.2 Write property test for color title display
    - **Property 7: Color Title Display in Adjuster**
    - **Validates: Requirements 7.2**
  
  - [x] 9.3 Implement HSB slider functionality
    - Convert ColorCreationState.selectedColor to HSB values
    - Update color preview square in real-time as sliders change
    - Update ColorCreationState.selectedColor from HSB values
    - _Requirements: 7.7, 8.4_
  
  - [ ]* 9.4 Write property tests for HSB functionality
    - **Property 8: Real-time Slider Synchronization**
    - **Validates: Requirements 7.7**
    - **Property 10: HSB Color Model Round-trip**
    - **Validates: Requirements 8.4**
  
  - [x] 9.5 Implement navigation from ColorAdjusterScreen
    - Save adjusted color values and navigate to AddColorScreen on "DONE" tap
    - Save adjusted color values and navigate to AddColorScreen on Back_Button tap
    - Navigate to InitialLogoScreen on Home_Icon tap
    - _Requirements: 7.8, 7.9, 7.10_
  
  - [ ]* 9.6 Write unit tests for ColorAdjusterScreen
    - Test UI elements presence
    - Test slider updates preview
    - Test navigation behavior
    - _Requirements: 7.1, 7.2, 7.7, 7.8_

- [x] 10. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Implement SwatchDetailsScreen
  - [x] 11.1 Create SwatchDetailsScreen as modal overlay
    - Display Back_Button in top left
    - Display "Swatch Details" title
    - Display large color display at top (full width)
    - Display color title below color display
    - Display created date and creator info in purple box
    - Display note text if provided
    - Display "Keepsake" button with dark gray color
    - Display "Share" button with dark gray color and share icon
    - Display Home_Icon at bottom
    - _Requirements: 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8, 9.9, 9.10_
  
  - [ ]* 11.2 Write property tests for swatch display
    - **Property 11: Swatch Title Display**
    - **Validates: Requirements 9.5**
    - **Property 12: Conditional Note Display**
    - **Validates: Requirements 9.7**
  
  - [x] 11.3 Implement share functionality
    - Format share content as "[Title]\n[Hex Value]\n[Note]"
    - Trigger native platform share sheet on "Share" button tap
    - Support Messages, Email, AirDrop, and other platform share targets
    - _Requirements: 10.1, 10.2, 10.3, 10.4_
  
  - [ ]* 11.4 Write property tests for share functionality
    - **Property 13: Share Content Completeness**
    - **Validates: Requirements 10.2**
    - **Property 14: Share Content Formatting**
    - **Validates: Requirements 10.4**
  
  - [x] 11.5 Implement navigation from SwatchDetailsScreen
    - Close modal and return to PaletteDetailScreen on Back_Button tap
    - Navigate to InitialLogoScreen on Home_Icon tap
    - _Requirements: 9.11, 9.12_
  
  - [ ]* 11.6 Write unit tests for SwatchDetailsScreen
    - Test UI elements presence
    - Test conditional note display
    - Test share functionality
    - Test navigation behavior
    - _Requirements: 9.2, 9.3, 9.5, 9.7, 10.1_

- [x] 12. Implement SummaryScreen
  - [x] 12.1 Create SummaryScreen layout
    - Display all 5 questions with their color palettes
    - Display "Done" button
    - Use existing summary screen design from current Zenmo app
    - _Requirements: 11.1, 11.2_
  
  - [x] 12.2 Implement navigation from SummaryScreen
    - Navigate to InitialLogoScreen on "Done" tap
    - _Requirements: 11.3_
  
  - [ ]* 12.3 Write unit tests for SummaryScreen
    - Test all questions displayed
    - Test done button navigation
    - _Requirements: 11.1, 11.2, 11.3_

- [x] 13. Implement state preservation across navigation
  - [x] 13.1 Implement state preservation on home navigation
    - Preserve all entered data (titles, notes, colors) when Home_Icon is tapped
    - Preserve completion state when navigating away from UnderstandScreen
    - Preserve palette colors when navigating away from PaletteDetailScreen
    - _Requirements: 18.1, 18.2, 18.3_
  
  - [ ]* 13.2 Write property tests for state preservation
    - **Property 25: State Preservation on Home Navigation**
    - **Validates: Requirements 18.1**
    - **Property 26: Completion State Preservation**
    - **Validates: Requirements 18.2**
    - **Property 27: Palette State Preservation**
    - **Validates: Requirements 18.3**
  
  - [ ]* 13.3 Write integration tests for state preservation
    - Test full navigation flow with state preservation
    - Test home navigation from various screens
    - _Requirements: 18.1, 18.2, 18.3_

- [x] 14. Implement PhoneFrame compatibility
  - [x] 14.1 Ensure all screens render within PhoneFrame on web
    - Verify all screens render at 414x896 dimensions on web
    - Verify all screens render full screen on mobile devices
    - Ensure all interactive elements are accessible within PhoneFrame boundaries
    - _Requirements: 1.5, 13.1, 13.2, 13.3, 13.4_
  
  - [ ]* 14.2 Write platform-specific tests
    - Test PhoneFrame wrapper on web
    - Test full-screen rendering on iOS
    - Test share functionality on both platforms
    - _Requirements: 13.1, 13.2, 20.1, 20.2, 20.4_

- [x] 15. Implement visual design consistency
  - [x] 15.1 Apply consistent styling across all screens
    - Verify all primary buttons use #6366F1 color
    - Verify all buttons have rounded corners
    - Verify all screens have white backgrounds
    - Verify all color squares have rounded corners
    - Verify clean, modern sans-serif typography throughout
    - Verify generous padding and margins for spacing
    - _Requirements: 12.1, 12.2, 12.6, 12.7, 12.8, 12.9_
  
  - [ ]* 15.2 Write property tests for visual consistency
    - **Property 19: Screen Background Consistency**
    - **Validates: Requirements 12.9**
  
  - [ ]* 15.3 Write visual regression tests
    - Test button styling consistency
    - Test color square styling consistency
    - Test typography consistency
    - _Requirements: 12.1, 12.2, 12.6, 12.7, 12.8_

- [x] 16. Final integration and wiring
  - [x] 16.1 Wire all screens together with navigation
    - Connect all navigation flows between screens
    - Ensure sequential question access is enforced
    - Ensure state is properly passed between screens
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_
  
  - [x] 16.2 Integrate with existing ColorPickerWidget
    - Ensure ColorPickerWidget opens from AddColorScreen
    - Ensure color selection updates ColorCreationState
    - Maintain existing Color_Picker functionality
    - _Requirements: 8.1, 8.2, 8.3_
  
  - [x] 16.3 Implement data persistence
    - Save FingerprintState to storage on changes
    - Load FingerprintState on app startup
    - Handle save/load errors gracefully
    - _Requirements: 14.1, 14.2, 14.3_
  
  - [ ]* 16.4 Write integration tests for full flow
    - Test complete fingerprint creation flow
    - Test navigation between all screens
    - Test data persistence across app restarts
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 11.1, 11.3_

- [x] 17. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- The implementation uses Flutter with Material Design 3 widgets
- All screens maintain backward compatibility with existing data models
- Sequential question access is enforced throughout the navigation flow
