# Color Picker Specification Reference

## Location

The complete specification for the color picker implementation is located in:
```
../.kiro/specs/color-picker-mosaic/
```

This folder is outside the git repository (in the Kiro workspace folder) but contains critical documentation.

## Spec Files

### 1. requirements.md
- 15 detailed requirements with acceptance criteria
- Exact mathematical formulas for all color calculations
- Ring value formulas, angle conversions, opacity calculations
- Organized mode parameters (gamma curves, interpolation)
- Randomized mode parameters (cluster weights, biases, anti-clumping)
- Deterministic seed calculation
- Anti-brown adjustments
- Uniqueness enforcement rules

### 2. design.md
- Complete architecture overview
- Component hierarchy and file organization
- State management approach
- Navigation flow
- Data models (HSV, Cluster, ClusterWeights)
- 36 correctness properties for testing
- Error handling strategy
- Performance considerations
- Testing strategy (unit, property-based, integration, visual regression)

### 3. tasks.md
- 17 implementation tasks with acceptance criteria
- Task 1-10: Core implementation (✅ COMPLETED)
- Task 11-17: Testing and documentation (⏳ NOT STARTED)
- Estimated effort: 50-65 hours total
- Critical path identified
- Recommended implementation order

## Key Information from Specs

### Mathematical Formulas (from requirements.md)

**Ring Value Calculations:**
- Display: `pow((ringIndex + 1) / 10, 0.5)`
- Selection: `pow((ringIndex + 1) / 10, 0.1)`

**Angle to Hue:**
- `(angleRadians * 180 / π + 360 + 90) % 360`

**Opacity (rings 5-9):**
- `1.0 - ((ringIndex - 5 + 1) / 5).clamp(0.0, 1.0)`

**Organized Mode:**
- vMin: `0.16 + (0.30 - 0.16) * (ringIndex / 9.0)`
- vGamma: `0.78 + (0.62 - 0.78) * (ringIndex / 9.0)`
- sStrong: `1.00 + (0.70 - 1.00) * (ringIndex / 9.0)`
- sWeak: `0.20 + (0.05 - 0.20) * (ringIndex / 9.0)`
- sGamma: `1.10` (fixed)

**Randomized Mode:**
- Deterministic seed: `hueIndex * 1009 + ringIndex * 9176`
- Hue drift per ring: `[12, 12, 10, 10, 8, 6, 5, 4, 3, 2]` degrees
- Saturation bias: `[0.04, 0.03, 0.02, 0.01, 0.00, -0.01, -0.02, -0.03, -0.04, -0.06]`
- Value bias: `[-0.10, -0.08, -0.06, -0.03, -0.01, 0.01, 0.03, 0.06, 0.08, 0.10]`
- Anti-clump threshold: `0.085`

### Cluster Definitions (from design.md)

```dart
pastel: sMin=0.28, sMax=0.50, vMin=0.85, vMax=0.98
mid:    sMin=0.50, sMax=0.75, vMin=0.60, vMax=0.85
vivid:  sMin=0.75, sMax=0.95, vMin=0.60, vMax=0.90
ink:    sMin=0.75, sMax=1.00, vMin=0.30, vMax=0.55
neon:   sMin=0.95, sMax=1.00, vMin=0.97, vMax=1.00
```

### 36 Correctness Properties (from design.md)

The design document defines 36 properties that should hold true across all executions:
- Properties 1-6: Ring calculations and opacity
- Properties 7-16: Organized mode behavior
- Properties 17-26: Randomized mode behavior
- Properties 27-33: Color space and adjustments
- Properties 34-36: Neutral mosaic behavior

These properties form the basis for property-based testing (Task 12).

## Implementation Status

**Completed (Tasks 1-10):**
- ✅ Color generation utilities with all formulas
- ✅ Hue/Value disc painter
- ✅ Organized mode color generation
- ✅ Randomized mode color generation
- ✅ Tile height assignment
- ✅ ColorPickerWidget
- ✅ ColorMosaicScreen
- ✅ NeutralMosaicScreen
- ✅ Integration into fingerprint flow
- ✅ Package dependencies

**Not Started (Tasks 11-17):**
- ⏳ Unit tests
- ⏳ Property-based tests (36 properties)
- ⏳ Widget tests
- ⏳ Integration tests
- ⏳ Visual regression testing
- ⏳ Performance testing
- ⏳ Code documentation and review

## Accessing Specs on New Computer

When you clone this project on a new computer, the spec files will NOT be in the git repository. They are in the Kiro workspace folder structure.

**To access them:**
1. Open the project in Kiro
2. Navigate to `.kiro/specs/color-picker-mosaic/`
3. Read the three markdown files for complete documentation

**Alternatively**, all critical information is also documented in:
- `PROJECT_STATUS.md` - Current implementation status
- `COLOR_PICKER_IMPLEMENTATION.md` - Implementation guide
- `lib/widgets/color_picker/README.md` - Usage documentation
- Code comments in all color picker files

## Questions?

If you need the spec files and don't have access to the Kiro workspace:
1. Check the documentation files listed above
2. Review the code comments in `lib/widgets/color_picker/`
3. All mathematical formulas are implemented in `color_generation_utils.dart`
4. The reference implementation is in `color_wallet_reference/` (not in git, but can be copied separately)

---

**Note**: The spec files are comprehensive and detailed. This reference document provides the key information needed to understand and continue the implementation.
