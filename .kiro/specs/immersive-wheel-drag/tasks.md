# Immersive Wheel Drag — Tasks

## Tasks

- [ ] 1. Exploratory tests (unfixed code)
  - [ ] 1.1 Write widget test that pumps `_ImmersiveWheel`, fires a `PointerMoveEvent(delta: Offset(100, 0))`, and asserts the wheel `Positioned` left value has changed — expect this to FAIL on unfixed code, confirming the bug
  - [ ] 1.2 Run the exploratory test on unfixed code and record the counterexample output to confirm root cause

- [x] 2. Implement the fix in `color_picker_widget.dart`
  - [x] 2.1 Add `_WheelState` immutable value class with `pan`, `fingerGlobal`, and `pressing` fields plus a static `initial` constant
  - [x] 2.2 Replace `_pan`, `_fingerGlobal`, `_pressing` instance fields on `_ImmersiveWheelState` with `final _notifier = ValueNotifier(_WheelState.initial)`
  - [x] 2.3 Update `_onPointerDown`, `_onPointerMove`, `_onPointerUp` to write `_notifier.value = ...` instead of calling `setState`
  - [x] 2.4 Wrap the `build` return value in `ValueListenableBuilder<_WheelState>` so the `Material`/`Listener`/`Stack` tree rebuilds on every notifier update
  - [x] 2.5 Dispose `_notifier` in `_ImmersiveWheelState.dispose()`

- [ ] 3. Fix-checking tests (fixed code — Property 1)
  - [ ] 3.1 Write widget test: pump fixed `_ImmersiveWheel`, fire `PointerMoveEvent(delta: Offset(100, 0))`, assert `Positioned.left` decreased by 100
  - [ ] 3.2 Write property-based test: generate random `Offset` deltas, assert accumulated `_pan` always stays within clamp bounds and `Positioned` offset matches

- [ ] 4. Preservation-checking tests (fixed code — Property 2)
  - [ ] 4.1 Write test: pointer down at a position inside the wheel radius calls `onColorChanged` with a non-null color
  - [ ] 4.2 Write test: pointer up fires `onDone` after the 100 ms delay
  - [ ] 4.3 Write test: while pressing, `_Loupe` widget is present in the tree at the expected screen position
  - [ ] 4.4 Write property-based test: for random tap positions inside the wheel radius, `onColorChanged` is always invoked
