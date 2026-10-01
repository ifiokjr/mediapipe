import 'dart:io';

import 'platform.dart';

/// Detects the active `dart:io` platform.
MpPlatform detectPlatform() {
  if (Platform.isAndroid) return MpPlatform.android;
  if (Platform.isIOS) return MpPlatform.ios;
  if (Platform.isLinux) return MpPlatform.linux;
  if (Platform.isMacOS) return MpPlatform.macos;
  if (Platform.isWindows) return MpPlatform.windows;
  return MpPlatform.unknown;
}
