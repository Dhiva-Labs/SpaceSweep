import 'dart:io';

import 'package:path/path.dart' as p;

import '../scan/background.dart';

/// One app's folder under `~/.cache`.
class CacheFolder {
  const CacheFolder(this.path, this.bytes);

  final String path;
  final int bytes;

  String get name => p.basename(path);
  String get label => cacheLabel(name);

  CacheFolder withBytes(int bytes) => CacheFolder(path, bytes);
}

class LinuxCacheScan {
  const LinuxCacheScan(this.folders, this.trashBytes, this.trashItems);

  /// Largest first; empty folders are left out.
  final List<CacheFolder> folders;
  final int trashBytes;
  final int trashItems;

  int get cacheBytes => folders.fold(0, (sum, f) => sum + f.bytes);
}

/// Readable names for common cache folders; anything else shows its folder
/// name.
String cacheLabel(String folder) => switch (folder) {
  'thumbnails' => 'Thumbnails',
  'mozilla' => 'Firefox',
  'google-chrome' => 'Google Chrome',
  'chromium' => 'Chromium',
  'BraveSoftware' => 'Brave',
  'microsoft-edge' => 'Microsoft Edge',
  'thunderbird' => 'Thunderbird',
  'spotify' => 'Spotify',
  'JetBrains' => 'JetBrains IDEs',
  'pip' => 'pip (Python packages)',
  'go-build' => 'Go build cache',
  'yarn' => 'Yarn packages',
  'pnpm' => 'pnpm packages',
  'fontconfig' => 'Font cache',
  'mesa_shader_cache' || 'mesa_shader_cache_db' => 'Shader cache (Mesa)',
  'nvidia' => 'NVIDIA shader cache',
  'tracker3' => 'GNOME search index',
  'gnome-software' => 'GNOME Software',
  'gstreamer-1.0' => 'GStreamer',
  _ => folder,
};

ScanTask<LinuxCacheScan, (int, int)> linuxCacheScanTask(
  String cacheDir,
  String trashDir,
) =>
    (emit) => scanLinuxCaches(
      cacheDir,
      trashDir,
      onFolder: (done, total) => emit((done, total)),
    );

/// Measures each folder in [cacheDir] and the trash in [trashDir]. Loose
/// files directly in [cacheDir] are skipped: they are tiny markers that
/// some tools rely on.
LinuxCacheScan scanLinuxCaches(
  String cacheDir,
  String trashDir, {
  void Function(int done, int total)? onFolder,
}) {
  final dirs = <String>[];
  try {
    for (final e in Directory(cacheDir).listSync(followLinks: false)) {
      if (e is Directory) dirs.add(e.path);
    }
  } on FileSystemException {
    // No ~/.cache, or not readable: nothing to report.
  }
  final folders = <CacheFolder>[];
  for (final (i, dir) in dirs.indexed) {
    final size = treeSize(dir);
    if (size > 0) folders.add(CacheFolder(dir, size));
    onFolder?.call(i + 1, dirs.length);
  }
  folders.sort((a, b) => b.bytes.compareTo(a.bytes));

  final trashFiles = p.join(trashDir, 'files');
  var trashItems = 0;
  try {
    trashItems = Directory(trashFiles).listSync(followLinks: false).length;
  } on FileSystemException {
    // Empty or missing trash.
  }
  final trashBytes =
      treeSize(trashFiles) + treeSize(p.join(trashDir, 'expunged'));
  return LinuxCacheScan(folders, trashBytes, trashItems);
}

/// Bytes of all regular files below [dir], without following links.
int treeSize(String dir) {
  var total = 0;
  try {
    for (final e in Directory(
      dir,
    ).listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += e.lengthSync();
        } on FileSystemException {
          // Vanished or unreadable.
        }
      }
    }
  } on FileSystemException {
    // Count what was readable.
  }
  return total;
}

/// Deletes everything inside [folder], a direct child of [cacheDir], and
/// returns the bytes freed. The folder itself stays so the app can keep
/// writing to it. Refuses anything that is not a real folder directly in
/// [cacheDir].
int clearCacheFolder(String cacheDir, String folder) {
  cacheDir = p.normalize(cacheDir);
  folder = p.normalize(folder);
  if (p.dirname(folder) != cacheDir ||
      FileSystemEntity.isLinkSync(folder) ||
      !FileSystemEntity.isDirectorySync(folder)) {
    throw ArgumentError.value(
      folder,
      'folder',
      'not a cache folder in $cacheDir',
    );
  }
  return _emptyFolders([folder]);
}

/// Permanently deletes everything in the trash at [trashDir] and returns
/// the bytes freed.
int emptyTrash(String trashDir) {
  trashDir = p.normalize(trashDir);
  if (p.basename(trashDir) != 'Trash') {
    throw ArgumentError.value(trashDir, 'trashDir', 'not a Trash folder');
  }
  return _emptyFolders([
    for (final sub in ['files', 'info', 'expunged']) p.join(trashDir, sub),
  ]);
}

ScanTask<int, void> clearCacheFolderTask(String cacheDir, String folder) =>
    (_) => clearCacheFolder(cacheDir, folder);

ScanTask<int, void> clearAllCachesTask(String cacheDir, List<String> folders) =>
    (_) => folders.fold(0, (sum, f) => sum + clearCacheFolder(cacheDir, f));

ScanTask<int, void> emptyTrashTask(String trashDir) =>
    (_) => emptyTrash(trashDir);

/// Deletes the contents of each folder (links are removed, never followed)
/// and returns how much smaller they got. Entries that can't be deleted,
/// such as files owned by another user, are left in place.
int _emptyFolders(List<String> folders) {
  var freed = 0;
  for (final folder in folders) {
    if (!FileSystemEntity.isDirectorySync(folder)) continue;
    final before = treeSize(folder);
    List<FileSystemEntity> children;
    try {
      children = Directory(folder).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final child in children) {
      try {
        if (child is Link || child is File) {
          child.deleteSync();
        } else if (child is Directory) {
          child.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // Skip what we may not delete.
      }
    }
    freed += before - treeSize(folder);
  }
  return freed;
}
