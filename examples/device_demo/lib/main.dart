import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mp_camera/mp_camera.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_vision/mp_vision.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Requests the camera permission from the host activity. The `camera` plugin
/// reports a denial as a generic initialization failure, so the demo asks first
/// and can show an actionable message.
const MethodChannel _permissions = MethodChannel('dev.ifiokjr.mp_device_demo/permissions');

Future<bool> _ensureCameraPermission() async {
  if (!Platform.isAndroid) return true;
  try {
    return await _permissions.invokeMethod<bool>('ensureCameraPermission') ?? false;

  } on PlatformException catch (error) {
    debugPrint('Permission request failed: $error');

    return false;
  }
}

/// Face detector model from MediaPipe's public asset bucket. The digest is
/// verified before the bytes reach the runtime.
final ModelAsset _faceModel = ModelAsset.uri(
  Uri.parse(
    'https://storage.googleapis.com/mediapipe-assets/tasks/testdata/vision/'
    'face_detection_short_range.tflite',
  ),
  sha256: 'bbff11cebd1eb27a1e004cae0b0e63ec8c551cbf34a4451148b4908b8db3eca8',
);

void main() {
  runApp(const MpDeviceDemoApp());
}

/// Live camera inference with device-motion-derived frame orientation.
class MpDeviceDemoApp extends StatelessWidget {
  /// Creates the demo application.
  const MpDeviceDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MP device demo',
    theme: ThemeData(colorSchemeSeed: const Color(0xFFFF694D), useMaterial3: true),
    home: const LiveInferencePage(),
  );
}

/// Streams camera frames through `FaceDetector` and reports live telemetry.
class LiveInferencePage extends StatefulWidget {
  /// Creates the live inference page.
  const LiveInferencePage({super.key});

  @override
  State<LiveInferencePage> createState() => _LiveInferencePageState();
}

class _LiveInferencePageState extends State<LiveInferencePage> {
  CameraController? _controller;
  FaceDetector? _detector;
  LatestFrameScheduler<MpCameraFrame>? _scheduler;
  MpCameraClock _clock = MpCameraClock();

  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;
  StreamSubscription<VisionLiveResult<DetectionResult>>? _results;
  StreamSubscription<LatestFrameFailure<MpCameraFrame>>? _failures;

