---
mp_audio: fix
mp_camera: fix
mp_core: fix
mp_genai: fix
mp_text: fix
mp_vision: fix
---

# Correctness and performance fixes

Lifecycle and error handling:

- `mp_core`: `NativeTaskIsolate` no longer leaks its ports and subscriptions
  when `Isolate.spawn` itself fails, kills a worker that reports an uncaught
  error or returns a malformed response instead of orphaning it, and shares one
  teardown path for every spawn failure. `LlmInference.generateResponse` in
  `mp_genai` can no longer surface an unhandled zone error when closing its
  temporary session.
- `mp_vision`: a failed `close()` reopens the task so cleanup can be retried;
  frames rejected by a backend no longer burn their timestamp; live-stream
  failures now reach both the results stream and the returned future on every
  platform; the web module load is retried after a transient failure; and the
  holistic landmarker releases its wasm result object after conversion.
- `mp_text`: the web backends serialize calls, drain in-flight work on close,
  and validate converted JavaScript results, failing with `MpException` instead
  of null-check and cast errors. A native language prediction without a code
  fails explicitly instead of decoding as an empty string.
- `mp_camera`: `LatestFrameScheduler.submit` throws `MpTaskClosedError` after
  close like every task, a throwing failures listener cannot terminate frame
  processing, and unknown device orientations fail with an `ArgumentError`
  instead of a null-check crash.

Validation:

- `mp_core`: NaN and infinity coordinates are rejected by `NormalizedRect`,
  NaN score thresholds by `ClassifierOptions`, and containers validate inputs
  before copying them.

Performance:

- `mp_core`: native results copy pixel and embedding buffers once instead of
  twice, `cosineSimilarity` no longer boxes every sample, platform detection is
  memoized, and web image conversion dispatches per image rather than per pixel.
- `mp_camera`: NV21, YUV420, and BGRA conversion loops hoist strides, sample
  chroma once per pixel pair, and clamp with branches instead of `num.clamp`.
- `mp_audio`, `mp_text`, `mp_genai`: each web runtime resolves its module and
  wasm fileset once per runtime instance and reuses it across task creations.
- `mp_genai`, `mp_text`: model files are written to disk asynchronously so
  multi-hundred-megabyte writes stay off the UI isolate.

API hygiene:

- `mp_core`: the generated FFI `MpStatus` is no longer exported from
  `native.dart`, removing the collision with the Dart-side `MpStatus`; dead
  conversion helpers were removed.
- `mp_genai`: the `collection` dependency that was already used is declared,
  and `ImageGenerator` rejects negative seeds.
