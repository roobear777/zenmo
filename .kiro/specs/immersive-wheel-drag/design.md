# Immersive Wheel Drag Bugfix Design

## Overview

The immersive color wheel overlay does not visually respond to drag gestures on Flutter web. The `_ImmersiveWheelState` calls `setState()` inside `onPointerMove`, but the `OverlayEntry` does not reliably rebuild because `OverlayEntry` content sits outside the normal widget subtree that `setState` marks dirty.

The fix is minimal: replace the `setState`-based approach in `_ImmersiveWheelState` with a `ValueNotifier<_WheelState>` + `ValueListenableBuilder`. Pointer event callbacks update the notifier; the builder reacts to every notification and rebuilds the overlay content unconditionally.

## Glossary

- **Bug_Condition (C)**: A `PointerMoveEvent` fires on the `Listener` inside the `OverlayEntry` with a non-zero delta, but the overlay does not visually update
- **Property (P)**: After the fix, every pointer move with non-zero delta causes the wheel world's `Positioned` offset to update and the overlay to re-render
- **Preservation**: All existing behaviors — color sampling, loupe display, dismiss-on-up, initial render — must remain identical
- **`_ImmersiveWheelState`**: The `State` class in `color_picker_widget.dart` that owns pan/finger/pressing state and builds the overlay content
- **`OverlayEntry`**: Flutter's mechanism for inserting widgets above the normal widget tree; its `markNeedsBuild()` path is separate from `setState`
- **`_WheelState`**: A plain immutable value class holding `pan`, `fingerGlobal`, and `pressing` — the data driven through the `ValueNotifier`

## Bug Details

### Bug Condition

The bug manifests when a `PointerMoveEvent` fires inside the `Listener` that wraps the overlay's `Stack`. `_onPointerMove` calls `setState()`, but because `_ImmersiveWheel` is the root content of an `OverlayEntry` (inserted via `rootOverlay: true`), Flutter's dirty-marking from `setState` does not reliably propagate a rebuild to the overlay layer on web. The wheel world's `Positioned` left/top values — derived from `_pan` — never update in the rendered frame.

**Formal Specification:**
```
FUNCTION isBugCondition(event)
  INPUT: event of type PointerEvent
  OUTPUT: boolean

  RETURN event IS PointerMoveEvent
         AND event.delta != Offset.zero
         AND overlayEntry IS active
         AND overlayPositionedOffset UNCHANGED after event
END FUNCTION
```

### Examples

- User drags right 50 px: `_pan` increments by `Offset(50, 0)` internally, but the wheel `Positioned` stays at its original `left` — wheel appears frozen
- User drags diagonally: `_pan` accumulates correctly in memory, but no frame is scheduled for the overlay, so the world never moves
- User drags to the edge: clamping logic runs correctly but the visual result is still the original centered position
- User taps without dragging: `onPointerDown` fires, color is sampled, overlay dismisses — this works fine (not in bug condition)

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Tapping the overlay samples the color at the tap position and calls `onColorChanged`
- Lifting the pointer dismisses the overlay after 100 ms and restores system UI mode
- Dragging over a valid color region continuously samples and reports the color under the pointer
- The loupe appears above the finger at the correct screen position while pressing
- The initial render shows a full-screen black background with the wheel world centered

**Scope:**
All behaviors that do NOT involve the overlay rebuilding in response to `_pan` changes are unaffected. This includes:
- Color sampling logic (`_colorAt`, `_sample`)
- Loupe positioning math
- Pan clamping arithmetic
- Dismiss-on-up timing
- The compact `ColorPickerWidget` that triggers the overlay

## Hypothesized Root Cause

1. **`setState` does not reliably rebuild `OverlayEntry` content on Flutter web**: `OverlayEntry` uses its own `markNeedsBuild()` mechanism. When `setState` is called on a `StatefulWidget` that is the direct content of an `OverlayEntry`, the element may not be marked dirty in the overlay's render pipeline on web, causing the frame to be skipped.

2. **`PointerMoveEvent.delta` is `Offset.zero` on Flutter web**: Flutter web mouse events may not populate `delta` correctly on `PointerMoveEvent`, meaning `_pan` never accumulates a non-zero value even if `setState` were working.

3. **Hit-test area mismatch**: The `Listener` wraps the `Stack`, but the `Positioned` child extends beyond the screen bounds (world is 6.4× screen). If the `Listener`'s hit-test area is smaller than expected, some move events may not reach it — though `HitTestBehavior.opaque` should prevent this.

The `ValueNotifier` fix addresses causes 1 and 2 simultaneously: `ValueNotifier.notifyListeners()` is synchronous and always triggers `ValueListenableBuilder` to schedule a rebuild, bypassing the `OverlayEntry` dirty-marking path entirely.

## Correctness Properties

Property 1: Bug Condition - Pointer Move Pans the Wheel World

_For any_ `PointerMoveEvent` where `isBugCondition` holds (non-zero delta, overlay active), the fixed overlay SHALL update the wheel world's `Positioned` left/top values to reflect the accumulated `_pan` offset, causing a visible re-render of the overlay in the same frame.

**Validates: Requirements 2.1, 2.2**

Property 2: Preservation - Non-Move Interactions Unchanged

_For any_ pointer interaction where `isBugCondition` does NOT hold (pointer down, pointer up, zero-delta move, or any interaction with the compact widget), the fixed code SHALL produce exactly the same observable behavior as the original code — same color sampling, same loupe display, same dismiss timing, same initial render.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

## Fix Implementation

### Changes Required

**File**: `zenmo/lib/widgets/color_picker/color_picker_widget.dart`

**Scope**: `_ImmersiveWheel` and `_ImmersiveWheelState` only — no other classes change.

**Specific Changes**:

