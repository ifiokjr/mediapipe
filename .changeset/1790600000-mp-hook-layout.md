---
mp: fix
---

# Ship a pub.dev-valid `hook/` directory

pub.dev rejects Dart files under `hook/` other than `hook/build.dart`, so the
native artifact catalog and download helper moved to
`lib/src/native/artifact.dart`. The 0.1.0 upload was rejected with "Hook files
are experimental and `hook/native_artifact.dart` is not allowed yet."
