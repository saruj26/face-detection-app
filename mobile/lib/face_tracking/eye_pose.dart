import 'dart:math' as math;
import 'dart:ui';

import 'coordinate_mapper.dart';

/// Position of the eyes in upright image space, plus head rotation reported by
/// the detector. This is all the 2D try-on needs.
class EyePose {
  const EyePose({
    required this.center,
    required this.eyeDistance,
    required this.rollRadians,
    this.yawDegrees = 0,
    this.pitchDegrees = 0,
  });

  /// Construct from two eye centres in any order.
  factory EyePose.fromEyes(
    Offset eyeA,
    Offset eyeB, {
    double yawDegrees = 0,
    double pitchDegrees = 0,
  }) {
    // Order by x so the roll angle stays in (-90°, 90°).
    final left = eyeA.dx <= eyeB.dx ? eyeA : eyeB;
    final right = identical(left, eyeA) ? eyeB : eyeA;
    final d = right - left;
    return EyePose(
      center: Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2),
      eyeDistance: d.distance,
      rollRadians: math.atan2(d.dy, d.dx),
      yawDegrees: yawDegrees,
      pitchDegrees: pitchDegrees,
    );
  }

  /// Midpoint between the eyes.
  final Offset center;

  /// Distance between the eye centres (same units as [center]).
  final double eyeDistance;

  /// In-plane rotation of the line through the eyes.
  final double rollRadians;

  /// Head turn left/right and up/down as reported by ML Kit (degrees).
  final double yawDegrees;
  final double pitchDegrees;

  Offset get leftEye => center - _halfVector;
  Offset get rightEye => center + _halfVector;

  Offset get _halfVector => Offset(
        math.cos(rollRadians) * eyeDistance / 2,
        math.sin(rollRadians) * eyeDistance / 2,
      );

  /// The same pose in widget space. Both eyes are mapped (so mirroring flips
  /// the roll direction correctly) and the pose is rebuilt from them.
  EyePose mapWith(CoordinateMapper mapper) => EyePose.fromEyes(
        mapper.mapPoint(leftEye),
        mapper.mapPoint(rightEye),
        yawDegrees: yawDegrees,
        pitchDegrees: pitchDegrees,
      );
}
