import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' as native;

import 'text_proofreader.dart';
import 'text_summarizer.dart';

const MethodChannel _methods = MethodChannel('dev.ifiokjr.mp_text/methods');
const EventChannel _events = EventChannel('dev.ifiokjr.mp_text/events');

final _MobileTextBridge _bridge = _MobileTextBridge();

/// Creates the Android or iOS proofreader backend registered by this plugin.
Future<TextProofreaderBackend> createPlatformTextProofreader(TextProofreaderOptions options) async {
  final _ResolvedModelFile model = await _resolveModelFile(options.baseOptions.modelAsset);
  try {
    final int handle = await _bridge.createTask('proofreader.create', <String, Object?>{
      'modelPath': model.path,
      'maxTokens': options.maxTokens,
    }, task: 'TextProofreader');
    return _MobileTextProofreader(handle, model);
  } on Object {
    await model.close();
    rethrow;
  }
}

/// Creates the Android or iOS summarizer backend registered by this plugin.
Future<TextSummarizerBackend> createPlatformTextSummarizer(TextSummarizerOptions options) async {
  final _ResolvedModelFile model = await _resolveModelFile(options.baseOptions.modelAsset);
  try {
    final int handle = await _bridge.createTask('summarizer.create', <String, Object?>{
      'modelPath': model.path,
      'maxTokens': options.maxTokens,
      'mode': options.mode.name,
    }, task: 'TextSummarizer');
    return _MobileTextSummarizer(handle, model);
  } on Object {
    await model.close();
    rethrow;
  }
}

final class _ResolvedModelFile {
  const _ResolvedModelFile(this.path, [this.temporaryDirectory]);

  final String path;
  final Directory? temporaryDirectory;

