import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../face_tracking/coordinate_mapper.dart';
import '../face_tracking/glasses_placement.dart';
import '../face_tracking/tracking_state.dart';
import '../models/fit_adjustment.dart';
import '../models/glasses.dart';

/// Paints the glasses overlay for the live camera preview.
///
/// Placed inside the same box as the camera preview (sized to the preview's
/// portrait size); [FitMode.cover] then accounts for any aspect-ratio
/// difference between the analysed frames and the preview stream. The outer
/// FittedBox handles cropping to the screen.
class LiveOverlayPainter extends CustomPainter {
  LiveOverlayPainter({
    required this.tracking,
    required this.overlay,
    required this.fit,
    required this.adjustment,
  }) : super(repaint: tracking);

  final ValueNotifier<TrackingResult> tracking;
  final ui.Image? overlay;
  final FitMetadata? fit;
  final FitAdjustment adjustment;

  @override
  void paint(Canvas canvas, Size size) {
    final result = tracking.value;
    final image = overlay;
    final fitMeta = fit;
    if (!result.hasPose || image == null || fitMeta == null) return;
    final mapper = CoordinateMapper(
      sourceSize: result.imageSize!,
      targetSize: size,
      fit: FitMode.cover,
      mirror: result.mirror,
    );
    GlassesPlacement.compute(
      pose: result.pose!.mapWith(mapper),
      fit: fitMeta,
      adjustment: adjustment,
    ).paint(canvas, image);
  }

  @override
  bool shouldRepaint(LiveOverlayPainter old) =>
      old.overlay != overlay || old.fit != fit || old.adjustment != adjustment;
}

/// Paints a still photo (letterboxed) with the glasses overlay.
class PhotoTryOnPainter extends CustomPainter {
  PhotoTryOnPainter({
    required this.photo,
    required this.tracking,
    required this.overlay,
    required this.fit,
    required this.adjustment,
  });

  final ui.Image photo;
  final TrackingResult tracking;
  final ui.Image? overlay;
  final FitMetadata? fit;
  final FitAdjustment adjustment;

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(photo.width.toDouble(), photo.height.toDouble());
    final mapper = CoordinateMapper(sourceSize: imageSize, targetSize: size, fit: FitMode.contain);
    canvas.drawImageRect(
      photo,
      Offset.zero & imageSize,
      mapper.imageRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final image = overlay;
    final fitMeta = fit;
    if (!tracking.hasPose || image == null || fitMeta == null) return;
    GlassesPlacement.compute(
      pose: tracking.pose!.mapWith(mapper),
      fit: fitMeta,
      adjustment: adjustment,
    ).paint(canvas, image);
  }

  @override
  bool shouldRepaint(PhotoTryOnPainter old) =>
      old.photo != photo ||
      old.tracking != tracking ||
      old.overlay != overlay ||
      old.fit != fit ||
      old.adjustment != adjustment;
}

/// Renders the photo + glasses at the photo's full resolution and returns PNG
/// bytes, ready to be saved to the gallery.
Future<Uint8List> renderTryOnPng({
  required ui.Image photo,
  required TrackingResult tracking,
  required ui.Image overlay,
  required FitMetadata fit,
  required FitAdjustment adjustment,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(photo, Offset.zero, Paint());
  if (tracking.hasPose) {
    // Pose is already in photo pixel space: no mapping needed.
    GlassesPlacement.compute(pose: tracking.pose!, fit: fit, adjustment: adjustment)
        .paint(canvas, overlay);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(photo.width, photo.height);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Could not encode image');
  return data.buffer.asUint8List();
}