  String _status = 'Starting…';
  String _motion = '—';
  int _faces = 0;
  double _confidence = 0;
  int _dropped = 0;
  int _processed = 0;
  CameraLensDirection _lens = CameraLensDirection.back;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_shutdown());
    super.dispose();
  }

  /// Shuts down in dependency order: sensors, camera, scheduler, then the task.
  /// Closing the task first would let an in-flight frame reach a released
  /// handle.
  Future<void> _shutdown() async {
    await _accelerometer?.cancel();
    await _gyroscope?.cancel();
    await _results?.cancel();
    await _failures?.cancel();

    final CameraController? controller = _controller;
    _controller = null;

    if (controller != null) {
      if (controller.value.isStreamingImages) await controller.stopImageStream();
      await controller.dispose();
    }

    await _scheduler?.close();
    _scheduler = null;
    await _detector?.close();
    _detector = null;
  }

  Future<void> _start() async {
    try {
      await _listenToMotion();

      _setStatus('Loading the face detector model…');
      final FaceDetector detector = await FaceDetector.create(
        FaceDetectorOptions(
          baseOptions: BaseOptions(modelAsset: _faceModel),
          runningMode: VisionRunningMode.liveStream,
        ),
      );
      _detector = detector;

      _setStatus('Opening the camera…');

      if (!await _ensureCameraPermission()) {
        _setStatus('Camera permission was denied. Grant it and restart the demo.');

        return;
      }

      final List<CameraDescription> cameras = await availableCameras();

      if (cameras.isEmpty) {
        _setStatus('No camera is available on this device.');

        return;
      }

      _lens = cameras.first.lensDirection;
      final CameraController controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );
      _controller = controller;
      await controller.initialize();

      // The scheduler keeps only the newest waiting frame. When inference cannot
      // keep up with the camera, older frames are dropped rather than queued so
      // the displayed result stays current.
      final LatestFrameScheduler<MpCameraFrame> scheduler = LatestFrameScheduler<MpCameraFrame>(
        _infer,
      );
      _scheduler = scheduler;
      _failures = scheduler.failures.listen((LatestFrameFailure<MpCameraFrame> failure) {
        _setStatus('Inference error: ${failure.error}');
      });
      _results = detector.results.listen(
        _onResult,
        onError: (Object error) => _setStatus('Inference error: $error'),
      );

      _clock = MpCameraClock();
      await controller.startImageStream(_onFrame);
      _setStatus('Streaming. Move the device to see orientation change.');

    } on Object catch (error, stackTrace) {
      _setStatus('Failed to start: $error');
      debugPrint('$stackTrace');
    }
  }

  /// Reads device motion so the demo can show the physical orientation that
  /// drives frame rotation, rather than only the reported interface state.
  Future<void> _listenToMotion() async {
    _accelerometer = accelerometerEventStream().listen((AccelerometerEvent event) {
      _setMotion(_describeTilt(event));
    });
    _gyroscope = gyroscopeEventStream().listen((GyroscopeEvent event) {
      final double magnitude = _magnitude(event.x, event.y, event.z);
      if (magnitude > 0.6) {
        setState(() => _motion = 'rotating ${magnitude.toStringAsFixed(1)}');
      }
    });
  }

  /// Maps the gravity vector onto a human-readable device orientation.
  String _describeTilt(AccelerometerEvent event) {
    const double threshold = 5.0;

    if (event.y.abs() > threshold) return event.y > 0 ? 'portrait' : 'portrait upside-down';
    if (event.x.abs() > threshold) return event.x > 0 ? 'landscape left' : 'landscape right';
    return 'flat';
  }

  double _magnitude(double x, double y, double z) => (x * x + y * y + z * z) * 0.5;

  void _onFrame(CameraImage cameraImage) {
    final CameraController? controller = _controller;
    final LatestFrameScheduler<MpCameraFrame>? scheduler = _scheduler;

    if (controller == null || scheduler == null) return;

    try {
      scheduler.submit(
        MpCameraFrameConverter.convert(
          cameraImage,
          timestampMs: _clock.nextTimestampMs(),
          rotationDegrees: MpCameraRotation.degrees(
            controller.description,
            controller.value.deviceOrientation,
          ),
          mirroredPreview: MpCameraRotation.isPreviewMirrored(controller.description),
        ),
      );

    } on Object catch (error) {
      // One malformed frame must not tear down the stream.
      debugPrint('Frame conversion failed: $error');
    }
  }

  Future<void> _infer(MpCameraFrame frame) => _detector!.detectAsync(
    frame.image,
    frame.timestampMs,
    processingOptions: frame.processingOptions,
  );

  void _onResult(VisionLiveResult<DetectionResult> event) {
    if (!mounted) return;
    final DetectionResult result = event.result;
    final Detection? best = result.detections.isEmpty ? null : result.detections.first;
    final LatestFrameScheduler<MpCameraFrame>? scheduler = _scheduler;
    setState(() {
      _faces = result.detections.length;
      _confidence = best == null || best.categories.isEmpty ? 0 : best.categories.first.score;
      _dropped = scheduler?.droppedCount ?? 0;
      _processed = scheduler?.processedCount ?? 0;
      _status = _faces == 0 ? 'No face in frame.' : 'Tracking $_faces face(s).';
    });
  }

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _status = value);
  }

  void _setMotion(String value) {
    if (!mounted || _motion.startsWith('rotating')) return;
    setState(() => _motion = value);
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? controller = _controller;
    final bool previewReady = controller != null && controller.value.isInitialized;

    return Scaffold(
      appBar: AppBar(title: const Text('MP device demo')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: previewReady
                    ? AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: CameraPreview(controller),
                      )
                    : const Text('Camera preview', style: TextStyle(color: Colors.white70)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_status, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _Metric(label: 'Faces', value: '$_faces'),
                _Metric(label: 'Top confidence', value: _confidence.toStringAsFixed(3)),
                _Metric(label: 'Device motion', value: _motion),
                _Metric(label: 'Processed frames', value: '$_processed'),
                _Metric(label: 'Dropped frames', value: '$_dropped'),
                _Metric(label: 'Camera', value: _lens.name),
                const SizedBox(height: 8),
                Text(
                  'Frames are converted by mp_camera, timestamped with a monotonic clock, '
                  'and scheduled so stale frames are dropped instead of queued.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}
