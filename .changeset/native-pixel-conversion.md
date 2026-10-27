---
mp_core: feat
---

# SIMD pixel conversion through the native runtime

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
