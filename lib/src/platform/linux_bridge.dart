import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'storage_bridge.dart';

/// Desktop Linux. The home folder stands in for shared storage, file access
/// needs no grant, and the Android-only cache tools give way to the Linux
/// cache screen (`~/.cache` and the desktop trash).
class LinuxStorageBridge implements StorageBridge {
  LinuxStorageBridge({Map<String, String>? environment})
    : _env = environment ?? Platform.environment;

  final Map<String, String> _env;

  bool get _inSnap => _env['SNAP'] != null;

  /// The user's real home, also inside a snap, where HOME is the snap's own
  /// data folder.
  String get home => p.normalize(_env['SNAP_REAL_HOME'] ?? _env['HOME'] ?? '/');

  /// Per-app caches. Inside a snap the XDG variables point into the snap, so
  /// the real `~/.cache` is used there.
  String get cacheDir => _xdg('XDG_CACHE_HOME') ?? p.join(home, '.cache');

  /// The freedesktop.org trash shared by file managers.
  String get trashDir =>
      p.join(_xdg('XDG_DATA_HOME') ?? p.join(home, '.local', 'share'), 'Trash');

  String? _xdg(String name) {
    final value = _env[name];
    if (_inSnap || value == null || !p.isAbsolute(value)) return null;
    return p.normalize(value);
  }

  @override
  Future<String> storageRoot() async => home;

  /// The user's document and media folders that exist. Scanning these rather
  /// than all of home keeps source trees, SDKs and app data out of reach.
  @override
  Future<List<String>> scanRoots() async {
    String? config;
    try {
      config = await File(
        p.join(home, '.config', 'user-dirs.dirs'),
      ).readAsString();
    } on FileSystemException {
      // Not readable (or absent): the English defaults apply.
    }
    return [
      for (final dir in userDirs(home, config))
        if (await Directory(dir).exists()) dir,
    ];
  }

  @override
  Future<int> sdkInt() async => 0;

  @override
  Future<StorageInfo> storageInfo() async {
    final (total, free) = _statvfs(home);
    return StorageInfo(totalBytes: total, freeBytes: free);
  }

  @override
  Future<bool> hasAllFilesAccess() async => true;

  @override
  Future<void> requestAllFilesAccess() async {}

  /// Nothing to grant on Linux; reporting access hides the Android prompt.
  @override
  Future<bool> hasUsageAccess() async => true;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<List<AppCacheInfo>> appCaches() async => const [];

  @override
  Future<Uint8List?> appIcon(String packageName) async => null;

  @override
  Future<void> openAppDetails(String packageName) async {}

  @override
  Future<TrimResult> trimCaches() async =>
      const TrimResult(0, 'Not available on Linux');

  @override
  Future<ClearCacheOutcome> clearExternalAppCaches() async =>
      ClearCacheOutcome.unsupported;

  @override
  Future<int> clearOwnCache() async => 0;

  @override
  Future<void> mediaScan(List<String> paths) async {}

  @override
  Future<Map<String, ApkInfo>> apkInfo(List<String> paths) async => const {};
}

/// The desktop, documents, downloads, music, pictures and videos folders
/// from an XDG `user-dirs.dirs` file, falling back to the English defaults.
/// Folders set to home itself (the spec's way of disabling one) or outside
/// home are left out.
List<String> userDirs(String home, String? userDirsFile) {
  const defaults = {
    'DESKTOP': 'Desktop',
    'DOCUMENTS': 'Documents',
    'DOWNLOAD': 'Downloads',
    'MUSIC': 'Music',
    'PICTURES': 'Pictures',
    'VIDEOS': 'Videos',
  };
  home = p.normalize(home);
  final configured = <String, String>{};
  final line = RegExp(r'^XDG_([A-Z]+)_DIR="(.*)"$');
  for (final raw in LineSplitter.split(userDirsFile ?? '')) {
    final m = line.firstMatch(raw.trim());
    if (m == null || !defaults.containsKey(m[1])) continue;
    final value = m[2]!.replaceFirst(r'$HOME', home);
    if (p.isAbsolute(value)) configured[m[1]!] = p.normalize(value);
  }
  return [
    for (final MapEntry(:key, :value) in defaults.entries)
      if (configured[key] ?? p.join(home, value) case final dir
          when dir != home && p.isWithin(home, dir))
        dir,
  ];
}

typedef _StatvfsNative =
    Int32 Function(Pointer<Utf8> path, Pointer<Uint64> buf);
typedef _StatvfsDart = int Function(Pointer<Utf8> path, Pointer<Uint64> buf);

/// Total and available bytes of the filesystem holding [path], via libc
/// `statvfs` (64-bit layout: f_bsize, f_frsize, f_blocks, f_bfree, f_bavail,
/// …, all 8-byte fields, 112 bytes in all).
(int, int) _statvfs(String path) {
  final statvfs = DynamicLibrary.process()
      .lookupFunction<_StatvfsNative, _StatvfsDart>('statvfs');
  final buf = calloc<Uint64>(14);
  final cPath = path.toNativeUtf8();
  try {
    if (statvfs(cPath, buf) != 0) {
      throw FileSystemException('statvfs failed', path);
    }
    final frsize = buf[1];
    return (buf[2] * frsize, buf[4] * frsize);
  } finally {
    calloc.free(buf);
    calloc.free(cPath);
  }
}
