import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'coordinate_mapper.dart';
import 'pose_estimator.dart';
import 'tracking_state.dart';

/// On-device face tracking with Google ML Kit.
///
/// * Live frames use a fast detector; only one frame is processed at a time
///   (frames arriving while busy are dropped), so inference never piles up.
/// * Still photos use a separate accurate-mode detector, created lazily.
/// * Images never leave the device.
class FaceTracker {
  FaceTracker({PoseLimits limits = const PoseLimits()})
      : _limits = limits,
        _estimator = PoseEstimator(limits: limits);

  final PoseLimits _limits;
  final PoseEstimator _estimator;
  final Stopwatch _clock = Stopwatch()..start();

  final FaceDetector _liveDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: true,
      enableContours: false,
      enableClassification: false,
      enableTracking: false,
      minFaceSize: 0.1,
    ),
  );
  FaceDetector? _stillDetector;

  bool _busy = false;
  bool _closed = false;

  bool get isBusy => _busy;

  void reset() => _estimator.reset();

  /// Processes a camera frame. Returns null if the frame was skipped (busy,
  /// closed or unsupported format); callers should keep the previous result.
  Future<TrackingResult?> processCameraImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) async {
    if (_busy || _closed) return null;
    _busy = true;
    try {
      final frame = _toInputImage(image, camera, deviceOrientation);
      if (frame == null) return null;
      final faces = await _liveDetector.processImage(frame.input);
      if (_closed) return null;
      return _estimator.update(
        faces.map(_toDetected).toList(growable: false),
        frame.geometry.uprightSize,
        _clock.elapsedMicroseconds / 1e6,
        mirror: frame.geometry.mirror,
      );
    } on PlatformException catch (e) {
      debugPrint('Face detection failed: ${e.code}');
      return null;
    } finally {
      _busy = false;
    }
  }

  /// Detects the face in an upright still photo (see normalizePhoto) of
  /// [imageSize] pixels. No smoothing is applied.
  Future<TrackingResult> processPhoto(String path, Size imageSize) async {
    final detector = _stillDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        minFaceSize: 0.05,
      ),
    );
    final faces = await detector.processImage(InputImage.fromFilePath(path));
    final (status, pose) = PoseEstimator.evaluate(
      faces.map(_toDetected).toList(growable: false),
      imageSize,
      _limits,
    );
    return TrackingResult(status: status, pose: pose, imageSize: imageSize);
  }

  Future<void> close() async {
    _closed = true;
    await _liveDetector.close();
    await _stillDetector?.close();
  }

  static DetectedFace _toDetected(Face face) {
    Offset? eye(FaceLandmarkType type) {
      final p = face.landmarks[type]?.position;
      return p == null ? null : Offset(p.x.toDouble(), p.y.toDouble());
    }

    return DetectedFace(
      boundingBox: face.boundingBox,
      leftEye: eye(FaceLandmarkType.leftEye),
      rightEye: eye(FaceLandmarkType.rightEye),
      yawDegrees: face.headEulerAngleY,
      rollDegrees: face.headEulerAngleZ,
      pitchDegrees: face.headEulerAngleX,
    );
  }

  static const _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// CameraImage -> ML Kit InputImage (NV21 on Android, BGRA8888 on iOS),
  /// following the official google_mlkit_flutter example.
  static ({InputImage input, CameraFrameGeometry geometry})? _toInputImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final isFront = camera.lensDirection == CameraLensDirection.front;
    final int rotationDegrees;
    if (Platform.isIOS) {
      rotationDegrees = camera.sensorOrientation;
    } else {
      final device = _orientationDegrees[deviceOrientation];
      if (device == null) return null;
      rotationDegrees = androidRotationCompensation(
        sensorOrientation: camera.sensorOrientation,
        deviceOrientationDegrees: device,
        isFrontCamera: isFront,
      );
    }
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    final rawSize = Size(image.width.toDouble(), image.height.toDouble());

    return (
      input: InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: rawSize,
          rotation: rotation, // used on Android
          format: format, // used on iOS
          bytesPerRow: plane.bytesPerRow, // used on iOS
        ),
      ),
      geometry: CameraFrameGeometry.forFrame(
        rawSize: rawSize,
        rotationDegrees: rotationDegrees,
        isFrontCamera: isFront,
        isIOS: Platform.isIOS,
      ),
    );
  }
}