1. **Add `_WheelState` value class**: A simple immutable class (or record) holding `pan`, `fingerGlobal`, and `pressing`. Replaces the three separate instance fields on `_ImmersiveWheelState`.

2. **Replace instance fields with `ValueNotifier`**: Remove `_pan`, `_fingerGlobal`, `_pressing` fields. Add `final _state = ValueNotifier(_WheelState.initial)`.

3. **Remove `setState` calls from gesture handlers**: `_onPointerDown`, `_onPointerMove`, `_onPointerUp` update `_notifier.value = ...` instead of calling `setState(() { ... })`.

4. **Wrap build output in `ValueListenableBuilder`**: The `build` method returns a `ValueListenableBuilder<_WheelState>` that rebuilds whenever the notifier fires. The existing `Material` + `Listener` + `Stack` tree moves inside the builder.

5. **Dispose the notifier**: Override `dispose()` to call `_state.dispose()` before `super.dispose()`.

6. **Keep `_liveColor` as a plain field**: Color sampling side-effects (`_liveColor`, `widget.onColorChanged`) do not need to be in the notifier — they are fire-and-forget callbacks, not rebuild triggers.

### Pseudocode Sketch

```
class _WheelState {
  final Offset pan
  final Offset fingerGlobal
  final bool pressing
  static initial = _WheelState(Offset.zero, Offset.zero, false)
}

class _ImmersiveWheelState extends State<_ImmersiveWheel> {
  final _notifier = ValueNotifier(_WheelState.initial)
  Color _liveColor  // not in notifier — side-effect only

  void _onPointerMove(PointerMoveEvent e, Size screen) {
    final next = _notifier.value.pan + e.delta  // clamp
    _notifier.value = _WheelState(next, e.position, true)
    _sample(e.position, screen)
  }

  Widget build(context) {
    final Size screen = MediaQuery.of(context).size
    return ValueListenableBuilder(
      valueListenable: _notifier,
      builder: (context, state, _) {
        // compute wl, wt from state.pan
        return Material(
          child: Listener(
            onPointerDown: ...,
            onPointerMove: ...,
            onPointerUp: ...,
            child: Stack([wheel Positioned, if state.pressing Loupe])
          )
        )
      }
    )
  }
}
```

## Testing Strategy

### Validation Approach

Two-phase: first run exploratory tests on the UNFIXED code to confirm the bug and root cause, then verify the fix with fix-checking and preservation-checking tests.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples demonstrating the bug on unfixed code. Confirm or refute the root cause hypotheses.

**Test Plan**: Use Flutter's `WidgetTester` to pump `_ImmersiveWheel`, simulate a `PointerMoveEvent` with a known delta, then assert the `Positioned` widget's `left` value has changed. Run on unfixed code — expect failure.

**Test Cases**:
1. **Move right 100 px**: Pump overlay, send `PointerMoveEvent(delta: Offset(100, 0))`, assert `Positioned.left` decreased by 100 (will fail on unfixed code)
2. **Move diagonal**: Send `PointerMoveEvent(delta: Offset(50, 50))`, assert both `left` and `top` updated (will fail on unfixed code)
3. **Multiple moves accumulate**: Send three sequential move events, assert `_pan` equals sum of deltas (may pass — state updates — but visual position still wrong)
4. **Zero-delta move**: Send `PointerMoveEvent(delta: Offset.zero)`, assert no rebuild is triggered (edge case)

**Expected Counterexamples**:
- `Positioned.left` and `top` remain at their initial centered values after move events
- Possible causes: `setState` not scheduling overlay rebuild, or `delta` always `Offset.zero` on web

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed overlay re-renders with the updated pan offset.

**Pseudocode:**
```
FOR ALL event WHERE isBugCondition(event) DO
  result := pumpOverlay_fixed(event)
  ASSERT worldPositionedLeft(result) == initialLeft - event.delta.dx
  ASSERT worldPositionedTop(result)  == initialTop  - event.delta.dy
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed code produces the same observable behavior as the original.

**Pseudocode:**
```
FOR ALL event WHERE NOT isBugCondition(event) DO
  ASSERT behavior_original(event) == behavior_fixed(event)
END FOR
```

**Testing Approach**: Property-based testing generates many random pointer-down positions and verifies color sampling still fires; generates random pointer-up events and verifies dismiss callback fires. This gives strong coverage across the non-buggy input domain.

**Test Cases**:
1. **Color sampling on tap**: For any tap position inside the wheel radius, `onColorChanged` is called with a non-null color — verify on fixed code
2. **Dismiss on pointer up**: After any pointer-up event, `onDone` is scheduled — verify on fixed code
3. **Loupe position**: While pressing, the `_Loupe` widget appears at `fingerGlobal.dy - _kLoupeOffset` — verify on fixed code
4. **Initial render**: Overlay renders `Material(color: Colors.black)` with a centered `Positioned` wheel — verify on fixed code

### Unit Tests

- Test `_WheelState` immutable copy-with semantics
- Test `_clampPan` keeps pan within `(ws - screen) / 2` bounds for arbitrary deltas
- Test `_colorAt` returns null outside wheel radius and correct HSV inside (unchanged logic)

### Property-Based Tests

- Generate random `Offset` deltas and verify accumulated `_pan` never exceeds clamp bounds (Property 1 — fix checking)
- Generate random tap positions inside the wheel and verify `onColorChanged` is always called (Property 2 — preservation)
- Generate random sequences of move events and verify `Positioned` left/top always equals the clamped pan offset (Property 1 — fix checking)

### Integration Tests

- Full flow: tap compact widget → overlay appears → drag → wheel pans → lift → overlay dismisses
- Drag to boundary: wheel clamps and does not scroll off-screen
- Color continuity: color reported during drag matches the color at the final pointer position
