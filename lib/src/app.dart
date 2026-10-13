import 'package:flutter/material.dart';

import 'platform/storage_bridge.dart';
import 'ui/home_screen.dart';

class SpaceSweepApp extends StatelessWidget {
  const SpaceSweepApp({super.key, required this.bridge});

  final StorageBridge bridge;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpaceSweep',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomeScreen(bridge: bridge),
    );
  }
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF00897B),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
