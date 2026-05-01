import 'dart:io';

import 'package:beagle_cli/cli_runner.dart';

Future<void> main(List<String> args) async {
  final code = await runCli(args);
  exit(code);
}
