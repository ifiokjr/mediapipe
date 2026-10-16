---
mp_audio: fix
mp_text: fix
mp_vision: fix
---

# Lifecycle cleanup and retry fixes

- `mp_vision`, `mp_audio`, `mp_text`: native backends seal themselves only
  after the native task is released. Previously a failed close left the
  backend marked closed, so the facade's documented retry re-invoked a no-op
  and permanently leaked the worker isolate and native task. A failed close
  now leaves the task open for a retried cleanup.
- `mp_audio`, `mp_text`: facades reopen after a failed close — matching the
  `mp_vision` behavior — and a concurrent second `close()` now awaits the
  in-flight attempt instead of resolving before cleanup finishes.
- `mp_vision`: frame processing allocates the native image inside the scope's
  error boundary, so an image-creation failure on the worker no longer leaks
  the per-call native arena (previously one full-frame buffer per failure).
