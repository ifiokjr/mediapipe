import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' as native;

import 'native_converters.dart';
import 'options.dart';
import 'results.dart';
import 'runtime.dart';

/// Creates the MediaPipe C vision runtime used on native platforms.
VisionRuntime createVisionRuntime() => const _NativeVisionRuntime();

enum _TaskKind {
  faceDetector,
  faceLandmarker,
  gestureRecognizer,
  handLandmarker,
  holisticLandmarker,
  imageClassifier,
  imageEmbedder,
  imageSegmenter,
  interactiveSegmenter,
  objectDetector,
  poseLandmarker,
}

extension on _TaskKind {
  String get taskName => switch (this) {
    _TaskKind.faceDetector => 'FaceDetector',
    _TaskKind.faceLandmarker => 'FaceLandmarker',
    _TaskKind.gestureRecognizer => 'GestureRecognizer',
    _TaskKind.handLandmarker => 'HandLandmarker',
    _TaskKind.holisticLandmarker => 'HolisticLandmarker',
    _TaskKind.imageClassifier => 'ImageClassifier',
    _TaskKind.imageEmbedder => 'ImageEmbedder',
    _TaskKind.imageSegmenter => 'ImageSegmenter',
    _TaskKind.interactiveSegmenter => 'InteractiveSegmenter',
    _TaskKind.objectDetector => 'ObjectDetector',
    _TaskKind.poseLandmarker => 'PoseLandmarker',
  };
}

final class _NativeVisionRuntime implements VisionRuntime {
  const _NativeVisionRuntime();

  Future<VisionTaskBackend<T>> _create<T>(_TaskKind kind, VisionTaskOptions options) async {
    final BaseOptions resolved = await _resolvedBaseOptions(options.baseOptions);
    return _NativeVisionBackend<T>(await _spawnVisionWorker(kind, options, resolved));
  }

  @override
  Future<VisionTaskBackend<DetectionResult>> createFaceDetector(FaceDetectorOptions options) =>
      _create<DetectionResult>(_TaskKind.faceDetector, options);

  @override
  Future<VisionTaskBackend<FaceLandmarkerResult>> createFaceLandmarker(
    FaceLandmarkerOptions options,
  ) => _create<FaceLandmarkerResult>(_TaskKind.faceLandmarker, options);

  @override
  Future<VisionTaskBackend<GestureRecognizerResult>> createGestureRecognizer(
    GestureRecognizerOptions options,
  ) => _create<GestureRecognizerResult>(_TaskKind.gestureRecognizer, options);

  @override
  Future<VisionTaskBackend<HandLandmarkerResult>> createHandLandmarker(
    HandLandmarkerOptions options,
  ) => _create<HandLandmarkerResult>(_TaskKind.handLandmarker, options);

  @override
  Future<VisionTaskBackend<HolisticLandmarkerResult>> createHolisticLandmarker(
    HolisticLandmarkerOptions options,
  ) => _create<HolisticLandmarkerResult>(_TaskKind.holisticLandmarker, options);

  @override
  Future<VisionTaskBackend<ClassificationResult>> createImageClassifier(
    ImageClassifierOptions options,
  ) => _create<ClassificationResult>(_TaskKind.imageClassifier, options);

  @override
  Future<VisionTaskBackend<EmbeddingResult>> createImageEmbedder(ImageEmbedderOptions options) =>
      _create<EmbeddingResult>(_TaskKind.imageEmbedder, options);

  @override
  Future<VisionTaskBackend<ImageSegmenterResult>> createImageSegmenter(
    ImageSegmenterOptions options,
  ) => _create<ImageSegmenterResult>(_TaskKind.imageSegmenter, options);

  @override
  Future<InteractiveSegmenterBackend> createInteractiveSegmenter(
    InteractiveSegmenterOptions options,
  ) async {
    final BaseOptions resolved = await _resolvedBaseOptions(options.baseOptions);
    return _NativeInteractiveSegmenter(
      await _spawnVisionWorker(_TaskKind.interactiveSegmenter, options, resolved),
    );
  }

  @override
  Future<VisionTaskBackend<DetectionResult>> createObjectDetector(ObjectDetectorOptions options) =>
      _create<DetectionResult>(_TaskKind.objectDetector, options);

  @override
  Future<VisionTaskBackend<PoseLandmarkerResult>> createPoseLandmarker(
    PoseLandmarkerOptions options,
  ) => _create<PoseLandmarkerResult>(_TaskKind.poseLandmarker, options);
}

