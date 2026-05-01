import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/screens/home_screen.dart';

class DriveBeagleApp extends ConsumerWidget {
  const DriveBeagleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMacMenuBar = Platform.isMacOS;
    return MaterialApp(
      title: 'drive-beagle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.dark,
      ),
      home: HomeScreen(compact: isMacMenuBar),
    );
  }
}
