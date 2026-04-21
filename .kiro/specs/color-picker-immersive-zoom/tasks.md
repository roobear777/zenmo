# Implementation Plan: color-picker-immersive-zoom

## Overview

Implement the immersive zoom mode for `ColorPickerWidget` and `AddColorScreen`. The work proceeds in five incremental steps: (1) add the callback API to `ColorPickerWidget`, (2) implement tap-vs-drag discrimination inside the widget, (3) build `_ImmersiveWheelHost` with its `AnimationController` and loupe math, (4) update `AddColorScreen` to fade/hide non-wheel UI, and (5) write the property-based tests.

## Tasks

- [x] 1. Add `onImmersiveModeChanged` callback to `ColorPickerWidget`
  - In `lib/widgets/color_picker/color_picker_widget.dart`, add the optional `ValueChanged<bool>? onImmersiveModeChanged` field to `ColorPickerWidget` with a default of `null`.
  - Update the `const` constructor to accept the new parameter.
  - Add internal state fields to `_ColorPickerWidgetState`: `Offset? _panStartPosition`, `double _totalPanDistance = 0`, `bool _isImmersive = false`.
  - No gesture logic changes yet — just the API surface and state fields.
  - _Requirements: 8.1, 8.3, 8.4_

  - [ ]* 1.1 Write unit test for backward compatibility (null callback)
    - Verify `ColorPickerWidget` renders and handles tap/pan without `onImmersiveModeChanged` provided.
    - Verify no exception is thrown on pan or tap when callback is null.
    - _Requirements: 8.4_

- [x] 2. Implement tap-vs-drag discrimination in `_ColorPickerWidgetState`
  - Replace the existing `onPanUpdate` handler with one that:
    - On `onPanStart`: records `_panStartPosition` and resets `_totalPanDistance = 0`.
    - On `onPanUpdate`: accumulates `_totalPanDistance`; when it first crosses 8 px, calls `onImmersiveModeChanged?.call(true)` and sets `_isImmersive = true`; always calls `_handleColorSelection`.
    - On `onPanEnd`: if `_isImmersive`, calls `onImmersiveModeChanged?.call(false)` and resets `_isImmersive = false` — does NOT call `_openMosaic`. If not immersive (tap path), existing `onTapUp` logic runs unchanged.
  - Keep `onTapDown` / `onTapUp` handlers unchanged; they are only reached when total movement stayed below 8 px.
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 1.1, 3.1, 5.3_

  - [ ]* 2.1 Write property test for Property 1 — tap threshold never triggers immersive mode
    - **Property 1: Tap threshold never triggers immersive mode**
    - Generator: `distance ∈ [0.0, 7.99)` arbitrary pan movement.
    - Assert `onImmersiveModeChanged` is never called with `true`.
    - **Validates: Requirements 1.4, 7.1, 7.3**

  - [ ]* 2.2 Write property test for Property 2 — pan threshold triggers immersive mode and suppresses mosaic navigation
    - **Property 2: Pan threshold triggers immersive mode and suppresses mosaic navigation**
    - Generator: `distance ∈ [8.0, 500.0)` pan movement.
    - Assert `onImmersiveModeChanged` called with `true` during gesture; no mosaic navigation on end.
    - **Validates: Requirements 7.2, 7.4, 5.3**

  - [ ]* 2.3 Write property test for Property 9 — backward compatibility with null callback
    - **Property 9: Null callback leaves widget fully functional**
    - Generator: arbitrary gesture sequences (taps, pans, mixed).
    - Assert no exception thrown; `onColorChanged` called correctly; mosaic navigation fires on valid taps.
    - **Validates: Requirements 8.4**

