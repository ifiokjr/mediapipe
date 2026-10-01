import 'dart:async';
import 'dart:js_interop';

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/web.dart';

import 'options.dart';
import 'results.dart';
import 'runtime.dart';
import 'web_converters.dart';

final WebTaskAssets _defaultAssets = WebTaskAssets(
  moduleUri: Uri.parse(
    'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/vision_bundle.mjs',
  ),
  wasmRoot: Uri.parse('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/wasm'),
);

/// Creates the default web vision runtime.
VisionRuntime createVisionRuntime() => WebVisionRuntime();

/// Browser runtime backed by the official `@mediapipe/tasks-vision` package.
final class WebVisionRuntime implements VisionRuntime {
  /// Creates a runtime using [assets].
  WebVisionRuntime({WebTaskAssets? assets}) : assets = assets ?? _defaultAssets;

  /// Locations of the JavaScript module and Wasm files.
  final WebTaskAssets assets;

  Future<({JSObject fileset, JSObject module})>? _loaded;

  Future<({JSObject fileset, JSObject module})> _load() => _loaded ??= _loadOnce();

  Future<({JSObject fileset, JSObject module})> _loadOnce() async {
    final JSObject module = await importWebTaskModule(assets.moduleUri);
    final JSObject resolver = requireWebObject(module, 'FilesetResolver');
    final JSPromise<JSObject> promise = callWebMethod<JSPromise<JSObject>>(
      resolver,
      'forVisionTasks',
      <JSAny?>[assets.wasmRoot.toString().toJS],
    );
    return (fileset: await promise.toDart, module: module);
  }

  Future<JSObject> _create(String task, Map<String, Object?> options) async {
    final ({JSObject fileset, JSObject module}) loaded = await _load();
    final JSObject taskClass = requireWebObject(loaded.module, task);
    final JSPromise<JSObject> promise = callWebMethod<JSPromise<JSObject>>(
      taskClass,
      'createFromOptions',
      <JSAny?>[loaded.fileset, webJsify(options)],
    );
    try {
      return await promise.toDart;
    } on Object catch (error) {
      throw MpException(
        MpStatus.internal,
        'MediaPipe could not create $task.',
        task: task,
        cause: error,
      );
    }
  }

  Future<Map<String, Object?>> _base(VisionTaskOptions options) async => <String, Object?>{
    'baseOptions': await resolveWebBaseOptions(options.baseOptions),
    'runningMode': options.runningMode == VisionRunningMode.image ? 'IMAGE' : 'VIDEO',
  };

  Future<VisionTaskBackend<T>> _task<T>({
    required String task,
    required VisionTaskOptions options,
    required String imageMethod,
    required String videoMethod,
    required T Function(JSAny? value) convert,
    Map<String, Object?> extraOptions = const <String, Object?>{},
  }) async => _WebVisionTask<T>(
    await _create(task, <String, Object?>{...await _base(options), ...extraOptions}),
    imageMethod: imageMethod,
    videoMethod: videoMethod,
    convert: convert,
  );

  @override
  Future<VisionTaskBackend<DetectionResult>> createFaceDetector(FaceDetectorOptions options) =>
      _task<DetectionResult>(
        task: 'FaceDetector',
        options: options,
        imageMethod: 'detect',
        videoMethod: 'detectForVideo',
        convert: webDetectionResult,
        extraOptions: <String, Object?>{
          'minDetectionConfidence': options.minDetectionConfidence,
          'minSuppressionThreshold': options.minSuppressionThreshold,
        },
      );

  @override
  Future<VisionTaskBackend<FaceLandmarkerResult>> createFaceLandmarker(
    FaceLandmarkerOptions options,
  ) => _task<FaceLandmarkerResult>(
    task: 'FaceLandmarker',
    options: options,
    imageMethod: 'detect',
    videoMethod: 'detectForVideo',
    convert: webFaceLandmarkerResult,
    extraOptions: <String, Object?>{
      'numFaces': options.numFaces,
      'minFaceDetectionConfidence': options.minFaceDetectionConfidence,
      'minFacePresenceConfidence': options.minFacePresenceConfidence,
      'minTrackingConfidence': options.minTrackingConfidence,
      'outputFaceBlendshapes': options.outputFaceBlendshapes,
      'outputFacialTransformationMatrixes': options.outputFacialTransformationMatrixes,
    },
  );

