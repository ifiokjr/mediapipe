import 'package:mp_core/mp_core.dart';

import 'options.dart';
import 'results.dart';
import 'runtime_stub.dart'
    if (dart.library.io) 'runtime_native.dart'
    if (dart.library.js_interop) 'runtime_web.dart'
    as platform;

/// A result emitted by a live-stream vision task.
final class VisionLiveResult<T> {
  /// Creates a live result associated with [timestampMs] and [input].
  const VisionLiveResult({required this.result, required this.input, required this.timestampMs});

  /// Task output.
  final T result;

  /// A safe copy of the input image associated with the output.
  final MpImage input;

  /// Input timestamp in milliseconds.
  final int timestampMs;
}

/// Common execution contract implemented by every platform vision backend.
abstract interface class VisionTaskBackend<T> implements MpTask {
  /// Results emitted for inputs submitted with [processLive].
  Stream<VisionLiveResult<T>> get results;

  /// Processes an unrelated still [image].
  Future<T> processImage(MpImage image, ImageProcessingOptions? processingOptions);

  /// Processes one frame from a decoded video.
  Future<T> processVideo(MpImage image, int timestampMs, ImageProcessingOptions? processingOptions);

  /// Submits one frame from a live stream.
  Future<void> processLive(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  );
}

/// Interactive segmentation execution contract.
abstract interface class InteractiveSegmenterBackend implements MpTask {
  /// Segments [image] using a user-supplied [prompt].
  Future<ImageSegmenterResult> segment(
    MpImage image,
    InteractivePrompt prompt,
    ImageProcessingOptions? processingOptions,
  );
}

/// A platform adapter capable of creating all MediaPipe vision task backends.
abstract interface class VisionRuntime {
  /// Creates a face detector backend.
  Future<VisionTaskBackend<DetectionResult>> createFaceDetector(FaceDetectorOptions options);

  /// Creates a face landmarker backend.
  Future<VisionTaskBackend<FaceLandmarkerResult>> createFaceLandmarker(
    FaceLandmarkerOptions options,
  );

  /// Creates a gesture recognizer backend.
  Future<VisionTaskBackend<GestureRecognizerResult>> createGestureRecognizer(
    GestureRecognizerOptions options,
  );

  /// Creates a hand landmarker backend.
  Future<VisionTaskBackend<HandLandmarkerResult>> createHandLandmarker(
    HandLandmarkerOptions options,
  );

  /// Creates a holistic landmarker backend.
  Future<VisionTaskBackend<HolisticLandmarkerResult>> createHolisticLandmarker(
    HolisticLandmarkerOptions options,
  );

  /// Creates an image classifier backend.
  Future<VisionTaskBackend<ClassificationResult>> createImageClassifier(
    ImageClassifierOptions options,
  );

  /// Creates an image embedder backend.
  Future<VisionTaskBackend<EmbeddingResult>> createImageEmbedder(ImageEmbedderOptions options);

  /// Creates an image segmenter backend.
  Future<VisionTaskBackend<ImageSegmenterResult>> createImageSegmenter(
    ImageSegmenterOptions options,
  );

  /// Creates an interactive segmenter backend.
  Future<InteractiveSegmenterBackend> createInteractiveSegmenter(
    InteractiveSegmenterOptions options,
  );

  /// Creates an object detector backend.
  Future<VisionTaskBackend<DetectionResult>> createObjectDetector(ObjectDetectorOptions options);

  /// Creates a pose landmarker backend.
  Future<VisionTaskBackend<PoseLandmarkerResult>> createPoseLandmarker(
    PoseLandmarkerOptions options,
  );
}

/// The adapter selected for the active platform.
VisionRuntime get defaultVisionRuntime => platform.createVisionRuntime();

/// An adapter used when the current build has no linked MediaPipe runtime.
final class UnsupportedVisionRuntime implements VisionRuntime {
  /// Creates an unsupported adapter for [platform].
  const UnsupportedVisionRuntime(this.platform);

  /// The platform for which no implementation was linked.
  final MpPlatform platform;

  Never _unsupported(String task) => throw MpException(
    MpStatus.unimplemented,
    'No $task backend is linked for ${platform.name}.',
    task: task,
  );

  @override
  Future<VisionTaskBackend<DetectionResult>> createFaceDetector(
    FaceDetectorOptions options,
  ) async => _unsupported('FaceDetector');

  @override
  Future<VisionTaskBackend<FaceLandmarkerResult>> createFaceLandmarker(
    FaceLandmarkerOptions options,
  ) async => _unsupported('FaceLandmarker');

  @override
  Future<VisionTaskBackend<GestureRecognizerResult>> createGestureRecognizer(
    GestureRecognizerOptions options,
  ) async => _unsupported('GestureRecognizer');

  @override
  Future<VisionTaskBackend<HandLandmarkerResult>> createHandLandmarker(
    HandLandmarkerOptions options,
  ) async => _unsupported('HandLandmarker');

  @override
  Future<VisionTaskBackend<HolisticLandmarkerResult>> createHolisticLandmarker(
    HolisticLandmarkerOptions options,
  ) async => _unsupported('HolisticLandmarker');

  @override
  Future<VisionTaskBackend<ClassificationResult>> createImageClassifier(
    ImageClassifierOptions options,
  ) async => _unsupported('ImageClassifier');

  @override
  Future<VisionTaskBackend<EmbeddingResult>> createImageEmbedder(
    ImageEmbedderOptions options,
  ) async => _unsupported('ImageEmbedder');

  @override
  Future<VisionTaskBackend<ImageSegmenterResult>> createImageSegmenter(
    ImageSegmenterOptions options,
  ) async => _unsupported('ImageSegmenter');

  @override
  Future<InteractiveSegmenterBackend> createInteractiveSegmenter(
    InteractiveSegmenterOptions options,
  ) async => _unsupported('InteractiveSegmenter');

  @override
  Future<VisionTaskBackend<DetectionResult>> createObjectDetector(
    ObjectDetectorOptions options,
  ) async => _unsupported('ObjectDetector');

  @override
  Future<VisionTaskBackend<PoseLandmarkerResult>> createPoseLandmarker(
    PoseLandmarkerOptions options,
  ) async => _unsupported('PoseLandmarker');
}
