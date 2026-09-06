---
title: Device verification
description: Use local inference for fast guidance without mistaking it for proof.
---

On-device models can check a capture before bytes leave the phone: whether a person or object is visible, framing is usable, or a requested gesture probably occurred. Treat this as an advisory result, not an authorization primitive.

## Suggested flow

1. Capture evidence and bind it to an attempt identifier.
2. Run the local task and show immediate, actionable guidance.
3. Preserve the original evidence; never replace it with model output.
4. Submit evidence, capture metadata, model version, and the advisory result to a secured service.
5. Make any reward, access, or trust decision with deterministic server policy and independent verification.

## Threat model

The application, model, local result, timestamps, camera metadata, and network payload can all be manipulated on a user-controlled device. Rooted devices, emulators, method hooking, pre-recorded media, and adversarial examples are normal conditions—not edge cases.

Use local inference to reduce failed captures and improve feedback. Do not let a confidence score mint an asset, release funds, grant a credential, or bypass server review.

## Data minimization

If a result is only needed for live guidance, avoid uploading it. If it helps server review, submit the smallest typed result needed and include a model identifier so policy can account for version changes.
