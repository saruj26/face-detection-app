import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:glasses_tryon/face_tracking/coordinate_mapper.dart';

void main() {
  group('CoordinateMapper', () {
    test('identity when sizes match', () {
      final m = CoordinateMapper(sourceSize: const Size(720, 1280), targetSize: const Size(720, 1280));
      expect(m.mapPoint(const Offset(100, 200)), const Offset(100, 200));
      expect(m.scale, 1);
    });

    test('uniform scale when aspect ratios match', () {
      final m = CoordinateMapper(sourceSize: const Size(720, 1280), targetSize: const Size(360, 640));
      expect(m.mapPoint(const Offset(720, 1280)), const Offset(360, 640));
      expect(m.mapLength(100), 50);
    });

    test('cover crops the overflowing axis symmetrically', () {
      // 3:4 image into a 9:16 screen: height-limited, sides cropped.
      final m = CoordinateMapper(
        sourceSize: const Size(480, 640),
        targetSize: const Size(360, 640),
        fit: FitMode.cover,
      );
      expect(m.scale, 1.0);
      expect(m.dx, -60); // (360 - 480) / 2
      expect(m.dy, 0);
      // Image centre stays at screen centre.
      expect(m.mapPoint(const Offset(240, 320)), const Offset(180, 320));
      expect(m.mapPoint(Offset.zero), const Offset(-60, 0));
    });

    test('contain letterboxes and keeps the whole image visible', () {
      final m = CoordinateMapper(
        sourceSize: const Size(1600, 1200),
        targetSize: const Size(400, 800),
        fit: FitMode.contain,
      );
      expect(m.scale, 0.25);
      expect(m.dx, 0);
      expect(m.dy, 250); // (800 - 300) / 2
      expect(m.imageRect, const Rect.fromLTWH(0, 250, 400, 300));
      expect(m.mapPoint(const Offset(1600, 1200)), const Offset(400, 550));
    });

    test('mirror flips x before scaling', () {
      final m = CoordinateMapper(
        sourceSize: const Size(720, 1280),
        targetSize: const Size(360, 640),
        mirror: true,
      );
      expect(m.mapPoint(const Offset(0, 0)), const Offset(360, 0));
      expect(m.mapPoint(const Offset(720, 1280)), const Offset(0, 640));
      expect(m.mapPoint(const Offset(180, 100)), const Offset(270, 50));
    });

    test('mirror + cover keeps the centre fixed', () {
      final m = CoordinateMapper(
        sourceSize: const Size(480, 640),
        targetSize: const Size(360, 640),
        mirror: true,
      );
      expect(m.mapPoint(const Offset(240, 320)), const Offset(180, 320));
      expect(m.mapPoint(const Offset(300, 320)).dx, closeTo(120, 1e-9));
    });
  });

  group('CameraFrameGeometry', () {
    test('Android portrait front camera: swap size and mirror', () {
      final g = CameraFrameGeometry.forFrame(
        rawSize: const Size(1280, 720),
        rotationDegrees: 270,
        isFrontCamera: true,
        isIOS: false,
      );
      expect(g.uprightSize, const Size(720, 1280));
      expect(g.mirror, isTrue);
    });

    test('Android portrait back camera: swap size, no mirror', () {
      final g = CameraFrameGeometry.forFrame(
        rawSize: const Size(1280, 720),
        rotationDegrees: 90,
        isFrontCamera: false,
        isIOS: false,
      );
      expect(g.uprightSize, const Size(720, 1280));
      expect(g.mirror, isFalse);
    });

    test('Android 0/180 rotation keeps size', () {
      final g = CameraFrameGeometry.forFrame(
        rawSize: const Size(1280, 720),
        rotationDegrees: 180,
        isFrontCamera: false,
        isIOS: false,
      );
      expect(g.uprightSize, const Size(1280, 720));
    });

    test('iOS buffers are already upright and mirrored', () {
      final g = CameraFrameGeometry.forFrame(
        rawSize: const Size(720, 1280),
        rotationDegrees: 90,
        isFrontCamera: true,
        isIOS: true,
      );
      expect(g.uprightSize, const Size(720, 1280));
      expect(g.mirror, isFalse);
    });
  });

  group('androidRotationCompensation', () {
    test('typical portrait values', () {
      expect(
        androidRotationCompensation(sensorOrientation: 270, deviceOrientationDegrees: 0, isFrontCamera: true),
        270,
      );
      expect(
        androidRotationCompensation(sensorOrientation: 90, deviceOrientationDegrees: 0, isFrontCamera: false),
        90,
      );
    });

    test('landscape compensation wraps correctly', () {
      expect(
        androidRotationCompensation(sensorOrientation: 270, deviceOrientationDegrees: 90, isFrontCamera: true),
        0,
      );
      expect(
        androidRotationCompensation(sensorOrientation: 90, deviceOrientationDegrees: 270, isFrontCamera: false),
        180,
      );
    });
  });
}
