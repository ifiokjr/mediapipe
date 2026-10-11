---
mp_core: feat
---

# Copy-free image buffers

`MpImageUint8.adopt`, `MpImageUint16.adopt`, and `MpImageFloat32.adopt` are now
public. An image produced from a freshly filled buffer — a camera-frame
conversion, a decoder output — can hand the buffer over instead of paying a
full-image defensive copy first. The default constructors keep their copying
behavior, so this is an opt-in fast path.
