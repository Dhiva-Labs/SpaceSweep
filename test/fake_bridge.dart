import 'dart:typed_data';

import 'package:space_sweep/src/platform/storage_bridge.dart';

class FakeBridge implements StorageBridge {
  FakeBridge(this.root);

  final String root;
  var allFiles = true;
  var usage = true;
  var apps = <AppCacheInfo>[];
  final scanned = <String>[];
  final opened = <String>[];
  var trimmed = 0;

  @override
  Future<String> storageRoot() async => root;

  @override
  Future<int> sdkInt() async => 35;

  @override
  Future<StorageInfo> storageInfo() async => const StorageInfo(
    totalBytes: 128 * 1000 * 1000 * 1000,
    freeBytes: 32 * 1000 * 1000 * 1000,
    imageBytes: 12 * 1000 * 1000 * 1000,
  );

  @override
  Future<bool> hasAllFilesAccess() async => allFiles;

  @override
  Future<void> requestAllFilesAccess() async => allFiles = true;

  @override
  Future<bool> hasUsageAccess() async => usage;

  @override
  Future<void> openUsageAccessSettings() async => usage = true;

  @override
  Future<List<AppCacheInfo>> appCaches() async => apps;

  @override
  Future<Uint8List?> appIcon(String packageName) async => null;

  @override
  Future<void> openAppDetails(String packageName) async =>
      opened.add(packageName);

  @override
  Future<TrimResult> trimCaches() async {
    trimmed++;
    return const TrimResult(5 * 1000 * 1000);
  }

  @override
  Future<ClearCacheOutcome> clearExternalAppCaches() async =>
      ClearCacheOutcome.cleared;

  @override
  Future<int> clearOwnCache() async => 0;

  @override
  Future<void> mediaScan(List<String> paths) async => scanned.addAll(paths);

  @override
  Future<Map<String, ApkInfo>> apkInfo(List<String> paths) async => const {};
}
