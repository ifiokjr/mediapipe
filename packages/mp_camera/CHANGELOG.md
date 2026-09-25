## [0.1.0](https://github.com/ifiokjr/mediapipe/releases/tag/v0.1.0) (2026-09-25)

### Features

#### Add the initial six-package API workspace

Defines shared task and result types; vision, text, audio, camera, and GenAI APIs;
web adapters; the classic native C bridge; mobile proofreading and summarization
plugin bridges; tests; and API documentation. Platform support remains limited
to the backends and real-model tests listed in the support matrix.

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #1](https://github.com/ifiokjr/mediapipe/pull/1)

#### Fix task deadlocks, equality, and error reporting

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

Fill the build hook's artifact catalog with the checksummed MediaPipe runtime
archives published for release `native-v1.0.0-1`: macOS ARM64, Linux x64, and
Android ARM64/x64. Published packages now bundle a native runtime at build time
instead of requiring a local `.mp-sdk` build, and a missing target still
resolves a local runtime with an actionable error.

_Owner:_ [@github-actions](https://github.com/apps/github-actions) · _Review:_ [PR #17](https://github.com/ifiokjr/mediapipe/pull/17)

## 0.0.0

- Reserve the package name before the first coordinated MP SDK release.
