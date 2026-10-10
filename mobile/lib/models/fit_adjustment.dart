/// Optional manual tweaks applied on top of the automatic fit.
///
/// Offsets are expressed as fractions of the detected eye distance so they
/// behave the same at any distance from the camera or image resolution.
class FitAdjustment {
  const FitAdjustment({this.scale = 1.0, this.offsetX = 0.0, this.offsetY = 0.0});

  static const identity = FitAdjustment();

  static const minScale = 0.75;
  static const maxScale = 1.3;
  static const maxOffsetX = 0.3;
  static const maxOffsetY = 0.4;

  final double scale;
  final double offsetX;
  final double offsetY;

  bool get isIdentity => scale == 1.0 && offsetX == 0.0 && offsetY == 0.0;

  FitAdjustment copyWith({double? scale, double? offsetX, double? offsetY}) {
    return FitAdjustment(
      scale: (scale ?? this.scale).clamp(minScale, maxScale).toDouble(),
      offsetX: (offsetX ?? this.offsetX).clamp(-maxOffsetX, maxOffsetX).toDouble(),
      offsetY: (offsetY ?? this.offsetY).clamp(-maxOffsetY, maxOffsetY).toDouble(),
    );
  }
}
