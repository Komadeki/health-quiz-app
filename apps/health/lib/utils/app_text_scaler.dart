import 'package:flutter/painting.dart';

/// Keep the system's per-font-size accessibility scaling, then apply the
/// learner's explicit in-app size preference without flattening the curve.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.preference);
  final TextScaler system;
  final double preference;
  @override
  double scale(double fontSize) => system.scale(fontSize) * preference;
  @override
  double get textScaleFactor => scale(14) / 14;
}
