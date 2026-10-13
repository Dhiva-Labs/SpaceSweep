import 'package:flutter/services.dart';

class StorageInfo {
  const StorageInfo({
    required this.totalBytes,
    required this.freeBytes,
    this.imageBytes,
    this.videoBytes,
    this.audioBytes,
    this.appBytes,
  });

  final int totalBytes;
  final int freeBytes;

  /// Breakdown totals; only known with usage access.
  final int? imageBytes;
  final int? videoBytes;
  final int? audioBytes;

  /// Installed apps: code plus data, caches included.
  final int? appBytes;

  int get usedBytes => totalBytes - freeBytes;
  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;
}

class AppCacheInfo {
  const AppCacheInfo({
    required this.packageName,
    required this.label,
    required this.cacheBytes,
    required this.dataBytes,
    required this.appBytes,
    required this.isSystem,
  });

  final String packageName;
  final String label;
  final int cacheBytes;
  final int dataBytes;
  final int appBytes;
  final bool isSystem;
}

class TrimResult {
  const TrimResult(this.freedBytes, [this.error]);

  final int freedBytes;
  final String? error;
}

enum ClearCacheOutcome { cleared, cancelled, failed, unsupported }

class ApkInfo {
  const ApkInfo({
    required this.packageName,
    required this.label,
    required this.versionName,
    required this.versionCode,
    this.installedVersionCode,
  });

  final String packageName;
  final String label;
  final String versionName;
  final int versionCode;
  final int? installedVersionCode;

  /// The same or a newer version is already installed.
  bool get isInstalled =>
      installedVersionCode != null && installedVersionCode! >= versionCode;
}

/// Android storage services the Dart side can't reach on its own.
abstract class StorageBridge {
  Future<String> storageRoot();

  /// Folders the file scans walk, all inside [storageRoot].
  Future<List<String>> scanRoots();

  Future<int> sdkInt();
  Future<StorageInfo> storageInfo();

  /// All-files access (Android 11+) or the legacy storage permission.
  Future<bool> hasAllFilesAccess();

  /// Opens the system grant screen (Android 11+) or asks for the legacy
  /// permission. Callers re-check [hasAllFilesAccess] when the app resumes.
  Future<void> requestAllFilesAccess();

  /// Usage access, needed to read other apps' cache sizes.
  Future<bool> hasUsageAccess();
  Future<void> openUsageAccessSettings();

  Future<List<AppCacheInfo>> appCaches();
  Future<Uint8List?> appIcon(String packageName);

  /// Opens the system App info page, where the user can clear its cache.
  Future<void> openAppDetails(String packageName);

  /// Asks Android to delete cached files across all apps, down to its own
  /// cache reserve (`StorageManager.allocateBytes`).
  Future<TrimResult> trimCaches();

  /// Android 11+: the system dialog that clears every app's external cache
  /// folder. Needs all-files access.
  Future<ClearCacheOutcome> clearExternalAppCaches();

  /// Clears this app's own cache; returns bytes freed.
  Future<int> clearOwnCache();

  /// Tells the media store that [paths] are gone so galleries drop them.
  Future<void> mediaScan(List<String> paths);

  Future<Map<String, ApkInfo>> apkInfo(List<String> paths);
}

class MethodChannelStorageBridge implements StorageBridge {
  MethodChannelStorageBridge([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('space_sweep/storage');

  final MethodChannel _channel;

  Future<T> _call<T>(String method, [Object? args]) async =>
      (await _channel.invokeMethod<T>(method, args)) as T;

  @override
  Future<String> storageRoot() => _call('storageRoot');

  /// All of shared storage.
  @override
  Future<List<String>> scanRoots() async => [await storageRoot()];

  @override
  Future<int> sdkInt() => _call('sdkInt');

  @override
  Future<StorageInfo> storageInfo() async {
    final m = await _call<Map>('storageInfo');
    return StorageInfo(
      totalBytes: m['total'] as int,
      freeBytes: m['free'] as int,
      imageBytes: m['images'] as int?,
      videoBytes: m['video'] as int?,
      audioBytes: m['audio'] as int?,
      appBytes: m['apps'] as int?,
    );
  }

  @override
  Future<bool> hasAllFilesAccess() => _call('hasAllFilesAccess');

  @override
  Future<void> requestAllFilesAccess() =>
      _channel.invokeMethod('requestAllFilesAccess');

  @override
  Future<bool> hasUsageAccess() => _call('hasUsageAccess');

  @override
  Future<void> openUsageAccessSettings() =>
      _channel.invokeMethod('openUsageAccessSettings');

  @override
  Future<List<AppCacheInfo>> appCaches() async {
    final list = await _call<List>('appCaches');
    return [
      for (final m in list.cast<Map>())
        AppCacheInfo(
          packageName: m['package'] as String,
          label: m['label'] as String,
          cacheBytes: m['cache'] as int,
          dataBytes: m['data'] as int,
          appBytes: m['app'] as int,
          isSystem: m['system'] as bool,
        ),
    ];
  }

  @override
  Future<Uint8List?> appIcon(String packageName) =>
      _channel.invokeMethod<Uint8List>('appIcon', {'package': packageName});

  @override
  Future<void> openAppDetails(String packageName) =>
      _channel.invokeMethod('openAppDetails', {'package': packageName});

  @override
  Future<TrimResult> trimCaches() async {
    final m = await _call<Map>('trimCaches');
    return TrimResult(m['freed'] as int, m['error'] as String?);
  }

  @override
  Future<ClearCacheOutcome> clearExternalAppCaches() async {
    final outcome = await _call<String>('clearExternalAppCaches');
    return ClearCacheOutcome.values.byName(outcome);
  }

  @override
  Future<int> clearOwnCache() => _call('clearOwnCache');

  @override
  Future<void> mediaScan(List<String> paths) async {
    if (paths.isEmpty) return;
    await _channel.invokeMethod('mediaScan', {'paths': paths});
  }

  @override
  Future<Map<String, ApkInfo>> apkInfo(List<String> paths) async {
    if (paths.isEmpty) return const {};
    final m = await _call<Map>('apkInfo', {'paths': paths});
    return {
      for (final MapEntry(:key, :value) in m.entries)
        key as String: ApkInfo(
          packageName: value['package'] as String,
          label: value['label'] as String,
          versionName: (value['versionName'] as String?) ?? '',
          versionCode: value['versionCode'] as int,
          installedVersionCode: value['installedVersionCode'] as int?,
        ),
    };
  }
}
