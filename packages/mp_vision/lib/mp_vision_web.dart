/// Browser runtime configuration for `package:mp_vision`.
library;

import 'dart:js_interop';

import 'package:meta/meta.dart';

import 'src/web_video_source.dart';

export 'src/runtime_web.dart' show WebVisionRuntime;
export 'src/web_video_source.dart' show WebVideoSource;

/// Wraps a JavaScript video element, such as an `HTMLVideoElement` from
/// `package:web`, for [WebVideoSource]-accepting processing calls.
///
/// ```dart
/// import 'package:web/web.dart' as web;
///
/// final result = await detector.processVideoElement(
///   webVideoSource(web.document.querySelector('video')! as web.HTMLVideoElement),
///   clock.nextTimestampMs(),
///   null,
/// );
/// ```
@useResult
WebVideoSource webVideoSource(JSObject element) => WebVideoSource(element);
