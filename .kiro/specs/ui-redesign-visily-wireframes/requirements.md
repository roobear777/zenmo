# Requirements Document

## Introduction

This document specifies the requirements for redesigning the Zenmo Flutter application UI to match new Visily wireframes. Zenmo is a "party fingerprint" application where users answer 5 reflective questions by selecting colors. The redesign introduces a new navigation flow, color palette management system, and modernized visual design while maintaining the core functionality of the existing application.

## Glossary

- **Zenmo_App**: The Flutter application for creating party fingerprints
- **Initial_Logo_Screen**: The entry screen displaying the Zenmo logo and primary navigation
- **Understand_Screen**: The screen displaying all 5 questions with expandable cards
- **Palette_Detail_Screen**: The screen showing selected colors and saved palettes for a specific question
- **Add_Color_Screen**: The screen for creating a new color with title and note
- **Color_Adjuster_Screen**: The screen with HSB sliders for fine-tuning color values
- **Swatch_Details_Screen**: The screen displaying full details of a saved color
- **Summary_Screen**: The screen showing all completed question answers
- **Color_Picker**: The existing hue/value disc and mosaic color selection system
- **Fingerprint_Answer**: The data model storing a user's answer to a question
- **Phone_Frame**: The iPhone XR wrapper (414x896) used for web display
- **Question_Card**: An expandable/collapsible card representing one of the 5 questions
- **Color_Palette**: A collection of up to 5 colors selected for a question
- **Saved_Palette**: A named color palette displayed as a visual example (non-interactive in this version)
- **Home_Icon**: The purple house icon that navigates to Initial_Logo_Screen
- **Back_Button**: The purple chevron left button that navigates to previous screen

## Requirements

### Requirement 1: Initial Logo Screen Display

**User Story:** As a user, I want to see a welcoming entry screen, so that I understand the app's purpose and can begin the fingerprint flow.

#### Acceptance Criteria

