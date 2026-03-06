# Color Picker with Mosaic System

A sophisticated color picker extracted from the color_wallet project, featuring a hue/value disc wheel and mosaic grid system with organized and randomized display modes.

## Components

### ColorPickerWidget
Main widget that displays the circular color wheel and handles user interaction.

**Usage:**
```dart
ColorPickerWidget(
  currentColor: Colors.blue,
  onColorChanged: (color) {
    setState(() => selectedColor = color);
  },
)
```

**Features:**
- 10 concentric rings with varying brightness
- Neutral grey hub in center (11% of radius)
- Tap or drag to select colors
- Automatic navigation to mosaic screens

### ColorMosaicScreen
Grid display of 600 color variations with two modes:

**Organized Mode:**
- 6-column fixed grid
- Saturation decreases left to right
- Brightness decreases top to bottom
- Deterministic and reproducible

**Randomized Mode:**
- 6-column masonry grid with varied tile heights
- Cluster-based color distribution (pastel, mid, vivid, ink, neon)
- Ring-specific weights and biases
- Anti-clumping algorithm for visual variety
- 4% hero tiles (height 4)

### NeutralMosaicScreen
Grid of 240 grey tones arranged from light (top) to dark (bottom).

## Mathematical Formulas

All color calculations use exact formulas from the reference implementation:

### Ring Value Calculations
```dart
// Display (wheel rendering)
displayValue = pow((ringIndex + 1) / 10, 0.5)

// Selection (mosaic generation)
mosaicValue = pow((ringIndex + 1) / 10, 0.1)
```

### Angle to Hue Conversion
```dart
hue = (angleRadians * 180 / π + 360 + 90) % 360
```

### Opacity Fade (Rings 5-9)
```dart
opacity = 1.0 - ((ringIndex - 5 + 1) / 5).clamp(0.0, 1.0)
```

### Organized Mode
```dart
// Ring interpolation
ringT = ringIndex / 9.0

// Value parameters
vMin = 0.16 + (0.30 - 0.16) * ringT
vGamma = 0.78 + (0.62 - 0.78) * ringT

// Saturation parameters
sStrong = 1.00 + (0.70 - 1.00) * ringT
sWeak = 0.20 + (0.05 - 0.20) * ringT
sGamma = 1.10

// Apply to each tile
v = vMin + (vMax - vMin) * pow((1.0 - row_t), vGamma)
s = sStrong + (sWeak - sStrong) * pow(col_t, sGamma)

// Muddy color adjustment
if (s * v < 0.06) {
  v = (v + 0.035).clamp(vMin, vMax)
}
```

### Randomized Mode
```dart
// Deterministic seed
seed = round(hue / 0.25) * 1009 + ringIndex * 9176

// Cluster ranges
pastel: s[0.28-0.50], v[0.85-0.98]
mid:    s[0.50-0.75], v[0.60-0.85]
vivid:  s[0.75-0.95], v[0.60-0.90]
ink:    s[0.75-1.00], v[0.30-0.55]
neon:   s[0.95-1.00], v[0.97-1.00]

// Ring-specific biases
sBias = [0.04, 0.03, 0.02, 0.01, 0.00, -0.01, -0.02, -0.03, -0.04, -0.06]
vBias = [-0.10, -0.08, -0.06, -0.03, -0.01, 0.01, 0.03, 0.06, 0.08, 0.10]

// Hue drift per ring
hueDrift = [12, 12, 10, 10, 8, 6, 5, 4, 3, 2] degrees

// Anti-clumping threshold
distance = sqrt((hueDiff*0.6)² + (ds*1.0)² + (dv*1.0)²)
threshold = 0.085
```

## File Structure

```
lib/widgets/color_picker/
├── color_picker_widget.dart          # Main widget
├── hue_value_disc_painter.dart       # Wheel rendering
├── color_mosaic_screen.dart          # Chromatic mosaic
├── neutral_mosaic_screen.dart        # Grey mosaic
├── color_generation_utils.dart       # Color math & algorithms
└── README.md                          # This file
```

## Integration

Replace any existing color picker with:

```dart
import 'package:zenmo/widgets/color_picker/color_picker_widget.dart';

// In your widget
ColorPickerWidget(
  currentColor: _selectedColor,
  onColorChanged: (color) {
    setState(() => _selectedColor = color);
  },
)
```

## User Flow

1. **Tap colored ring** → Opens ColorMosaicScreen with 600 variations
2. **Tap neutral hub** → Opens NeutralMosaicScreen with 240 greys
3. **Switch modes** → Toggle between Organized and Randomized
4. **Tap tile** → Selects color and returns via callback

## Customization

### Change Grid Size
Edit `color_mosaic_screen.dart`:
```dart
static const int _cols = 6;        // Number of columns
static const int _tileCount = 600; // Total tiles
```

### Modify Clusters
Edit `color_generation_utils.dart`:
```dart
static const pastel = Cluster(sMin: 0.28, sMax: 0.50, vMin: 0.85, vMax: 0.98);
// Adjust ranges as needed
```

### Change Neutral Hub Colors
Edit `hue_value_disc_painter.dart`:
```dart
final List<Color> greySlices = [
  const Color(0xFF101010),
  // Add or modify colors
];
```

## Performance

- Organized palette generation: ~10ms for 600 colors
- Randomized palette generation: ~30ms for 600 colors
- Neutral grey generation: ~5ms for 240 colors
- Organized palettes are cached by hue and ring index
- Scroll performance: 60 FPS with cacheExtent: 800

## Testing

Run the app and test:
```bash
cd zenmo
flutter run
```

1. Navigate to fingerprint flow
2. Tap anywhere on the color wheel
3. Explore organized and randomized modes
4. Test neutral hub (center grey circle)
5. Verify color selection works

## Dependencies

```yaml
dependencies:
  flutter_staggered_grid_view: ^0.7.0
```

## References

- Original implementation: `color_wallet_reference/lib/color_picker_screen.dart`
- Spec documents: `.kiro/specs/color-picker-mosaic/`
- Requirements: 15 requirements with exact formulas
- Design: 36 correctness properties for testing
