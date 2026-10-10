import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;

import '../models/fit_adjustment.dart';
import '../models/glasses.dart';
import 'eye_pose.dart';

/// Where and how to draw the overlay PNG, in the same coordinate space as the
/// [EyePose] it was computed from (widget space on screen, image pixels when
/// exporting).
class GlassesPlacement {
  const GlassesPlacement({
    required this.anchor,
    required this.width,
    required this.height,
    required this.rotationRadians,
    required this.anchorX,
    required this.anchorY,
  });

  /// Point the PNG anchor is placed on.
  final Offset anchor;
  final double width;
  final double height;
  final double rotationRadians;

  /// Normalised anchor inside the PNG.
  final double anchorX;
  final double anchorY;

  /// Overlay rectangle in the rotated local frame centred on [anchor].
  Rect get localRect => Rect.fromLTWH(-anchorX * width, -anchorY * height, width, height);

  /// Purely 2D placement:
  /// * width from the eye distance and the frame's [FitMetadata.eyeSpanRatio]
  /// * rotation from the roll of the line through the eyes
  /// * anchor at the eye midpoint, optionally nudged by [adjustment]
  ///   (offsets are fractions of the eye distance, applied along the rotated
  ///   axes so "up" stays "up" for a tilted head).
  factory GlassesPlacement.compute({
    required EyePose pose,
    required FitMetadata fit,
    FitAdjustment adjustment = FitAdjustment.identity,
  }) {
    final width = pose.eyeDistance / fit.eyeSpanRatio * fit.defaultScale * adjustment.scale;
    final height = width / fit.aspectRatio;
    final c = math.cos(pose.rollRadians);
    final s = math.sin(pose.rollRadians);
    final ox = adjustment.offsetX * pose.eyeDistance;
    final oy = adjustment.offsetY * pose.eyeDistance;
    final anchor = pose.center + Offset(ox * c - oy * s, ox * s + oy * c);
    return GlassesPlacement(
      anchor: anchor,
      width: width,
      height: height,
      rotationRadians: pose.rollRadians,
      anchorX: fit.anchorX,
      anchorY: fit.anchorY,
    );
  }

  /// Transforms a point given in overlay-local normalised coordinates
  /// (0..1 across the PNG) to the output space. Used by tests and hit checks.
  Offset transformNormalized(Offset normalized) {
    final local = Offset((normalized.dx - anchorX) * width, (normalized.dy - anchorY) * height);
    final c = math.cos(rotationRadians);
    final s = math.sin(rotationRadians);
    return anchor + Offset(local.dx * c - local.dy * s, local.dx * s + local.dy * c);
  }

  /// Draws [overlay] onto [canvas].
  void paint(Canvas canvas, ui.Image overlay, {double opacity = 1.0}) {
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(rotationRadians);
    final src = Rect.fromLTWH(0, 0, overlay.width.toDouble(), overlay.height.toDouble());
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;
    if (opacity < 1.0) {
      paint.color = Color.fromRGBO(0, 0, 0, opacity);
    }
    canvas.drawImageRect(overlay, src, localRect, paint);
    canvas.restore();
  }
}
