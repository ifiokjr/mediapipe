import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/web.dart';

import 'llm_inference.dart';
import 'options.dart';
import 'runtime.dart';

final WebTaskAssets _defaultAssets = WebTaskAssets(
  moduleUri: Uri.parse(
    'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.29/genai_bundle.mjs',
  ),
  wasmRoot: Uri.parse('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.29/wasm'),
);

/// Creates the default web generative AI runtime.
GenAiRuntime createGenAiRuntime() => WebGenAiRuntime();

/// Browser runtime backed by the official `@mediapipe/tasks-genai` package.
final class WebGenAiRuntime implements GenAiRuntime {
  /// Creates a runtime using [assets].
  WebGenAiRuntime({WebTaskAssets? assets}) : assets = assets ?? _defaultAssets;

  /// Locations of the JavaScript module and Wasm files.
  final WebTaskAssets assets;

  @override
  Future<LlmInferenceBackend> createLlmInference(LlmInferenceOptions options) async {
    final JSObject module = await importWebTaskModule(assets.moduleUri);
    final JSObject resolver = requireWebObject(module, 'FilesetResolver');
    final JSPromise<JSObject> filesetPromise = callWebMethod<JSPromise<JSObject>>(
      resolver,
      'forGenAiTasks',
      <JSAny?>[assets.wasmRoot.toString().toJS],
    );
    final JSObject taskClass = requireWebObject(module, 'LlmInference');
    final JSPromise<JSObject> taskPromise = callWebMethod<JSPromise<JSObject>>(
      taskClass,
      'createFromOptions',
      <JSAny?>[
        await filesetPromise.toDart,
        webJsify(<String, Object?>{
          'baseOptions': await _llmBaseOptions(options),
          'maxTokens': options.maxTokens,
          'topK': options.maxTopK,
          'loraRanks': options.supportedLoraRanks,
          'numResponses': 1,
          'forceF32': options.forceF32,
          'maxNumImages': options.maxNumImages,
          'supportAudio': options.supportAudio,
          'disableRewinding': options.disableRewinding,
        }),
      ],
    );
    try {
      return _WebLlmInference(await taskPromise.toDart);
    } on Object catch (error) {
      throw MpException(
        MpStatus.internal,
        'MediaPipe could not create LlmInference.',
        task: 'LlmInference',
        cause: error,
      );
    }
  }
}

Future<Map<String, Object?>> _llmBaseOptions(LlmInferenceOptions options) async {
  final Map<String, Object?> result = await resolveWebBaseOptions(options.baseOptions);
  result['delegate'] = switch (options.preferredBackend) {
    LlmBackend.defaultBackend => result['delegate'],
    LlmBackend.cpu => 'CPU',
    LlmBackend.gpu => 'GPU',
  };
  return result;
}

final class _WebLlmInference implements LlmInferenceBackend {
  _WebLlmInference(this._task);

  final JSObject _task;
  Future<void> _pending = Future<void>.value();
  bool _isClosed = false;

  @override
  bool get isClosed => _isClosed;

  void _ensureOpen() {
    if (_isClosed) {
      throw const MpException(MpStatus.failedPrecondition, 'The web LLM task is closed.');
    }
  }

  @override
  Future<LlmSessionBackend> createSession(LlmSessionOptions options) async {
    _ensureOpen();
    _validateWebSessionOptions(options);
    return _WebLlmSession(this, options);
  }

  @override
  Future<int> sizeInTokens(String text) async {
    _ensureOpen();
    final JSAny? result = callWebMethod<JSAny?>(_task, 'sizeInTokens', <JSAny?>[text.toJS]);
    final int? count = webOptionalInt(webDartify(result));
    if (count == null) {
      throw const MpException(MpStatus.internal, 'MediaPipe could not count the input tokens.');
    }
    return count;
  }

