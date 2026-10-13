import 'dart:io';

import 'package:path/path.dart' as p;

import 'background.dart';
import 'walker.dart';

enum JunkKind {
  /// `.thumbnails` folders: previews gallery apps rebuild on demand.
  thumbnails,

  /// Installer packages (.apk, .apks, .xapk, .apkm) left after installing.
  apk,

  /// Temporary, partial-download and log files untouched for a day.
  temp,

  /// Media moved to the system trash (`.trashed-*`), deleted for good
  /// after 30 days anyway.
  trashed,

  /// Folders with no files anywhere inside.
  emptyFolder,
}

String junkLabel(JunkKind kind) => switch (kind) {
  JunkKind.thumbnails => 'Thumbnail caches',
  JunkKind.apk => 'Installer files (APK)',
  JunkKind.temp => 'Temporary & log files',
  JunkKind.trashed => 'Media in the trash',
  JunkKind.emptyFolder => 'Empty folders',
};

String junkDescription(JunkKind kind) => switch (kind) {
  JunkKind.thumbnails =>
    'Image previews that gallery apps recreate when needed.',
  JunkKind.apk =>
    'Installers you probably no longer need once the app is installed.',
  JunkKind.temp =>
    'Leftover temp files, broken downloads and logs older than a day.',
  JunkKind.trashed =>
    'Photos and videos waiting in the trash. Deleting them can\'t be undone.',
  JunkKind.emptyFolder => 'Folders that contain nothing.',
};

class JunkItem {
  const JunkItem(
    this.kind,
    this.path,
    this.size,
    this.modifiedMs, {
    this.isDirectory = false,
  });

  final JunkKind kind;
  final String path;
  final int size;
  final int modifiedMs;
  final bool isDirectory;

  String get name => p.basename(path);
}

/// Top-level folders Android and apps expect to exist, never reported as
/// empty even when they are.
const standardFolders = {
  'Alarms', 'Android', 'Audiobooks', 'DCIM', 'Documents', 'Download', //
  'Movies', 'Music', 'Notifications', 'Pictures', 'Podcasts', 'Recordings',
  'Ringtones',
};

const _apkExtensions = {'.apk', '.apks', '.xapk', '.apkm'};
const _tempExtensions = {
  '.tmp',
  '.temp',
  '.part',
  '.partial',
  '.crdownload',
  '.log',
};
const tempMinAge = Duration(days: 1);

ScanTask<List<JunkItem>, int> junkScanTask(String root) =>
    (emit) => scanJunk(root, onFolder: emit);

/// Walks [root] once and classifies junk.
///
/// Conservative by design: anything it cannot read counts as "not empty",
/// hidden folders are never reported as empty, the `Android` tree is only
/// searched for installers and temp files, and temp files must be at least
/// [tempMinAge] old so active downloads are left alone.
List<JunkItem> scanJunk(
  String root, {
  DateTime? now,
  void Function(int folders)? onFolder,
}) {
  root = p.normalize(root);
  final scanner = _JunkScanner(
    root,
    (now ?? DateTime.now()).subtract(tempMinAge),
    onFolder,
  );
  scanner.visit(root, depth: 0);
  scanner.items.sort((a, b) {
    final kind = a.kind.index.compareTo(b.kind.index);
    return kind != 0 ? kind : b.size.compareTo(a.size);
  });
  return scanner.items;
}

class _Summary {
  const _Summary(this.hasContent, this.bytes, [this.emptyChildren = const []]);

  /// True when the folder holds at least one file, link or unreadable entry.
  final bool hasContent;
  final int bytes;

  /// For an empty folder: its direct subfolders (all empty too).
  final List<String> emptyChildren;
}

class _JunkScanner {
  _JunkScanner(this.root, this.tempCutoff, this.onFolder);

  final String root;
  final DateTime tempCutoff;
  final void Function(int folders)? onFolder;
  final items = <JunkItem>[];
  var _folders = 0;

  static const _maxDepth = 64;