final class _NativeVisionBackend<T> implements VisionTaskBackend<T> {
  _NativeVisionBackend(this._worker);

  final native.NativeTaskIsolate _worker;
  final StreamController<VisionLiveResult<T>> _results =
      StreamController<VisionLiveResult<T>>.broadcast();
  Future<void> _tail = Future<void>.value();
  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Stream<VisionLiveResult<T>> get results => _results.stream;

  @override
  Future<T> processImage(MpImage image, ImageProcessingOptions? processingOptions) => _run(
    () async =>
        await _worker.request<Object>(_VisionProcess(image, processingOptions: processingOptions))
            as T,
  );

  @override
  Future<T> processVideo(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) => _run(
    () async =>
        await _worker.request<Object>(
              _VisionProcess(image, timestampMs: timestampMs, processingOptions: processingOptions),
            )
            as T,
  );

  @override
  Future<void> processLive(
    MpImage image,
    int timestampMs,
    ImageProcessingOptions? processingOptions,
  ) => _run(() async {
    final T result =
        await _worker.request<Object>(
              _VisionProcess(image, timestampMs: timestampMs, processingOptions: processingOptions),
            )
            as T;
    _results.add(VisionLiveResult<T>(result: result, input: image, timestampMs: timestampMs));
  });

  @override
  Future<void> close() => _run(() async {
    if (_closed) return;
    _closed = true;
    await _worker.request<void>(_VisionClose.instance);
    await _worker.dispose();
    await _results.close();
  });

