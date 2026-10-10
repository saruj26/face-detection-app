import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:glasses_tryon/face_tracking/one_euro_filter.dart';
import 'package:glasses_tryon/face_tracking/pose_estimator.dart';
import 'package:glasses_tryon/face_tracking/tracking_state.dart';

const imageSize = Size(720, 1280);

DetectedFace face({
  Rect box = const Rect.fromLTWH(200, 400, 320, 400),
  Offset? left = const Offset(300, 550),
  Offset? right = const Offset(420, 550),
  double yaw = 0,
  double roll = 0,
  double pitch = 0,
}) =>
    DetectedFace(
      boundingBox: box,
      leftEye: left,
      rightEye: right,
      yawDegrees: yaw,
      rollDegrees: roll,
      pitchDegrees: pitch,
    );

void main() {
  group('PoseEstimator.evaluate', () {
    const limits = PoseLimits();

    TrackingStatus status(List<DetectedFace> faces) =>
        PoseEstimator.evaluate(faces, imageSize, limits).$1;

    test('no face', () => expect(status([]), TrackingStatus.noFace));
    test('multiple faces', () => expect(status([face(), face()]), TrackingStatus.multipleFaces));
    test('face too small', () {
      expect(status([face(box: const Rect.fromLTWH(0, 0, 50, 60))]), TrackingStatus.tooFar);
    });
    test('turned head is unsupported', () {
      expect(status([face(yaw: 40)]), TrackingStatus.unsupportedAngle);
      expect(status([face(pitch: -30)]), TrackingStatus.unsupportedAngle);
      expect(status([face(roll: 50)]), TrackingStatus.unsupportedAngle);
    });
    test('missing eye landmarks', () {
      expect(status([face(right: null)]), TrackingStatus.eyesNotFound);
    });
    test('valid single face produces a pose', () {
      final (s, pose) = PoseEstimator.evaluate([face()], imageSize, limits);
      expect(s, TrackingStatus.tracking);
      expect(pose!.center, const Offset(360, 550));
      expect(pose.eyeDistance, 120);
    });
  });

  group('PoseEstimator.update', () {
    test('holds the last pose briefly when the face disappears, then hides', () {
      final est = PoseEstimator(holdDuration: const Duration(milliseconds: 250));
      expect(est.update([face()], imageSize, 0.0).hasPose, isTrue);
      expect(est.update([], imageSize, 0.1).hasPose, isTrue); // within hold
      expect(est.update([], imageSize, 0.5).hasPose, isFalse); // lost
      expect(est.update([], imageSize, 0.5).status, TrackingStatus.noFace);
    });

    test('multiple faces hide immediately', () {
      final est = PoseEstimator();
      est.update([face()], imageSize, 0.0);
      final r = est.update([face(), face()], imageSize, 0.03);
      expect(r.hasPose, isFalse);
      expect(r.status, TrackingStatus.multipleFaces);
    });

    test('smoothing reduces jitter of a still face', () {
      final est = PoseEstimator();
      final rnd = math.Random(1);
      final rawX = <double>[];
      final smoothX = <double>[];
      for (var i = 0; i < 120; i++) {
        final jitter = (rnd.nextDouble() - 0.5) * 8; // ±4 px landmark noise
        rawX.add(300 + jitter);
        final r = est.update(
          [face(left: Offset(300 + jitter, 550), right: Offset(420 + jitter, 550))],
          imageSize,
          i / 30,
        );
        smoothX.add(r.pose!.center.dx);
      }
      double variance(List<double> v) {
        final tail = v.sublist(30);
        final mean = tail.reduce((a, b) => a + b) / tail.length;
        return tail.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / tail.length;
      }

      expect(variance(smoothX), lessThan(variance(rawX) * 0.5));
    });

    test('mirror flag is carried through', () {
      final est = PoseEstimator();
      expect(est.update([face()], imageSize, 0, mirror: true).mirror, isTrue);
    });
  });

  group('OneEuroFilter', () {
    test('first value passes through', () {
      expect(OneEuroFilter().filter(5, 0), 5);
    });

    test('constant input stays constant', () {
      final f = OneEuroFilter(minCutoff: 1, beta: 0.5);
      for (var i = 0; i < 30; i++) {
        expect(f.filter(3, i / 30), closeTo(3, 1e-12));
      }
    });

    test('converges to a step change', () {
      final f = OneEuroFilter(minCutoff: 1, beta: 1);
      f.filter(0, 0);
      var y = 0.0;
      for (var i = 1; i <= 60; i++) {
        y = f.filter(10, i / 30);
      }
      expect(y, closeTo(10, 0.05));
    });

    test('higher beta follows fast motion with less lag', () {
      final slow = OneEuroFilter(minCutoff: 1, beta: 0);
      final fast = OneEuroFilter(minCutoff: 1, beta: 5);
      double ys = 0, yf = 0;
      for (var i = 0; i < 10; i++) {
        final x = i * 10.0; // moving quickly
        ys = slow.filter(x, i / 30);
        yf = fast.filter(x, i / 30);
      }
      expect((90 - yf).abs(), lessThan((90 - ys).abs()));
    });

    test('reset forgets history', () {
      final f = OneEuroFilter();
      f.filter(100, 0);
      f.reset();
      expect(f.isInitialized, isFalse);
      expect(f.filter(1, 1), 1);
    });
  });
}
