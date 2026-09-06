/// Low-level generated bindings for the MediaPipe Tasks C API.
///
/// Most applications should use `mp_audio`, `mp_text`, or `mp_vision`. This
/// library is public so those independently published packages can share one
/// bundled native runtime.
library;

export 'src/native/bindings.g.dart';
export 'src/native/support.dart';
export 'src/native/task_isolate.dart';
