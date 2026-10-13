import 'dart:io';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/platform/linux_bridge.dart';
import 'src/platform/storage_bridge.dart';

void main() {
  final StorageBridge bridge = Platform.isLinux
      ? LinuxStorageBridge()
      : MethodChannelStorageBridge();
  runApp(SpaceSweepApp(bridge: bridge));
}
