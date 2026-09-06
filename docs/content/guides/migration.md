---
title: API mapping
description: Map MediaPipe and Google ML Kit Flutter concepts to MP types.
---

MP follows MediaPipe Task concepts while making ownership and platform differences explicit.

## Concept mapping

| MediaPipe concept        | MP SDK                                    |
| ------------------------ | ----------------------------------------- |
| Base options             | `BaseOptions`                             |
| Model file / buffer      | `ModelAsset.path` / `ModelAsset.bytes`    |
| Running mode             | `VisionRunningMode` or `AudioRunningMode` |
| Image processing options | `ImageProcessingOptions`                  |
| Task-specific result     | Immutable Dart result class               |
| Native close / delete    | `await task.close()`                      |
| Result listener          | Typed `Stream<VisionLiveResult<T>>`       |

## From google/flutter-mediapipe

The earlier repository generated Dart bindings and included native asset
experiments. Its generated `mediapipe` library and MP define different symbols
and ownership rules, so they should not be imported into the same application.
Replace task construction first, then translate inputs and results one feature
at a time.

## From Google ML Kit Flutter

The lifecycle is familiar: create a detector, process typed input, and close it. MP differs in three important ways:

- packages are grouped by signal family rather than one package per detector;
- model assets and execution delegates are application-controlled;
- web and desktop use dedicated adapters where upstream MediaPipe provides a runtime.

Like ML Kit Flutter's input package, `mp_camera` keeps camera conversion separate
from task APIs. It also provides a bounded latest-frame scheduler and typed
frame metadata.

## Coordinate overlays

Keep preview mirroring separate from sensor pixels. Pass sensor rotation through `ImageProcessingOptions`; apply preview mirroring only when painting a result. Test all four device orientations and both lens directions on real hardware.
