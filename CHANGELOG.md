# Changelog

All notable changes to the MP SDK are documented here. The six public packages
share one version and are released together.

This project follows [Semantic Versioning](https://semver.org/).

## [0.1.0](https://github.com/ifiokjr/mediapipe/releases/tag/v0.1.0) (2026-09-07)

Grouped release for `mp`.

### Features

#### Add the initial six-package API workspace

_Packages:_ _mp_core_, _mp_vision_, _mp_camera_, _mp_text_, _mp_audio_, _mp_genai_

Defines shared task and result types; vision, text, audio, camera, and GenAI APIs;
web adapters; the classic native C bridge; mobile proofreading and summarization
plugin bridges; tests; and API documentation. Platform support remains limited
to the backends and real-model tests listed in the support matrix.

_Owner:_ [@ifiokjr](https://github.com/ifiokjr) · _Review:_ [PR #1](https://github.com/ifiokjr/mediapipe/pull/1)

### Other

- **mp**: Update package changelogs in grouped releases
- **mp**: Skip source changeset previews on prepared release PRs.