1. THE Initial_Logo_Screen SHALL display "zenmo" text centered on a white background
2. THE Initial_Logo_Screen SHALL display a "Test Questions" button with rounded corners and blue/purple color (#6366F1)
3. THE Initial_Logo_Screen SHALL display "Anonymous Feedback Survey" link text at the bottom
4. WHEN the user taps the "Test Questions" button, THE Zenmo_App SHALL navigate to the Understand_Screen
5. THE Initial_Logo_Screen SHALL use the Phone_Frame wrapper with dimensions 414x896 on web

### Requirement 2: Questions Overview Display

**User Story:** As a user, I want to see all 5 questions at once, so that I understand the scope of the fingerprint flow.

#### Acceptance Criteria

1. THE Understand_Screen SHALL display a Back_Button in the top left corner
2. THE Understand_Screen SHALL display "Party Questions" label at top center
3. THE Understand_Screen SHALL display all 5 questions as Question_Cards
4. THE Understand_Screen SHALL display the first Question_Card in expanded state showing a color palette preview with 4 colored squares
5. THE Understand_Screen SHALL display questions 2 through 5 as collapsed Question_Cards showing only question text
6. THE Understand_Screen SHALL display a chevron down icon at the bottom
7. THE Understand_Screen SHALL display a Home_Icon at bottom center
8. WHEN the user taps the Back_Button, THE Zenmo_App SHALL navigate to the Initial_Logo_Screen
9. WHEN the user taps the Home_Icon, THE Zenmo_App SHALL navigate to the Initial_Logo_Screen

### Requirement 3: Sequential Question Navigation

**User Story:** As a user, I want to answer questions in order, so that I complete the fingerprint flow systematically.

#### Acceptance Criteria

1. THE Zenmo_App SHALL enforce sequential question answering from question 1 to question 5
2. WHEN the user taps an expanded Question_Card, THE Zenmo_App SHALL navigate to the Palette_Detail_Screen for that question
3. WHEN the user completes question N, THE Zenmo_App SHALL enable question N+1 for interaction
4. WHEN the user completes all 5 questions, THE Zenmo_App SHALL navigate to the Summary_Screen
5. THE Zenmo_App SHALL prevent users from accessing question N+1 before completing question N

### Requirement 4: Palette Detail Display

**User Story:** As a user, I want to see my selected colors and add new colors, so that I can build my answer to a question.

#### Acceptance Criteria

1. THE Palette_Detail_Screen SHALL display a Back_Button in the top left corner
2. THE Palette_Detail_Screen SHALL display the question text at the top
3. THE Palette_Detail_Screen SHALL display a grid of selected colors as squares in a row with a maximum of 5 colors
4. THE Palette_Detail_Screen SHALL display a "+ Add a color" button with blue/purple color and rounded corners
5. THE Palette_Detail_Screen SHALL display a 3-column grid of Saved_Palettes below the add button
6. THE Palette_Detail_Screen SHALL display each Saved_Palette as a large square tile with colors and title
7. THE Palette_Detail_Screen SHALL display a "+" tile for adding new palettes
8. THE Palette_Detail_Screen SHALL display a Home_Icon at the bottom
9. WHEN the user taps the Back_Button, THE Zenmo_App SHALL navigate to the Understand_Screen
10. WHEN the user taps "+ Add a color", THE Zenmo_App SHALL navigate to the Add_Color_Screen
11. WHEN the user taps the Home_Icon, THE Zenmo_App SHALL navigate to the Initial_Logo_Screen

### Requirement 5: Color Creation Interface

**User Story:** As a user, I want to create a new color with a title and note, so that I can express my answer meaningfully.

#### Acceptance Criteria

1. THE Add_Color_Screen SHALL display a Back_Button in the top left corner
2. THE Add_Color_Screen SHALL display "Adding a Color" as the title
3. THE Add_Color_Screen SHALL display a "Title (required)" text input field
4. THE Add_Color_Screen SHALL display a two-column layout with color preview on the left and color wheel on the right
5. THE Add_Color_Screen SHALL display a color preview square with "PREVIEW" label and "Tap to fine tune your color" text
6. THE Add_Color_Screen SHALL display a color wheel circle with "Color Wheel" label and "Drag to Select" text
7. THE Add_Color_Screen SHALL display a "Note to Self (Optional/ for your eyes only)" text area
8. THE Add_Color_Screen SHALL display a "SAVE" button with blue/purple color and full width
9. THE Add_Color_Screen SHALL display a Home_Icon at the bottom
10. WHEN the user taps the color preview square, THE Zenmo_App SHALL navigate to the Color_Adjuster_Screen
11. WHEN the user taps the Back_Button, THE Zenmo_App SHALL navigate to the Palette_Detail_Screen
12. WHEN the user taps the Home_Icon, THE Zenmo_App SHALL navigate to the Initial_Logo_Screen

### Requirement 6: Color Saving Validation

**User Story:** As a user, I want to be prevented from saving incomplete colors, so that all my colors have required information.

#### Acceptance Criteria

1. WHEN the user taps "SAVE" with an empty title field, THE Zenmo_App SHALL display a validation error message "Title is required"
2. WHEN the user taps "SAVE" with a valid title and selected color, THE Zenmo_App SHALL save the color to the current question's Color_Palette
3. WHEN the user taps "SAVE" with a valid title and selected color, THE Zenmo_App SHALL navigate to the Palette_Detail_Screen
4. WHEN a Color_Palette contains 5 colors, THE Zenmo_App SHALL disable the "+ Add a color" button on the Palette_Detail_Screen
5. THE "SAVE" button SHALL be enabled regardless of title field state (validation occurs on tap)

### Requirement 7: Color Adjustment Interface

**User Story:** As a user, I want to fine-tune my color using HSB sliders, so that I can select the exact color I want.

#### Acceptance Criteria

1. THE Color_Adjuster_Screen SHALL display a Back_Button in the top left corner
2. THE Color_Adjuster_Screen SHALL display "ADJUST: [Title]" at the top where [Title] is the color title
3. THE Color_Adjuster_Screen SHALL display a large color preview square
4. THE Color_Adjuster_Screen SHALL display three sliders labeled "Hue", "Saturation", and "Brightness"
5. THE Color_Adjuster_Screen SHALL display a "DONE" button with blue/purple color
6. THE Color_Adjuster_Screen SHALL display a Home_Icon at the bottom
7. WHEN the user adjusts any slider, THE Color_Adjuster_Screen SHALL update the color preview square in real-time
8. WHEN the user taps "DONE", THE Zenmo_App SHALL save the adjusted color values and navigate to the Add_Color_Screen
9. WHEN the user taps the Back_Button, THE Zenmo_App SHALL save the adjusted color values and navigate to the Add_Color_Screen
10. WHEN the user taps the Home_Icon, THE Zenmo_App SHALL navigate to the Initial_Logo_Screen

### Requirement 8: Color Picker Integration

**User Story:** As a user, I want to use the existing color picker system, so that I can select colors using familiar controls.

#### Acceptance Criteria

1. WHEN the user taps the color wheel area on Add_Color_Screen, THE Zenmo_App SHALL open the existing Color_Picker (hue/value disc and mosaic screens)
2. WHEN the user selects a color from the Color_Picker, THE Add_Color_Screen SHALL update the color preview square to display the selected color
3. THE Zenmo_App SHALL maintain the current Color_Picker functionality including hue/value disc, chromatic mosaic, and neutral mosaic screens
4. THE Color_Adjuster_Screen SHALL use HSB slider values that correspond to the Color_Picker's color model
5. THE color wheel area on Add_Color_Screen SHALL display "Color Wheel" label and "Drag to Select" text as a placeholder

### Requirement 9: Swatch Details Display

**User Story:** As a user, I want to view full details of a saved color by tapping it, so that I can review my color choices and share them.

#### Acceptance Criteria

1. WHEN the user taps a color square in the Palette_Detail_Screen grid, THE Zenmo_App SHALL display the Swatch_Details_Screen as a modal overlay
2. THE Swatch_Details_Screen SHALL display a Back_Button in the top left corner
3. THE Swatch_Details_Screen SHALL display "Swatch Details" as the title
4. THE Swatch_Details_Screen SHALL display a large color display at the top spanning full width
5. THE Swatch_Details_Screen SHALL display the color title below the color display
6. THE Swatch_Details_Screen SHALL display created date and creator info in a purple box
7. THE Swatch_Details_Screen SHALL display the note text if provided
8. THE Swatch_Details_Screen SHALL display a "Keepsake" button with dark gray color
9. THE Swatch_Details_Screen SHALL display a "Share" button with dark gray color and share icon
10. THE Swatch_Details_Screen SHALL display a Home_Icon at the bottom
11. WHEN the user taps the Back_Button, THE Zenmo_App SHALL close the modal and return to Palette_Detail_Screen
12. WHEN the user taps the Home_Icon, THE Zenmo_App SHALL navigate to the Initial_Logo_Screen

### Requirement 10: Native Share Functionality

**User Story:** As a user, I want to share my color swatches, so that I can communicate my choices with others.

#### Acceptance Criteria

1. WHEN the user taps the "Share" button on Swatch_Details_Screen, THE Zenmo_App SHALL trigger the native platform share sheet
2. THE Zenmo_App SHALL include the color title, color hex value, and note text in the share content
3. THE Zenmo_App SHALL support sharing via Messages, Email, AirDrop, and other platform-available share targets
4. THE Zenmo_App SHALL format the share content as human-readable text

### Requirement 11: Summary Screen Display

**User Story:** As a user, I want to see all my completed answers, so that I can review my party fingerprint before finishing.

#### Acceptance Criteria

1. THE Summary_Screen SHALL display all 5 questions with their corresponding Color_Palettes
2. THE Summary_Screen SHALL display a "Done" button
3. WHEN the user taps "Done", THE Zenmo_App SHALL navigate to the Initial_Logo_Screen
4. THE Summary_Screen SHALL use the existing summary screen design from the current Zenmo_App

### Requirement 12: Visual Design Consistency

**User Story:** As a user, I want a consistent and modern visual design, so that the app feels polished and professional.

#### Acceptance Criteria

1. THE Zenmo_App SHALL use blue/purple color (#6366F1) for all primary buttons
2. THE Zenmo_App SHALL use rounded corners for all buttons
3. THE Zenmo_App SHALL use full width for primary action buttons where applicable
4. THE Zenmo_App SHALL use purple outline for the Home_Icon
5. THE Zenmo_App SHALL use purple chevron left for all Back_Buttons
6. THE Zenmo_App SHALL use clean, modern sans-serif typography throughout
7. THE Zenmo_App SHALL use generous padding and margins for spacing
8. THE Zenmo_App SHALL use rounded corners for all color squares
9. THE Zenmo_App SHALL use white backgrounds for all screens

### Requirement 13: Phone Frame Compatibility

**User Story:** As a developer, I want the redesigned UI to work with the existing Phone_Frame wrapper, so that the web experience remains consistent.

#### Acceptance Criteria

1. THE Zenmo_App SHALL render all screens within the Phone_Frame wrapper with dimensions 414x896 on web
2. THE Zenmo_App SHALL render all screens at full screen on mobile devices
3. THE Zenmo_App SHALL maintain the iPhone XR size constraints for the Phone_Frame
4. THE Zenmo_App SHALL ensure all interactive elements are accessible within the Phone_Frame boundaries

### Requirement 14: Data Model Compatibility

**User Story:** As a developer, I want the redesigned UI to work with the existing data model, so that I don't need to migrate existing data.

#### Acceptance Criteria

1. THE Zenmo_App SHALL continue using the existing Fingerprint_Answer data model
2. THE Zenmo_App SHALL store Color_Palette data in a format compatible with Fingerprint_Answer
3. THE Zenmo_App SHALL preserve all existing data fields including color values, titles, and notes
4. THE Zenmo_App SHALL maintain backward compatibility with any existing stored fingerprints

### Requirement 15: Question Progress Tracking

**User Story:** As a user, I want to see which questions I've completed, so that I know my progress through the fingerprint flow.

#### Acceptance Criteria

1. WHEN a question has at least one color with a title in its Color_Palette, THE Understand_Screen SHALL mark that question as completed
2. THE Understand_Screen SHALL visually distinguish completed questions from incomplete questions
3. WHEN the user returns to the Understand_Screen, THE Zenmo_App SHALL display the current question in expanded state
4. WHEN all 5 questions are completed, THE Understand_Screen SHALL enable navigation to the Summary_Screen
5. WHEN a question has colors but no title, THE Zenmo_App SHALL not mark that question as completed

### Requirement 16: Saved Palettes Display (Example Placeholders)

**User Story:** As a user, I want to see example saved palettes before I add colors, so that I understand the visual style, and have them disappear once I start adding my own colors.

#### Acceptance Criteria

1. WHEN a question's Color_Palette is empty, THE Palette_Detail_Screen SHALL display example Saved_Palettes with titles including "Need more sleep", "Passsssion", "No thanks gran...", "Spring Blooms A...", "Deserunt ut ut dui", and "[add an answer]"
2. WHEN the user adds at least one color to the Color_Palette, THE Palette_Detail_Screen SHALL hide all example Saved_Palettes
3. THE Palette_Detail_Screen SHALL display Saved_Palettes in a 3-column grid layout
4. THE Palette_Detail_Screen SHALL display each Saved_Palette as a large square tile with colors and title
5. WHEN the user taps an example Saved_Palette, THE Zenmo_App SHALL not perform any action

### Requirement 17: Anonymous Feedback Survey Placeholder

**User Story:** As a user, I want to see the Anonymous Feedback Survey link, so that I know this feature exists (even though it's not functional yet).

#### Acceptance Criteria

1. THE Initial_Logo_Screen SHALL display "Anonymous Feedback Survey" link text at the bottom
2. WHEN the user taps "Anonymous Feedback Survey", THE Zenmo_App SHALL not perform any action
3. THE Initial_Logo_Screen SHALL style the "Anonymous Feedback Survey" text as a link with appropriate visual treatment

### Requirement 18: Navigation State Preservation

**User Story:** As a user, I want my progress to be preserved when I navigate away, so that I don't lose my work if I tap the home icon.

#### Acceptance Criteria

1. WHEN the user taps the Home_Icon from any screen, THE Zenmo_App SHALL preserve all entered data including titles, notes, and selected colors
2. WHEN the user returns to the Understand_Screen after tapping Home_Icon, THE Zenmo_App SHALL display the same completion state as before
3. WHEN the user navigates back to a Palette_Detail_Screen, THE Zenmo_App SHALL display all previously added colors
4. WHEN the user navigates back to the Add_Color_Screen, THE Zenmo_App SHALL preserve the title and note text if the color was not saved

### Requirement 19: Color Preview Synchronization

**User Story:** As a user, I want the color preview to update as I select colors, so that I can see my selection in real-time.

#### Acceptance Criteria

1. WHEN the user interacts with the Color_Picker on Add_Color_Screen, THE color preview square SHALL update to display the currently selected color
2. WHEN the user adjusts sliders on Color_Adjuster_Screen, THE color preview square SHALL update to display the adjusted color
3. WHEN the user returns from Color_Adjuster_Screen to Add_Color_Screen, THE color preview square SHALL display the adjusted color
4. THE Zenmo_App SHALL synchronize color values between Color_Picker, Color_Adjuster_Screen, and preview displays with a latency of less than 100ms

### Requirement 20: Platform Compatibility

**User Story:** As a developer, I want the redesigned UI to work on web and iOS, so that I can deploy to both platforms.

#### Acceptance Criteria

1. THE Zenmo_App SHALL render correctly on web browsers
2. THE Zenmo_App SHALL render correctly on iOS devices for TestFlight distribution
3. THE Zenmo_App SHALL use Flutter widgets that are compatible with both web and iOS platforms
4. THE Zenmo_App SHALL handle platform-specific features (like native share) with appropriate fallbacks for web