  Future<R> _run<R>(Future<R> Function() action) {
    final Future<R> operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

final class _NativeInteractiveSegmenter implements InteractiveSegmenterBackend {
  _NativeInteractiveSegmenter(this._worker);

  final native.NativeTaskIsolate _worker;
  Future<void> _tail = Future<void>.value();
  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<ImageSegmenterResult> segment(
    MpImage image,
    InteractivePrompt prompt,
    ImageProcessingOptions? processingOptions,
  ) {
    final Future<ImageSegmenterResult> operation = _tail.then(
      (_) => _worker.request<ImageSegmenterResult>(
        _InteractiveProcess(image, prompt, processingOptions: processingOptions),
      ),
    );
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  @override
  Future<void> close() {
    final Future<void> operation = _tail.then((_) async {
      if (_closed) return;
      _closed = true;
      await _worker.request<void>(_VisionClose.instance);
      await _worker.dispose();
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

final class _VisionWorkerInit {
  const _VisionWorkerInit(this.kind, this.options, this.baseOptions);

  final _TaskKind kind;
  final VisionTaskOptions options;
  final BaseOptions baseOptions;
}

final class _VisionProcess {
  const _VisionProcess(this.image, {this.timestampMs, this.processingOptions});

  final MpImage image;
  final int? timestampMs;
  final ImageProcessingOptions? processingOptions;
}

final class _InteractiveProcess {
  const _InteractiveProcess(this.image, this.prompt, {this.processingOptions});

  final MpImage image;
  final InteractivePrompt prompt;
  final ImageProcessingOptions? processingOptions;
}

final class _VisionClose {
  const _VisionClose._();

  static const _VisionClose instance = _VisionClose._();
}

Future<native.NativeTaskIsolate> _spawnVisionWorker(
  _TaskKind kind,
  VisionTaskOptions options,
  BaseOptions baseOptions,
) => native.NativeTaskIsolate.spawn(
  factory: _createVisionWorker,
  initialMessage: _VisionWorkerInit(kind, options, baseOptions),
  debugName: 'mp_vision.${kind.name}',
);

native.NativeTaskWorkerHandler _createVisionWorker(Object? initialMessage) {
  final _VisionWorkerInit initialization = initialMessage! as _VisionWorkerInit;
  final int address = _createTask(
    initialization.kind,
    initialization.options,
    initialization.baseOptions,
  );
  return (Object? command) {
    if (command is _VisionClose) {
      _closeTask(initialization.kind, address);
      return null;
    }
    if (command case final _InteractiveProcess request) {
      return _segmentInteractive(address, request.image, request.prompt, request.processingOptions);
    }
    final _VisionProcess request = command! as _VisionProcess;
    return _processTask(
      initialization.kind,
      address,
      request.image,
      request.timestampMs,
      request.processingOptions,
    );
  };
}

Future<BaseOptions> _resolvedBaseOptions(BaseOptions options) async => BaseOptions(
  modelAsset: await native.resolveNativeModelAsset(options.modelAsset),
  delegate: options.delegate,
  liteRtOptions: options.liteRtOptions,
);

int _createTask(_TaskKind kind, VisionTaskOptions options, BaseOptions baseOptions) {
  final native.NativeScope scope = native.NativeScope(task: kind.taskName);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    return switch (kind) {
      _TaskKind.faceDetector => _createFaceDetector(
        scope,
        options as FaceDetectorOptions,
        baseOptions,
        error,
      ),
      _TaskKind.faceLandmarker => _createFaceLandmarker(
        scope,
        options as FaceLandmarkerOptions,
        baseOptions,
        error,
      ),
      _TaskKind.gestureRecognizer => _createGestureRecognizer(
        scope,
        options as GestureRecognizerOptions,
        baseOptions,
        error,
      ),
      _TaskKind.handLandmarker => _createHandLandmarker(
        scope,
        options as HandLandmarkerOptions,
        baseOptions,
        error,
      ),
      _TaskKind.holisticLandmarker => _createHolisticLandmarker(
        scope,
        options as HolisticLandmarkerOptions,
        baseOptions,
        error,
      ),
      _TaskKind.imageClassifier => _createImageClassifier(
        scope,
        options as ImageClassifierOptions,
        baseOptions,
        error,
      ),
      _TaskKind.imageEmbedder => _createImageEmbedder(
        scope,
        options as ImageEmbedderOptions,
        baseOptions,
        error,
      ),
      _TaskKind.imageSegmenter => _createImageSegmenter(
        scope,
        options as ImageSegmenterOptions,
        baseOptions,
        error,
      ),
      _TaskKind.interactiveSegmenter => _createInteractiveSegmenter(
        scope,
        options as InteractiveSegmenterOptions,
        baseOptions,
        error,
      ),
      _TaskKind.objectDetector => _createObjectDetector(
        scope,
        options as ObjectDetectorOptions,
        baseOptions,
        error,
      ),
      _TaskKind.poseLandmarker => _createPoseLandmarker(
        scope,
        options as PoseLandmarkerOptions,
        baseOptions,
        error,
      ),
    };
  } finally {
    scope.release();
  }
}

native.MpRunningMode _runningMode(VisionRunningMode mode) => switch (mode) {
  VisionRunningMode.image => native.MpRunningMode.MP_RUNNING_MODE_IMAGE,
  VisionRunningMode.video ||
  VisionRunningMode.liveStream => native.MpRunningMode.MP_RUNNING_MODE_VIDEO,
};

int _createFaceDetector(
  native.NativeScope scope,
  FaceDetectorOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.MpFaceDetectorOptions> input = scope
      .allocator<native.MpFaceDetectorOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..min_detection_confidence = options.minDetectionConfidence
    ..min_suppression_threshold = options.minSuppressionThreshold
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpFaceDetectorPtr> output = scope.allocator<native.MpFaceDetectorPtr>();
  scope.check(native.MpFaceDetectorCreate(input, output, error), error);
  return output.value.address;
}

int _createFaceLandmarker(
  native.NativeScope scope,
  FaceLandmarkerOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.MpFaceLandmarkerOptions> input = scope
      .allocator<native.MpFaceLandmarkerOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..num_faces = options.numFaces
    ..min_face_detection_confidence = options.minFaceDetectionConfidence
    ..min_face_presence_confidence = options.minFacePresenceConfidence
    ..min_tracking_confidence = options.minTrackingConfidence
    ..output_face_blendshapes = options.outputFaceBlendshapes
    ..output_facial_transformation_matrixes = options.outputFacialTransformationMatrixes
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpFaceLandmarkerPtr> output = scope
      .allocator<native.MpFaceLandmarkerPtr>();
  scope.check(native.MpFaceLandmarkerCreate(input, output, error), error);
  return output.value.address;
}

int _createGestureRecognizer(
  native.NativeScope scope,
  GestureRecognizerOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.MpGestureRecognizerOptions> input = scope
      .allocator<native.MpGestureRecognizerOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..num_hands = options.numHands
    ..min_hand_detection_confidence = options.minHandDetectionConfidence
    ..min_hand_presence_confidence = options.minHandPresenceConfidence
    ..min_tracking_confidence = options.minTrackingConfidence
    ..canned_gestures_classifier_options = scope
        .classifierOptions(options.cannedGesturesClassifierOptions)
        .ref
    ..custom_gestures_classifier_options = scope
        .classifierOptions(options.customGesturesClassifierOptions)
        .ref
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpGestureRecognizerPtr> output = scope
      .allocator<native.MpGestureRecognizerPtr>();
  scope.check(native.MpGestureRecognizerCreate(input, output, error), error);
  return output.value.address;
}

int _createHandLandmarker(
  native.NativeScope scope,
  HandLandmarkerOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.MpHandLandmarkerOptions> input = scope
      .allocator<native.MpHandLandmarkerOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..num_hands = options.numHands
    ..min_hand_detection_confidence = options.minHandDetectionConfidence
    ..min_hand_presence_confidence = options.minHandPresenceConfidence
    ..min_tracking_confidence = options.minTrackingConfidence
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpHandLandmarkerPtr> output = scope
      .allocator<native.MpHandLandmarkerPtr>();
  scope.check(native.MpHandLandmarkerCreate(input, output, error), error);
  return output.value.address;
}

int _createHolisticLandmarker(
  native.NativeScope scope,
  HolisticLandmarkerOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.MpHolisticLandmarkerOptions> input = scope
      .allocator<native.MpHolisticLandmarkerOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..min_face_detection_confidence = options.minFaceDetectionConfidence
    ..min_face_suppression_threshold = options.minFaceSuppressionThreshold
    ..min_face_presence_confidence = options.minFacePresenceConfidence
    ..min_hand_landmarks_confidence = options.minHandLandmarksConfidence
    ..min_pose_detection_confidence = options.minPoseDetectionConfidence
    ..min_pose_suppression_threshold = options.minPoseSuppressionThreshold
    ..min_pose_presence_confidence = options.minPosePresenceConfidence
    ..output_face_blendshapes = options.outputFaceBlendshapes
    ..output_pose_segmentation_masks = options.outputPoseSegmentationMasks
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpHolisticLandmarkerPtr> output = scope
      .allocator<native.MpHolisticLandmarkerPtr>();
  scope.check(native.MpHolisticLandmarkerCreate(input, output, error), error);
  return output.value.address;
}

int _createImageClassifier(
  native.NativeScope scope,
  ImageClassifierOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.MpImageClassifierOptions> input = scope
      .allocator<native.MpImageClassifierOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..classifier_options = scope.classifierOptions(options.classifierOptions).ref
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpImageClassifierPtr> output = scope
      .allocator<native.MpImageClassifierPtr>();
  scope.check(native.MpImageClassifierCreate(input, output, error), error);
  return output.value.address;
}

int _createImageEmbedder(
  native.NativeScope scope,
  ImageEmbedderOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.ImageEmbedderOptions> input = scope
      .allocator<native.ImageEmbedderOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..embedder_options = scope.embedderOptions(options.embedderOptions).ref
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpImageEmbedderPtr> output = scope
      .allocator<native.MpImageEmbedderPtr>();
  scope.check(native.MpImageEmbedderCreate(input, output, error), error);
  return output.value.address;
}

int _createImageSegmenter(
  native.NativeScope scope,
  ImageSegmenterOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.MpImageSegmenterOptions> input = scope
      .allocator<native.MpImageSegmenterOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..display_names_locale = scope.string(options.displayNamesLocale)
    ..output_confidence_masks = options.outputConfidenceMasks
    ..output_category_mask = options.outputCategoryMask
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpImageSegmenterPtr> output = scope
      .allocator<native.MpImageSegmenterPtr>();
  scope.check(native.MpImageSegmenterCreate(input, output, error), error);
  return output.value.address;
}

int _createInteractiveSegmenter(
  native.NativeScope scope,
  InteractiveSegmenterOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.MpInteractiveSegmenterLegacyOptions> input = scope
      .allocator<native.MpInteractiveSegmenterLegacyOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..output_confidence_masks = options.outputConfidenceMasks
    ..output_category_mask = options.outputCategoryMask;
  final ffi.Pointer<native.MpInteractiveSegmenterLegacyPtr> output = scope
      .allocator<native.MpInteractiveSegmenterLegacyPtr>();
  scope.check(native.MpInteractiveSegmenterLegacyCreate(input, output, error), error);
  return output.value.address;
}

int _createObjectDetector(
  native.NativeScope scope,
  ObjectDetectorOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ClassifierOptions filters = options.classifierOptions ?? ClassifierOptions();
  final ffi.Pointer<native.MpObjectDetectorOptions> input = scope
      .allocator<native.MpObjectDetectorOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..display_names_locale = scope.string(filters.displayNamesLocale)
    ..max_results = filters.maxResults ?? -1
    ..score_threshold = filters.scoreThreshold ?? 0
    ..category_allowlist = scope.strings(filters.categoryAllowlist)
    ..category_allowlist_count = filters.categoryAllowlist.length
    ..category_denylist = scope.strings(filters.categoryDenylist)
    ..category_denylist_count = filters.categoryDenylist.length
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpObjectDetectorPtr> output = scope
      .allocator<native.MpObjectDetectorPtr>();
  scope.check(native.MpObjectDetectorCreate(input, output, error), error);
  return output.value.address;
}

int _createPoseLandmarker(
  native.NativeScope scope,
  PoseLandmarkerOptions options,
  BaseOptions base,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<native.MpPoseLandmarkerOptions> input = scope
      .allocator<native.MpPoseLandmarkerOptions>();
  input.ref
    ..base_options = scope.baseOptions(base).ref
    ..running_mode = _runningMode(options.runningMode)
    ..num_poses = options.numPoses
    ..min_pose_detection_confidence = options.minPoseDetectionConfidence
    ..min_pose_presence_confidence = options.minPosePresenceConfidence
    ..min_tracking_confidence = options.minTrackingConfidence
    ..output_segmentation_masks = options.outputSegmentationMasks
    ..result_callback = ffi.nullptr;
  final ffi.Pointer<native.MpPoseLandmarkerPtr> output = scope
      .allocator<native.MpPoseLandmarkerPtr>();
  scope.check(native.MpPoseLandmarkerCreate(input, output, error), error);
  return output.value.address;
}

Object _processTask(
  _TaskKind kind,
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) => switch (kind) {
  _TaskKind.faceDetector => _processFaceDetector(address, image, timestampMs, processingOptions),
  _TaskKind.faceLandmarker => _processFaceLandmarker(
    address,
    image,
    timestampMs,
    processingOptions,
  ),
  _TaskKind.gestureRecognizer => _processGestureRecognizer(
    address,
    image,
    timestampMs,
    processingOptions,
  ),
  _TaskKind.handLandmarker => _processHandLandmarker(
    address,
    image,
    timestampMs,
    processingOptions,
  ),
  _TaskKind.holisticLandmarker => _processHolisticLandmarker(
    address,
    image,
    timestampMs,
    processingOptions,
  ),
  _TaskKind.imageClassifier => _processImageClassifier(
    address,
    image,
    timestampMs,
    processingOptions,
  ),
  _TaskKind.imageEmbedder => _processImageEmbedder(address, image, timestampMs, processingOptions),
  _TaskKind.imageSegmenter => _processImageSegmenter(
    address,
    image,
    timestampMs,
    processingOptions,
  ),
  _TaskKind.objectDetector => _processObjectDetector(
    address,
    image,
    timestampMs,
    processingOptions,
  ),
  _TaskKind.poseLandmarker => _processPoseLandmarker(
    address,
    image,
    timestampMs,
    processingOptions,
  ),
  _TaskKind.interactiveSegmenter => throw StateError('Use the interactive task entrypoint.'),
};

DetectionResult _processFaceDetector(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'FaceDetector');
  final ffi.Pointer<native.MpFaceDetectorResult> result = scope
      .allocator<native.MpFaceDetectorResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpFaceDetectorDetectImage(
            ffi.Pointer<native.MpFaceDetectorInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpFaceDetectorDetectForVideo(
            ffi.Pointer<native.MpFaceDetectorInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return native.detectionResultFromNative(result.ref, timestampMs: timestampMs);
  } finally {
    if (ownsResult) native.MpFaceDetectorCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

FaceLandmarkerResult _processFaceLandmarker(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'FaceLandmarker');
  final ffi.Pointer<native.MpFaceLandmarkerResult> result = scope
      .allocator<native.MpFaceLandmarkerResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpFaceLandmarkerDetectImage(
            ffi.Pointer<native.MpFaceLandmarkerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpFaceLandmarkerDetectForVideo(
            ffi.Pointer<native.MpFaceLandmarkerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return faceLandmarkerResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpFaceLandmarkerCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

GestureRecognizerResult _processGestureRecognizer(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'GestureRecognizer');
  final ffi.Pointer<native.MpGestureRecognizerResult> result = scope
      .allocator<native.MpGestureRecognizerResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpGestureRecognizerRecognizeImage(
            ffi.Pointer<native.MpGestureRecognizerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpGestureRecognizerRecognizeForVideo(
            ffi.Pointer<native.MpGestureRecognizerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return gestureRecognizerResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpGestureRecognizerCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

HandLandmarkerResult _processHandLandmarker(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'HandLandmarker');
  final ffi.Pointer<native.MpHandLandmarkerResult> result = scope
      .allocator<native.MpHandLandmarkerResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpHandLandmarkerDetectImage(
            ffi.Pointer<native.MpHandLandmarkerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpHandLandmarkerDetectForVideo(
            ffi.Pointer<native.MpHandLandmarkerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return handLandmarkerResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpHandLandmarkerCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

HolisticLandmarkerResult _processHolisticLandmarker(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'HolisticLandmarker');
  final ffi.Pointer<native.MpHolisticLandmarkerResult> result = scope
      .allocator<native.MpHolisticLandmarkerResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpHolisticLandmarkerDetectImage(
            ffi.Pointer<native.MpHolisticLandmarkerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpHolisticLandmarkerDetectForVideo(
            ffi.Pointer<native.MpHolisticLandmarkerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return holisticLandmarkerResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpHolisticLandmarkerCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

ClassificationResult _processImageClassifier(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'ImageClassifier');
  final ffi.Pointer<native.MpImageClassifierResult> result = scope
      .allocator<native.MpImageClassifierResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpImageClassifierClassifyImage(
            ffi.Pointer<native.MpImageClassifierInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpImageClassifierClassifyForVideo(
            ffi.Pointer<native.MpImageClassifierInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return native.classificationResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpImageClassifierCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

EmbeddingResult _processImageEmbedder(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'ImageEmbedder');
  final ffi.Pointer<native.ImageEmbedderResult> result = scope
      .allocator<native.ImageEmbedderResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpImageEmbedderEmbedImage(
            ffi.Pointer<native.MpImageEmbedderInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpImageEmbedderEmbedForVideo(
            ffi.Pointer<native.MpImageEmbedderInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return native.embeddingResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpImageEmbedderCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

ImageSegmenterResult _processImageSegmenter(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'ImageSegmenter');
  final ffi.Pointer<native.MpImageSegmenterResult> result = scope
      .allocator<native.MpImageSegmenterResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpImageSegmenterSegmentImage(
            ffi.Pointer<native.MpImageSegmenterInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpImageSegmenterSegmentForVideo(
            ffi.Pointer<native.MpImageSegmenterInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return imageSegmenterResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpImageSegmenterCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

DetectionResult _processObjectDetector(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'ObjectDetector');
  final ffi.Pointer<native.MpObjectDetectorResult> result = scope
      .allocator<native.MpObjectDetectorResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpObjectDetectorDetectImage(
            ffi.Pointer<native.MpObjectDetectorInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpObjectDetectorDetectForVideo(
            ffi.Pointer<native.MpObjectDetectorInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return native.detectionResultFromNative(result.ref, timestampMs: timestampMs);
  } finally {
    if (ownsResult) native.MpObjectDetectorCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

PoseLandmarkerResult _processPoseLandmarker(
  int address,
  MpImage image,
  int? timestampMs,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'PoseLandmarker');
  final ffi.Pointer<native.MpPoseLandmarkerResult> result = scope
      .allocator<native.MpPoseLandmarkerResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = timestampMs == null
        ? native.MpPoseLandmarkerDetectImage(
            ffi.Pointer<native.MpPoseLandmarkerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            result,
            error,
          )
        : native.MpPoseLandmarkerDetectForVideo(
            ffi.Pointer<native.MpPoseLandmarkerInternal>.fromAddress(address),
            input,
            scope.imageProcessingOptions(processingOptions),
            timestampMs,
            result,
            error,
          );
    scope.check(status, error);
    ownsResult = true;
    return poseLandmarkerResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpPoseLandmarkerCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

ImageSegmenterResult _segmentInteractive(
  int address,
  MpImage image,
  InteractivePrompt prompt,
  ImageProcessingOptions? processingOptions,
) {
  final native.NativeScope scope = native.NativeScope(task: 'InteractiveSegmenter');
  final ffi.Pointer<native.MpImageSegmenterResult> result = scope
      .allocator<native.MpImageSegmenterResult>();
  var ownsResult = false;
  final native.MpImagePtr input = scope.image(image);
  try {
    final ffi.Pointer<native.MpRegionOfInterest> region = _interactiveRegion(scope, prompt);
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(
      native.MpInteractiveSegmenterLegacySegmentImage(
        ffi.Pointer<native.MpInteractiveSegmenterLegacyInternal>.fromAddress(address),
        input,
        region,
        scope.imageProcessingOptions(processingOptions),
        result,
        error,
      ),
      error,
    );
    ownsResult = true;
    return imageSegmenterResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpInteractiveSegmenterLegacyCloseResult(result);
    native.MpImageFree(input);
    scope.release();
  }
}

ffi.Pointer<native.MpRegionOfInterest> _interactiveRegion(
  native.NativeScope scope,
  InteractivePrompt prompt,
) {
  switch (prompt) {
    case KeypointPrompt(:final point):
      final ffi.Pointer<native.MpNormalizedKeypoint> keypoint = scope
          .allocator<native.MpNormalizedKeypoint>();
      keypoint.ref
        ..x = point.x
        ..y = point.y
        ..label = ffi.nullptr
        ..score = 0
        ..has_score = false;
      return native.MpRegionOfInterest.$allocate(
        scope.allocator,
        format: native.MpRegionOfInterestFormat.MP_REGION_OF_INTEREST_FORMAT_KEYPOINT,
        keypoint: keypoint,
        scribble: ffi.nullptr,
        scribble_count: 0,
      );
    case ScribblePrompt(:final points):
      final ffi.Pointer<native.MpNormalizedKeypoint> scribble = scope
          .allocator<native.MpNormalizedKeypoint>(points.length);
      for (var index = 0; index < points.length; index += 1) {
        scribble[index]
          ..x = points[index].x
          ..y = points[index].y
          ..label = ffi.nullptr
          ..score = 0
          ..has_score = false;
      }
      return native.MpRegionOfInterest.$allocate(
        scope.allocator,
        format: native.MpRegionOfInterestFormat.MP_REGION_OF_INTEREST_FORMAT_SCRIBBLE,
        keypoint: ffi.nullptr,
        scribble: scribble,
        scribble_count: points.length,
      );
    case StrokePrompt():
      throw const MpException(
        MpStatus.unimplemented,
        'Signed brush strokes are currently available only in the web runtime.',
        task: 'InteractiveSegmenter',
      );
  }
}

void _closeTask(_TaskKind kind, int address) {
  final native.NativeScope scope = native.NativeScope(task: kind.taskName);
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    final native.MpStatus status = switch (kind) {
      _TaskKind.faceDetector => native.MpFaceDetectorClose(
        ffi.Pointer<native.MpFaceDetectorInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.faceLandmarker => native.MpFaceLandmarkerClose(
        ffi.Pointer<native.MpFaceLandmarkerInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.gestureRecognizer => native.MpGestureRecognizerClose(
        ffi.Pointer<native.MpGestureRecognizerInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.handLandmarker => native.MpHandLandmarkerClose(
        ffi.Pointer<native.MpHandLandmarkerInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.holisticLandmarker => native.MpHolisticLandmarkerClose(
        ffi.Pointer<native.MpHolisticLandmarkerInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.imageClassifier => native.MpImageClassifierClose(
        ffi.Pointer<native.MpImageClassifierInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.imageEmbedder => native.MpImageEmbedderClose(
        ffi.Pointer<native.MpImageEmbedderInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.imageSegmenter => native.MpImageSegmenterClose(
        ffi.Pointer<native.MpImageSegmenterInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.interactiveSegmenter => native.MpInteractiveSegmenterLegacyClose(
        ffi.Pointer<native.MpInteractiveSegmenterLegacyInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.objectDetector => native.MpObjectDetectorClose(
        ffi.Pointer<native.MpObjectDetectorInternal>.fromAddress(address),
        error,
      ),
      _TaskKind.poseLandmarker => native.MpPoseLandmarkerClose(
        ffi.Pointer<native.MpPoseLandmarkerInternal>.fromAddress(address),
        error,
      ),
    };
    scope.check(status, error);
  } finally {
    scope.release();
  }
}
