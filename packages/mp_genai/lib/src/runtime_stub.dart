import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Creates the default non-web generative AI runtime.
GenAiRuntime createGenAiRuntime() => UnsupportedGenAiRuntime(MpPlatform.current);
