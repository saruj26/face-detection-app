import 'dart:ui';

import 'eye_pose.dart';

enum TrackingStatus {
  initializing,
  tracking,
  noFace,
  multipleFaces,
  tooFar,
  unsupportedAngle,
  eyesNotFound,
}

extension TrackingStatusText on TrackingStatus {
  /// User guidance shown above the preview, or null when tracking is fine.
  String? get guidance => switch (this) {
        TrackingStatus.initializing => 'Looking for your face…',
        TrackingStatus.tracking => null,
        TrackingStatus.noFace => 'No face detected. Center your face in good, even light.',
        TrackingStatus.multipleFaces =>
          'Multiple faces detected. Make sure only one person is in view.',
        TrackingStatus.tooFar => 'Move a little closer to the camera.',
        TrackingStatus.unsupportedAngle =>
          'Face the camera straight on. Side and tilted views are not supported.',
        TrackingStatus.eyesNotFound =>
          'Eyes not visible. Remove anything covering them and improve lighting.',
      };
}

/// Output of the tracker for one frame / photo. [pose] is in upright image
/// space ([imageSize]) and is only set while [status] is tracking.
class TrackingResult {
  const TrackingResult({
    required this.status,
    this.pose,
    this.imageSize,
    this.mirror = false,
  });

  static const initial = TrackingResult(status: TrackingStatus.initializing);

  final TrackingStatus status;
  final EyePose? pose;
  final Size? imageSize;
  final bool mirror;

  bool get hasPose => status == TrackingStatus.tracking && pose != null && imageSize != null;
}
