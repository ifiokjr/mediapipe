---
mp_core: feat
mp_genai: feat
mp_text: feat
---

# New capabilities from the quality pass

- `mp_core`: `TaskLifecycle.reopen()` lets a task whose backend cleanup failed
  stay usable so `close()` can be retried instead of leaking the underlying
  isolate and native handles.
- `mp_genai`, `mp_text`: streaming chunk types (`LlmGenerationChunk`,
  `RagGenerationChunk`, `TextSummarizerChunk`, `TextProofreaderChunk`) now
  implement value equality and hashing, so runtime-built instances compare by
  content the way every result type already does.
