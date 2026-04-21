# Bugfix Requirements Document

## Introduction

When the user taps the compact color wheel widget, the immersive full-screen wheel overlay appears correctly. However, dragging/moving the pointer does not pan the wheel world — the wheel stays static regardless of drag input. This prevents users from exploring different parts of the color wheel by panning.

The bug affects Flutter web specifically. The `_ImmersiveWheelState` holds `_pan` offset state and `_onPointerMove` updates it via `setState`, but the overlay world does not visually respond to pointer move events.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the user opens the immersive wheel overlay and moves the pointer (mouse drag or touch drag) THEN the system does not pan the wheel world — the `_pan` offset updates internally but the overlay does not visually re-render

1.2 WHEN the user drags across the immersive overlay on Flutter web THEN the system does not fire `onPointerMove` events on the `Listener` widget (or fires them but the resulting `setState` does not cause the `OverlayEntry` to rebuild)

1.3 WHEN `_onPointerMove` is called and `setState` is invoked inside `_ImmersiveWheelState` THEN the system does not update the `Positioned` widget's `left`/`top` values that position the wheel world, leaving the wheel visually frozen

### Expected Behavior (Correct)

2.1 WHEN the user drags on the immersive overlay THEN the system SHALL pan the wheel world by updating `_pan` with the cumulative pointer delta and re-rendering the `Positioned` wheel at the new offset

2.2 WHEN `_onPointerMove` fires with a non-zero delta THEN the system SHALL trigger a visible rebuild of the overlay so the wheel world moves in sync with the drag gesture

2.3 WHEN the user drags to the edge of the pannable area THEN the system SHALL clamp `_pan` so the wheel world does not scroll beyond its bounds, and SHALL reflect the clamped position in the rendered layout

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the user taps (pointer down without significant movement) on the immersive overlay THEN the system SHALL CONTINUE TO sample the color at the tap position and invoke `onColorChanged`

3.2 WHEN the user lifts the pointer after interacting with the immersive overlay THEN the system SHALL CONTINUE TO dismiss the overlay after the short delay and restore system UI mode

3.3 WHEN the user drags over a valid color region of the wheel THEN the system SHALL CONTINUE TO sample and report the color under the pointer position in real time

3.4 WHEN the user is pressing and the loupe is visible THEN the system SHALL CONTINUE TO display the loupe at the correct position above the finger/cursor during a drag

3.5 WHEN the immersive overlay first appears THEN the system SHALL CONTINUE TO render the full-screen black background with the wheel world centered on screen