  Future<void> close() async {
    final Directory? directory = temporaryDirectory;
    if (directory != null && directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

Future<_ResolvedModelFile> _resolveModelFile(ModelAsset asset) async {
  final ModelAsset resolved = await native.resolveNativeModelAsset(asset);
  switch (resolved) {
    case ModelAssetPath(:final path):
      final File file = File(path).absolute;
      if (!file.existsSync()) {
        throw MpException(MpStatus.notFound, 'The model file does not exist: ${file.path}');
      }
      return _ResolvedModelFile(file.path);
    case ModelAssetBytes(:final bytes, :final name):
      final Directory directory = await Directory.systemTemp.createTemp('mp_text_model_');
      final String rawName = name?.split(RegExp(r'[/\\]')).lastOrNull ?? 'model.litertlm';
      final String safeName = rawName.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
      final File file = File('${directory.path}${Platform.pathSeparator}$safeName');
      try {
        file.writeAsBytesSync(bytes, flush: true);
        return _ResolvedModelFile(file.path, directory);
      } on Object {
        directory.deleteSync(recursive: true);
        rethrow;
      }
    case ModelAssetUri():
      throw const MpException(
        MpStatus.failedPrecondition,
        'The native model URI was not resolved.',
      );
  }
}

abstract base class _MobileTextTask implements MpTask {
  _MobileTextTask(this.handle, this.model, this.taskName);

  final int handle;
  final _ResolvedModelFile model;
  final String taskName;

  bool _closed = false;
  bool _busy = false;
  Future<void>? _activeOperation;

  @override
  bool get isClosed => _closed;

  void ensureAvailable() {
    if (_closed) throw MpTaskClosedError(taskName);
    if (_busy) {
      throw MpException(
        MpStatus.failedPrecondition,
        '$taskName already has an active operation.',
        task: taskName,
      );
    }
  }

  Future<T> runExclusive<T>(Future<T> Function() operation) {
    ensureAvailable();
    _busy = true;
    final Future<T> result = operation().whenComplete(() => _busy = false);
    _activeOperation = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Stream<T> runStreaming<T>(_StreamOperation<T> Function() operation) {
    ensureAvailable();
    _busy = true;
    final _StreamOperation<T> result = operation();
    _activeOperation = result.done.whenComplete(() => _busy = false);
    return result.stream;
  }

  Future<void> closeTask(String method) async {
    if (_closed) return;
    _closed = true;
    await _activeOperation;
    try {
      await _bridge.invokeVoid(method, <String, Object?>{'handle': handle}, task: taskName);
    } finally {
      await model.close();
    }
  }
}

final class _MobileTextProofreader extends _MobileTextTask implements TextProofreaderBackend {
  _MobileTextProofreader(int handle, _ResolvedModelFile model)
    : super(handle, model, 'TextProofreader');

  @override
  Future<TextProofreaderResult> proofread(String text) => runExclusive(() async {
    final Map<Object?, Object?> result = await _bridge.invokeMap(
      'proofreader.proofread',
      <String, Object?>{'handle': handle, 'text': text},
      task: taskName,
    );
    return TextProofreaderResult(
      text: _requiredString(result, 'text', taskName),
      corrections: _readCorrections(result['corrections'], taskName),
    );
  });

  @override
  Stream<TextProofreaderChunk> proofreadStreaming(String text) => runStreaming(
    () => _bridge.startStream(
      'proofreader.stream',
      <String, Object?>{'handle': handle, 'text': text},
      task: taskName,
      convert: (Map<Object?, Object?> event) => TextProofreaderChunk(
        text: _requiredString(event, 'text', taskName),
        isDone: _requiredBool(event, 'isDone', taskName),
        corrections: _readCorrections(event['corrections'], taskName),
      ),
    ),
  );

  @override
  Future<void> close() => closeTask('proofreader.close');
}

final class _MobileTextSummarizer extends _MobileTextTask implements TextSummarizerBackend {
  _MobileTextSummarizer(int handle, _ResolvedModelFile model)
    : super(handle, model, 'TextSummarizer');

  @override
  Future<TextSummarizerResult> summarize(String text) => runExclusive(() async {
    final Map<Object?, Object?> result = await _bridge.invokeMap(
      'summarizer.summarize',
      <String, Object?>{'handle': handle, 'text': text},
      task: taskName,
    );
    return TextSummarizerResult(_requiredString(result, 'summary', taskName));
  });

  @override
  Stream<TextSummarizerChunk> summarizeStreaming(String text) => runStreaming(
    () => _bridge.startStream(
      'summarizer.stream',
      <String, Object?>{'handle': handle, 'text': text},
      task: taskName,
      convert: (Map<Object?, Object?> event) => TextSummarizerChunk(
        text: _requiredString(event, 'text', taskName),
        isDone: _requiredBool(event, 'isDone', taskName),
      ),
    ),
  );

  @override
  Future<void> close() => closeTask('summarizer.close');
}

final class _StreamOperation<T> {
  const _StreamOperation(this.stream, this.done);

  final Stream<T> stream;
  final Future<void> done;
}

abstract interface class _PendingStream {
  void add(Map<Object?, Object?> event);

  void fail(Object error, [StackTrace? stackTrace]);

  void close();
}

final class _TypedPendingStream<T> implements _PendingStream {
  _TypedPendingStream(this.convert);

  final T Function(Map<Object?, Object?> event) convert;
  final StreamController<T> controller = StreamController<T>.broadcast();
  final Completer<void> completion = Completer<void>();
  bool _streamClosed = false;

  @override
  void add(Map<Object?, Object?> event) {
    if (_streamClosed) return;
    try {
      controller.add(convert(event));
    } on Object catch (error, stackTrace) {
      _streamClosed = true;
      controller.addError(error, stackTrace);
      unawaited(controller.close());
    }
  }

  @override
  void fail(Object error, [StackTrace? stackTrace]) {
    if (completion.isCompleted) return;
    completion.complete();
    if (!_streamClosed) {
      _streamClosed = true;
      controller.addError(error, stackTrace);
      unawaited(controller.close());
    }
  }

  @override
  void close() {
    if (completion.isCompleted) return;
    completion.complete();
    if (!_streamClosed) {
      _streamClosed = true;
      unawaited(controller.close());
    }
  }
}

final class _MobileTextBridge {
  _MobileTextBridge() {
    _events.receiveBroadcastStream().listen(_onEvent, onError: _onEventChannelError);
  }

  final Map<String, _PendingStream> _pending = <String, _PendingStream>{};
  var _nextRequest = 0;

  Future<int> createTask(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    final Object? result = await _invoke(method, arguments, task: task);
    if (result is num) return result.toInt();
    throw MpException(MpStatus.internal, '$task creation returned an invalid handle.', task: task);
  }

  Future<Map<Object?, Object?>> invokeMap(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    final Object? result = await _invoke(method, arguments, task: task);
    if (result case final Map<Object?, Object?> map) return map;
    throw MpException(MpStatus.internal, '$task returned an invalid result.', task: task);
  }

  Future<void> invokeVoid(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    await _invoke(method, arguments, task: task);
  }

  _StreamOperation<T> startStream<T>(
    String method,
    Map<String, Object?> arguments, {
    required String task,
    required T Function(Map<Object?, Object?> event) convert,
  }) {
    final String requestId = '${DateTime.now().microsecondsSinceEpoch}-${_nextRequest++}';
    final _TypedPendingStream<T> pending = _TypedPendingStream<T>(convert);
    _pending[requestId] = pending;
    unawaited(
      _invoke(method, <String, Object?>{
        ...arguments,
        'requestId': requestId,
      }, task: task).catchError((Object error, StackTrace stackTrace) {
        _pending.remove(requestId)?.fail(error, stackTrace);
        return null;
      }),
    );
    return _StreamOperation<T>(pending.controller.stream, pending.completion.future);
  }

  Future<Object?> _invoke(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    try {
      return await _methods.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException catch (error) {
      throw MpException(
        MpStatus.unimplemented,
        'The $task platform plugin is not registered.',
        task: task,
        cause: error,
      );
    } on PlatformException catch (error) {
      throw MpException(
        _statusFromPlatformCode(error.code),
        error.message ?? '$task failed in the platform runtime.',
        task: task,
        cause: error,
      );
    }
  }

  void _onEvent(Object? rawEvent) {
    if (rawEvent is! Map<Object?, Object?>) return;
    final String? requestId = rawEvent['requestId'] as String?;
    if (requestId == null) return;
    final _PendingStream? pending = _pending[requestId];
    if (pending == null) return;
    switch (rawEvent['kind']) {
      case 'data':
        pending.add(rawEvent);
      case 'done':
        _pending.remove(requestId)?.close();
      case 'error':
        final String message = rawEvent['message'] as String? ?? 'The platform stream failed.';
        final String code = rawEvent['code'] as String? ?? 'internal';
        _pending.remove(requestId)?.fail(MpException(_statusFromPlatformCode(code), message));
    }
  }

  void _onEventChannelError(Object error, StackTrace stackTrace) {
    final List<_PendingStream> pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final _PendingStream stream in pending) {
      stream.fail(error, stackTrace);
    }
  }
}

String _requiredString(Map<Object?, Object?> map, String key, String task) {
  final Object? value = map[key];
  if (value is String) return value;
  throw MpException(MpStatus.internal, '$task returned a non-string $key.', task: task);
}

bool _requiredBool(Map<Object?, Object?> map, String key, String task) {
  final Object? value = map[key];
  if (value is bool) return value;
  throw MpException(MpStatus.internal, '$task returned a non-boolean $key.', task: task);
}

List<TextCorrection> _readCorrections(Object? raw, String task) {
  if (raw == null) return const <TextCorrection>[];
  if (raw is! List<Object?>) {
    throw MpException(MpStatus.internal, '$task returned invalid corrections.', task: task);
  }
  return raw
      .map((Object? value) {
        if (value is! Map<Object?, Object?>) {
          throw MpException(MpStatus.internal, '$task returned an invalid correction.', task: task);
        }
        final String type = _requiredString(value, 'type', task);
        return TextCorrection(
          type: switch (type) {
            'same' => TextCorrectionType.same,
            'insertion' => TextCorrectionType.insertion,
            'deletion' => TextCorrectionType.deletion,
            _ => throw MpException(
              MpStatus.internal,
              '$task returned an unknown correction type: $type.',
              task: task,
            ),
          },
          text: _requiredString(value, 'text', task),
        );
      })
      .toList(growable: false);
}

MpStatus _statusFromPlatformCode(String code) => switch (code) {
  'cancelled' => MpStatus.cancelled,
  'invalid_argument' => MpStatus.invalidArgument,
  'not_found' => MpStatus.notFound,
  'resource_exhausted' => MpStatus.resourceExhausted,
  'failed_precondition' => MpStatus.failedPrecondition,
  'unimplemented' => MpStatus.unimplemented,
  'unavailable' => MpStatus.unavailable,
  _ => MpStatus.internal,
};
