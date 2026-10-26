---
mp_core: feat
mp_camera: fix
---

# Shared pixel-conversion kernels and a performance gate

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
