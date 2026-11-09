---
mp_core: fix
---

# Model URI transport and digest checks

- Native model downloads no longer follow redirects blindly. Each hop must
  stay on HTTPS, and plain HTTP is still accepted only when the original URI
  is loopback. An HTTPS URL therefore cannot be downgraded to HTTP or turned
  into a request to a loopback service, and a loopback download cannot be
  redirected off the machine.
- A `file` URI that includes a SHA-256 digest is verified before the path is
  handed to the runtime. A missing file or a digest mismatch fails instead of
  loading the bytes unchecked.
- `requireRemoteModelUri` is exported from `package:mp_core/native.dart` as
  the transport check both download paths use.
