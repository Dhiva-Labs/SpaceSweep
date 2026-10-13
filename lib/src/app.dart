import 'package:flutter/material.dart';

import 'platform/storage_bridge.dart';
import 'theme.dart';
import 'ui/home_screen.dart';

class SpaceSweepApp extends StatelessWidget {
  const SpaceSweepApp({super.key, required this.bridge});

  final StorageBridge bridge;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpaceSweep',
      debugShowCheckedModeBanner: false,
      theme: sweepTheme(Brightness.light),
      darkTheme: sweepTheme(Brightness.dark),
      home: HomeScreen(bridge: bridge),
    );
  }
}
