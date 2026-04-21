# Requirements Document

## Introduction

The color-picker-immersive-zoom feature enhances the color selection experience on the Add Color screen. When a user begins dragging on the `ColorPickerWidget` (the hue/value disc wheel), the wheel animates to fill the entire screen while all other UI elements fade out, giving the user a focused, loupe-like picking experience. When the user lifts their finger, the wheel animates back to its original inline size and position, and the rest of the UI fades back in. The selected color continues to be communicated via the existing `onColorChanged` callback, and the mosaic navigation flow remains intact.

## Glossary

- **ColorPickerWidget**: The hue/value disc wheel widget defined in `lib/widgets/color_picker/color_picker_widget.dart`.
- **AddColorScreen**: The screen that embeds `ColorPickerWidget` inline, defined in `lib/screens/add_color_screen.dart`.
- **ImmersiveMode**: The state in which the wheel occupies the full screen and all other AddColorScreen UI is hidden.
- **NormalMode**: The default state in which the wheel is displayed inline at square aspect ratio within the AddColorScreen layout.
- **PhoneFrame**: The 414×896 logical-pixel container that constrains the app on web.
- **PanGesture**: A continuous drag gesture beginning with `onPanStart` and ending with `onPanEnd` on the `ColorPickerWidget`.
- **TapGesture**: A discrete press-and-release gesture (`onTapDown` / `onTapUp`) on the `ColorPickerWidget` that does not involve significant movement.
- **ZoomAnimation**: The animation that transitions the wheel between NormalMode size/position and ImmersiveMode size/position.
- **FadeAnimation**: The animation that transitions the opacity of all non-wheel UI elements between visible and hidden.
- **LoupeTransform**: The pan-following translation applied to the wheel during ImmersiveMode so that the point under the user's finger is centred on screen.
- **MosaicScreen**: Either `ColorMosaicScreen` or `NeutralMosaicScreen`, navigated to after a valid color ring tap or neutral-hub tap.
- **onColorChanged**: The `ValueChanged<Color>` callback passed into `ColorPickerWidget` that reports the currently selected color to the parent.

---

## Requirements

### Requirement 1: Immersive Mode Trigger

**User Story:** As a user, I want the color wheel to expand to fill the screen when I start dragging on it, so that I have a large, precise picking surface without accidental taps on other controls.

#### Acceptance Criteria

1. WHEN a PanGesture begins on the `ColorPickerWidget`, THE `ColorPickerWidget` SHALL notify `AddColorScreen` that ImmersiveMode has started.
2. WHEN ImmersiveMode starts, THE `ZoomAnimation` SHALL animate the wheel from its current inline bounds to the full bounds of the `PhoneFrame` within 300 ms using a smooth ease-in-out curve.
3. WHEN ImmersiveMode starts, THE `FadeAnimation` SHALL animate the opacity of all non-wheel UI elements (top bar, question prompt, title text field, reveal sections, action buttons, home navigation button) from 1.0 to 0.0 within 300 ms.
4. WHEN a TapGesture (no pan movement) occurs on the `ColorPickerWidget`, THE `ColorPickerWidget` SHALL NOT trigger ImmersiveMode.
5. WHILE ImmersiveMode is active, THE `AddColorScreen` SHALL render non-wheel UI elements with pointer events disabled so that invisible elements cannot receive touches.

---

### Requirement 2: Loupe / Pan-Centering Behaviour

**User Story:** As a user, I want the area of the wheel under my finger to stay centred on screen as I drag, so that my finger never obscures the color I am selecting.

#### Acceptance Criteria

1. WHILE ImmersiveMode is active and a PanGesture is in progress, THE `LoupeTransform` SHALL translate the wheel so that the point on the wheel currently under the user's finger is positioned at the centre of the `PhoneFrame`.
2. WHILE ImmersiveMode is active, THE `LoupeTransform` SHALL clamp the translation so that the wheel never exposes empty space beyond its own painted bounds (i.e., the wheel edge does not scroll past the screen edge).
3. WHILE ImmersiveMode is active and a PanGesture is in progress, THE `ColorPickerWidget` SHALL continue to call `onColorChanged` with the color at the current finger position on every pan update, at the same rate as in NormalMode.
4. WHILE ImmersiveMode is active, THE `ColorPickerWidget` SHALL display the wheel at full `PhoneFrame` dimensions (414×896 logical pixels on web) before the `LoupeTransform` is applied.

---

### Requirement 3: Exit from Immersive Mode

**User Story:** As a user, I want the screen to return to its normal layout when I lift my finger, so that I can review my selection and continue filling in the form.

#### Acceptance Criteria

1. WHEN a PanGesture ends on the `ColorPickerWidget`, THE `ColorPickerWidget` SHALL notify `AddColorScreen` that ImmersiveMode has ended.
2. WHEN ImmersiveMode ends, THE `ZoomAnimation` SHALL animate the wheel from its full-screen bounds back to its original inline bounds within 300 ms using a smooth ease-in-out curve.
3. WHEN ImmersiveMode ends, THE `FadeAnimation` SHALL animate the opacity of all non-wheel UI elements from 0.0 back to 1.0 within 300 ms.
4. WHEN ImmersiveMode ends, THE `LoupeTransform` SHALL animate back to zero translation (wheel centred in its inline position) in sync with the `ZoomAnimation`.
5. WHEN ImmersiveMode ends, THE `AddColorScreen` SHALL restore pointer events on all non-wheel UI elements once the `FadeAnimation` completes.

