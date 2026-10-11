---
mp_audio: docs
mp_core: docs
mp_genai: docs
mp_text: docs
mp_vision: docs
---

# Example and documentation updates

- The bare package examples (`mp_core`, `mp_audio`, `mp_genai`, `mp_vision`)
  are now instructive walkthroughs of each package's options, containers,
  lifecycle, and error contract instead of single-assert stubs, and remain
  runnable on any platform including the browser.
- The CLI hand-landmarks demo reads the upstream raised-hand test image
  (`pointing_up.jpg`) instead of the cats-and-dogs photo, and every pinned
  example asset digest is now regression-tested for format.
- The mp_text README describes the example fixture accurately and points at the
  runnable CLI demos.
