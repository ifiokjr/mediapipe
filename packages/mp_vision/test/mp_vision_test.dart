import 'dart:async';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_vision/mp_vision.dart';
import 'package:test/test.dart';

void main() {
  test('face detector delegates still images and closes once', () async {
    final _FakeVisionBackend<DetectionResult> backend = _FakeVisionBackend<DetectionResult>(
      DetectionResult(detections: const <Detection>[]),
    );
    final FaceDetector detector = await FaceDetector.create(
      FaceDetectorOptions(baseOptions: _baseOptions()),
      runtime: _FaceDetectorRuntime(backend),
    );

    final DetectionResult result = await detector.detect(_image());
    await detector.close();
    await detector.close();

    expect(result.detections, isEmpty);
    expect(backend.imageCount, 1);
    expect(backend.closeCount, 1);
    expect(() => detector.detect(_image()), throwsA(isA<MpTaskClosedError>()));
  });

  test('video mode validates timestamps before invoking the backend', () async {
    final _FakeVisionBackend<DetectionResult> backend = _FakeVisionBackend<DetectionResult>(
      DetectionResult(detections: const <Detection>[]),
    );
    final FaceDetector detector = await FaceDetector.create(
      FaceDetectorOptions(baseOptions: _baseOptions(), runningMode: VisionRunningMode.video),
      runtime: _FaceDetectorRuntime(backend),
    );

    await detector.detectForVideo(_image(), 10);

    expect(backend.videoTimestamps, <int>[10]);
    expect(() => detector.detectForVideo(_image(), 10), throwsArgumentError);
    expect(() => detector.detect(_image()), throwsStateError);
    await detector.close();
  });

  test('live mode exposes typed result events', () async {
    final _FakeVisionBackend<DetectionResult> backend = _FakeVisionBackend<DetectionResult>(
      DetectionResult(detections: const <Detection>[]),
    );
    final FaceDetector detector = await FaceDetector.create(
      FaceDetectorOptions(baseOptions: _baseOptions(), runningMode: VisionRunningMode.liveStream),
      runtime: _FaceDetectorRuntime(backend),
    );
    final MpImage image = _image();
    final Future<VisionLiveResult<DetectionResult>> nextResult = detector.results.first;

    await detector.detectAsync(image, 22);
    backend.controller.add(
      VisionLiveResult<DetectionResult>(
        result: DetectionResult(detections: const <Detection>[]),
        input: image,
        timestampMs: 22,
      ),
    );

    expect((await nextResult).timestampMs, 22);
    expect(backend.liveTimestamps, <int>[22]);
    await detector.close();
  });

  test('task options reject unsafe values', () {
    expect(
      () => FaceDetectorOptions(baseOptions: _baseOptions(), minDetectionConfidence: 1.1),
      throwsArgumentError,
    );
    expect(
      () => HandLandmarkerOptions(baseOptions: _baseOptions(), numHands: 0),
      throwsArgumentError,
    );
    expect(
      () => ImageSegmenterOptions(baseOptions: _baseOptions(), outputConfidenceMasks: false),
      throwsArgumentError,
    );
  });

  test('interactive prompts are immutable and validated', () {
    final List<PromptPoint> points = <PromptPoint>[PromptPoint(0.2, 0.4)];
    final ScribblePrompt prompt = InteractivePrompt.scribble(points) as ScribblePrompt;

    points.add(PromptPoint(0.3, 0.5));

    expect(prompt.points, hasLength(1));
    expect(() => PromptPoint(-0.1, 0.5), throwsArgumentError);
    expect(() => InteractivePrompt.strokes(const <PromptStroke>[]), throwsArgumentError);
  });

  test('a rejected frame does not burn its timestamp', () async {
    final _FakeVisionBackend<DetectionResult> backend = _FakeVisionBackend<DetectionResult>(
      DetectionResult(detections: const <Detection>[]),
    );
    final FaceDetector detector = await FaceDetector.create(
      FaceDetectorOptions(baseOptions: _baseOptions(), runningMode: VisionRunningMode.video),
      runtime: _FaceDetectorRuntime(backend),
    );

    backend.failNextVideo = StateError('frame rejected');
    await expectLater(detector.detectForVideo(_image(), 10), throwsStateError);

    // The same timestamp must be accepted once the failure is resolved.
    await detector.detectForVideo(_image(), 10);
    expect(backend.videoTimestamps, <int>[10]);
    await detector.close();
  });

  test('live results reject tasks that are not in live-stream mode', () async {
    final FaceDetector detector = await FaceDetector.create(
      FaceDetectorOptions(baseOptions: _baseOptions(), runningMode: VisionRunningMode.video),
      runtime: _FaceDetectorRuntime(_FakeVisionBackend<DetectionResult>(null)),
    );

    expect(() => detector.results, throwsStateError);
    await detector.close();
  });

  test('a failed close reopens the task so cleanup can be retried', () async {
    final _FlakyCloseBackend<DetectionResult> backend = _FlakyCloseBackend<DetectionResult>();
    final FaceDetector detector = await FaceDetector.create(
      FaceDetectorOptions(baseOptions: _baseOptions()),
      runtime: _FaceDetectorRuntime(backend),
    );

    await expectLater(detector.close(), throwsStateError);
    expect(detector.isClosed, isFalse);

    await detector.close();
    expect(detector.isClosed, isTrue);
    expect(backend.closeCount, 2);
  });

  test('every task wrapper delegates processing and closes once', () async {
    final _EveryTaskRuntime runtime = _EveryTaskRuntime();
    FaceDetector? faceDetector;
    FaceLandmarker? faceLandmarker;
    GestureRecognizer? gestureRecognizer;
    HandLandmarker? handLandmarker;
    HolisticLandmarker? holisticLandmarker;
    ImageClassifier? imageClassifier;
    ImageEmbedder? imageEmbedder;
    ImageSegmenter? imageSegmenter;
    ObjectDetector? objectDetector;
    PoseLandmarker? poseLandmarker;
    InteractiveSegmenter? interactiveSegmenter;

    final List<(String, Future<MpTask> Function(), Future<Object?> Function())> tasks =
        <(String, Future<MpTask> Function(), Future<Object?> Function())>[
          (
            'FaceDetector',
            () async => faceDetector = await FaceDetector.create(
              FaceDetectorOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => faceDetector!.detect(_image()),
          ),
          (
            'FaceLandmarker',
            () async => faceLandmarker = await FaceLandmarker.create(
              FaceLandmarkerOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => faceLandmarker!.detect(_image()),
          ),
          (
            'GestureRecognizer',
            () async => gestureRecognizer = await GestureRecognizer.create(
              GestureRecognizerOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => gestureRecognizer!.recognize(_image()),
          ),
          (
            'HandLandmarker',
            () async => handLandmarker = await HandLandmarker.create(
              HandLandmarkerOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => handLandmarker!.detect(_image()),
          ),
          (
            'HolisticLandmarker',
            () async => holisticLandmarker = await HolisticLandmarker.create(
              HolisticLandmarkerOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => holisticLandmarker!.detect(_image()),
          ),
          (
            'ImageClassifier',
            () async => imageClassifier = await ImageClassifier.create(
              ImageClassifierOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => imageClassifier!.classify(_image()),
          ),
          (
            'ImageEmbedder',
            () async => imageEmbedder = await ImageEmbedder.create(
              ImageEmbedderOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => imageEmbedder!.embed(_image()),
          ),
          (
            'ImageSegmenter',
            () async => imageSegmenter = await ImageSegmenter.create(
              ImageSegmenterOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => imageSegmenter!.segment(_image()),
          ),
          (
            'ObjectDetector',
            () async => objectDetector = await ObjectDetector.create(
              ObjectDetectorOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => objectDetector!.detect(_image()),
          ),
          (
            'PoseLandmarker',
            () async => poseLandmarker = await PoseLandmarker.create(
              PoseLandmarkerOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => poseLandmarker!.detect(_image()),
          ),
          (
            'InteractiveSegmenter',
            () async => interactiveSegmenter = await InteractiveSegmenter.create(
              InteractiveSegmenterOptions(baseOptions: _baseOptions()),
              runtime: runtime,
            ),
            () => interactiveSegmenter!.segment(
              _image(),
              InteractivePrompt.keypoint(PromptPoint(0.5, 0.5)),
            ),
          ),
        ];

    for (final (String name, Future<MpTask> Function() create, Future<Object?> Function() process)
        in tasks) {
      final MpTask task = await create();
      final Object? result = await process();
      expect(result, isNotNull, reason: '$name returned a result');
      await task.close();
      await task.close();
      expect(task.isClosed, isTrue, reason: '$name closed exactly once');
    }
  });
}

BaseOptions _baseOptions() => BaseOptions(modelAsset: ModelAsset.path('model.task'));

MpImage _image() => MpImage.uint8(
  width: 1,
  height: 1,
  format: MpImageFormat.srgb,
  data: Uint8List.fromList(<int>[0, 0, 0]),
);

final class _FakeVisionBackend<T> implements VisionTaskBackend<T> {
  _FakeVisionBackend(this.output);

  final T? output;
  final StreamController<VisionLiveResult<T>> controller =
      StreamController<VisionLiveResult<T>>.broadcast();
  final List<int> videoTimestamps = <int>[];
  final List<int> liveTimestamps = <int>[];
  int imageCount = 0;
  int closeCount = 0;
  Object? failNextVideo;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Stream<VisionLiveResult<T>> get results => controller.stream;

  @override
  Future<T> processImage(MpImage image, ImageProcessingOptions? processingOptions) async {
    imageCount++;

    return output as T;
  }

  @override
  Future<T> processVideo(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) async {
    final Object? failure = failNextVideo;
    failNextVideo = null;
    if (failure case final StateError error) throw error;
    videoTimestamps.add(timestampMs);

    return output as T;
  }

  @override
  Future<void> processLive(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) async => liveTimestamps.add(timestampMs);

  @override
  Future<void> close() async {
    closeCount++;
    await controller.close();
  }
}

final class _FlakyCloseBackend<T> implements VisionTaskBackend<T> {
  final StreamController<VisionLiveResult<T>> controller =
      StreamController<VisionLiveResult<T>>.broadcast();
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Stream<VisionLiveResult<T>> get results => controller.stream;

  @override
  Future<T> processImage(MpImage image, ImageProcessingOptions? processingOptions) async =>
      throw UnimplementedError();

  @override
  Future<T> processVideo(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) async => throw UnimplementedError();

  @override
  Future<void> processLive(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) async => throw UnimplementedError();

  @override
  Future<void> close() async {
    closeCount++;
    if (closeCount == 1) throw StateError('close failed');

    await controller.close();
  }
}

final class _FakeInteractiveSegmenterBackend implements InteractiveSegmenterBackend {
  int segmentCount = 0;
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Future<ImageSegmenterResult> segment(
    MpImage image,
    InteractivePrompt prompt,
    ImageProcessingOptions? processingOptions,
  ) async {
    segmentCount++;

    return ImageSegmenterResult();
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

final class _EveryTaskRuntime implements VisionRuntime {
  final _FakeVisionBackend<DetectionResult> faceDetector = _FakeVisionBackend<DetectionResult>(
    DetectionResult(detections: const <Detection>[]),
  );
  final _FakeVisionBackend<FaceLandmarkerResult> faceLandmarker =
      _FakeVisionBackend<FaceLandmarkerResult>(
        FaceLandmarkerResult(faceLandmarks: const <List<NormalizedLandmark>>[]),
      );
  final _FakeVisionBackend<GestureRecognizerResult> gestureRecognizer =
      _FakeVisionBackend<GestureRecognizerResult>(
        GestureRecognizerResult(
          gestures: const <List<Category>>[],
          handedness: const <List<Category>>[],
          landmarks: const <List<NormalizedLandmark>>[],
          worldLandmarks: const <List<Landmark>>[],
        ),
      );
  final _FakeVisionBackend<HandLandmarkerResult> handLandmarker =
      _FakeVisionBackend<HandLandmarkerResult>(
        HandLandmarkerResult(
          handedness: const <List<Category>>[],
          landmarks: const <List<NormalizedLandmark>>[],
          worldLandmarks: const <List<Landmark>>[],
        ),
      );
  final _FakeVisionBackend<HolisticLandmarkerResult> holisticLandmarker =
      _FakeVisionBackend<HolisticLandmarkerResult>(
        HolisticLandmarkerResult(
          faceLandmarks: const <List<NormalizedLandmark>>[],
          poseLandmarks: const <List<NormalizedLandmark>>[],
          poseWorldLandmarks: const <List<Landmark>>[],
          leftHandLandmarks: const <List<NormalizedLandmark>>[],
          leftHandWorldLandmarks: const <List<Landmark>>[],
          rightHandLandmarks: const <List<NormalizedLandmark>>[],
          rightHandWorldLandmarks: const <List<Landmark>>[],
        ),
      );
  final _FakeVisionBackend<ClassificationResult> imageClassifier =
      _FakeVisionBackend<ClassificationResult>(
        ClassificationResult(classifications: const <Classifications>[]),
      );
  final _FakeVisionBackend<EmbeddingResult> imageEmbedder = _FakeVisionBackend<EmbeddingResult>(
    EmbeddingResult(embeddings: const <Embedding>[]),
  );
  final _FakeVisionBackend<ImageSegmenterResult> imageSegmenter =
      _FakeVisionBackend<ImageSegmenterResult>(ImageSegmenterResult());
  final _FakeVisionBackend<DetectionResult> objectDetector = _FakeVisionBackend<DetectionResult>(
    DetectionResult(detections: const <Detection>[]),
  );
  final _FakeVisionBackend<PoseLandmarkerResult> poseLandmarker =
      _FakeVisionBackend<PoseLandmarkerResult>(
        PoseLandmarkerResult(
          landmarks: const <List<NormalizedLandmark>>[],
          worldLandmarks: const <List<Landmark>>[],
        ),
      );
  final _FakeInteractiveSegmenterBackend interactiveSegmenter = _FakeInteractiveSegmenterBackend();

  @override
  Future<VisionTaskBackend<DetectionResult>> createFaceDetector(
    FaceDetectorOptions options,
  ) async => faceDetector;

  @override
  Future<VisionTaskBackend<FaceLandmarkerResult>> createFaceLandmarker(
    FaceLandmarkerOptions options,
  ) async => faceLandmarker;

  @override
  Future<VisionTaskBackend<GestureRecognizerResult>> createGestureRecognizer(
    GestureRecognizerOptions options,
  ) async => gestureRecognizer;

  @override
  Future<VisionTaskBackend<HandLandmarkerResult>> createHandLandmarker(
    HandLandmarkerOptions options,
  ) async => handLandmarker;

  @override
  Future<VisionTaskBackend<HolisticLandmarkerResult>> createHolisticLandmarker(
    HolisticLandmarkerOptions options,
  ) async => holisticLandmarker;

  @override
  Future<VisionTaskBackend<ClassificationResult>> createImageClassifier(
    ImageClassifierOptions options,
  ) async => imageClassifier;

  @override
  Future<VisionTaskBackend<EmbeddingResult>> createImageEmbedder(
    ImageEmbedderOptions options,
  ) async => imageEmbedder;

  @override
  Future<VisionTaskBackend<ImageSegmenterResult>> createImageSegmenter(
    ImageSegmenterOptions options,
  ) async => imageSegmenter;

  @override
  Future<InteractiveSegmenterBackend> createInteractiveSegmenter(
    InteractiveSegmenterOptions options,
  ) async => interactiveSegmenter;

  @override
  Future<VisionTaskBackend<DetectionResult>> createObjectDetector(
    ObjectDetectorOptions options,
  ) async => objectDetector;

  @override
  Future<VisionTaskBackend<PoseLandmarkerResult>> createPoseLandmarker(
    PoseLandmarkerOptions options,
  ) async => poseLandmarker;
}

final class _FaceDetectorRuntime implements VisionRuntime {
  const _FaceDetectorRuntime(this.backend);

  final VisionTaskBackend<DetectionResult> backend;

  @override
  Future<VisionTaskBackend<DetectionResult>> createFaceDetector(
    FaceDetectorOptions options,
  ) async => backend;

  @override
  Future<VisionTaskBackend<FaceLandmarkerResult>> createFaceLandmarker(
    FaceLandmarkerOptions options,
  ) => throw UnimplementedError();

  @override
  Future<VisionTaskBackend<GestureRecognizerResult>> createGestureRecognizer(
    GestureRecognizerOptions options,
  ) => throw UnimplementedError();

  @override
  Future<VisionTaskBackend<HandLandmarkerResult>> createHandLandmarker(
    HandLandmarkerOptions options,
  ) => throw UnimplementedError();

  @override
  Future<VisionTaskBackend<HolisticLandmarkerResult>> createHolisticLandmarker(
    HolisticLandmarkerOptions options,
  ) => throw UnimplementedError();

  @override
  Future<VisionTaskBackend<ClassificationResult>> createImageClassifier(
    ImageClassifierOptions options,
  ) => throw UnimplementedError();

  @override
  Future<VisionTaskBackend<EmbeddingResult>> createImageEmbedder(ImageEmbedderOptions options) =>
      throw UnimplementedError();

  @override
  Future<VisionTaskBackend<ImageSegmenterResult>> createImageSegmenter(
    ImageSegmenterOptions options,
  ) => throw UnimplementedError();

  @override
  Future<InteractiveSegmenterBackend> createInteractiveSegmenter(
    InteractiveSegmenterOptions options,
  ) => throw UnimplementedError();

  @override
  Future<VisionTaskBackend<DetectionResult>> createObjectDetector(ObjectDetectorOptions options) =>
      throw UnimplementedError();

  @override
  Future<VisionTaskBackend<PoseLandmarkerResult>> createPoseLandmarker(
    PoseLandmarkerOptions options,
  ) => throw UnimplementedError();
}
