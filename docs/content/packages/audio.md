---
title: mp_audio
description: Classification for complete audio clips and timestamped chunks.
---

`AudioClassifier` accepts immutable, interleaved floating-point `AudioData` with explicit sample rate and channel count. Classification results preserve the windows and timestamps produced by the model.

## Clip mode

Use `AudioRunningMode.audioClips` for unrelated recordings. This path uses the official clip API on native and web runtimes.

## Stream mode

Use `AudioRunningMode.audioStream` with strictly increasing timestamps. The browser adapter classifies independent timestamped chunks because the JavaScript API does not expose native stream callbacks.

Native audio streaming is not declared supported until a callback-copy bridge guarantees the upstream result is copied before its memory expires. Clip inference remains independent of that work.

Multi-channel browser input is downmixed to mono for the official task surface. Applications that need a different channel policy should transform samples before constructing `AudioData`.
