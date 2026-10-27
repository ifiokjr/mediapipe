# Changelog

All notable changes to the MP SDK are documented here. The six public packages
share one version and are released together.

This project follows [Semantic Versioning](https://semver.org/).

## [0.1.4](https://github.com/ifiokjr/mediapipe/releases/tag/v0.1.4) (2026-10-27)

Grouped release for `mp`.

### Features

#### Packed landmark lists

_Packages:_ 🟠 _mp_core_, 🟢 _mp_vision_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #46](https://github.com/ifiokjr/mediapipe/pull/46)

- `mp_core`: `NormalizedLandmarkList` and `LandmarkList` implement the
  existing `List<NormalizedLandmark>`/`List<Landmark>` contracts over one
  packed `Float32List` — five floats per landmark (x, y, z, visibility,
  presence, with absent confidences stored as quiet NaN) plus optional
  parallel names. A 478-point face result costs one buffer instead of
  hundreds of objects: cheaper to allocate on the worker isolate, cheaper to
  copy to the caller, and directly iterable by painting loops through
  `values` without materializing landmark objects. `fromLandmarks` packs
  app-built lists the same way; coordinates are 32-bit floats exactly as the
  native runtime reports them.
- `mp_vision`: native result conversion fills those packed lists directly
  from the C structs, so every landmarker result (face, hand, pose, gesture,
  holistic) crosses isolates as contiguous data. The concrete list type
  changes; reading code keeps working unchanged because the new lists are
  real `List`s with the same value equality.

#### Frame pacing and live scheduling telemetry

_Packages:_ 🟠 _mp_core_, 🟢 _mp_camera_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #43](https://github.com/ifiokjr/mediapipe/pull/43)

- `mp_core`: `LatestFrameScheduler` moves here from `mp_camera` so pure Dart
  pipelines can use it, and gains a `maxQueueAge` policy that discards a frame
  which waited through a long inference stall instead of running it late, a
  `stats` snapshot with counters, `processedPerSecond`, and rolling p50/p95
  queue-wait and processing times, and a `dart:developer` timeline task around
  every processed frame for DevTools.
- `mp_core`: `FramePacer` admits one frame per interval by camera timestamp
  before any pixel conversion runs, so a skipped frame costs nothing;
  `FramePacer.targetFps` derives the interval from a target rate.
- `mp_core`: `LatencyWindow` is the bounded rolling window with nearest-rank
  percentiles behind the scheduler statistics, public for timing other stages.
- `mp_camera`: re-exports `LatestFrameScheduler`, `LatestFrameFailure`, and
  `LatestFrameStats` from `mp_core`; existing imports keep working.

#### Content-addressed model cache

_Packages:_ 🟠 _mp_core_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #44](https://github.com/ifiokjr/mediapipe/pull/44)

- `ModelAsset.uri` accepts `cacheDirectory`. On native platforms a
  digest-pinned model is downloaded once into a content-addressed cache (the
  SHA-256 digest is the file name), verified by hashing on every reuse, and
  replaced automatically when the cached file is corrupted or truncated. The
  download streams to a temporary file and hashes as bytes arrive, so a
  multi-hundred-megabyte model never sits in the Dart heap, and MediaPipe
  opens the finished file by path — which lets it map the file instead of
  copying it — rather than receiving a buffer. `cacheDirectory` requires a
  digest; browser builds ignore it.
- `ModelCache` and `maximumRemoteModelBytes` are exported from
  `package:mp_core/native.dart` for applications that want to pre-warm models.
- Remote model URIs still require HTTPS, except that plain HTTP is now accepted
  from loopback addresses so local development servers (and the SDK's own
  tests) can serve models; digest verification applies there too.

#### SIMD pixel conversion through the native runtime

_Packages:_ 🟠 _mp_core_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #48](https://github.com/ifiokjr/mediapipe/pull/48)

- `mp_core`: `PixelConverter` dispatches NV21, planar YUV420, and Android's
  semi-planar YUV420 to libyuv's NEON/SSE paths — compiled into the bundled
  native runtime as the SDK's own `MpPixel*` shim — when the linked runtime
  carries those symbols, and runs the pure Dart kernels otherwise. Output
  matches the Dart kernels to within fixed-point rounding (at most two levels
  per channel); the BGRA swizzle is exact. `nativePixelConversionSupported`
  in `package:mp_core/native.dart` reports which path is active, and
  `PixelConverter.forceDartKernels` lets tests compare the two.
- The native builder copies the shim from `tool/native/` into the pinned
  MediaPipe checkout, links `@libyuv`, exports the symbols through the Linux
  and Android version scripts, and `verify_native` requires them; a native
  integration test checks the accelerated and Dart conversions against each
  other on every native CI lane.

#### Shared pixel-conversion kernels and a performance gate

_Packages:_ 🟠 _mp_core_, 🟢 _mp_camera_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #41](https://github.com/ifiokjr/mediapipe/pull/41)

- `mp_core`: `PixelConverter` and `PixelPlane` expose the camera pixel-layout
  conversions as pure Dart kernels — BGRA8888, NV21, and three-plane YUV420
  covering both planar and Android's semi-planar layouts with independent row
  and pixel strides. Each kernel validates its strides and buffer lengths,
  writes one freshly allocated buffer, and returns an image that adopts it
  without a second copy, so the hot path no longer depends on Flutter-only
  code.
- `mp_camera`: the frame converter now wraps each `package:camera` plane and
  delegates to those kernels. Conversion output is unchanged; stride
  validation moved into `mp_core`, so a BGRA plane reporting a pixel stride
  other than four now fails with a descriptive `StateError` instead of
  producing silently wrong colors.
- The repository gained a `benchmarks/` suite over every pure-Dart hot path —
  pixel conversion, image construction, isolate frame transfer, result
  containers, and embedding similarity — plus two gates that run on every pull
  request: changed production lines must be covered by the unit tests
  (`tool/check_patch_coverage.dart`), and benchmark results must not regress
  against the base commit on the same runner (`tool/compare_benchmarks.dart`).

#### Live video-element input on the web

_Packages:_ 🟠 _mp_vision_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #47](https://github.com/ifiokjr/mediapipe/pull/47)

- `mp_vision`: `processVideoElement` on every vision task accepts a live
  browser video element, wrapped with `webVideoSource` from
  `package:mp_vision/mp_vision_web.dart`. MediaPipe samples the element's
  current frame straight from the compositor, so a web camera pipeline skips
  the canvas draw, the `ImageData` copy, and the `MpImage` round trip that the
  pixel path pays per frame. Accepted in video and live-stream mode with the
  semantics of `processVideo`; native runtimes fail with
  `MpStatus.unimplemented` and continue to expect converted frames.

#### Overlay coordinate transform and ui.Image interop

_Packages:_ 🟠 _mp_camera_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #45](https://github.com/ifiokjr/mediapipe/pull/45)

- `mp_camera`: `CameraOverlayTransform` maps MediaPipe's normalized landmarks,
  pixel bounding boxes, and regions of interest onto the preview widget,
  accounting for the inference rotation (results are relative to the upright
  frame), a mirrored front-camera preview, and the `BoxFit` placing the preview
  — `cover` cropping, `contain` letterboxing, and every other fit included via
  Flutter's own fitting rules.
- `mp_camera`: `MpImage.toUiImage()` uploads sRGB, sRGBA, gray, and
  single-channel float confidence masks as `ui.Image` for canvas painting, and
  `ui.Image.toMpImage()` reads decoded images back into an sRGBA `MpImage` for
  still-image inference — no hand-written byte shuffling left to applications.

### Fixes

#### Lifecycle cleanup and retry fixes

_Packages:_ 🟢 _mp_vision_, 🟢 _mp_text_, 🟢 _mp_audio_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #34](https://github.com/ifiokjr/mediapipe/pull/34)

- `mp_vision`, `mp_audio`, `mp_text`: native backends seal themselves only
  after the native task is released. Previously a failed close left the
  backend marked closed, so the facade's documented retry re-invoked a no-op
  and permanently leaked the worker isolate and native task. A failed close
  now leaves the task open for a retried cleanup.
- `mp_audio`, `mp_text`: facades reopen after a failed close — matching the
  `mp_vision` behavior — and a concurrent second `close()` now awaits the
  in-flight attempt instead of resolving before cleanup finishes.
- `mp_vision`: frame processing allocates the native image inside the scope's
  error boundary, so an image-creation failure on the worker no longer leaks
  the per-call native arena (previously one full-frame buffer per failure).

## [0.1.3](https://github.com/ifiokjr/mediapipe/releases/tag/v0.1.3) (2026-10-12)

Grouped release for `mp`.

### Features

#### Copy-free image buffers

_Packages:_ 🟠 _mp_core_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #29](https://github.com/ifiokjr/mediapipe/pull/29) · _Related issues:_ [#27](https://github.com/ifiokjr/mediapipe/issues/27)

`MpImageUint8.adopt`, `MpImageUint16.adopt`, and `MpImageFloat32.adopt` are now
public. An image produced from a freshly filled buffer — a camera-frame
conversion, a decoder output — can hand the buffer over instead of paying a
full-image defensive copy first. The default constructors keep their copying
behavior, so this is an opt-in fast path.

### Fixes

#### Resolve alongside newer native-asset toolchains

_Packages:_ 🟢 _mp_core_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #31](https://github.com/ifiokjr/mediapipe/pull/31)

`mp_core` now accepts `code_assets` 2.x and `hooks` 2.2, the versions newer
Flutter SDKs and other build-hook packages resolve. Applications that depend on
both `mp_core` and a package requiring `code_assets` 2.x no longer fail version
solving. Older Flutter workspaces keep resolving the 1.x line.

#### Round-two correctness and polish fixes

_Packages:_ 🟢 _mp_vision_, 🟢 _mp_camera_, 🟢 _mp_text_, 🟢 _mp_genai_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #29](https://github.com/ifiokjr/mediapipe/pull/29) · _Related issues:_ [#27](https://github.com/ifiokjr/mediapipe/issues/27)

- `mp_camera`: frame conversion adopts the freshly filled pixel buffers instead
  of copying them again, so a 1080p frame now allocates its RGB/RGBA buffer
  once per frame instead of twice with an extra megabyte-scale memcpy.
- `mp_text`: streaming text tasks buffer platform events until the caller
  subscribes, so a fast first chunk is never dropped between the method call
  and `listen`.
- `mp_genai`, `mp_text`: streaming request ids are a plain counter instead of a
  wall-clock prefix, keeping them deterministic across tests and traces.
- `mp_vision`: the web interactive segmenter now forwards
  `processingOptions` (rotation and region of interest) on the signed-stroke
  path instead of silently dropping them.

### Documentation

#### Example and documentation updates

_Packages:_ ⚪ _mp_core_, ⚪ _mp_vision_, ⚪ _mp_text_, ⚪ _mp_audio_, ⚪ _mp_genai_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #29](https://github.com/ifiokjr/mediapipe/pull/29) · _Related issues:_ [#27](https://github.com/ifiokjr/mediapipe/issues/27)

- The bare package examples (`mp_core`, `mp_audio`, `mp_genai`, `mp_vision`)
  are now instructive walkthroughs of each package's options, containers,
  lifecycle, and error contract instead of single-assert stubs, and remain
  runnable on any platform including the browser.
- The CLI hand-landmarks demo reads the upstream raised-hand test image
  (`pointing_up.jpg`) instead of the cats-and-dogs photo, and every pinned
  example asset digest is now regression-tested for format.
- The mp_text README describes the example fixture accurately and points at the
  runnable CLI demos.

## [0.1.2](https://github.com/ifiokjr/mediapipe/releases/tag/v0.1.2) (2026-10-07)

Grouped release for `mp`.

### Features

#### New capabilities from the quality pass

_Packages:_ 🟠 _mp_core_, 🟠 _mp_text_, 🟠 _mp_genai_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #27](https://github.com/ifiokjr/mediapipe/pull/27)

- `mp_core`: `TaskLifecycle.reopen()` lets a task whose backend cleanup failed
  stay usable so `close()` can be retried instead of leaking the underlying
  isolate and native handles.
- `mp_genai`, `mp_text`: streaming chunk types (`LlmGenerationChunk`,
  `RagGenerationChunk`, `TextSummarizerChunk`, `TextProofreaderChunk`) now
  implement value equality and hashing, so runtime-built instances compare by
  content the way every result type already does.

### Fixes

- **Monostyle style pass.** Blank-line breathing room around control flow and returns, group splits, and collapsed blank runs, applied by `monostyle fix` and kept where the pinned formatters put them. No behavior change.
  _Packages:_ 🟢 _mp_core_, 🟢 _mp_vision_, 🟢 _mp_camera_, 🟢 _mp_text_, 🟢 _mp_audio_, 🟢 _mp_genai_
  _Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #19](https://github.com/ifiokjr/mediapipe/pull/19)

#### Correctness and performance fixes

_Packages:_ 🟢 _mp_core_, 🟢 _mp_vision_, 🟢 _mp_camera_, 🟢 _mp_text_, 🟢 _mp_audio_, 🟢 _mp_genai_

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #27](https://github.com/ifiokjr/mediapipe/pull/27)

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

## [0.1.1](https://github.com/ifiokjr/mediapipe/releases/tag/v0.1.1) (2026-09-28)

Grouped release for `mp`.

### Fixes

#### Ship a pub.dev-valid `hook/` directory

pub.dev rejects Dart files under `hook/` other than `hook/build.dart`, so the
native artifact catalog and download helper moved to
`lib/src/native/artifact.dart`. The 0.1.0 upload was rejected with "Hook files
are experimental and `hook/native_artifact.dart` is not allowed yet."

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #20](https://github.com/ifiokjr/mediapipe/pull/20)

## [0.1.0](https://github.com/ifiokjr/mediapipe/releases/tag/v0.1.0) (2026-09-28)

Grouped release for `mp`.

### Features

#### Add the initial six-package API workspace

_Packages:_ 🟠 _mp_core_, 🟠 _mp_vision_, 🟠 _mp_camera_, 🟠 _mp_text_, 🟠 _mp_audio_, 🟠 _mp_genai_

Defines shared task and result types; vision, text, audio, camera, and GenAI APIs;
web adapters; the classic native C bridge; mobile proofreading and summarization
plugin bridges; tests; and API documentation. Platform support remains limited
to the backends and real-model tests listed in the support matrix.

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #1](https://github.com/ifiokjr/mediapipe/pull/1)

#### Fix task deadlocks, equality, and error reporting

_Packages:_ 🟢 _mp_core_, 🟢 _mp_vision_, 🟢 _mp_text_, 🟢 _mp_genai_, 🟠 _mp_camera_, ⚪ _mp_audio_

Fixes defects that could strand a task, crash an error handler, or surface an
unusable error:

- The `mp_text` and `mp_genai` platform bridges set their busy flag before
  invoking an operation, so an operation that threw before returning a future
  left the task permanently busy. Rejecting a non-8-bit image on an Android LLM
  session was the reachable case; every later call then failed with
  `failedPrecondition`. Both bridges now route through `Future.sync`.
- `LlmInference.generateResponse` attached session cleanup to a derived future,
  so a caller that handled a generation error still received an unhandled zone
  error, and a synchronous failure leaked the temporary session.
- A build with no linked MediaPipe runtime failed inside `dart:ffi` with a bare
  `ArgumentError` naming an internal asset id. Native task creation now reports
  `MpStatus.unavailable` and names the user define that supplies a local
  runtime.
- The Android GenAI plugin collapsed every platform error into
  `internal`. Common failure shapes now map to distinct statuses the Dart
  bridge already understands.
- The native runtime reported the full Dart VM version — which embeds OS
  details — to MediaPipe's usage logging as `host_version`. It now sends a
  stable SDK label, and the privacy guide documents exactly what the SDK
  reports.
- `HolisticLandmarkerResult`, `PoseLandmarkerResult`, `ImageSegmenterResult`,
  `PromptPoint`, and `PromptStroke` lacked `==`/`hashCode` while their sibling
  result types had them, so comparing results across task instances compared
  identity.
- `MpCameraClock` exposed no way to read the last issued timestamp; it now
  reports `lastTimestampMs` for latency monitoring and tests.

Adds missing coverage: `MpCameraClock` monotonicity, result equality for the
types above, and generation-chunk equality. Adds a documentation site link
checker, a docs-data consistency check, `mdt`-synchronized READMEs, and runnable
examples — including a device demo that streams camera frames through a face
detector and reports motion and drop telemetry.

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #15](https://github.com/ifiokjr/mediapipe/pull/15)

### Fixes

#### Register the native runtime artifact catalog

_Packages:_ 🟢 _mp_core_, 🟢 _mp_vision_, 🟢 _mp_camera_, 🟢 _mp_text_, 🟢 _mp_audio_, 🟢 _mp_genai_

Fill the build hook's artifact catalog with the checksummed MediaPipe runtime
archives published for release `native-v1.0.0-1`: macOS ARM64, Linux x64, and
Android ARM64/x64. Published packages now bundle a native runtime at build time
instead of requiring a local `.mp-sdk` build, and a missing target still
resolves a local runtime with an actionable error.

_Owner:_ [@github-actions](https://github.com/apps/github-actions) · _Review:_ [PR #17](https://github.com/ifiokjr/mediapipe/pull/17)

#### Cover the published native runtime resolution path

_Packages:_ 🟢 _mp_core_

Add a regression test for the build-hook path a package with no
`native_library_directory` user define takes: resolving the checksummed archive
named by `native_artifacts.json` for the host. The test skips when the catalog
publishes no build for the test host, because a missing target legitimately
bundles nothing.

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #18](https://github.com/ifiokjr/mediapipe/pull/18) · _Related issues:_ [#17](https://github.com/ifiokjr/mediapipe/issues/17)

### Other

- **Update package changelogs in grouped releases.**
  _Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #7](https://github.com/ifiokjr/mediapipe/pull/7)
- **Skip source changeset previews on prepared release PRs.**
  _Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #8](https://github.com/ifiokjr/mediapipe/pull/8)
