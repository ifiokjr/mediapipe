import 'platform_stub.dart'
    if (dart.library.io) 'platform_io.dart'
    if (dart.library.js_interop) 'platform_web.dart';

/// Flutter and Dart runtime families supported by MP packages.
enum MpPlatform {
  /// Android applications.
  android,

  /// iOS applications.
  ios,

  /// Browser applications compiled to JavaScript or WebAssembly.
  web,

  /// Linux desktop applications.
  linux,

  /// macOS desktop applications.
  macos,

  /// Windows desktop applications.
  windows,

  /// A runtime not recognized by this SDK version.
  unknown;

  /// Detects the current runtime without importing `dart:io` on web.
  static MpPlatform get current => detectPlatform();
}
