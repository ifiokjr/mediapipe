// Copyright 2026 The MP SDK Authors.
// SPDX-License-Identifier: Apache-2.0

#include "mp_pixel_conversion.h"

#include "libyuv/convert.h"

namespace {

// libyuv's RAW output is 24-bit RGB in memory, which is the sRGB sample order
// the Dart kernels produce.
constexpr int kSrgbBytesPerPixel = 3;
constexpr int kSrgbaBytesPerPixel = 4;

}  // namespace

int MpPixelBgraToSrgba(const uint8_t* src, int src_stride, int width, int height, uint8_t* dst) {
  if (src == nullptr || dst == nullptr || width <= 0 || height <= 0 ||
      src_stride < width * kSrgbaBytesPerPixel) {
    return -1;
  }
  for (int row = 0; row < height; ++row) {
    const uint8_t* source_row = src + static_cast<size_t>(row) * src_stride;
    uint8_t* destination_row = dst + static_cast<size_t>(row) * width * kSrgbaBytesPerPixel;
    for (int column = 0; column < width; ++column) {
      destination_row[0] = source_row[2];
      destination_row[1] = source_row[1];
      destination_row[2] = source_row[0];
      destination_row[3] = source_row[3];
      source_row += kSrgbaBytesPerPixel;
      destination_row += kSrgbaBytesPerPixel;
    }
  }
  return 0;
}

int MpPixelNv21ToSrgb(const uint8_t* src, int src_stride, int width, int height, uint8_t* dst) {
  if (src == nullptr || dst == nullptr || width <= 0 || height <= 0 || src_stride < width ||
      (width % 2) != 0 || (height % 2) != 0) {
    return -1;
  }
  const uint8_t* vu = src + static_cast<size_t>(src_stride) * height;
  return libyuv::NV21ToRAW(
      /*src_y=*/src, /*src_stride_y=*/src_stride, /*src_vu=*/vu,
      /*src_stride_vu=*/src_stride, /*dst_raw=*/dst,
      /*dst_stride_raw=*/width * kSrgbBytesPerPixel, width, height);
}

int MpPixelYuv420ToSrgb(const uint8_t* y, int y_stride, int y_pixel_stride, const uint8_t* u,
                        int u_stride, int u_pixel_stride, const uint8_t* v, int v_stride,
                        int v_pixel_stride, int width, int height, uint8_t* dst) {
  if (y == nullptr || u == nullptr || v == nullptr || dst == nullptr || width <= 0 ||
      height <= 0 || (width % 2) != 0 || (height % 2) != 0 || y_pixel_stride <= 0 ||
      u_pixel_stride <= 0 || v_pixel_stride <= 0 || y_stride < width * y_pixel_stride) {
    return -1;
  }
  const int dst_stride = width * kSrgbBytesPerPixel;
  if (y_pixel_stride == 1 && u_pixel_stride == 1 && v_pixel_stride == 1) {
    return libyuv::I420ToRAW(y, y_stride, u, u_stride, v, v_stride, dst, dst_stride, width,
                             height);
  }
  // Android exposes semi-planar layouts as three planes over one interleaved
  // chroma buffer with a pixel stride of two; hand that buffer to the NV12
  // path directly.
  if (y_pixel_stride == 1 && u_pixel_stride == 2 && v_pixel_stride == 2 && v == u + 1) {
    return libyuv::NV12ToRAW(y, y_stride, u, u_stride, dst, dst_stride, width, height);
  }
  return -1;
}
