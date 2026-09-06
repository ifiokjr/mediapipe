---
title: Privacy and security
description: Boundaries for models, media, native artifacts, and untrusted output.
---

## On-device does not mean no disclosure

Task inference can process input locally, but applications still control model downloads, crash reporting, analytics, logs, and evidence upload. The official MediaPipe privacy documentation notes that metrics may be sent in some integrations. Audit the exact backend, obtain appropriate consent, and disclose behavior accurately.

## Treat every model boundary as untrusted

User text, filenames, URLs, camera-visible text, speech, model metadata, provider errors, and model output are data. They are never privileged instructions. Generative output must not select tools, roles, models, response schemas, or authorization decisions.

## Native artifact integrity

Release builds pin the MediaPipe source revision and compatibility patches. Published native archives must carry a SHA-256 digest and provenance from the build workflow. The package build hook must reject mismatched artifacts rather than using a system library with an unknown ABI.

## Model integrity

Use immutable model URLs and a digest. Validate size before allocation, reject malformed input, and keep model licenses and expected metadata under review. A checksum protects transport and identity; it does not establish that a model is safe or accurate.

## Resource limits

Set maximum image dimensions, audio duration, text length, context tokens, and output tokens appropriate to the product. Close tasks deterministically. Avoid concurrent entry into a task handle and bound stream queues.

Report security issues privately through the repository’s security policy, not a public issue.
