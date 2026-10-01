import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Creates the default non-web vision runtime.
VisionRuntime createVisionRuntime() => UnsupportedVisionRuntime(MpPlatform.current);
