---
mp_core: feat
mp_vision: fix
---

# Packed landmark lists

- `mp_core`: `NormalizedLandmarkList` and `LandmarkList` implement the
  existing `List<NormalizedLandmark>`/`List<Landmark>` contracts over one
  packed `Float32List` — five floats per landmark (x, y, z, visibility,
  presence, with absent confidences stored as quiet NaN) plus optional
  parallel names. A 478-point face result costs one buffer instead of
  hundreds of objects: cheaper to allocate on the worker isolate, cheaper to
  copy to the caller, and directly iterable by painting loops through
  `values` without materializing landmark objects. `fromLandmarks` packs
  app-built lists the same way; coordinates are 32-bit floats exactly as the
  native runtime reports them.
- `mp_vision`: native result conversion fills those packed lists directly
  from the C structs, so every landmarker result (face, hand, pose, gesture,
  holistic) crosses isolates as contiguous data. The concrete list type
  changes; reading code keeps working unchanged because the new lists are
  real `List`s with the same value equality.
