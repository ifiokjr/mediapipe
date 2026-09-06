import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Creates the default non-web text runtime.
TextRuntime createTextRuntime() => UnsupportedTextRuntime(MpPlatform.current);
