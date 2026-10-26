import 'dart:io';

import 'package:mp_benchmarks/mp_benchmarks.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runBenchmarkCli(arguments, out: stdout, err: stderr);
}
