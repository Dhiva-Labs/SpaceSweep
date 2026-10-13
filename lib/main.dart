import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/platform/storage_bridge.dart';

void main() {
  runApp(SpaceSweepApp(bridge: MethodChannelStorageBridge()));
}
