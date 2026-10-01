/// Status codes exposed by the MediaPipe Tasks C API.
enum MpStatus {
  /// The operation completed successfully.
  ok(0),

  /// The operation was cancelled.
  cancelled(1),

  /// A supplied argument was invalid.
  invalidArgument(3),

  /// The operation exceeded its deadline.
  deadlineExceeded(4),

  /// A requested object was not found.
  notFound(5),

  /// The requested object already exists.
  alreadyExists(6),

  /// The caller does not have permission to perform the operation.
  permissionDenied(7),

  /// A required resource is exhausted.
  resourceExhausted(8),

  /// The operation could not run in the current state.
  failedPrecondition(9),

  /// The operation was aborted.
  aborted(10),

  /// A supplied value falls outside the supported range.
  outOfRange(11),

  /// The requested behavior is not implemented by the active runtime.
  unimplemented(12),

  /// An internal runtime error occurred.
  internal(13),

  /// The runtime is unavailable.
  unavailable(14),

  /// A data-loss condition was detected.
  dataLoss(15),

  /// Authentication is required or failed.
  unauthenticated(16),

  /// The native runtime returned an unrecognized status code.
  unknown(-1);

  const MpStatus(this.code);

  /// The integer value used by the native API.
  final int code;

  /// Converts a native status code into a stable Dart value.
  static MpStatus fromCode(int code) => MpStatus.values.firstWhere(
    (MpStatus status) => status.code == code,
    orElse: () => MpStatus.unknown,
  );
}

/// An exception reported by a MediaPipe task runtime.
final class MpException implements Exception {
  /// Creates an exception with a stable [status] and human-readable [message].
  const MpException(this.status, this.message, {this.task, this.cause});

  /// The native or platform-neutral status category.
  final MpStatus status;

  /// A description suitable for logs and developer-facing diagnostics.
  final String message;

  /// The task that reported the failure, when known.
  final String? task;

  /// The platform error that caused this exception, when one is available.
  final Object? cause;

  @override
  String toString() {
    final String prefix = task == null ? 'MpException' : 'MpException($task)';
    final String causeSuffix = cause == null ? '' : ' Cause: $cause';
    return '$prefix: ${status.name}: $message$causeSuffix';
  }
}

/// An error thrown when a task is used after it has been closed.
final class MpTaskClosedError extends StateError {
  /// Creates an error for [taskName].
  MpTaskClosedError(String taskName) : super('$taskName has already been closed.');
}
