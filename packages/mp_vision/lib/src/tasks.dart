import 'package:mp_core/mp_core.dart';

import 'options.dart';
import 'results.dart';
import 'runtime.dart';

abstract base class _VisionTask<T> implements MpTask {
  _VisionTask(this.options, this._backend, String taskName) : _lifecycle = TaskLifecycle(taskName);

  /// Options used to create this task.
  final VisionTaskOptions options;

  final VisionTaskBackend<T> _backend;
  final TaskLifecycle _lifecycle;
  final TimestampTracker _timestamps = TimestampTracker();

  @override
  bool get isClosed => _lifecycle.isClosed;

  Stream<VisionLiveResult<T>> get liveResults {
    _lifecycle.ensureOpen();
    return _backend.results;
  }

  Future<T> processImage(MpImage image, ImageProcessingOptions? processingOptions) {
    _lifecycle.ensureOpen();
    _requireMode(VisionRunningMode.image, 'image processing');
    return _backend.processImage(image, processingOptions);
  }

  Future<T> processVideo(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) {
    _lifecycle.ensureOpen();
    _requireMode(VisionRunningMode.video, 'video processing');
    _timestamps.add(timestampMs);
    return _backend.processVideo(image, timestampMs, processingOptions);
  }

  Future<void> processLive(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) {
    _lifecycle.ensureOpen();
    _requireMode(VisionRunningMode.liveStream, 'live-stream processing');
    _timestamps.add(timestampMs);
    return _backend.processLive(image, timestampMs, processingOptions);
  }

  void _requireMode(VisionRunningMode expected, String operation) {
    if (options.runningMode != expected) {
      throw StateError(
        '$operation requires ${expected.name} mode; this task uses ${options.runningMode.name}.',
      );
    }
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}

/// Detects faces and their bounding boxes.
final class FaceDetector extends _VisionTask<DetectionResult> {
  FaceDetector._(FaceDetectorOptions options, VisionTaskBackend<DetectionResult> backend)
    : super(options, backend, 'FaceDetector');

  /// Creates a face detector using [runtime], or the active platform adapter.
  static Future<FaceDetector> create(FaceDetectorOptions options, {VisionRuntime? runtime}) async =>
      FaceDetector._(options, await (runtime ?? defaultVisionRuntime).createFaceDetector(options));

  /// Results emitted by [detectAsync].
  Stream<VisionLiveResult<DetectionResult>> get results => liveResults;

  /// Detects faces in an unrelated still [image].
  Future<DetectionResult> detect(MpImage image, {ImageProcessingOptions? processingOptions}) =>
      processImage(image, processingOptions);

  /// Detects faces in one decoded video frame.
  Future<DetectionResult> detectForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for face detection.
  Future<void> detectAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}

/// Detects facial landmarks, blendshapes, and transforms.
final class FaceLandmarker extends _VisionTask<FaceLandmarkerResult> {
  FaceLandmarker._(FaceLandmarkerOptions options, VisionTaskBackend<FaceLandmarkerResult> backend)
    : super(options, backend, 'FaceLandmarker');

  /// Creates a face landmarker using [runtime], or the active platform adapter.
  static Future<FaceLandmarker> create(
    FaceLandmarkerOptions options, {
    VisionRuntime? runtime,
  }) async => FaceLandmarker._(
    options,
    await (runtime ?? defaultVisionRuntime).createFaceLandmarker(options),
  );

  /// Results emitted by [detectAsync].
  Stream<VisionLiveResult<FaceLandmarkerResult>> get results => liveResults;

  /// Detects facial landmarks in an unrelated still [image].
  Future<FaceLandmarkerResult> detect(MpImage image, {ImageProcessingOptions? processingOptions}) =>
      processImage(image, processingOptions);

  /// Detects facial landmarks in one decoded video frame.
  Future<FaceLandmarkerResult> detectForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for facial landmarking.
  Future<void> detectAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}

/// Recognizes gestures and hand landmarks.
final class GestureRecognizer extends _VisionTask<GestureRecognizerResult> {
  GestureRecognizer._(
    GestureRecognizerOptions options,
    VisionTaskBackend<GestureRecognizerResult> backend,
  ) : super(options, backend, 'GestureRecognizer');

  /// Creates a gesture recognizer using [runtime], or the active platform adapter.
  static Future<GestureRecognizer> create(
    GestureRecognizerOptions options, {
    VisionRuntime? runtime,
  }) async => GestureRecognizer._(
    options,
    await (runtime ?? defaultVisionRuntime).createGestureRecognizer(options),
  );

  /// Results emitted by [recognizeAsync].
  Stream<VisionLiveResult<GestureRecognizerResult>> get results => liveResults;

  /// Recognizes gestures in an unrelated still [image].
  Future<GestureRecognizerResult> recognize(
    MpImage image, {
    ImageProcessingOptions? processingOptions,
  }) => processImage(image, processingOptions);

  /// Recognizes gestures in one decoded video frame.
  Future<GestureRecognizerResult> recognizeForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for gesture recognition.
  Future<void> recognizeAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}

/// Detects hand landmarks and handedness.
final class HandLandmarker extends _VisionTask<HandLandmarkerResult> {
  HandLandmarker._(HandLandmarkerOptions options, VisionTaskBackend<HandLandmarkerResult> backend)
    : super(options, backend, 'HandLandmarker');

  /// Creates a hand landmarker using [runtime], or the active platform adapter.
  static Future<HandLandmarker> create(
    HandLandmarkerOptions options, {
    VisionRuntime? runtime,
  }) async => HandLandmarker._(
    options,
    await (runtime ?? defaultVisionRuntime).createHandLandmarker(options),
  );

  /// Results emitted by [detectAsync].
  Stream<VisionLiveResult<HandLandmarkerResult>> get results => liveResults;

  /// Detects hand landmarks in an unrelated still [image].
  Future<HandLandmarkerResult> detect(MpImage image, {ImageProcessingOptions? processingOptions}) =>
      processImage(image, processingOptions);

  /// Detects hand landmarks in one decoded video frame.
  Future<HandLandmarkerResult> detectForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for hand landmarking.
  Future<void> detectAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}

/// Detects face, pose, and hand landmarks in one task.
final class HolisticLandmarker extends _VisionTask<HolisticLandmarkerResult> {
  HolisticLandmarker._(
    HolisticLandmarkerOptions options,
    VisionTaskBackend<HolisticLandmarkerResult> backend,
  ) : super(options, backend, 'HolisticLandmarker');

  /// Creates a holistic landmarker using [runtime], or the active platform adapter.
  static Future<HolisticLandmarker> create(
    HolisticLandmarkerOptions options, {
    VisionRuntime? runtime,
  }) async => HolisticLandmarker._(
    options,
    await (runtime ?? defaultVisionRuntime).createHolisticLandmarker(options),
  );

  /// Results emitted by [detectAsync].
  Stream<VisionLiveResult<HolisticLandmarkerResult>> get results => liveResults;

  /// Detects holistic landmarks in an unrelated still [image].
  Future<HolisticLandmarkerResult> detect(
    MpImage image, {
    ImageProcessingOptions? processingOptions,
  }) => processImage(image, processingOptions);

  /// Detects holistic landmarks in one decoded video frame.
  Future<HolisticLandmarkerResult> detectForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for holistic landmarking.
  Future<void> detectAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}

/// Classifies images with a task-compatible model.
final class ImageClassifier extends _VisionTask<ClassificationResult> {
  ImageClassifier._(ImageClassifierOptions options, VisionTaskBackend<ClassificationResult> backend)
    : super(options, backend, 'ImageClassifier');

  /// Creates an image classifier using [runtime], or the active platform adapter.
  static Future<ImageClassifier> create(
    ImageClassifierOptions options, {
    VisionRuntime? runtime,
  }) async => ImageClassifier._(
    options,
    await (runtime ?? defaultVisionRuntime).createImageClassifier(options),
  );

  /// Results emitted by [classifyAsync].
  Stream<VisionLiveResult<ClassificationResult>> get results => liveResults;

  /// Classifies an unrelated still [image].
  Future<ClassificationResult> classify(
    MpImage image, {
    ImageProcessingOptions? processingOptions,
  }) => processImage(image, processingOptions);

  /// Classifies one decoded video frame.
  Future<ClassificationResult> classifyForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for image classification.
  Future<void> classifyAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}

/// Extracts vector embeddings from images.
final class ImageEmbedder extends _VisionTask<EmbeddingResult> {
  ImageEmbedder._(ImageEmbedderOptions options, VisionTaskBackend<EmbeddingResult> backend)
    : super(options, backend, 'ImageEmbedder');

  /// Creates an image embedder using [runtime], or the active platform adapter.
  static Future<ImageEmbedder> create(
    ImageEmbedderOptions options, {
    VisionRuntime? runtime,
  }) async => ImageEmbedder._(
    options,
    await (runtime ?? defaultVisionRuntime).createImageEmbedder(options),
  );

  /// Results emitted by [embedAsync].
  Stream<VisionLiveResult<EmbeddingResult>> get results => liveResults;

  /// Extracts embeddings from an unrelated still [image].
  Future<EmbeddingResult> embed(MpImage image, {ImageProcessingOptions? processingOptions}) =>
      processImage(image, processingOptions);

  /// Extracts embeddings from one decoded video frame.
  Future<EmbeddingResult> embedForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for image embedding.
  Future<void> embedAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}

/// Assigns category and confidence masks to image pixels.
final class ImageSegmenter extends _VisionTask<ImageSegmenterResult> {
  ImageSegmenter._(ImageSegmenterOptions options, VisionTaskBackend<ImageSegmenterResult> backend)
    : super(options, backend, 'ImageSegmenter');

  /// Creates an image segmenter using [runtime], or the active platform adapter.
  static Future<ImageSegmenter> create(
    ImageSegmenterOptions options, {
    VisionRuntime? runtime,
  }) async => ImageSegmenter._(
    options,
    await (runtime ?? defaultVisionRuntime).createImageSegmenter(options),
  );

  /// Results emitted by [segmentAsync].
  Stream<VisionLiveResult<ImageSegmenterResult>> get results => liveResults;

  /// Segments an unrelated still [image].
  Future<ImageSegmenterResult> segment(
    MpImage image, {
    ImageProcessingOptions? processingOptions,
  }) => processImage(image, processingOptions);

  /// Segments one decoded video frame.
  Future<ImageSegmenterResult> segmentForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for segmentation.
  Future<void> segmentAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}

/// Segments an image using points, scribbles, or signed brush strokes.
final class InteractiveSegmenter implements MpTask {
  InteractiveSegmenter._(this._backend);

  final InteractiveSegmenterBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('InteractiveSegmenter');

  /// Creates an interactive segmenter using [runtime], or the platform adapter.
  static Future<InteractiveSegmenter> create(
    InteractiveSegmenterOptions options, {
    VisionRuntime? runtime,
  }) async => InteractiveSegmenter._(
    await (runtime ?? defaultVisionRuntime).createInteractiveSegmenter(options),
  );

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Segments [image] according to [prompt].
  Future<ImageSegmenterResult> segment(
    MpImage image,
    InteractivePrompt prompt, {
    ImageProcessingOptions? processingOptions,
  }) {
    _lifecycle.ensureOpen();
    return _backend.segment(image, prompt, processingOptions);
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}

/// Detects objects and their bounding boxes.
final class ObjectDetector extends _VisionTask<DetectionResult> {
  ObjectDetector._(ObjectDetectorOptions options, VisionTaskBackend<DetectionResult> backend)
    : super(options, backend, 'ObjectDetector');

  /// Creates an object detector using [runtime], or the active platform adapter.
  static Future<ObjectDetector> create(
    ObjectDetectorOptions options, {
    VisionRuntime? runtime,
  }) async => ObjectDetector._(
    options,
    await (runtime ?? defaultVisionRuntime).createObjectDetector(options),
  );

  /// Results emitted by [detectAsync].
  Stream<VisionLiveResult<DetectionResult>> get results => liveResults;

  /// Detects objects in an unrelated still [image].
  Future<DetectionResult> detect(MpImage image, {ImageProcessingOptions? processingOptions}) =>
      processImage(image, processingOptions);

  /// Detects objects in one decoded video frame.
  Future<DetectionResult> detectForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for object detection.
  Future<void> detectAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}

/// Detects pose landmarks and optional segmentation masks.
final class PoseLandmarker extends _VisionTask<PoseLandmarkerResult> {
  PoseLandmarker._(PoseLandmarkerOptions options, VisionTaskBackend<PoseLandmarkerResult> backend)
    : super(options, backend, 'PoseLandmarker');

  /// Creates a pose landmarker using [runtime], or the active platform adapter.
  static Future<PoseLandmarker> create(
    PoseLandmarkerOptions options, {
    VisionRuntime? runtime,
  }) async => PoseLandmarker._(
    options,
    await (runtime ?? defaultVisionRuntime).createPoseLandmarker(options),
  );

  /// Results emitted by [detectAsync].
  Stream<VisionLiveResult<PoseLandmarkerResult>> get results => liveResults;

  /// Detects pose landmarks in an unrelated still [image].
  Future<PoseLandmarkerResult> detect(MpImage image, {ImageProcessingOptions? processingOptions}) =>
      processImage(image, processingOptions);

  /// Detects pose landmarks in one decoded video frame.
  Future<PoseLandmarkerResult> detectForVideo(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processVideo(image, timestampMs, processingOptions);

  /// Submits one live-stream frame for pose landmarking.
  Future<void> detectAsync(
    MpImage image,
    int timestampMs, {
    ImageProcessingOptions? processingOptions,
  }) => processLive(image, timestampMs, processingOptions);
}
