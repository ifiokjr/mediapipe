import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mp_camera/mp_camera.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_vision/mp_vision.dart';

const String _models = 'https://storage.googleapis.com/mediapipe-assets/tasks/testdata/vision/';

/// Owns one camera and one task. Reconfiguration and disposal are serialized so
/// a slow model download cannot resurrect a closed camera or overwrite a new mode.
final class TrackingSession extends ChangeNotifier {
  /// Creates an idle session; hardware is only opened by an explicit user action.
  TrackingSession();

  /// Camera for the preview, when initialized.
  CameraController? camera;

  /// Upright, unmirrored pose coordinates.
  List<NormalizedLandmark> pose = <NormalizedLandmark>[];

  /// Upright, unmirrored face coordinates.
  List<NormalizedLandmark> face = <NormalizedLandmark>[];

  /// User-facing startup, tracking, or failure status.
  String status = 'Try the demo, or switch on your camera.';

  /// Whether startup is in progress.
  bool loading = false;

  /// Latest successful image aspect ratio after rotation.
  double aspectRatio = 3 / 4;

  /// Timestamp of the latest successful inference.
  int timestampMs = 0;

  /// Latency of the latest inference, in milliseconds.
  int latencyMs = 0;
  FaceLandmarker? _faceTask;
  PoseLandmarker? _poseTask;
  LatestFrameScheduler<MpCameraFrame>? _scheduler;
  StreamSubscription<LatestFrameFailure<MpCameraFrame>>? _failures;
  Future<void> _operation = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  Timer? _watchdog;
  final Stopwatch _sinceResult = Stopwatch();

