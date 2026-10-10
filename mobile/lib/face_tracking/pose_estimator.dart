import 'dart:ui';

import 'eye_pose.dart';
import 'one_euro_filter.dart';
import 'tracking_state.dart';

/// Detector-agnostic description of one detected face (decouples the fitting
/// logic from ML Kit so it can be unit-tested).
class DetectedFace {
  const DetectedFace({
    required this.boundingBox,
    this.leftEye,
    this.rightEye,
    this.yawDegrees,
    this.rollDegrees,
    this.pitchDegrees,
  });

  final Rect boundingBox;
  final Offset? leftEye;
  final Offset? rightEye;
  final double? yawDegrees;
  final double? rollDegrees;
  final double? pitchDegrees;
}

/// Limits beyond which a flat 2D overlay looks wrong, so we hide it.
class PoseLimits {
  const PoseLimits({
    this.maxYawDegrees = 28,
    this.maxPitchDegrees = 25,
    this.maxRollDegrees = 35,
    this.minFaceWidthFraction = 0.12,
  });

  final double maxYawDegrees;
  final double maxPitchDegrees;
  final double maxRollDegrees;

  /// Faces narrower than this fraction of the image are too far away for
  /// reliable eye landmarks.
  final double minFaceWidthFraction;
}

/// Turns raw detections into a stable [TrackingResult]:
/// validates the scene (one face, eyes visible, supported angle), smooths the
/// eye pose with 1€ filters and briefly holds the last pose to bridge single
/// dropped frames.
class PoseEstimator {
  PoseEstimator({this.limits = const PoseLimits(), this.holdDuration = const Duration(milliseconds: 250)});

  final PoseLimits limits;

  /// How long to keep showing the last pose when the face is momentarily lost.
  final Duration holdDuration;

  // Filters operate on coordinates normalised by image width so the tuning
  // does not depend on camera resolution.
  final _cx = OneEuroFilter(minCutoff: 1.2, beta: 3.0);
  final _cy = OneEuroFilter(minCutoff: 1.2, beta: 3.0);
  final _dist = OneEuroFilter(minCutoff: 0.8, beta: 2.0);
  final _roll = OneEuroFilter(minCutoff: 1.0, beta: 0.6);

  TrackingResult? _lastGood;
  double? _lastGoodTime;

  void reset() {
    for (final f in [_cx, _cy, _dist, _roll]) {
      f.reset();
    }
    _lastGood = null;
    _lastGoodTime = null;
  }

  /// Validates detections without smoothing (used for still photos).
  static (TrackingStatus, EyePose?) evaluate(
    List<DetectedFace> faces,
    Size imageSize,
    PoseLimits limits,
  ) {
    if (faces.isEmpty) return (TrackingStatus.noFace, null);
    if (faces.length > 1) return (TrackingStatus.multipleFaces, null);
    final face = faces.single;
    if (face.boundingBox.width < imageSize.width * limits.minFaceWidthFraction) {
      return (TrackingStatus.tooFar, null);
    }
    final yaw = face.yawDegrees ?? 0;
    final pitch = face.pitchDegrees ?? 0;
    final roll = face.rollDegrees ?? 0;
    if (yaw.abs() > limits.maxYawDegrees ||
        pitch.abs() > limits.maxPitchDegrees ||
        roll.abs() > limits.maxRollDegrees) {
      return (TrackingStatus.unsupportedAngle, null);
    }
    final l = face.leftEye;
    final r = face.rightEye;
    if (l == null || r == null || (l - r).distance < 4) {
      return (TrackingStatus.eyesNotFound, null);
    }
    return (
      TrackingStatus.tracking,
      EyePose.fromEyes(l, r, yawDegrees: yaw, pitchDegrees: pitch),
    );
  }

  /// Processes one video frame. [timeSeconds] must be monotonic.
  TrackingResult update(
    List<DetectedFace> faces,
    Size imageSize,
    double timeSeconds, {
    bool mirror = false,
  }) {
    final (status, raw) = evaluate(faces, imageSize, limits);
    if (status != TrackingStatus.tracking || raw == null) {
      final last = _lastGood;
      final lastTime = _lastGoodTime;
      final holdSeconds = holdDuration.inMicroseconds / 1e6;
      // Bridge brief drop-outs (blinks, motion blur) only when no face at all
      // was found; other states (e.g. multiple faces) hide immediately.
      if (status == TrackingStatus.noFace &&
          last != null &&
          lastTime != null &&
          timeSeconds - lastTime <= holdSeconds) {
        return last;
      }
      reset();
      return TrackingResult(status: status, imageSize: imageSize, mirror: mirror);
    }

    final w = imageSize.width;
    final smoothed = EyePose(
      center: Offset(
        _cx.filter(raw.center.dx / w, timeSeconds) * w,
        _cy.filter(raw.center.dy / w, timeSeconds) * w,
      ),
      eyeDistance: _dist.filter(raw.eyeDistance / w, timeSeconds) * w,
      rollRadians: _roll.filter(raw.rollRadians, timeSeconds),
      yawDegrees: raw.yawDegrees,
      pitchDegrees: raw.pitchDegrees,
    );
    final result = TrackingResult(
      status: TrackingStatus.tracking,
      pose: smoothed,
      imageSize: imageSize,
      mirror: mirror,
    );
    _lastGood = result;
    _lastGoodTime = timeSeconds;
    return result;
  }
}