  LlmGeneration generate(List<Object> prompt, LlmSessionOptions options) {
    _ensureOpen();
    final StreamController<LlmGenerationChunk> controller =
        StreamController<LlmGenerationChunk>.broadcast();
    final Completer<String> response = Completer<String>();
    bool doneChunkSent = false;

    _pending = _pending
        .catchError((Object _) {})
        .then((_) async {
          _ensureOpen();
          await _applyOptions(options);
          JSObject? lora;
          if (options.loraAsset case final ModelAsset asset) {
            final JSPromise<JSObject> loadPromise = callWebMethod<JSPromise<JSObject>>(
              _task,
              'loadLoraModel',
              <JSAny?>[_modelAssetValue(asset)],
            );
            lora = await loadPromise.toDart;
          }

          void onProgress(JSString partial, JSBoolean done) {
            if (controller.isClosed) return;
            final bool isDone = done.toDart;
            doneChunkSent = doneChunkSent || isDone;
            controller.add(LlmGenerationChunk(text: partial.toDart, isDone: isDone));
          }

          final JSFunction listener = onProgress.toJS;
          final List<JSAny?> arguments = <JSAny?>[webJsify(prompt)];
          if (lora != null) arguments.add(lora);
          arguments.add(listener);
          final JSPromise<JSString> promise = callWebMethod<JSPromise<JSString>>(
            _task,
            'generateResponse',
            arguments,
          );
          final String finalResponse = (await promise.toDart).toDart;
          if (!doneChunkSent && !controller.isClosed) {
            controller.add(const LlmGenerationChunk(text: '', isDone: true));
          }
          if (!response.isCompleted) response.complete(finalResponse);
          await controller.close();
          callWebMethod<JSAny?>(_task, 'clearCancelSignals');
        })
        .catchError((Object error, StackTrace stackTrace) async {
          if (!response.isCompleted) response.completeError(error, stackTrace);
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
            await controller.close();
          }
        });

    return LlmGeneration(
      chunks: controller.stream,
      response: response.future,
      cancel: () async {
        if (!_isClosed) callWebMethod<JSAny?>(_task, 'cancelProcessing');
      },
    );
  }

  Future<void> _applyOptions(LlmSessionOptions options) async {
    final JSPromise<JSAny?> promise = callWebMethod<JSPromise<JSAny?>>(
      _task,
      'setOptions',
      <JSAny?>[
        webJsify(<String, Object?>{
          'topK': options.topK,
          'temperature': options.temperature,
          'randomSeed': options.randomSeed,
          'numResponses': options.numResponses,
        }),
      ],
    );
    await promise.toDart;
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    await _pending;
    _isClosed = true;
    callWebMethod<JSAny?>(_task, 'close');
  }
}

final class _WebLlmSession implements LlmSessionBackend {
  _WebLlmSession(this._engine, this._options);

  final _WebLlmInference _engine;
  final List<Object> _prompt = <Object>[];
  LlmSessionOptions _options;
  bool _isClosed = false;

  @override
  bool get isClosed => _isClosed;

  void _ensureOpen() {
    if (_isClosed) {
      throw const MpException(MpStatus.failedPrecondition, 'The web LLM session is closed.');
    }
  }

  @override
  Future<void> addQueryChunk(String text) async {
    _ensureOpen();
    final PromptTemplates? templates = _options.promptTemplates;
    _prompt.add(templates == null ? text : '${templates.userPrefix}$text${templates.userSuffix}');
  }

  @override
  Future<void> addImage(MpImage image) async {
    _ensureOpen();
    _prompt.add(<String, Object?>{'imageSource': webImageData(image)});
  }

  @override
  Future<void> addAudio(Uint8List wavBytes) async {
    _ensureOpen();
    final ({Float32List samples, double sampleRateHz}) audio = _decodeWav(wavBytes);
    _prompt.add(<String, Object?>{
      'audioSource': <String, Object?>{
        'audioSampleRateHz': audio.sampleRateHz,
        'audioSamples': audio.samples,
      },
    });
  }

  @override
  Future<LlmGeneration> generate() async {
    _ensureOpen();
    if (_prompt.isEmpty) {
      throw const MpException(MpStatus.invalidArgument, 'The LLM prompt is empty.');
    }
    final List<Object> prompt = List<Object>.of(_prompt);
    if (_options.promptTemplates case final PromptTemplates templates) {
      final String suffix = '${templates.modelPrefix}${templates.modelSuffix}';
      if (suffix.isNotEmpty) prompt.add(suffix);
    }
    return _engine.generate(prompt, _options);
  }

  @override
  Future<int> sizeInTokens(String text) {
    _ensureOpen();
    return _engine.sizeInTokens(text);
  }

  @override
  Future<LlmSessionBackend> clone() async {
    _ensureOpen();
    final _WebLlmSession clone = _WebLlmSession(_engine, _options);
    clone._prompt.addAll(_prompt);
    return clone;
  }

