// Copyright 2026 The MP SDK Authors.
// SPDX-License-Identifier: Apache-2.0
//
// SIMD pixel conversion for the MP SDK's camera hot path. The functions mirror
// the pure Dart kernels in `package:mp_core` (`PixelConverter`): they read the
// same padded plane layouts, write the same tightly packed sRGB/sRGBA bytes,
// and return 0 on success or a negative value when the layout is unsupported,
// letting the caller fall back to the Dart implementation.

#ifndef MP_PIXEL_CONVERSION_H_
#define MP_PIXEL_CONVERSION_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Swizzles a BGRA8888 plane with row stride into tightly packed sRGBA bytes.
int MpPixelBgraToSrgba(const uint8_t* src, int src_stride, int width, int height, uint8_t* dst);

// Converts an NV21 buffer — the Y plane followed by interleaved VU rows that
// share src_stride — into tightly packed sRGB bytes.
int MpPixelNv21ToSrgb(const uint8_t* src, int src_stride, int width, int height, uint8_t* dst);

// Converts three-plane YUV420 into tightly packed sRGB bytes. Each chroma
// plane carries its own row and pixel strides; pixel stride 1 selects the
// planar I420 path and interleaved semi-planar buffers (v one byte after u
// with pixel stride 2) select the NV12 path. Other layouts return an error so
// the caller can fall back.
int MpPixelYuv420ToSrgb(const uint8_t* y, int y_stride, int y_pixel_stride, const uint8_t* u,
                        int u_stride, int u_pixel_stride, const uint8_t* v, int v_stride,
                        int v_pixel_stride, int width, int height, uint8_t* dst);

#ifdef __cplusplus
}
#endif

#endif  // MP_PIXEL_CONVERSION_H_
