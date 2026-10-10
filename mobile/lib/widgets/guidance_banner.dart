import 'package:flutter/material.dart';

import '../face_tracking/tracking_state.dart';

/// Floating hint telling the user how to get a usable face detection.
class GuidanceBanner extends StatelessWidget {
  const GuidanceBanner({super.key, required this.status});

  final TrackingStatus status;

  @override
  Widget build(BuildContext context) {
    final text = status.guidance;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: text == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : Container(
              key: ValueKey(status),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      text,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  IconData get _icon => switch (status) {
        TrackingStatus.multipleFaces => Icons.groups_outlined,
        TrackingStatus.tooFar => Icons.zoom_in,
        TrackingStatus.unsupportedAngle => Icons.screen_rotation_alt,
        TrackingStatus.eyesNotFound => Icons.visibility_off_outlined,
        TrackingStatus.initializing => Icons.face_retouching_natural,
        _ => Icons.face_outlined,
      };
}
