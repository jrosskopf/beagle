import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'engine_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final host = await EngineHost.boot();
  runApp(ProviderScope(
    overrides: [engineHostProvider.overrideWithValue(host)],
    child: const DriveBeagleApp(),
  ));
}