  @override
  Future<VisionTaskBackend<GestureRecognizerResult>> createGestureRecognizer(
    GestureRecognizerOptions options,
  ) => _task<GestureRecognizerResult>(
    task: 'GestureRecognizer',
    options: options,
    imageMethod: 'recognize',
    videoMethod: 'recognizeForVideo',
    convert: webGestureRecognizerResult,
    extraOptions: <String, Object?>{
      'numHands': options.numHands,
      'minHandDetectionConfidence': options.minHandDetectionConfidence,
      'minHandPresenceConfidence': options.minHandPresenceConfidence,
      'minTrackingConfidence': options.minTrackingConfidence,
      if (options.cannedGesturesClassifierOptions case final ClassifierOptions value)
        'cannedGesturesClassifierOptions': webClassifierOptions(value),
      if (options.customGesturesClassifierOptions case final ClassifierOptions value)
        'customGesturesClassifierOptions': webClassifierOptions(value),
    },
  );

  @override
  Future<VisionTaskBackend<HandLandmarkerResult>> createHandLandmarker(
    HandLandmarkerOptions options,
  ) => _task<HandLandmarkerResult>(
    task: 'HandLandmarker',
    options: options,
    imageMethod: 'detect',
    videoMethod: 'detectForVideo',
    convert: webHandLandmarkerResult,
    extraOptions: <String, Object?>{
      'numHands': options.numHands,
      'minHandDetectionConfidence': options.minHandDetectionConfidence,
      'minHandPresenceConfidence': options.minHandPresenceConfidence,
      'minTrackingConfidence': options.minTrackingConfidence,
    },
  );

  @override
  Future<VisionTaskBackend<HolisticLandmarkerResult>> createHolisticLandmarker(
    HolisticLandmarkerOptions options,
  ) => _task<HolisticLandmarkerResult>(
    task: 'HolisticLandmarker',
    options: options,
    imageMethod: 'detect',
    videoMethod: 'detectForVideo',
    convert: webHolisticLandmarkerResult,
    extraOptions: <String, Object?>{
      'minFaceDetectionConfidence': options.minFaceDetectionConfidence,
      'minFaceSuppressionThreshold': options.minFaceSuppressionThreshold,
      'minFacePresenceConfidence': options.minFacePresenceConfidence,
      'outputFaceBlendshapes': options.outputFaceBlendshapes,
      'minPoseDetectionConfidence': options.minPoseDetectionConfidence,
      'minPoseSuppressionThreshold': options.minPoseSuppressionThreshold,
      'minPosePresenceConfidence': options.minPosePresenceConfidence,
      'outputPoseSegmentationMasks': options.outputPoseSegmentationMasks,
      'minHandLandmarksConfidence': options.minHandLandmarksConfidence,
    },
  );

  @override
  Future<VisionTaskBackend<ClassificationResult>> createImageClassifier(
    ImageClassifierOptions options,
  ) => _task<ClassificationResult>(
    task: 'ImageClassifier',
    options: options,
    imageMethod: 'classify',
    videoMethod: 'classifyForVideo',
    convert: (JSAny? value) => webClassificationResult(webDartify(value)! as Map<Object?, Object?>),
    extraOptions: webClassifierOptions(options.classifierOptions),
  );

  @override
  Future<VisionTaskBackend<EmbeddingResult>> createImageEmbedder(ImageEmbedderOptions options) =>
      _task<EmbeddingResult>(
        task: 'ImageEmbedder',
        options: options,
        imageMethod: 'embed',
        videoMethod: 'embedForVideo',
        convert: webEmbeddingResult,
        extraOptions: webEmbedderOptions(options.embedderOptions),
      );

