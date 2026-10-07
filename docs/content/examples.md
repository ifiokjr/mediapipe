---
title: Examples
description: Runnable examples for every package, from a plain Dart script to a live camera app.
---

Every package in this SDK ships an example that creates a real task, runs
inference, and closes it. The examples are built in continuous integration and
run on a device, so one that stops compiling breaks the build.

## Continuous integration

Two commands run the same code paths in CI:

```sh
devenv shell test:examples
devenv shell test:android-device
```

`test:examples` runs the Dart examples on the host against a real native
runtime. `test:android-device` drives the mp_text native plugin fixture on an
attached Android device, and `test:device-demo` launches the Flutter demo on
one.

## Dart examples

These run with `dart run` from the repository root. Each downloads its model
once, verifies the SHA-256 digest, and caches it under the system temporary
directory or `MP_EXAMPLE_CACHE`.

| Example                                         | Demonstrates                                                                  |
| ----------------------------------------------- | ----------------------------------------------------------------------------- |
| `examples/cli/bin/core_model_assets.dart`       | Model assets, image and audio containers, timestamp rules, and typed failures |
| `examples/cli/bin/vision_face_detection.dart`   | Face detection over a real photograph with bounding boxes and keypoints       |
| `examples/cli/bin/vision_hand_landmarks.dart`   | Hand landmarks, handedness, and world coordinates on the same photograph      |
| `examples/cli/bin/text_language_detection.dart` | Language identification across four languages                                 |
| `examples/cli/bin/text_tasks.dart`              | Language detection plus text embedding and cosine similarity                  |
| `examples/cli/bin/audio_classification.dart`    | Clip classification and the native streaming contract                         |
| `examples/cli/bin/genai_llm.dart`               | LLM session creation, streamed chunks, and cancellation                       |

Run one:

```sh
dart run examples/cli/bin/vision_face_detection.dart
```

The native examples need a MediaPipe runtime. A Flutter build resolves one
through the native asset hook; a standalone `dart run` reads a local `.mp-sdk`
directory:

```sh
devenv shell native:build
dart run examples/cli/bin/vision_face_detection.dart
```

## Flutter device demo

`examples/device_demo` is a live camera playground: it streams frames through
pose and face landmarkers, counts exercise reps, and projects 3D accessories
onto the tracked face. It is the end-to-end test for the camera path: frame
conversion, monotonic timestamps, latest-frame backpressure, and deterministic
cleanup on shutdown.

```sh
cd examples/device_demo
repo-flutter run
```

The demo requests the camera permission itself and downloads its digest-pinned
models on first launch, so no manual setup is required. A browser build runs in
a synthetic-preview mode without a camera.

The repository also carries a second, device-only entry point,
`lib/device_telemetry.dart`, which streams a face detector while reporting
device motion, processed frames, and dropped frames:

```sh
cd examples/device_demo
repo-flutter run -t lib/device_telemetry.dart
```

## What the examples prove

- A task is created, used, and closed without leaking native or JavaScript
  resources.
- Timestamps advance monotonically across a live stream.
- A slow model drops stale frames instead of building an unbounded queue.
- An unsupported platform documents itself through `MpStatus.unimplemented`
  rather than failing vaguely.

Read the [live streams](guides/live-streams) guide for the scheduling rules these
examples rely on, or the [models](guides/models) guide for how to supply a model
safely in production.
