---
mp_vision: feat
---

# Live video-element input on the web

- `mp_vision`: `processVideoElement` on every vision task accepts a live
  browser video element, wrapped with `webVideoSource` from
  `package:mp_vision/mp_vision_web.dart`. MediaPipe samples the element's
  current frame straight from the compositor, so a web camera pipeline skips
  the canvas draw, the `ImageData` copy, and the `MpImage` round trip that the
  pixel path pays per frame. Accepted in video and live-stream mode with the
  semantics of `processVideo`; native runtimes fail with
  `MpStatus.unimplemented` and continue to expect converted frames.