  /// Stops existing resources before opening the selected task and lens.
  Future<void> configure({required bool enabled, required bool faceMode, bool front = true}) {
    final int generation = ++_generation;
    loading = enabled;
    pose = <NormalizedLandmark>[];
    face = <NormalizedLandmark>[];
    _notify();
    return _operation = _operation.then((_) async {
      try {
        await _release();

        if (_disposed || generation != _generation) return;

        if (!enabled) {
          loading = false;
          status = 'Camera off · animated demo';
          _notify();
          return;
        }

        if (kIsWeb ||
            (defaultTargetPlatform != TargetPlatform.android &&
                defaultTargetPlatform != TargetPlatform.iOS)) {
          throw UnsupportedError('Live camera requires Android or iOS. Demo mode works here.');
        }

        status = 'Loading ${faceMode ? 'face' : 'pose'} model…';
        _notify();

        if (faceMode) {
          _faceTask = await FaceLandmarker.create(
            FaceLandmarkerOptions(
              baseOptions: BaseOptions(
                modelAsset: ModelAsset.uri(
                  Uri.parse('${_models}face_landmarker.task'),
                  sha256: '7cf2bbf1842c429e9defee38e7f1c4238978d8a6faf2da145bb19846f86bd2f4',
                ),
              ),
              runningMode: VisionRunningMode.video,
            ),
          );
        } else {
          _poseTask = await PoseLandmarker.create(
            PoseLandmarkerOptions(
              baseOptions: BaseOptions(
                modelAsset: ModelAsset.uri(
                  Uri.parse('${_models}pose_landmarker.task'),
                  sha256: 'fb9cc326c88fc2a4d9a6d355c28520d5deacfbaa375b56243b0141b546080596',
                ),
              ),
              runningMode: VisionRunningMode.video,
            ),
          );
        }

        if (_disposed || generation != _generation) return;

        if (defaultTargetPlatform == TargetPlatform.android) {
          const MethodChannel permission = MethodChannel('dev.ifiokjr.mp_device_demo/permissions');
          final bool granted =
              await permission.invokeMethod<bool>('ensureCameraPermission') ?? false;

          if (!granted) {
            throw StateError(
              'Camera permission denied. Enable camera access in Settings, then retry.',
            );
          }
        }

        final List<CameraDescription> cameras = await availableCameras();

        if (cameras.isEmpty) throw StateError('No camera found. Connect a camera and retry.');
        final CameraLensDirection lens = front
            ? CameraLensDirection.front
            : CameraLensDirection.back;
        final CameraDescription description = cameras.firstWhere(
          (CameraDescription c) => c.lensDirection == lens,
          orElse: () => cameras.first,
        );
        final CameraController controller = CameraController(
          description,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
              ? ImageFormatGroup.bgra8888
              : ImageFormatGroup.nv21,
        );
        camera = controller;
        await controller.initialize();
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

        if (_disposed || generation != _generation) return;
        final MpCameraClock clock = MpCameraClock();
        final LatestFrameScheduler<MpCameraFrame> scheduler = LatestFrameScheduler<MpCameraFrame>(
          (MpCameraFrame frame) => _infer(frame, generation),
        );
        _scheduler = scheduler;
        _sinceResult.reset();
        _sinceResult.start();
        _watchdog = Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (_sinceResult.elapsedMilliseconds <= 750 || (pose.isEmpty && face.isEmpty)) return;
          pose = <NormalizedLandmark>[];
          face = <NormalizedLandmark>[];
          status = 'Tracking paused · waiting for a fresh camera frame';
          _notify();
        });
        _failures = scheduler.failures.listen(
          (LatestFrameFailure<MpCameraFrame> failure) => _frameError(failure.error),
        );
        await controller.startImageStream((CameraImage image) {
          if (_disposed || generation != _generation) return;

          try {
            scheduler.submit(
              MpCameraFrameConverter.convert(
                image,
                timestampMs: clock.nextTimestampMs(),
                rotationDegrees: MpCameraRotation.degrees(
                  description,
                  DeviceOrientation.portraitUp,
                ),
                mirroredPreview: MpCameraRotation.isPreviewMirrored(description),
              ),
            );
          } on Object catch (error) {
            _frameError(error);
          }
        });
        status = 'Find your light. Step into frame.';
      } on Object catch (error) {
        status = 'Could not start: ${describeSessionError(error)}';
        try {
          await _release();
        } on Object catch (cleanupError) {
          status = '$status. Cleanup failed: $cleanupError';
        }
      } finally {
        if (generation == _generation) {
          loading = false;
          _notify();
        }
      }
    });
  }

  Future<void> _infer(MpCameraFrame frame, int generation) async {
    if (_disposed || generation != _generation) return;
    final Stopwatch timer = Stopwatch()..start();
    final MpImageUint8 image = uprightImage(
      frame.image as MpImageUint8,
      frame.processingOptions.rotationDegrees,
    );
    final FaceLandmarker? faceTask = _faceTask;
    final PoseLandmarker? poseTask = _poseTask;
    List<NormalizedLandmark> nextFace = <NormalizedLandmark>[];
    List<NormalizedLandmark> nextPose = <NormalizedLandmark>[];

    if (faceTask != null) {
      final FaceLandmarkerResult result = await faceTask.detectForVideo(image, frame.timestampMs);
      nextFace = result.faceLandmarks.firstOrNull ?? <NormalizedLandmark>[];
    }

    if (poseTask != null) {
      final PoseLandmarkerResult result = await poseTask.detectForVideo(image, frame.timestampMs);
      nextPose = result.landmarks.firstOrNull ?? <NormalizedLandmark>[];
    }

    if (_disposed || generation != _generation) return;
    face = nextFace;
    pose = nextPose;
    aspectRatio = image.width / image.height;
    timestampMs = frame.timestampMs;
    latencyMs = timer.elapsedMilliseconds;
    _sinceResult.reset();
    status = face.isEmpty && pose.isEmpty
        ? 'No person found · step into frame'
        : 'Tracking live · all processing stays on device';
    _notify();
  }

  void _frameError(Object error) {
    pose = <NormalizedLandmark>[];
    face = <NormalizedLandmark>[];
    status = 'Tracking interrupted: ${describeSessionError(error)}';
    _notify();
  }

  Future<void> _release() async {
    _watchdog?.cancel();
    _watchdog = null;
    _sinceResult.stop();
    final CameraController? controller = camera;
    final LatestFrameScheduler<MpCameraFrame>? scheduler = _scheduler;
    final FaceLandmarker? faceTask = _faceTask;
    final PoseLandmarker? poseTask = _poseTask;
    final List<Object> errors = <Object>[];
    camera = null;
    _scheduler = null;
    _faceTask = null;
    _poseTask = null;

    // Every resource gets a close attempt even if the platform camera fails.
    // Errors remain visible and cannot poison the next reconfiguration future.
    Future<void> close(Future<void> Function() operation) async {
      try {
        await operation();
      } on Object catch (error) {
        errors.add(error);
      }
    }

    if (controller != null) {
      if (controller.value.isStreamingImages) await close(controller.stopImageStream);
      await close(controller.dispose);
    }

    if (scheduler != null) await close(scheduler.close);
    await close(() async {
      await _failures?.cancel();
    });
    _failures = null;

    if (faceTask != null) await close(faceTask.close);

    if (poseTask != null) await close(poseTask.close);

    if (errors.isNotEmpty) throw StateError('Resource cleanup failed: ${errors.join('; ')}');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(
      _operation.then((_) => _release()).catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'motion playground',
            context: ErrorDescription('while closing a tracking session'),
          ),
        );
      }),
    );
    super.dispose();
  }
}

/// Renders [error] for the status line without implementation-detail prefixes.
///
/// `StateError('Camera permission denied…')` should read as the message, not
/// "Bad state: Camera permission denied…".
String describeSessionError(Object error) {
  if (error is MpException) return error.message;
  final String text = error.toString();

  for (final String prefix in const <String>[
    'Bad state: ',
    'Invalid argument(s): ',
    'Exception: ',
    'FormatException: ',
  ]) {
    if (text.startsWith(prefix)) return text.substring(prefix.length);
  }

  return text;
}

/// Rotates pixels before inference so landmark, angle, and preview coordinates
/// share one upright space. This avoids platform-specific output rotation rules.
MpImageUint8 uprightImage(MpImageUint8 image, int rotation) {
  if (rotation == 0) return image;

  if (!<int>[90, 180, 270].contains(rotation)) throw ArgumentError.value(rotation, 'rotation');
  final bool swap = rotation != 180;
  final int width = swap ? image.height : image.width;
  final int height = swap ? image.width : image.height;
  final int channels = image.format.channels;
  final Uint8List pixels = Uint8List(image.data.length);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final (int dx, int dy) = switch (rotation) {
        90 => (image.height - 1 - y, x),
        180 => (image.width - 1 - x, image.height - 1 - y),
        _ => (y, image.width - 1 - x),
      };

      final int source = (y * image.width + x) * channels;
      final int target = (dy * width + dx) * channels;
      pixels.setRange(target, target + channels, image.data, source);
    }
  }

  return MpImageUint8(width: width, height: height, format: image.format, data: pixels);
}
