---
mp_core: feat
---

# Content-addressed model cache

- `ModelAsset.uri` accepts `cacheDirectory`. On native platforms a
  digest-pinned model is downloaded once into a content-addressed cache (the
  SHA-256 digest is the file name), verified by hashing on every reuse, and
  replaced automatically when the cached file is corrupted or truncated. The
  download streams to a temporary file and hashes as bytes arrive, so a
  multi-hundred-megabyte model never sits in the Dart heap, and MediaPipe
  opens the finished file by path — which lets it map the file instead of
  copying it — rather than receiving a buffer. `cacheDirectory` requires a
  digest; browser builds ignore it.
- `ModelCache` and `maximumRemoteModelBytes` are exported from
  `package:mp_core/native.dart` for applications that want to pre-warm models.
- Remote model URIs still require HTTPS, except that plain HTTP is now accepted
  from loopback addresses so local development servers (and the SDK's own
  tests) can serve models; digest verification applies there too.
