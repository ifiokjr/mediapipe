---
title: Architecture
description: Package boundaries, generated bindings, and backend rules.
---

## Package graph

```text
mp_camera ──┐
mp_vision ──┤
mp_text ────┼──> mp_core
mp_audio ───┤
mp_genai ───┘
```

`mp_core` owns data contracts and the classic native library asset. Each task package owns its public task facade, options, result conversion, platform runtime, and tests. `mp_camera` is optional and depends on Flutter’s camera plugin.

## Classic native runtime

MediaPipe’s aggregate C target contains all classic vision, text, and audio tasks. A pinned builder applies narrowly documented compatibility patches, builds one library per target, and produces generated `dart:ffi` bindings from the public C headers.

The committed bindings are reviewed like source. CI regenerates them and fails on drift. Native results are copied into immutable Dart values and closed in the same operation.

## Web runtime

Conditional exports keep `dart:js_interop` out of native compilation and `dart:io`/FFI out of web compilation. Web adapters import exact upstream ESM versions, convert public inputs, and normalize JavaScript results into the same immutable types.

## GenAI runtime

GenAI is isolated because upstream does not expose it through the classic C aggregate. The web backend implements LLM inference. The Android plugin implements LLM inference, function calling, RAG, and image generation. iOS and desktop GenAI calls currently fail with an explicit unsupported status.

## Test coverage

Unit tests cover option validation, lifecycle, result conversion, media
conversion, scheduling, and failure cleanup. The current real-model lanes run
language detection in Chrome and macOS, plus face detection against the macOS C
runtime. The mobile fixture compiles and launches the Android `mp_text` and
`mp_genai` plugins and the iOS `mp_text` plugin. Proofreader, summarizer, and
Android GenAI model tests remain pending.
