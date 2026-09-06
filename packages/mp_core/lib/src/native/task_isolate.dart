import 'dart:async';
import 'dart:isolate';

/// Handles commands inside a dedicated native-task isolate.
typedef NativeTaskWorkerHandler = FutureOr<Object?> Function(Object? command);

/// Creates a command handler inside a dedicated native-task isolate.
typedef NativeTaskWorkerFactory =
    FutureOr<NativeTaskWorkerHandler> Function(Object? initialMessage);

/// A request/response worker that keeps one native task on one isolate.
///
/// Native task handles are created, invoked, and released on the worker rather
/// than being passed between short-lived isolates. Commands and results must be
/// sendable between Dart isolates.
final class NativeTaskIsolate {
  NativeTaskIsolate._(
    this._isolate,
    this._responses,
    this._responseSubscription,
    this._lifecyclePorts,
    this._lifecycleSubscriptions,
    this._commands,
  );

  final Isolate _isolate;
  final ReceivePort _responses;
  final StreamSubscription<Object?> _responseSubscription;
  final List<ReceivePort> _lifecyclePorts;
  final List<StreamSubscription<Object?>> _lifecycleSubscriptions;
  final SendPort _commands;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  var _nextRequestId = 0;
  var _disposed = false;

  /// Starts a worker with [factory] and its sendable [initialMessage].
  static Future<NativeTaskIsolate> spawn({
    required NativeTaskWorkerFactory factory,
    required Object? initialMessage,
    String? debugName,
  }) async {
    final ReceivePort responses = ReceivePort();
    final ReceivePort errors = ReceivePort();
    final ReceivePort exits = ReceivePort();
    final Completer<_NativeTaskReady> ready = Completer<_NativeTaskReady>();
    NativeTaskIsolate? worker;
    Object? earlyTermination;
    late final StreamSubscription<Object?> responseSubscription;
    responseSubscription = responses.listen((Object? message) {
      if (message case final _NativeTaskReady value) {
        if (!ready.isCompleted) ready.complete(value);
        return;
      }
      worker?._handleResponse(message);
    });
    final StreamSubscription<Object?> errorSubscription = errors.listen((Object? message) {
      final Object error = _remoteError(message);
      if (!ready.isCompleted) {
        ready.completeError(error);
      } else if (worker case final NativeTaskIsolate activeWorker) {
        activeWorker._handleTermination(error);
      } else {
        earlyTermination = error;
      }
    });
    final StreamSubscription<Object?> exitSubscription = exits.listen((Object? _) {
      final StateError error = StateError('Native task worker exited unexpectedly.');
      if (!ready.isCompleted) {
        ready.completeError(error);
      } else if (worker case final NativeTaskIsolate activeWorker) {
        activeWorker._handleTermination(error);
      } else {
        earlyTermination = error;
      }
    });
    final Isolate isolate = await Isolate.spawn<_NativeTaskBootstrap>(
      _runNativeTaskWorker,
      _NativeTaskBootstrap(responses.sendPort, factory, initialMessage),
      debugName: debugName,
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );
    late final _NativeTaskReady handshake;
    try {
      handshake = await ready.future;
    } on Object {
      isolate.kill(priority: Isolate.immediate);
      await responseSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      responses.close();
      errors.close();
      exits.close();
      rethrow;
    }
    if (handshake.error case final Object error) {
      isolate.kill(priority: Isolate.immediate);
      await responseSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      responses.close();
      errors.close();
      exits.close();
      Error.throwWithStackTrace(error, handshake.stackTrace ?? StackTrace.empty);
    }
    final NativeTaskIsolate result = NativeTaskIsolate._(
      isolate,
      responses,
      responseSubscription,
      <ReceivePort>[errors, exits],
      <StreamSubscription<Object?>>[errorSubscription, exitSubscription],
      handshake.commands!,
    );
    worker = result;
    if (earlyTermination case final Object error) {
      result._handleTermination(error);
    }
    return result;
  }

