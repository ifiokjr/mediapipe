import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Creates the default non-web audio runtime.
AudioRuntime createAudioRuntime() => UnsupportedAudioRuntime(MpPlatform.current);
