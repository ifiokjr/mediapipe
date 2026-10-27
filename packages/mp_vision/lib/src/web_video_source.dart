import 'package:meta/meta.dart';

/// A live video element handed to a vision task without pixel conversion.
///
/// Only the browser adapter constructs one — see
/// `package:mp_vision/mp_vision_web.dart` — because the wrapped object is a
/// JavaScript `HTMLVideoElement`. MediaPipe reads the element's current frame
/// straight from the compositor, so a web camera pipeline skips the canvas
/// draw, the `ImageData` copy, and the `MpImage` round trip entirely.
///
/// ```dart
/// final source = webVideoSource(videoElement);
/// final result = await detector.processVideoElement(source, timestampMs, null);
/// ```
@immutable
final class WebVideoSource {
  /// Wraps a platform video handle.
  @internal
  const WebVideoSource(this.handle);

  /// The opaque platform video object.
  final Object handle;
}