  /// Sends one command and completes with its typed result.
  Future<T> request<T>(Object? command) {
    if (_disposed) throw StateError('NativeTaskIsolate is disposed.');
    final int requestId = _nextRequestId;
    _nextRequestId += 1;
    final Completer<Object?> completer = Completer<Object?>();
    _pending[requestId] = completer;
    _commands.send(_NativeTaskRequest(requestId, command));
    return completer.future.then((Object? value) => value as T);
  }

  /// Releases the Dart isolate after the task's close command has completed.
  Future<void> dispose() async {
    if (_disposed) return;
    if (_pending.isNotEmpty) {
      throw StateError('Cannot dispose a native task worker with pending requests.');
    }
    _disposed = true;
    await _releaseResources(kill: true);
  }

  Future<void> _releaseResources({required bool kill}) async {
    await _responseSubscription.cancel();
    for (final StreamSubscription<Object?> subscription in _lifecycleSubscriptions) {
      await subscription.cancel();
    }
    _responses.close();
    for (final ReceivePort port in _lifecyclePorts) {
      port.close();
    }
    if (kill) _isolate.kill(priority: Isolate.immediate);
  }

  void _handleResponse(Object? message) {
    if (message is! _NativeTaskResponse) {
      for (final Completer<Object?> pending in _pending.values) {
        pending.completeError(StateError('Native task worker returned an invalid response.'));
      }
      _pending.clear();
      return;
    }
    final Completer<Object?>? completer = _pending.remove(message.requestId);
    if (completer == null) return;
    if (message.error case final Object error) {
      completer.completeError(error, message.stackTrace);
    } else {
      completer.complete(message.result);
    }
  }

  void _handleTermination(Object error) {
    if (_disposed) return;
    _disposed = true;
    for (final Completer<Object?> pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    unawaited(_releaseResources(kill: false));
  }
}

Object _remoteError(Object? message) {
  if (message case <Object?>[final Object error, final Object stackTrace]) {
    return RemoteError(error.toString(), stackTrace.toString());
  }
  return StateError('Native task worker failed: $message');
}

final class _NativeTaskBootstrap {
  const _NativeTaskBootstrap(this.responses, this.factory, this.initialMessage);

  final SendPort responses;
  final NativeTaskWorkerFactory factory;
  final Object? initialMessage;
}

final class _NativeTaskReady {
  const _NativeTaskReady({this.commands, this.error, this.stackTrace});

  final SendPort? commands;
  final Object? error;
  final StackTrace? stackTrace;
}

final class _NativeTaskRequest {
  const _NativeTaskRequest(this.requestId, this.command);

  final int requestId;
  final Object? command;
}

final class _NativeTaskResponse {
  const _NativeTaskResponse({required this.requestId, this.result, this.error, this.stackTrace});

  final int requestId;
  final Object? result;
  final Object? error;
  final StackTrace? stackTrace;
}

Future<void> _runNativeTaskWorker(_NativeTaskBootstrap bootstrap) async {
  final ReceivePort commands = ReceivePort();
  late final NativeTaskWorkerHandler handler;
  try {
    handler = await bootstrap.factory(bootstrap.initialMessage);
  } on Object catch (error, stackTrace) {
    bootstrap.responses.send(_NativeTaskReady(error: error, stackTrace: stackTrace));
    commands.close();
    return;
  }
  bootstrap.responses.send(_NativeTaskReady(commands: commands.sendPort));
  await for (final Object? message in commands) {
    if (message is! _NativeTaskRequest) continue;
    try {
      final Object? result = await handler(message.command);
      bootstrap.responses.send(_NativeTaskResponse(requestId: message.requestId, result: result));
    } on Object catch (error, stackTrace) {
      bootstrap.responses.send(
        _NativeTaskResponse(requestId: message.requestId, error: error, stackTrace: stackTrace),
      );
    }
  }
}
