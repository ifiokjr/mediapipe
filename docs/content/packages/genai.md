---
title: mp_genai
description: Stateful, streaming, multimodal LLM inference where upstream backends permit it.
---

`LlmInference` owns model weights and creates `LlmSession` instances. Sessions accept text, images, and WAV audio, then return a cancellable `LlmGeneration` with both incremental chunks and a final response future.

## Sessions

Sessions can be cloned to branch a conversation and can update mutable sampling controls. A LoRA adapter and graph options are fixed at session creation because changing either would invalidate native state.

## Platform contract

The web runtime uses the pinned official MediaPipe GenAI JavaScript package. Support for a session option is checked explicitly; for example, web top-p values other than `1` currently fail as unsupported.

Android and iOS require separate native bridges because GenAI is not included in the classic aggregate C library. Desktop platforms have no open-source upstream GenAI backend and are reported as unsupported.

The Android MediaPipe LLM API is deprecated toward LiteRT-LM. Application code should depend on this package’s session contract, not on backend-specific types.

## Safety

Model output is untrusted text. Never execute it, treat it as authorization, or replay it as privileged instructions. Bound prompt size and output tokens, validate any structured response, and keep high-impact decisions deterministic.
