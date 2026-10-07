# Changelog

All notable changes to the MP SDK are documented here. The six public packages
share one version and are released together.

This project follows [Semantic Versioning](https://semver.org/).

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
