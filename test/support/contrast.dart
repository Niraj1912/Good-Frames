import 'package:flutter/painting.dart';

// WCAG's contrast ratio: 4.5 or more is readable for normal-size text.
double contrast(Color a, Color b) {
  final (light, dark) = a.computeLuminance() > b.computeLuminance()
      ? (a, b)
      : (b, a);
  return (light.computeLuminance() + 0.05) / (dark.computeLuminance() + 0.05);
}