  @override
  Future<VisionTaskBackend<ImageSegmenterResult>> createImageSegmenter(
    ImageSegmenterOptions options,
  ) => _task<ImageSegmenterResult>(
    task: 'ImageSegmenter',
    options: options,
    imageMethod: 'segment',
    videoMethod: 'segmentForVideo',
    convert: webImageSegmenterResult,
    extraOptions: <String, Object?>{
      if (options.displayNamesLocale case final String locale) 'displayNamesLocale': locale,
      'outputConfidenceMasks': options.outputConfidenceMasks,
      'outputCategoryMask': options.outputCategoryMask,
    },
  );

  @override
  Future<InteractiveSegmenterBackend> createInteractiveSegmenter(
    InteractiveSegmenterOptions options,
  ) async {
    final Map<String, Object?> baseOptions = await resolveWebBaseOptions(options.baseOptions);
    return _WebInteractiveSegmenter(
      createSplit: () =>
          _create('InteractiveSegmenter', <String, Object?>{'baseOptions': baseOptions}),
      createLegacy: () => _create('InteractiveSegmenterLegacy', <String, Object?>{
        'baseOptions': baseOptions,
        'runningMode': 'IMAGE',
        'outputConfidenceMasks': options.outputConfidenceMasks,
        'outputCategoryMask': options.outputCategoryMask,
      }),
    );
  }

  @override
  Future<VisionTaskBackend<DetectionResult>> createObjectDetector(ObjectDetectorOptions options) =>
      _task<DetectionResult>(
        task: 'ObjectDetector',
        options: options,
        imageMethod: 'detect',
        videoMethod: 'detectForVideo',
        convert: webDetectionResult,
        extraOptions: webClassifierOptions(options.classifierOptions),
      );

  @override
  Future<VisionTaskBackend<PoseLandmarkerResult>> createPoseLandmarker(
    PoseLandmarkerOptions options,
  ) => _task<PoseLandmarkerResult>(
    task: 'PoseLandmarker',
    options: options,
    imageMethod: 'detect',
    videoMethod: 'detectForVideo',
    convert: webPoseLandmarkerResult,
    extraOptions: <String, Object?>{
      'numPoses': options.numPoses,
      'minPoseDetectionConfidence': options.minPoseDetectionConfidence,
      'minPosePresenceConfidence': options.minPosePresenceConfidence,
      'minTrackingConfidence': options.minTrackingConfidence,
      'outputSegmentationMasks': options.outputSegmentationMasks,
    },
  );
}

final class _WebVisionTask<T> implements VisionTaskBackend<T> {
  _WebVisionTask(
    this._task, {
    required this.imageMethod,
    required this.videoMethod,
    required this.convert,
  });

  final JSObject _task;
  final String imageMethod;
  final String videoMethod;
  final T Function(JSAny? value) convert;
  final StreamController<VisionLiveResult<T>> _controller =
      StreamController<VisionLiveResult<T>>.broadcast();
  Future<void> _pending = Future<void>.value();
  bool _isClosed = false;

  @override
  bool get isClosed => _isClosed;

  @override
  Stream<VisionLiveResult<T>> get results => _controller.stream;

  void _ensureOpen() {
    if (_isClosed) {
      throw const MpException(MpStatus.failedPrecondition, 'The web vision task is closed.');
    }
  }

  @override
  Future<T> processImage(MpImage image, ImageProcessingOptions? processingOptions) {
    _ensureOpen();
    final List<JSAny?> arguments = <JSAny?>[webImageData(image)];
    if (processingOptions != null) arguments.add(webJsify(_processingOptions(processingOptions)));
    return Future<T>.value(convert(callWebMethod<JSAny?>(_task, imageMethod, arguments)));
  }

  @override
  Future<T> processVideo(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) {
    _ensureOpen();
    final List<JSAny?> arguments = <JSAny?>[webImageData(image), timestampMs.toJS];
    if (processingOptions != null) arguments.add(webJsify(_processingOptions(processingOptions)));
    return Future<T>.value(convert(callWebMethod<JSAny?>(_task, videoMethod, arguments)));
  }

