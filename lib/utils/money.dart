/// Simple currency formatting helper
String dollars(int cents) {
  final v = (cents / 100).toStringAsFixed(2);
  return '\$$v';
}
