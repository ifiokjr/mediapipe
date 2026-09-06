---
title: Platform support
description: Implemented backends, tests, and remaining work by package and target.
---

The goal is one Dart API across Flutter’s supported platforms. “Supported” means the repository builds, runs real inference in continuous integration or on a maintained test device, and has a documented upstream runtime—not merely that Dart code compiles.

## Current implementation status

| Package     | Web                          | macOS                        | Linux                | Windows              | Android                                                                          | iOS                                                                        |
| ----------- | ---------------------------- | ---------------------------- | -------------------- | -------------------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `mp_core`   | Implemented                  | Native build in validation   | Native build planned | Native build planned | Packaging planned                                                                | Packaging planned                                                          |
| `mp_camera` | Conversion API               | Conversion API               | Conversion API       | Conversion API       | Conversion tested                                                                | Conversion tested                                                          |
| `mp_vision` | Implemented                  | Native build in validation   | Planned              | Planned              | Planned                                                                          | Planned                                                                    |
| `mp_text`   | Language detector model test | Language detector model test | Planned              | Planned              | Proofreader/summarizer native constructor tested; real-model tests pending       | Proofreader/summarizer native constructor tested; real-model tests pending |
| `mp_audio`  | Clip + chunk adapter         | Clip implemented             | Planned              | Planned              | Planned                                                                          | Planned                                                                    |
| `mp_genai`  | LLM adapter implemented      | No upstream backend          | No upstream backend  | No upstream backend  | LLM native constructor tested; other plugin APIs build; real-model tests pending | No plugin implementation                                                   |

This table is intentionally conservative. A platform becomes supported only after artifact packaging and a real-model integration test are green.

## Web

The web runtimes load pinned official ESM releases from jsDelivr. Model URLs with a SHA-256 digest are fetched and verified before their bytes enter MediaPipe. Vision live-stream calls are serialized over the official video API because the JavaScript Tasks surface exposes image and video modes. Audio streaming similarly classifies independent timestamped chunks.

Browser image conversion currently normalizes input to 8-bit RGBA `ImageData`. Higher-precision source images lose precision at that boundary.

## Desktop

Classic vision, text, and audio tasks are built from MediaPipe’s aggregate C target and accessed through generated `dart:ffi` bindings. The project owns reproducible artifact builds and must publish checksummed artifacts for each supported operating system and architecture before desktop support is declared stable.

MediaPipe’s open-source GenAI Task does not provide a desktop C runtime. `mp_genai` reports that capability as unsupported rather than silently using a remote model.

## Android and iOS

Proofreading and summarization use the official platform-specific text APIs. The
plugin build fixture compiles and launches on Android and iOS. Device tests pass
malformed model bytes through each native constructor and verify that the SDK
returns a typed failure rather than `unimplemented`. The fixture does not bundle
the separately distributed `.litertlm` models, so successful model inference
remains a support gate.

The iOS bridge currently uses CocoaPods because MediaPipe does not publish an
official Swift Package Manager package for its task frameworks. Flutter's
[package-manager integration](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)
falls back to CocoaPods for this plugin. SwiftPM-only integration remains
blocked on an independently hosted, checksummed XCFramework release or
[upstream support](https://github.com/google-ai-edge/mediapipe/issues/5464).

The other classic tasks are intended to use the C task contract where packaging
permits it. GenAI requires separate platform bridges because it is not part of
the aggregate C library. The Android plugin implements LLM inference, function
calling, RAG, and image generation. A device test verifies that LLM construction
reaches the native SDK. This does not count as model qualification; tests with
the separately distributed models are still required. The Android upstream LLM
API is deprecated in favor of LiteRT-LM.

See the [release policy](project/releases) for the criteria that move a cell from planned to supported.