  @override
  Future<void> processLive(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) {
    _ensureOpen();
    return _pending = _pending
        .then((_) async {
          final T result = await processVideo(image, timestampMs, processingOptions);
          if (!_isClosed) {
            _controller.add(
              VisionLiveResult<T>(result: result, input: image, timestampMs: timestampMs),
            );
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!_isClosed) _controller.addError(error, stackTrace);
        });
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _pending;
    callWebMethod<JSAny?>(_task, 'close');
    await _controller.close();
  }
}

final class _WebInteractiveSegmenter implements InteractiveSegmenterBackend {
  _WebInteractiveSegmenter({required this.createSplit, required this.createLegacy});

  final Future<JSObject> Function() createSplit;
  final Future<JSObject> Function() createLegacy;
  Future<JSObject>? _split;
  Future<JSObject>? _legacy;
  bool _isClosed = false;

  @override
  bool get isClosed => _isClosed;

  @override
  Future<ImageSegmenterResult> segment(
    MpImage image,
    InteractivePrompt prompt,
    ImageProcessingOptions? processingOptions,
  ) {
    if (_isClosed) {
      throw const MpException(MpStatus.failedPrecondition, 'The interactive segmenter is closed.');
    }
    return switch (prompt) {
      StrokePrompt(:final strokes) => _segmentStrokes(image, strokes),
      KeypointPrompt() || ScribblePrompt() => _segmentLegacy(image, prompt, processingOptions),
    };
  }

  Future<ImageSegmenterResult> _segmentStrokes(MpImage image, List<PromptStroke> strokes) async {
    final JSObject task = await (_split ??= createSplit());
    callWebMethod<JSAny?>(task, 'setImage', <JSAny?>[webImageData(image)]);
    final JSAny? mask = callWebMethod<JSAny?>(task, 'segment', <JSAny?>[
      webJsify(
        strokes
            .map(
              (PromptStroke stroke) => <String, Object?>{
                'brushMode': switch (stroke.brushMode) {
                  BrushMode.positive => 1,
                  BrushMode.negative => 2,
                  BrushMode.lasso => 3,
                },
                'point': stroke.points
                    .map((PromptPoint point) => <String, double>{'x': point.x, 'y': point.y})
                    .toList(),
                'isCompleted': stroke.isCompleted,
              },
            )
            .toList(),
      ),
    ]);
    return webSingleConfidenceMask(mask);
  }

  Future<ImageSegmenterResult> _segmentLegacy(
    MpImage image,
    InteractivePrompt prompt,
    ImageProcessingOptions? processingOptions,
  ) async {
    final JSObject task = await (_legacy ??= createLegacy());
    final Map<String, Object?> roi = switch (prompt) {
      KeypointPrompt(:final point) => <String, Object?>{
        'keypoint': <String, double>{'x': point.x, 'y': point.y},
      },
      ScribblePrompt(:final points) => <String, Object?>{
        'scribble': points
            .map((PromptPoint point) => <String, double>{'x': point.x, 'y': point.y})
            .toList(),
      },
      StrokePrompt() => throw StateError('Signed strokes use the split segmenter.'),
    };
    final List<JSAny?> arguments = <JSAny?>[webImageData(image), webJsify(roi)];
    if (processingOptions != null) arguments.add(webJsify(_processingOptions(processingOptions)));
    return webImageSegmenterResult(callWebMethod<JSAny?>(task, 'segment', arguments));
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    final Future<JSObject>? split = _split;
    final Future<JSObject>? legacy = _legacy;
    if (split != null) callWebMethod<JSAny?>(await split, 'close');
    if (legacy != null) callWebMethod<JSAny?>(await legacy, 'close');
  }
}

Map<String, Object?> _processingOptions(ImageProcessingOptions options) => <String, Object?>{
  'rotationDegrees': options.rotationDegrees,
  if (options.regionOfInterest case final NormalizedRect roi)
    'regionOfInterest': <String, double>{
      'left': roi.left,
      'top': roi.top,
      'right': roi.right,
      'bottom': roi.bottom,
    },
};
