---
title: Releases
description: Coordinated versions, immutable records, and rate-limited publishing.
---

All six packages share one MonoChange version group. A user-visible or compatibility change adds a changeset, and the release preparation workflow opens or updates a release pull request. The embedded release record is the audit source for versions, changelogs, and tags.

## Bootstrap publication

The unclaimed names are first reserved with minimal `0.0.0` packages. pub.dev allows four package uploads per four-hour window and twelve per day, so bootstrap publication is ordered:

1. `mp_core`, `mp_vision`, `mp_camera`, `mp_text`
2. `mp_audio`, `mp_genai` after the window resets

No bootstrap package claims production support. The first feature release is prepared only after the relevant platform integration checks pass.

## Release chain

1. Validate changesets and compute the grouped release plan.
2. Open the generated release pull request.
3. Require formatting, analysis, unit, browser, native, docs, and package-archive checks.
4. Merge the exact reviewed release commit.
5. Tag from its embedded MonoChange record.
6. Publish exact tag artifacts using pub.dev trusted publishing and GitHub OIDC.

Tags and published versions are never rebuilt from a moving branch. Failed partial publication resumes from the same immutable release record.

## Support declaration

A platform is supported only when CI or a maintained device runs a real model, resource cleanup is tested, its artifact is reproducible, and the limitation is documented. Compilation alone is not enough.
