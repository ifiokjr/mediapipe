---
mp_core: fix
---

# Resolve alongside newer native-asset toolchains

`mp_core` now accepts `code_assets` 2.x and `hooks` 2.2, the versions newer
Flutter SDKs and other build-hook packages resolve. Applications that depend on
both `mp_core` and a package requiring `code_assets` 2.x no longer fail version
solving. Older Flutter workspaces keep resolving the 1.x line.
