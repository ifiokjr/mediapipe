import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/web.dart';

import 'audio_classifier.dart';
import 'runtime.dart';

final WebTaskAssets _defaultAssets = WebTaskAssets(
  moduleUri: Uri.parse(
    'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-audio@1.0.1/audio_bundle.mjs',
  ),
  wasmRoot: Uri.parse('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-audio@1.0.1/wasm'),
);

/// Creates the default web audio runtime.
AudioRuntime createAudioRuntime() => WebAudioRuntime();

/// Browser runtime backed by the official `@mediapipe/tasks-audio` package.
final class WebAudioRuntime implements AudioRuntime {
  /// Creates a runtime using [assets].
  WebAudioRuntime({WebTaskAssets? assets}) : assets = assets ?? _defaultAssets;

  /// Locations of the JavaScript module and Wasm files.
  final WebTaskAssets assets;

  @override
  Future<AudioClassifierBackend> createAudioClassifier(AudioClassifierOptions options) async {
    final JSObject module = await importWebTaskModule(assets.moduleUri);
    final JSObject resolver = requireWebObject(module, 'FilesetResolver');
    final JSPromise<JSObject> filesetPromise = callWebMethod<JSPromise<JSObject>>(
      resolver,
      'forAudioTasks',
      <JSAny?>[assets.wasmRoot.toString().toJS],
    );
    final JSObject taskClass = requireWebObject(module, 'AudioClassifier');
    final JSPromise<JSObject> taskPromise = callWebMethod<JSPromise<JSObject>>(
      taskClass,
      'createFromOptions',
      <JSAny?>[
        await filesetPromise.toDart,
        webJsify(<String, Object?>{
          'baseOptions': await resolveWebBaseOptions(options.baseOptions),
          ...webClassifierOptions(options.classifierOptions),
        }),
      ],
    );
    try {
      return _WebAudioClassifier(await taskPromise.toDart, options.runningMode);
    } on Object catch (error) {
      throw MpException(
        MpStatus.internal,
        'MediaPipe could not create AudioClassifier.',
        task: 'AudioClassifier',
        cause: error,
      );
    }
  }
}

final class _WebAudioClassifier implements AudioClassifierBackend {
  _WebAudioClassifier(this._task, this._runningMode);

  final JSObject _task;
  final AudioRunningMode _runningMode;
  final StreamController<AudioClassifierResult> _controller =
      StreamController<AudioClassifierResult>.broadcast();
  Future<void> _pending = Future<void>.value();
  bool _isClosed = false;

  @override
  bool get isClosed => _isClosed;

  @override
  Stream<AudioClassifierResult> get results => _controller.stream;

  void _ensureOpen() {
    if (_isClosed) {
      throw const MpException(MpStatus.failedPrecondition, 'The web audio task is closed.');
    }
  }

  @override
  Future<AudioClassifierResult> classify(AudioData audio) async {
    _ensureOpen();
    final Float32List mono = _toMono(audio);
    final JSAny? raw = callWebMethod<JSAny?>(_task, 'classify', <JSAny?>[
      mono.toJS,
      audio.sampleRateHz.toJS,
    ]);
    final List<Object?> windows = webDartify(raw)! as List<Object?>;
    return AudioClassifierResult(
      windows.map((Object? value) => webClassificationResult(value! as Map<Object?, Object?>)),
    );
  }

  @override
  Future<void> classifyAsync(AudioData audio, int timestampMs) {
    _ensureOpen();
    if (_runningMode != AudioRunningMode.audioStream) {
      throw const MpException(
        MpStatus.failedPrecondition,
        'classifyAsync requires audioStream mode.',
      );
    }
    return _pending = _pending
        .then((_) async {
          final AudioClassifierResult result = await classify(audio);
          if (_isClosed) return;
          _controller.add(
            AudioClassifierResult(
              result.classifications.map(
                (ClassificationResult classification) => ClassificationResult(
                  classifications: classification.classifications,
                  timestampMs: timestampMs + (classification.timestampMs ?? 0),
                ),
              ),
            ),
          );
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

Float32List _toMono(AudioData audio) {
  if (audio.channelCount == 1) return Float32List.fromList(audio.samples);
  final Float32List mono = Float32List(audio.frameCount);
  for (int frame = 0; frame < audio.frameCount; frame += 1) {
    double sum = 0;
    for (int channel = 0; channel < audio.channelCount; channel += 1) {
      sum += audio.samples[(frame * audio.channelCount) + channel];
    }
    mono[frame] = sum / audio.channelCount;
  }
  return mono;
}
