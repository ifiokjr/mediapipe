---
mp_camera: feat
---

# Overlay coordinate transform and ui.Image interop

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
