import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../face_tracking/face_tracker.dart';
import '../face_tracking/tracking_state.dart';
import '../models/fit_adjustment.dart';
import '../models/glasses.dart';
import '../providers/providers.dart';
import '../services/gallery_service.dart';
import '../services/image_normalizer.dart';
import '../widgets/adjust_panel.dart';
import '../widgets/frame_selector.dart';
import '../widgets/glasses_overlay_painter.dart';
import '../widgets/guidance_banner.dart';

enum _Mode { live, photo }

/// Live camera or still-photo virtual try-on.
///
/// The camera is only alive while this screen is shown and the app is in the
/// foreground. Faces are processed on-device; captured/picked photos are kept
/// in the app's temp directory only while displayed and are deleted afterwards
/// unless the user explicitly saves the composite to the gallery.
class TryOnScreen extends ConsumerStatefulWidget {
  const TryOnScreen({super.key});

  @override
  ConsumerState<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends ConsumerState<TryOnScreen> with WidgetsBindingObserver {
  final FaceTracker _tracker = FaceTracker();
  final ValueNotifier<TrackingResult> _tracking = ValueNotifier(TrackingResult.initial);
  final ImagePicker _picker = ImagePicker();
  final GalleryService _gallery = GalleryService();

  _Mode _mode = _Mode.live;

  // Live camera state
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  CameraController? _controller;
  bool _cameraStarting = false;
  String? _cameraError;
  bool _permissionProblem = false;

  // Photo state
  File? _photoFile;
  ui.Image? _photoImage;
  TrackingResult _photoTracking = TrackingResult.initial;

  String? _busyText;
  bool _showAdjust = false;
  bool _disposed = false;
  // The system photo picker sends the app to the background; don't restart
  // the camera on resume while it is open.
  bool _pickingPhoto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final launch = ref.read(tryOnLaunchProvider);
      ref.read(tryOnLaunchProvider.notifier).set(TryOnLaunch.live);
      if (launch == TryOnLaunch.pickPhoto) {
        _pickPhoto();
      } else {
        _initLiveCamera();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    _disposeController(controller);
    _tracker.close();
    _tracking.dispose();
    _photoImage?.dispose();
    deleteNormalizedPhoto(_photoFile);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_mode != _Mode.live || _pickingPhoto) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Release the camera in the background. `inactive` is ignored on
        // purpose: permission dialogs trigger it while the camera starts.
        if (!_cameraStarting) _stopCamera();
      case AppLifecycleState.resumed:
        // Also retries after the user granted permission in Settings.
        if (_controller == null && !_cameraStarting) _initLiveCamera();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  // ------------------------------------------------------------------ camera

  Future<void> _initLiveCamera() async {
    if (_disposed) return;
    _clearPhoto();
    setState(() {
      _mode = _Mode.live;
      _cameraError = null;
      _permissionProblem = false;
    });
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        final front = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
        _cameraIndex = front >= 0 ? front : 0;
      }
      if (_cameras.isEmpty) {
        _setCameraError('No camera was found on this device. You can still upload a photo.');
        return;
      }
      await _startCamera(_cameras[_cameraIndex]);
    } on CameraException catch (e) {
      _handleCameraException(e);
    }
  }

  Future<void> _startCamera(CameraDescription description) async {
    if (_cameraStarting || _disposed) return;
    _cameraStarting = true;
    try {
      await _stopCamera();
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        // Formats supported by ML Kit's byte input on each platform.
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      _controller = controller;
      _tracker.reset();
      _tracking.value = TrackingResult.initial;
      if (mounted) setState(() {});

      await controller.initialize();
      // The UI is portrait-only; keep capture/analysis orientation consistent.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (_disposed || _controller != controller) {
        await _disposeController(controller);
        return;
      }
      await controller.startImageStream((image) => _onFrame(image, controller));
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      _handleCameraException(e);
    } finally {
      _cameraStarting = false;
    }
  }

  void _onFrame(CameraImage image, CameraController controller) {
    // Drop frames while the previous one is still being analysed.
    if (_tracker.isBusy || _controller != controller || _mode != _Mode.live) return;
    final orientation =
        controller.value.lockedCaptureOrientation ?? controller.value.deviceOrientation;
    _tracker.processCameraImage(image, controller.description, orientation).then((result) {
      if (result != null && !_disposed && _controller == controller && _mode == _Mode.live) {
        _tracking.value = result;
      }
    });
  }

  Future<void> _stopCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    if (mounted && !_disposed) setState(() {});
    await _disposeController(controller);
  }

  Future<void> _disposeController(CameraController? controller) async {
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) await controller.stopImageStream();
    } on CameraException {
      // Already stopped.
    }
    await controller.dispose();
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _cameraStarting) return;
    final current = _cameras[_cameraIndex].lensDirection;
    final other = _cameras.indexWhere((c) => c.lensDirection != current);
    _cameraIndex = other >= 0 ? other : (_cameraIndex + 1) % _cameras.length;
    await _startCamera(_cameras[_cameraIndex]);
  }

  void _handleCameraException(CameraException e) {
    const permissionCodes = {
      'CameraAccessDenied',
      'CameraAccessDeniedWithoutPrompt',
      'CameraAccessRestricted',
    };
    final isPermission = permissionCodes.contains(e.code);
    _controller = null;
    _setCameraError(
      isPermission
          ? 'Camera access is needed for live try-on. Allow camera access for this app '
              'in your phone\'s Settings, then tap Retry. You can still upload a photo.'
          : 'The camera could not be started (${e.code}). Close other camera apps and try again.',
      permission: isPermission,
    );
  }

  void _setCameraError(String message, {bool permission = false}) {
    if (!mounted || _disposed) return;
    setState(() {
      _cameraError = message;
      _permissionProblem = permission;
    });
  }

  // ------------------------------------------------------------------ photos

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture) {
      return;
    }
    _setBusy('Capturing…');
    try {
      if (controller.value.isStreamingImages) await controller.stopImageStream();
      final shot = await controller.takePicture();
      // Android front-camera captures are not mirrored, unlike the preview;
      // mirror them so the photo matches what the user just saw.
      final mirror =
          Platform.isAndroid && controller.description.lensDirection == CameraLensDirection.front;
      await _stopCamera();
      await _loadPhoto(shot.path, mirror: mirror, deleteSource: true);
    } on CameraException catch (e) {
      _snack('Could not take a photo: ${e.description ?? e.code}');
      unawaited(_initLiveCamera());
    } finally {
      _setBusy(null);
    }
  }

  Future<void> _pickPhoto() async {
    XFile? picked;
    _pickingPhoto = true;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      _snack('Could not open your photos: ${e.message ?? e.code}');
    } finally {
      _pickingPhoto = false;
    }
    if (_disposed) return;
    if (picked == null) {
      // Cancelled: make sure the live camera is running again if we were in
      // live mode (it may have been released while the picker was open).
      if (_mode == _Mode.live && _controller == null) {
        unawaited(_initLiveCamera());
      }
      return;
    }
    await _stopCamera();
    await _loadPhoto(picked.path, mirror: false);
  }

  Future<void> _loadPhoto(String path, {required bool mirror, bool deleteSource = false}) async {
    _setBusy('Detecting face…');
    File? normalized;
    try {
      normalized = await normalizePhoto(path, mirror: mirror);
      if (deleteSource) unawaited(deleteNormalizedPhoto(File(path)));
      final codec = await ui.instantiateImageCodec(await normalized.readAsBytes());
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final result = await _tracker.processPhoto(
        normalized.path,
        Size(image.width.toDouble(), image.height.toDouble()),
      );
      if (!mounted || _disposed) {
        image.dispose();
        await deleteNormalizedPhoto(normalized);
        return;
      }
      _clearPhoto();
      setState(() {
        _mode = _Mode.photo;
        _photoFile = normalized;
        _photoImage = image;
        _photoTracking = result;
        _cameraError = null;
      });
    } on FormatException {
      await deleteNormalizedPhoto(normalized);
      _snack('This image could not be read. Please choose a JPEG or PNG photo.');
      _fallBackToLiveIfEmpty();
    } on PlatformException catch (e) {
      await deleteNormalizedPhoto(normalized);
      _snack('Face detection failed: ${e.message ?? e.code}');
      _fallBackToLiveIfEmpty();
    } on FileSystemException {
      await deleteNormalizedPhoto(normalized);
      _snack('The photo could not be opened.');
      _fallBackToLiveIfEmpty();
    } finally {
      _setBusy(null);
    }
  }

  void _fallBackToLiveIfEmpty() {
    if (_mode == _Mode.live && _controller == null) unawaited(_initLiveCamera());
  }

  void _clearPhoto() {
    _photoImage?.dispose();
    _photoImage = null;
    unawaited(deleteNormalizedPhoto(_photoFile));
    _photoFile = null;
    _photoTracking = TrackingResult.initial;
  }

  Future<void> _save(Glasses glasses) async {
    final photo = _photoImage;
    if (photo == null) return;
    if (!_photoTracking.hasPose) {
      _snack('Nothing to save yet: no usable face was detected in this photo.');
      return;
    }
    _setBusy('Saving…');
    try {
      final overlay = await ref.read(overlayImageProvider(glasses.overlayImageUrl).future);
      final png = await renderTryOnPng(
        photo: photo,
        tracking: _photoTracking,
        overlay: overlay,
        fit: glasses.fit,
        adjustment: ref.read(fitAdjustmentProvider),
      );
      final result = await _gallery.savePng(png);
      _snack(switch (result) {
        SaveImageResult.saved => 'Saved to your gallery (album "${GalleryService.album}").',
        SaveImageResult.permissionDenied =>
          'Permission to save photos was denied. Allow Photos/Storage access for this app in Settings.',
        SaveImageResult.notEnoughSpace => 'Not enough storage space to save the image.',
        SaveImageResult.failed => 'The image could not be saved. Please try again.',
      });
    } catch (_) {
      _snack('The image could not be saved. Please try again.');
    } finally {
      _setBusy(null);
    }
  }

  // ---------------------------------------------------------------- helpers

  void _setBusy(String? text) {
    if (!mounted || _disposed) return;
    setState(() => _busyText = text);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(catalogueProvider);
    final items = switch (catalogue) {
      AsyncData(:final value) => value.items,
      _ => const <Glasses>[],
    };
    final selected = ref.watch(selectedGlassesProvider) ?? (items.isEmpty ? null : items.first);
    final adjustment = ref.watch(fitAdjustmentProvider);
    final ui.Image? overlay = selected == null
        ? null
        : switch (ref.watch(overlayImageProvider(selected.overlayImageUrl))) {
            AsyncData(:final value) => value,
            _ => null,
          };

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _mode == _Mode.live
                ? _buildLiveView(overlay, selected?.fit, adjustment)
                : _buildPhotoView(overlay, selected?.fit, adjustment),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const SizedBox(height: 8),
                if (_cameraError == null)
                  _mode == _Mode.live
                      ? ValueListenableBuilder<TrackingResult>(
                          valueListenable: _tracking,
                          builder: (_, r, _) => GuidanceBanner(
                            status: _controller == null ? TrackingStatus.initializing : r.status,
                          ),
                        )
                      : GuidanceBanner(status: _photoTracking.status),
                const Spacer(),
                if (_showAdjust)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: AdjustPanel(onClose: () => setState(() => _showAdjust = false)),
                  ),
                if (items.isNotEmpty)
                  FrameSelector(
                    items: items,
                    selected: selected,
                    onSelected: (g) => ref.read(selectedGlassesProvider.notifier).select(g),
                  )
                else if (catalogue.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                const SizedBox(height: 10),
                _buildActions(selected),
                const SizedBox(height: 10),
              ],
            ),
          ),
          if (_busyText != null) _BusyOverlay(text: _busyText!),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final canSwitch = _mode == _Mode.live && _cameras.length > 1 && _controller != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            _mode == _Mode.live ? 'Live try-on' : 'Photo try-on',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          _RoundIconButton(
            icon: Icons.tune,
            tooltip: 'Adjust fit',
            selected: _showAdjust,
            onPressed: () => setState(() => _showAdjust = !_showAdjust),
          ),
          if (canSwitch)
            _RoundIconButton(
              icon: Icons.cameraswitch_outlined,
              tooltip: 'Switch camera',
              onPressed: _switchCamera,
            ),
        ],
      ),
    );
  }

  Widget _buildActions(Glasses? selected) {
    final isLive = _mode == _Mode.live;
    final busy = _busyText != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _PillButton(
              icon: Icons.photo_library_outlined,
              label: 'Upload',
              onPressed: busy ? null : _pickPhoto,
            ),
          ),
          const SizedBox(width: 12),
          if (isLive)
            _ShutterButton(
              onPressed: busy || _controller == null ? null : _capture,
            )
          else
            _ShutterButton(
              icon: Icons.download_rounded,
              tooltip: 'Save to gallery',
              onPressed: busy || selected == null || !_photoTracking.hasPose
                  ? null
                  : () => _save(selected),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: _PillButton(
              icon: isLive ? Icons.info_outline : Icons.videocam_outlined,
              label: isLive ? 'Tips' : 'Live',
              onPressed: busy
                  ? null
                  : () => isLive ? _showTips() : unawaited(_initLiveCamera()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveView(ui.Image? overlay, FitMetadata? fit, FitAdjustment adjustment) {
    final error = _cameraError;
    if (error != null) {
      return _MessageView(
        icon: _permissionProblem ? Icons.no_photography_outlined : Icons.error_outline,
        message: error,
        actionLabel: 'Retry',
        onAction: _initLiveCamera,
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _MessageView(icon: null, message: 'Starting camera…', loading: true);
    }
    final previewSize = controller.value.previewSize!;
    // previewSize is reported in landscape; the UI is portrait.
    final portrait = Size(
      math.min(previewSize.width, previewSize.height),
      math.max(previewSize.width, previewSize.height),
    );
    return ClipRect(
      child: FittedBox(
        // Fill the screen; the overlay lives inside the same box as the
        // preview, so cropping/scaling apply to both identically.
        fit: BoxFit.cover,
        child: SizedBox(
          width: portrait.width,
          height: portrait.height,
          child: CameraPreview(
            controller,
            child: CustomPaint(
              painter: LiveOverlayPainter(
                tracking: _tracking,
                overlay: overlay,
                fit: fit,
                adjustment: adjustment,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoView(ui.Image? overlay, FitMetadata? fit, FitAdjustment adjustment) {
    final photo = _photoImage;
    if (photo == null) return const SizedBox.shrink();
    return CustomPaint(
      painter: PhotoTryOnPainter(
        photo: photo,
        tracking: _photoTracking,
        overlay: overlay,
        fit: fit,
        adjustment: adjustment,
      ),
    );
  }

  void _showTips() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('For the best fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            Text('• Hold the phone at eye level, about an arm\'s length away.'),
            Text('• Face the camera straight on. Turning more than ~25° hides the glasses.'),
            Text('• Use even, front-facing light; avoid strong backlight.'),
            Text('• Take off your own glasses for the cleanest preview.'),
            Text('• Use "Adjust fit" to fine-tune size and position.'),
            SizedBox(height: 12),
            Text(
              'This is a 2D overlay positioned from detected eye landmarks. It is an '
              'approximation of how a frame looks, not a measurement of fit.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ widgets

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });

  final IconData? icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) const CircularProgressIndicator(color: Colors.white),
            if (icon != null) Icon(icon, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton.filled(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: selected ? Colors.white : Colors.black45,
          foregroundColor: selected ? Colors.black : Colors.white,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.onPressed,
    this.icon = Icons.camera_alt_rounded,
    this.tooltip = 'Capture',
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? Colors.white : Colors.white38,
              border: Border.all(color: Colors.white70, width: 4),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
            ),
            child: Icon(icon, size: 32, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}
