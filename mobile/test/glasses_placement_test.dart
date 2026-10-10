import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:glasses_tryon/face_tracking/coordinate_mapper.dart';
import 'package:glasses_tryon/face_tracking/eye_pose.dart';
import 'package:glasses_tryon/face_tracking/glasses_placement.dart';
import 'package:glasses_tryon/models/fit_adjustment.dart';
import 'package:glasses_tryon/models/glasses.dart';

const fit = FitMetadata(
  imageWidth: 1000,
  imageHeight: 400,
  eyeSpanRatio: 0.25,
  anchorX: 0.5,
  anchorY: 0.5,
);

Matcher offsetCloseTo(Offset expected, [double eps = 1e-6]) => predicate<Offset>(
      (o) => (o - expected).distance < eps,
      'offset close to $expected',
    );

void main() {
  group('EyePose', () {
    test('level eyes', () {
      final p = EyePose.fromEyes(const Offset(100, 200), const Offset(200, 200));
      expect(p.center, const Offset(150, 200));
      expect(p.eyeDistance, 100);
      expect(p.rollRadians, 0);
    });

    test('eye order does not matter', () {
      final a = EyePose.fromEyes(const Offset(200, 220), const Offset(100, 200));
      final b = EyePose.fromEyes(const Offset(100, 200), const Offset(200, 220));
      expect(a.center, b.center);
      expect(a.rollRadians, closeTo(b.rollRadians, 1e-12));
    });

    test('mirroring flips the roll direction', () {
      final pose = EyePose.fromEyes(const Offset(100, 100), const Offset(200, 120));
      final mapper = CoordinateMapper(
        sourceSize: const Size(400, 400),
        targetSize: const Size(400, 400),
        mirror: true,
      );
      final mapped = pose.mapWith(mapper);
      expect(mapped.rollRadians, closeTo(-pose.rollRadians, 1e-9));
      expect(mapped.center, offsetCloseTo(const Offset(250, 110)));
      expect(mapped.eyeDistance, closeTo(pose.eyeDistance, 1e-9));
    });

    test('scaling the view scales the eye distance', () {
      final pose = EyePose.fromEyes(const Offset(300, 500), const Offset(420, 500));
      final mapper = CoordinateMapper(sourceSize: const Size(720, 1280), targetSize: const Size(360, 640));
      expect(pose.mapWith(mapper).eyeDistance, closeTo(60, 1e-9));
    });
  });

  group('GlassesPlacement', () {
    test('width from eye distance and eye span ratio', () {
      final pose = EyePose.fromEyes(const Offset(100, 200), const Offset(200, 200));
      final p = GlassesPlacement.compute(pose: pose, fit: fit);
      expect(p.width, closeTo(400, 1e-9)); // 100 / 0.25
      expect(p.height, closeTo(160, 1e-9)); // keeps 1000:400 aspect
      expect(p.anchor, const Offset(150, 200));
      expect(p.rotationRadians, 0);
      expect(p.localRect, const Rect.fromLTWH(-200, -80, 400, 160));
    });

    test('lens positions land on the eyes for a frame whose lens span equals the eye span', () {
      // Lenses at x = 0.375 and 0.625 => span 0.25 = eyeSpanRatio.
      final pose = EyePose.fromEyes(const Offset(120, 300), const Offset(220, 340));
      final p = GlassesPlacement.compute(pose: pose, fit: fit);
      expect(p.transformNormalized(const Offset(0.375, 0.5)), offsetCloseTo(const Offset(120, 300)));
      expect(p.transformNormalized(const Offset(0.625, 0.5)), offsetCloseTo(const Offset(220, 340)));
    });

    test('rotation follows head roll', () {
      final pose = EyePose.fromEyes(const Offset(0, 0), const Offset(100, 100));
      final p = GlassesPlacement.compute(pose: pose, fit: fit);
      expect(p.rotationRadians, closeTo(math.pi / 4, 1e-12));
    });

    test('manual adjustment scales and offsets along the rotated axes', () {
      final pose = EyePose.fromEyes(const Offset(100, 200), const Offset(200, 200));
      final p = GlassesPlacement.compute(
        pose: pose,
        fit: fit,
        adjustment: const FitAdjustment(scale: 1.2, offsetY: 0.1, offsetX: -0.2),
      );
      expect(p.width, closeTo(480, 1e-9));
      // offsetY 0.1 * eyeDistance(100) = 10 px down, offsetX -20 px.
      expect(p.anchor, offsetCloseTo(const Offset(130, 210)));

      // Tilted 90°: "down" in the face frame becomes -x on screen.
      const tilted = EyePose(center: Offset(0, 0), eyeDistance: 100, rollRadians: math.pi / 2);
      final q = GlassesPlacement.compute(
        pose: tilted,
        fit: fit,
        adjustment: const FitAdjustment(offsetY: 0.1),
      );
      expect(q.anchor, offsetCloseTo(const Offset(-10, 0)));
    });

    test('default scale from metadata is applied', () {
      const bigger = FitMetadata(imageWidth: 1000, imageHeight: 400, eyeSpanRatio: 0.25, defaultScale: 1.1);
      final pose = EyePose.fromEyes(const Offset(0, 0), const Offset(100, 0));
      expect(GlassesPlacement.compute(pose: pose, fit: bigger).width, closeTo(440, 1e-9));
    });

    test('end-to-end: image-space pose on a mirrored, cropped preview', () {
      // 720x1280 frame shown on a 360x640 widget (exact half), front camera.
      final pose = EyePose.fromEyes(const Offset(300, 500), const Offset(420, 500));
      final mapper = CoordinateMapper(
        sourceSize: const Size(720, 1280),
        targetSize: const Size(360, 640),
        mirror: true,
      );
      final p = GlassesPlacement.compute(pose: pose.mapWith(mapper), fit: fit);
      expect(p.anchor, offsetCloseTo(const Offset(180, 250))); // (720-360)/2 = 180
      expect(p.width, closeTo(240, 1e-9)); // 60 / 0.25
    });
  });

  test('FitAdjustment clamps to the allowed ranges', () {
    const a = FitAdjustment();
    final b = a.copyWith(scale: 5, offsetX: -2, offsetY: 2);
    expect(b.scale, FitAdjustment.maxScale);
    expect(b.offsetX, -FitAdjustment.maxOffsetX);
    expect(b.offsetY, FitAdjustment.maxOffsetY);
    expect(a.isIdentity, isTrue);
  });
}