  @override
  Future<void> updateOptions(LlmSessionOptions options) async {
    _ensureOpen();
    _validateWebSessionOptions(options);
    _options = options;
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    _prompt.clear();
  }
}

void _validateWebSessionOptions(LlmSessionOptions options) {
  if (options.topP != 1) {
    throw const MpException(
      MpStatus.unimplemented,
      'The MediaPipe web LLM runtime does not expose nucleus sampling.',
    );
  }
  if (options.constraintHandle != null) {
    throw const MpException(
      MpStatus.unimplemented,
      'Native constrained-decoding handles cannot be used on the web.',
    );
  }
}

JSAny? _modelAssetValue(ModelAsset asset) => switch (asset) {
  ModelAssetPath(:final path) => path.toJS,
  ModelAssetUri(:final uri) => uri.toString().toJS,
  ModelAssetBytes(:final bytes) => bytes.toJS,
};

({Float32List samples, double sampleRateHz}) _decodeWav(Uint8List bytes) {
  final ByteData data = ByteData.sublistView(bytes);
  if (bytes.length < 44 || _ascii(bytes, 0, 4) != 'RIFF' || _ascii(bytes, 8, 4) != 'WAVE') {
    throw const MpException(MpStatus.invalidArgument, 'Audio prompts must be RIFF/WAVE data.');
  }
  int offset = 12;
  int? format;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? audioOffset;
  int? audioLength;
  while (offset + 8 <= bytes.length) {
    final String id = _ascii(bytes, offset, 4);
    final int length = data.getUint32(offset + 4, Endian.little);
    final int payload = offset + 8;
    if (payload + length > bytes.length) break;
    if (id == 'fmt ' && length >= 16) {
      format = data.getUint16(payload, Endian.little);
      channels = data.getUint16(payload + 2, Endian.little);
      sampleRate = data.getUint32(payload + 4, Endian.little);
      bitsPerSample = data.getUint16(payload + 14, Endian.little);
    } else if (id == 'data') {
      audioOffset = payload;
      audioLength = length;
    }
    offset = payload + length + (length.isOdd ? 1 : 0);
  }
  if (format == null ||
      channels == null ||
      channels <= 0 ||
      sampleRate == null ||
      bitsPerSample == null ||
      audioOffset == null ||
      audioLength == null) {
    throw const MpException(MpStatus.invalidArgument, 'The WAVE file is missing audio metadata.');
  }
  final int bytesPerSample = bitsPerSample ~/ 8;
  if (bytesPerSample == 0 || audioLength % (bytesPerSample * channels) != 0) {
    throw const MpException(MpStatus.invalidArgument, 'The WAVE sample layout is invalid.');
  }
  final int frameCount = audioLength ~/ (bytesPerSample * channels);
  final Float32List samples = Float32List(frameCount);
  for (int frame = 0; frame < frameCount; frame += 1) {
    double sum = 0;
    for (int channel = 0; channel < channels; channel += 1) {
      final int sampleOffset = audioOffset + ((frame * channels + channel) * bytesPerSample);
      sum += _wavSample(data, sampleOffset, format, bitsPerSample);
    }
    samples[frame] = sum / channels;
  }
  return (samples: samples, sampleRateHz: sampleRate.toDouble());
}

double _wavSample(ByteData data, int offset, int format, int bitsPerSample) {
  if (format == 3 && bitsPerSample == 32) return data.getFloat32(offset, Endian.little);
  if (format != 1) {
    throw MpException(MpStatus.unimplemented, 'WAVE format $format is not supported.');
  }
  return switch (bitsPerSample) {
    8 => (data.getUint8(offset) - 128) / 128,
    16 => data.getInt16(offset, Endian.little) / 32768,
    24 => _int24(data, offset) / 8388608,
    32 => data.getInt32(offset, Endian.little) / 2147483648,
    _ => throw MpException(
      MpStatus.unimplemented,
      '$bitsPerSample-bit PCM WAVE audio is not supported.',
    ),
  };
}

int _int24(ByteData data, int offset) {
  int value =
      data.getUint8(offset) | (data.getUint8(offset + 1) << 8) | (data.getUint8(offset + 2) << 16);
  if ((value & 0x800000) != 0) value |= ~0xffffff;
  return value;
}

String _ascii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));