- [x] 3. Implement `_ImmersiveWheelHost` with `AnimationController` and loupe transform
  - In `lib/screens/add_color_screen.dart`, replace the `_BigWheel` stateless widget with a new `_ImmersiveWheelHost` `StatefulWidget` that uses `TickerProviderStateMixin`.
  - Add `AnimationController _zoomCtrl` (300 ms) and `CurvedAnimation _zoomAnim` (`Curves.easeInOut`).
  - Add `Offset _loupeOffset = Offset.zero` state field.
  - Implement `_onImmersiveModeChanged(bool immersive)`: calls `_zoomCtrl.forward()` on `true`, `_zoomCtrl.reverse()` on `false` (both from current value, supporting interruption — Requirements 6.1, 6.2).
  - Implement loupe math in a pan-position update path:
    - `rawT = screenCenter - fingerPosition` (where `screenCenter = Offset(kFrameWidth/2, kFrameHeight/2)`).
    - Clamp: `maxTx = (kImmersiveWheelSize - kFrameWidth) / 2 = 241`, `maxTy = 0`.
    - `effectiveOffset = Offset.lerp(Offset.zero, clampedOffset, _zoomAnim.value)!`
  - Build method: `AnimatedBuilder` over `_zoomAnim` → `Stack` → `Transform.translate(offset: effectiveOffset)` wrapping `ColorPickerWidget` sized to `lerp(normalSize, kImmersiveWheelSize, t)`.
  - Dispose `_zoomCtrl` in `dispose()`.
  - _Requirements: 1.2, 2.1, 2.2, 2.4, 3.2, 3.4, 6.1, 6.2, 6.4_

  - [ ]* 3.1 Write property test for Property 3 — loupe centering raw translation
    - **Property 3: Loupe centering — raw translation places finger at screen centre**
    - Generator: `fingerPos: Offset` within frame bounds `[0, 414] × [0, 896]`.
    - Assert `screenCenter - fingerPos == rawTranslation` (i.e. `wheelCenter + T + (p - wheelCenter) == screenCenter`).
    - **Validates: Requirements 2.1**

  - [ ]* 3.2 Write property test for Property 4 — loupe clamping keeps wheel within screen bounds
    - **Property 4: Loupe clamping keeps wheel within screen bounds**
    - Generator: `rawTx ∈ [-1000, 1000]`, `rawTy ∈ [-1000, 1000]`.
    - Assert `|clampedTx| <= (kImmersiveWheelSize - kFrameWidth) / 2` and `|clampedTy| <= 0`.
    - **Validates: Requirements 2.2**

  - [ ]* 3.3 Write property test for Property 6 — animation interruption forward from any reverse progress
    - **Property 6: Animation interruption — forward from any reverse progress**
    - Generator: `t ∈ (0.0, 1.0)` while `ZoomAnimation` is reversing.
    - Assert animation value increases after a new pan start.
    - **Validates: Requirements 6.1**

  - [ ]* 3.4 Write property test for Property 7 — animation interruption reverse from any forward progress
    - **Property 7: Animation interruption — reverse from any forward progress**
    - Generator: `t ∈ (0.0, 1.0)` while `ZoomAnimation` is animating forward.
    - Assert animation value decreases after pan end.
    - **Validates: Requirements 6.2**

  - [ ]* 3.5 Write property test for Property 10 — loupe translation is zero when animation is at rest in NormalMode
    - **Property 10: Loupe translation is zero when animation is at rest in NormalMode**
    - Generator: any `rawOffset`.
    - Assert effective offset == `Offset.zero` when `_zoomAnim.value == 0.0`.
    - **Validates: Requirements 3.4**

- [x] 4. Update `AddColorScreen` to fade/hide non-wheel UI
  - In `_AddColorScreenState`, add `bool _isImmersive = false`.
  - Add handler `void _onImmersiveModeChanged(bool immersive) => setState(() => _isImmersive = immersive)`.
  - Wrap all non-wheel children (top bar `Padding`, question prompt `Padding`, the `Expanded > SingleChildScrollView` column, and the home nav `Padding`) in:
    ```dart
    IgnorePointer(
      ignoring: _isImmersive,
      child: AnimatedOpacity(
        opacity: _isImmersive ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: /* non-wheel UI */,
      ),
    )
    ```
  - Pass `onImmersiveModeChanged: _onImmersiveModeChanged` down to `_ImmersiveWheelHost`.
  - Place `_ImmersiveWheelHost` in a `Stack` so it can expand beyond the normal column flow during ImmersiveMode.
  - _Requirements: 1.3, 1.5, 3.3, 3.5, 8.2_

  - [ ]* 4.1 Write property test for Property 8 — fade opacity is always in sync with zoom animation progress
    - **Property 8: Fade opacity is always in sync with zoom animation progress**
    - Generator: `t ∈ [0.0, 1.0]` sampled at arbitrary points including during interruptions.
    - Assert `AnimatedOpacity.opacity == 1.0 - curvedT` at every sampled `t`.
    - **Validates: Requirements 6.3, 1.3, 3.3**

  - [ ]* 4.2 Write integration test for full AddColorScreen immersive flow
    - Pump `AddColorScreen` in a widget test.
    - Simulate pan on wheel → verify `_isImmersive` becomes `true` and non-wheel widgets have `opacity == 0.0`.
    - Simulate pan end → verify `_isImmersive` becomes `false` and non-wheel widgets fade back.
    - _Requirements: 1.1, 1.3, 3.1, 3.3_

- [x] 5. Wire color selection continuity and property test for color retention
  - Verify that `_handleColorSelection` is called on every `onPanUpdate` regardless of immersive state, so `onColorChanged` fires continuously during a drag.
  - Confirm `AddColorScreen._onColorPicked` updates `ColorCreationState` and the top-bar swatch during ImmersiveMode.
  - _Requirements: 2.3, 4.1, 4.2, 4.3_

  - [ ]* 5.1 Write property test for Property 5 — color is retained after any pan sequence
    - **Property 5: Color is retained after any pan sequence**
    - Generator: sequence of `Offset` pan positions within wheel bounds.
    - Assert `selectedColor == colorAt(lastPosition)` after pan end; `onColorChanged` called with that color.
    - **Validates: Requirements 4.1, 4.2**

- [x] 6. Final checkpoint — ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP.
- Each task references specific requirements for traceability.
- Property tests use the `fast_check` package; tag each test with `// Feature: color-picker-immersive-zoom, Property N: <property text>`.
- `AnimationController.forward()` / `.reverse()` called from current value naturally handles interruption (Requirements 6.1, 6.2) — no extra logic needed.
- `IgnorePointer` keeps non-wheel widgets in the tree (preserving `TextEditingController` state) while blocking touches during ImmersiveMode.
