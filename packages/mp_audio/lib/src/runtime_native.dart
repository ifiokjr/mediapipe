import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' as native;

import 'audio_classifier.dart';
import 'runtime.dart';

/// Creates the MediaPipe C audio runtime used on native platforms.
AudioRuntime createAudioRuntime() => const _NativeAudioRuntime();

final class _NativeAudioRuntime implements AudioRuntime {
  const _NativeAudioRuntime();

  @override
  Future<AudioClassifierBackend> createAudioClassifier(AudioClassifierOptions options) async {
    if (options.runningMode == AudioRunningMode.audioStream) {
      throw const MpException(
        MpStatus.unimplemented,
        'Native streaming audio requires a callback-copy bridge that is not linked in this build.',
        task: 'AudioClassifier',
      );
    }
    final AudioClassifierOptions resolved = AudioClassifierOptions(
      baseOptions: BaseOptions(
        modelAsset: await native.resolveNativeModelAsset(options.baseOptions.modelAsset),
        delegate: options.baseOptions.delegate,
        liteRtOptions: options.baseOptions.liteRtOptions,
      ),
      classifierOptions: options.classifierOptions,
      runningMode: options.runningMode,
    );
    return _NativeAudioClassifier(
      await native.NativeTaskIsolate.spawn(
        factory: _createAudioWorker,
        initialMessage: resolved,
        debugName: 'mp_audio.audio_classifier',
      ),
    );
  }
}

final class _NativeAudioClassifier implements AudioClassifierBackend {
  _NativeAudioClassifier(this._worker);

  final native.NativeTaskIsolate _worker;
  final StreamController<AudioClassifierResult> _results =
      StreamController<AudioClassifierResult>.broadcast();
  Future<void> _tail = Future<void>.value();
  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Stream<AudioClassifierResult> get results => _results.stream;

  @override
  Future<AudioClassifierResult> classify(AudioData audio) =>
      _run(() => _worker.request<AudioClassifierResult>(audio));

  @override
  Future<void> classifyAsync(AudioData audio, int timestampMs) => throw const MpException(
    MpStatus.unimplemented,
    'Native streaming audio requires a callback-copy bridge that is not linked in this build.',
    task: 'AudioClassifier',
  );

  @override
  Future<void> close() => _run(() async {
    if (_closed) return;
    _closed = true;
    await _worker.request<void>(_AudioClose.instance);
    await _worker.dispose();
    await _results.close();
  });

  Future<T> _run<T>(Future<T> Function() action) {
    final Future<T> operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

final class _AudioClose {
  const _AudioClose._();

  static const _AudioClose instance = _AudioClose._();
}

native.NativeTaskWorkerHandler _createAudioWorker(Object? initialMessage) {
  final int address = _createAudioClassifier(initialMessage! as AudioClassifierOptions);
  return (Object? command) {
    if (command is _AudioClose) {
      _closeAudioClassifier(address);
      return null;
    }
    return _classifyAudio(address, command! as AudioData);
  };
}

int _createAudioClassifier(AudioClassifierOptions options) {
  final native.NativeScope scope = native.NativeScope(task: 'AudioClassifier');
  try {
    final ffi.Pointer<native.MpAudioClassifierOptions> nativeOptions = scope
        .allocator<native.MpAudioClassifierOptions>();
    nativeOptions.ref
      ..base_options = scope.baseOptions(options.baseOptions).ref
      ..classifier_options = scope.classifierOptions(options.classifierOptions).ref
      ..running_mode = native.MpAudioRunningMode.kMpAudioRunningModeAudioClips
      ..result_callback = ffi.nullptr;
    final ffi.Pointer<native.MpAudioClassifierPtr> output = scope
        .allocator<native.MpAudioClassifierPtr>();
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(native.MpAudioClassifierCreate(nativeOptions, output, error), error);
    return output.value.address;
  } finally {
    scope.release();
  }
}

AudioClassifierResult _classifyAudio(int address, AudioData audio) {
  final native.NativeScope scope = native.NativeScope(task: 'AudioClassifier');
  final ffi.Pointer<native.MpAudioClassifierResult> result = scope
      .allocator<native.MpAudioClassifierResult>();
  var ownsResult = false;
  try {
    final ffi.Pointer<ffi.Float> samples = scope.allocator<ffi.Float>(audio.samples.length);
    samples.asTypedList(audio.samples.length).setAll(0, audio.samples);
    final ffi.Pointer<native.MpAudioData> data = native.MpAudioData.$allocate(
      scope.allocator,
      num_channels: audio.channelCount,
      sample_rate: audio.sampleRateHz,
      audio_data: samples,
      audio_data_size: audio.samples.length,
    );
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(
      native.MpAudioClassifierClassify(
        ffi.Pointer<native.MpAudioClassifierInternal>.fromAddress(address),
        data,
        result,
        error,
      ),
      error,
    );
    ownsResult = true;
    return AudioClassifierResult(
      List<ClassificationResult>.generate(
        result.ref.results_count,
        (int index) => native.classificationResultFromNative(result.ref.results[index]),
        growable: false,
      ),
    );
  } finally {
    if (ownsResult) native.MpAudioClassifierCloseResult(result);
    scope.release();
  }
}

void _closeAudioClassifier(int address) {
  final native.NativeScope scope = native.NativeScope(task: 'AudioClassifier');
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(
      native.MpAudioClassifierClose(
        ffi.Pointer<native.MpAudioClassifierInternal>.fromAddress(address),
        error,
      ),
      error,
    );
  } finally {
    scope.release();
  }
}
