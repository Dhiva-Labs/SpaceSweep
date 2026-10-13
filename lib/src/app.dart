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
      // On a wide desktop window keep the phone-sized layout centred
      // instead of stretching cards across the screen.
      builder: (context, child) => LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth <= 720
            ? child!
            : ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: child,
                  ),
                ),
              ),
      ),
    );
  }
}
