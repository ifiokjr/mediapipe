import 'platform.dart';

/// Detects the platform when neither IO nor web platform libraries are present.
MpPlatform detectPlatform() => MpPlatform.unknown;
