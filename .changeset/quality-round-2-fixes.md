---
mp_camera: fix
mp_genai: fix
mp_text: fix
mp_vision: fix
---

# Round-two correctness and polish fixes

- `mp_camera`: frame conversion adopts the freshly filled pixel buffers instead
  of copying them again, so a 1080p frame now allocates its RGB/RGBA buffer
  once per frame instead of twice with an extra megabyte-scale memcpy.
- `mp_text`: streaming text tasks buffer platform events until the caller
  subscribes, so a fast first chunk is never dropped between the method call
  and `listen`.
- `mp_genai`, `mp_text`: streaming request ids are a plain counter instead of a
  wall-clock prefix, keeping them deterministic across tests and traces.
- `mp_vision`: the web interactive segmenter now forwards
  `processingOptions` (rotation and region of interest) on the signed-stroke
  path instead of silently dropping them.