  _Summary visit(String dir, {required int depth}) {
    onFolder?.call(++_folders);
    if (depth > _maxDepth) return const _Summary(true, 0);
    final List<FileSystemEntity> children;
    try {
      children = Directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      return const _Summary(true, 0);
    }

    var hasContent = false;
    var bytes = 0;
    final emptyChildren = <String>[];
    for (final entity in children) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (isPrivatePath(root, entity.path)) {
          hasContent = true;
          continue;
        }
        if (name.toLowerCase() == '.thumbnails') {
          final size = _treeSize(entity.path);
          hasContent = true;
          bytes += size;
          if (size > 0) {
            items.add(
              JunkItem(
                JunkKind.thumbnails,
                entity.path,
                size,
                _modified(entity.path),
                isDirectory: true,
              ),
            );
          }
          continue;
        }
        final child = visit(entity.path, depth: depth + 1);
        bytes += child.bytes;
        if (child.hasContent) {
          hasContent = true;
        } else {
          emptyChildren.add(entity.path);
          _rememberEmpty[entity.path] = child.emptyChildren;
        }
      } else if (entity is File) {
        hasContent = true;
        final stat = entity.statSync();
        if (stat.type != FileSystemEntityType.file) continue;
        bytes += stat.size;
        final kind = _classify(name, stat.modified);
        if (kind != null) {
          items.add(
            JunkItem(
              kind,
              entity.path,
              stat.size,
              stat.modified.millisecondsSinceEpoch,
            ),
          );
        }
      } else {
        // Links and special files: content we never touch.
        hasContent = true;
      }
    }

    if (!hasContent && dir != root) {
      return _Summary(false, 0, emptyChildren);
    }
    for (final empty in emptyChildren) {
      _reportEmpty(empty, dir);
    }
    return _Summary(true, bytes);
  }

  final _rememberEmpty = <String, List<String>>{};

  /// Reports [folder] as junk unless it must stay, in which case its own
  /// empty subfolders are reported instead.
  void _reportEmpty(String folder, String parent) {
    final name = p.basename(folder);
    if (name.startsWith('.')) return;
    final inAndroid =
        p.isWithin(p.join(root, 'Android'), folder) ||
        folder == p.join(root, 'Android');
    if (inAndroid) return;
    if (parent == root && standardFolders.contains(name)) {
      for (final child in _rememberEmpty[folder] ?? const <String>[]) {
        _reportEmpty(child, folder);
      }
      return;
    }
    items.add(
      JunkItem(
        JunkKind.emptyFolder,
        folder,
        0,
        _modified(folder),
        isDirectory: true,
      ),
    );
  }

  JunkKind? _classify(String name, DateTime modified) {
    final lower = name.toLowerCase();
    if (lower.startsWith('.trashed-')) return JunkKind.trashed;
    if (lower.startsWith('.')) return null;
    final ext = p.extension(lower);
    if (_apkExtensions.contains(ext)) return JunkKind.apk;
    final isTemp = _tempExtensions.contains(ext) || lower.startsWith(r'~$');
    if (isTemp && modified.isBefore(tempCutoff)) return JunkKind.temp;
    return null;
  }
}

int _treeSize(String dir) {
  var total = 0;
  try {
    for (final e in Directory(
      dir,
    ).listSync(recursive: true, followLinks: false)) {
      if (e is File) total += e.statSync().size;
    }
  } on FileSystemException {
    // Count what was readable.
  }
  return total;
}

int _modified(String path) {
  final stat = FileStat.statSync(path);
  return stat.type == FileSystemEntityType.notFound
      ? 0
      : stat.modified.millisecondsSinceEpoch;
}

/// True when a folder tree contains anything other than folders.
bool treeHasContent(String dir) {
  try {
    for (final e in Directory(
      dir,
    ).listSync(recursive: true, followLinks: false)) {
      if (e is! Directory) return true;
    }
    return false;
  } on FileSystemException {
    return true;
  }
}
