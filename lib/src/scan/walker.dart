import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/file_entry.dart';

/// Folders below the storage root that hold other apps' private data.
/// Android 11+ hides them even from all-files access, and deleting from
/// them on older releases breaks apps, so scans never enter them.
const privateDirs = ['Android/data', 'Android/obb'];

bool isPrivatePath(String root, String path) {
  for (final dir in privateDirs) {
    final private = p.join(root, dir);
    if (path == private || p.isWithin(private, path)) return true;
  }
  return false;
}

/// [walkFiles] over each of [roots] in turn; [onFile] counts across all of
/// them. Roots nested inside another root are skipped so no file is listed
/// twice.
Iterable<FileEntry> walkRoots(
  List<String> roots, {
  bool includeHidden = false,
  int minSize = 0,
  void Function(int filesSeen)? onFile,
}) sync* {
  var offset = 0;
  for (final root in distinctRoots(roots)) {
    var seenHere = 0;
    yield* walkFiles(
      root,
      includeHidden: includeHidden,
      minSize: minSize,
      onFile: (n) {
        seenHere = n;
        onFile?.call(offset + n);
      },
    );
    offset += seenHere;
  }
}

/// Normalised [roots] without duplicates or roots inside another root.
List<String> distinctRoots(List<String> roots) {
  final normal = {for (final r in roots) p.normalize(r)}.toList()..sort();
  final out = <String>[];
  for (final r in normal) {
    if (!out.any((kept) => kept == r || p.isWithin(kept, r))) out.add(r);
  }
  return out;
}

/// Lists regular files below [root], depth first.
///
/// Symlinks are never followed, so a file is reported at most once.
/// Folders that cannot be read are skipped. Hidden files and folders (dot
/// names) are skipped unless [includeHidden] is set; they mostly belong to
/// apps that expect them to stay put.
Iterable<FileEntry> walkFiles(
  String root, {
  bool includeHidden = false,
  int minSize = 0,
  void Function(int filesSeen)? onFile,
}) sync* {
  root = p.normalize(root);
  final stack = <String>[root];
  var seen = 0;
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> children;
    try {
      children = Directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final entity in children) {
      final name = p.basename(entity.path);
      if (!includeHidden && name.startsWith('.')) continue;
      if (entity is Directory) {
        if (!isPrivatePath(root, entity.path)) stack.add(entity.path);
      } else if (entity is File) {
        final stat = entity.statSync();
        if (stat.type != FileSystemEntityType.file) continue;
        onFile?.call(++seen);
        if (stat.size < minSize) continue;
        yield FileEntry(
          entity.path,
          stat.size,
          stat.modified.millisecondsSinceEpoch,
        );
      }
    }
  }
}
