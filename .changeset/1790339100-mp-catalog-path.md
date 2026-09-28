---
mp_core:
  type: fix
  version: "0.1.0"
---

# Cover the published native runtime resolution path

Add a regression test for the build-hook path a package with no
`native_library_directory` user define takes: resolving the checksummed archive
named by `native_artifacts.json` for the host. The test skips when the catalog
publishes no build for the test host, because a missing target legitimately
bundles nothing.
