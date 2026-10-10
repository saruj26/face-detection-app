import 'dart:math' as math;
import 'dart:ui';

/// How the source image is fitted into the target widget.
enum FitMode {
  /// Fill the target, cropping the overflowing side (camera preview).
  cover,

  /// Show the whole image, letterboxing the remaining space (still photos).
  contain,
}

/// Maps points from upright image space (the space ML Kit reports landmarks
/// in, after rotation) to widget space.
///
/// Handles uniform scaling, centring/cropping for [FitMode.cover] and
/// letterboxing for [FitMode.contain], and horizontal mirroring for front
/// camera previews.
class CoordinateMapper {
  CoordinateMapper({
    required this.sourceSize,
    required this.targetSize,
    this.fit = FitMode.cover,
    this.mirror = false,
  }) : assert(sourceSize.width > 0 && sourceSize.height > 0) {
    final sx = targetSize.width / sourceSize.width;
    final sy = targetSize.height / sourceSize.height;
    scale = fit == FitMode.cover ? math.max(sx, sy) : math.min(sx, sy);
    dx = (targetSize.width - sourceSize.width * scale) / 2;
    dy = (targetSize.height - sourceSize.height * scale) / 2;
  }

  final Size sourceSize;
  final Size targetSize;
  final FitMode fit;
  final bool mirror;

  late final double scale;
  late final double dx;
  late final double dy;

  Offset mapPoint(Offset p) {
    final x = mirror ? sourceSize.width - p.dx : p.dx;
    return Offset(x * scale + dx, p.dy * scale + dy);
  }

  double mapLength(double length) => length * scale;

  /// The rectangle the full source image occupies in widget space (may extend
  /// beyond the widget for [FitMode.cover]).
  Rect get imageRect =>
      Rect.fromLTWH(dx, dy, sourceSize.width * scale, sourceSize.height * scale);
}

/// Geometry of one camera frame relative to what the user sees.
class CameraFrameGeometry {
  const CameraFrameGeometry({required this.uprightSize, required this.mirror});

  /// Size of the frame after rotation to upright (portrait) orientation.
  /// ML Kit landmark coordinates are reported in this space.
  final Size uprightSize;

  /// Whether the on-screen preview is a mirror image of the frame.
  final bool mirror;

  /// [rawSize] is CameraImage.width/height, [rotationDegrees] the rotation
  /// passed to ML Kit.
  ///
  /// * Android: buffers are in sensor orientation; ML Kit rotates them, so a
  ///   90/270° rotation swaps width and height. The front-camera preview is
  ///   mirrored but the analysed buffer is not, so x must be flipped.
  /// * iOS: the camera plugin already delivers upright, mirrored (front)
  ///   buffers, matching the preview, so no swap or flip is needed.
  factory CameraFrameGeometry.forFrame({
    required Size rawSize,
    required int rotationDegrees,
    required bool isFrontCamera,
    required bool isIOS,
  }) {
    if (isIOS) {
      return CameraFrameGeometry(uprightSize: rawSize, mirror: false);
    }
    final swap = rotationDegrees == 90 || rotationDegrees == 270;
    return CameraFrameGeometry(
      uprightSize: swap ? Size(rawSize.height, rawSize.width) : rawSize,
      mirror: isFrontCamera,
    );
  }
}

/// Rotation (degrees) ML Kit needs to make an Android camera buffer upright.
/// Mirrors the logic of the official google_mlkit example.
int androidRotationCompensation({
  required int sensorOrientation,
  required int deviceOrientationDegrees,
  required bool isFrontCamera,
}) {
  if (isFrontCamera) {
    return (sensorOrientation + deviceOrientationDegrees) % 360;
  }
  return (sensorOrientation - deviceOrientationDegrees + 360) % 360;
}
