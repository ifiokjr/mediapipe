---
title: Releases
description: Coordinated versions, immutable records, and single-pass trusted publishing.
---

All six packages share one MonoChange version group. A user-visible or compatibility change adds a changeset, and the release preparation workflow opens or updates a release pull request. The embedded release record is the audit source for versions, changelogs, and tags.

## Bootstrap publication

The unclaimed names were first reserved with minimal `0.0.0` packages. pub.dev limits brand-new package creation (`package-created`, per user/agent) to four packages per two-minute burst and twelve per day, so bootstrap publication was ordered with `mp_core` first:

1. `mp_core`, `mp_vision`, `mp_camera`, `mp_text`
2. `mp_audio`, `mp_genai` after the burst window reset

No bootstrap package claims production support. The first feature release is prepared only after the relevant platform integration checks pass.

## Feature releases

For new versions of existing packages, pub.dev allows 200 uploads per two-minute, hourly, and daily window per GitHub Actions OIDC repository agent (`package-published`, `scope: user`) and 3 per two minutes, 6 per hour, and 12 per day per individual package (`package-published`, `scope: package`). MonoChange's enforced `pub_dev` policy allows up to 12 pending packages per `publish-packages` invocation.

All six packages therefore publish in one pass after a single `publisher` environment approval:

1. Merging the release PR runs `release-pr.yml`, which pushes the `v*` tag and creates one draft GitHub release.
2. The tag push starts `publish.yml` on `refs/tags/v*` and pauses for one `publisher` approval.
3. `tool/plan_pub_batch.dart` queries pub.dev for versions still missing in dependency order (`mp_core` first) and selects up to 12 packages (all six in one run).
4. MonoChange verifies readiness and publishes the batch to pub.dev with trusted publishing (OIDC).
5. `monochange/actions/publish-draft-releases` makes the existing draft GitHub release public in place, leaving exactly one GitHub release per tag.

If a future release ever has more pending packages than one run may publish, the workflow's `continue` job dispatches the next batch directly on the release tag ref instead of relying on a cron schedule. Reruns are safe: versions already present on pub.dev are skipped, and publishing an already-public GitHub release is a no-op.

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
