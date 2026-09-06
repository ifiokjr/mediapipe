import 'dart:io';

import 'package:mp_core/mp_core.dart';

import 'platform_channel_flutter.dart';
import 'runtime.dart';

/// Creates the Android generative AI bridge when the plugin is available.
GenAiRuntime createGenAiRuntime() =>
    Platform.isAndroid ? const MobileGenAiRuntime() : UnsupportedGenAiRuntime(MpPlatform.current);