---

### Requirement 4: Color Selection Continuity

**User Story:** As a user, I want the color I dragged to remain selected after the wheel returns to normal size, so that my pick is not lost during the transition.

#### Acceptance Criteria

1. WHEN ImmersiveMode ends, THE `ColorPickerWidget` SHALL retain the last color selected during the PanGesture as the active `selectedColor`.
2. WHEN ImmersiveMode ends, THE `ColorPickerWidget` SHALL call `onColorChanged` with the final selected color exactly once if the color changed during the PanGesture.
3. THE `AddColorScreen` SHALL update the color preview (top-bar swatch and `_BigColorPreview`) to reflect the color reported by `onColorChanged` during and after ImmersiveMode.

---

### Requirement 5: Mosaic Navigation Compatibility

**User Story:** As a user, I want to be able to tap a color ring (not drag) and still navigate to the mosaic screen as before, so that the immersive zoom feature does not break the existing mosaic flow.

#### Acceptance Criteria

1. WHEN a TapGesture ends on a coloured ring of the `ColorPickerWidget` while in NormalMode, THE `ColorPickerWidget` SHALL navigate to `ColorMosaicScreen` as it does today.
2. WHEN a TapGesture ends on the neutral hub of the `ColorPickerWidget` while in NormalMode, THE `ColorPickerWidget` SHALL navigate to `NeutralMosaicScreen` as it does today.
3. IF ImmersiveMode is active when a PanGesture ends, THEN THE `ColorPickerWidget` SHALL NOT automatically navigate to a `MosaicScreen`; mosaic navigation SHALL only be triggered by a subsequent TapGesture in NormalMode.
4. WHEN the user returns from a `MosaicScreen` after ImmersiveMode has been used in the same session, THE `AddColorScreen` SHALL display the correct selected color in the preview.

---

### Requirement 6: Animation Interruption Handling

**User Story:** As a user, I want the animations to behave predictably if I start a new gesture before the previous animation finishes, so that the UI never gets stuck in a broken state.

#### Acceptance Criteria

1. IF a PanGesture begins while the `ZoomAnimation` is still reversing (returning to NormalMode), THEN THE `ZoomAnimation` SHALL reverse direction and animate forward to ImmersiveMode from its current progress value.
2. IF a PanGesture ends while the `ZoomAnimation` is still animating forward (entering ImmersiveMode), THEN THE `ZoomAnimation` SHALL reverse direction and animate back to NormalMode from its current progress value.
3. WHILE an interrupted `ZoomAnimation` is in progress, THE `FadeAnimation` SHALL remain in sync with the `ZoomAnimation` progress at all times.
4. IF the `AddColorScreen` is disposed while ImmersiveMode is active, THEN THE `ColorPickerWidget` SHALL dispose of its `AnimationController` without throwing an error.

---

### Requirement 7: Tap-vs-Drag Discrimination

**User Story:** As a user, I want a short tap on the wheel to behave exactly as it does today (select color, open mosaic), so that the immersive zoom only activates on intentional drags.

#### Acceptance Criteria

1. THE `ColorPickerWidget` SHALL classify a gesture as a TapGesture if the total pointer movement from `onPanStart` to `onPanEnd` is less than 8 logical pixels.
2. THE `ColorPickerWidget` SHALL classify a gesture as a PanGesture if the total pointer movement from `onPanStart` to `onPanEnd` is 8 logical pixels or greater.
3. WHEN a gesture is classified as a TapGesture, THE `ColorPickerWidget` SHALL NOT enter ImmersiveMode and SHALL process the gesture using the existing tap logic (`onTapDown` / `onTapUp`).
4. WHEN a gesture is classified as a PanGesture, THE `ColorPickerWidget` SHALL enter ImmersiveMode and SHALL NOT trigger mosaic navigation on gesture end.

---

### Requirement 8: State Communication Interface

**User Story:** As a developer, I want a clean interface between `ColorPickerWidget` and `AddColorScreen` for communicating immersive state, so that the two widgets remain loosely coupled.

#### Acceptance Criteria

1. THE `ColorPickerWidget` SHALL expose an `onImmersiveModeChanged` callback of type `ValueChanged<bool>` that is called with `true` when ImmersiveMode starts and `false` when ImmersiveMode ends.
2. THE `AddColorScreen` SHALL pass an `onImmersiveModeChanged` handler to `ColorPickerWidget` that updates a local boolean state variable controlling the visibility of non-wheel UI.
3. THE `ColorPickerWidget` SHALL NOT depend on any `AddColorScreen`-specific state or context; all communication SHALL occur through the `onColorChanged` and `onImmersiveModeChanged` callbacks.
4. WHERE the `onImmersiveModeChanged` callback is not provided, THE `ColorPickerWidget` SHALL function in NormalMode only, with no immersive behaviour, preserving backward compatibility.
