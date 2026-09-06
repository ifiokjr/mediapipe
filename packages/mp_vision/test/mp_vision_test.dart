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

  final T output;
  final StreamController<VisionLiveResult<T>> controller =
      StreamController<VisionLiveResult<T>>.broadcast();
  final List<int> videoTimestamps = <int>[];
  final List<int> liveTimestamps = <int>[];
  int imageCount = 0;
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Stream<VisionLiveResult<T>> get results => controller.stream;

  @override
  Future<T> processImage(MpImage image, ImageProcessingOptions? processingOptions) async {
    imageCount++;
    return output;
  }

  @override
  Future<T> processVideo(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) async {
    videoTimestamps.add(timestampMs);
    return output;
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
