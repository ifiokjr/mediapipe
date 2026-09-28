---
mp_core:
  type: fix
  version: "0.1.0"
mp_vision:
  type: fix
  version: "0.1.0"
mp_camera:
  type: fix
  version: "0.1.0"
mp_text:
  type: fix
  version: "0.1.0"
mp_audio:
  type: fix
  version: "0.1.0"
mp_genai:
  type: fix
  version: "0.1.0"
---

# Register the native runtime artifact catalog

Fill the build hook's artifact catalog with the checksummed MediaPipe runtime
archives published for release `native-v1.0.0-1`: macOS ARM64, Linux x64, and
Android ARM64/x64. Published packages now bundle a native runtime at build time
instead of requiring a local `.mp-sdk` build, and a missing target still
resolves a local runtime with an actionable error.
