import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/file_entry.dart';
import '../scan/duplicates.dart';
import '../scan/junk.dart';
import '../scan/walker.dart';

class SkippedItem {
  const SkippedItem(this.path, this.reason);

  final String path;
  final String reason;
}

class DeleteReport {
  final deleted = <String>[];
  final skipped = <SkippedItem>[];
  var freedBytes = 0;

  void _skip(String path, String reason) =>
      skipped.add(SkippedItem(path, reason));
}

/// Deletes what the scans found, re-checking every item first.
///
/// Rules, in order of importance:
/// * a duplicate group always keeps at least one copy, and only when that
///   copy is still on disk unchanged;
/// * nothing outside [root], or inside other apps' private folders, is
///   ever touched;
/// * a file that changed (size or modified time) or turned into a link
///   since the scan is skipped, not deleted.
class Cleaner {
  Cleaner(String root) : root = p.normalize(root);

  final String root;

  Future<DeleteReport> deleteDuplicates(
    Iterable<DuplicateGroup> groups,
    Set<String> selected,
  ) async {
    final report = DeleteReport();
    for (final group in groups) {
      final victims = group.files
          .where((f) => selected.contains(f.path))
          .toList();
      if (victims.isEmpty) continue;
      final keepers = group.files.where((f) => !selected.contains(f.path));
      if (keepers.isEmpty) {
        for (final v in victims) {
          report._skip(v.path, 'Every copy was selected; one must stay');
        }
        continue;
      }
      var keeperIntact = false;
      for (final k in keepers) {
        if (await _unchanged(k)) {
          keeperIntact = true;
          break;
        }
      }
      if (!keeperIntact) {
        for (final v in victims) {
          report._skip(v.path, 'The copy being kept changed or is missing');
        }
        continue;
      }
      for (final v in victims) {
        await _deleteFile(v, report);
      }
    }
    return report;
  }

  Future<DeleteReport> deleteFiles(Iterable<FileEntry> files) async {
    final report = DeleteReport();
    for (final f in files) {
      await _deleteFile(f, report);
    }
    return report;
  }

  Future<DeleteReport> deleteJunk(Iterable<JunkItem> items) async {
    final report = DeleteReport();
    for (final item in items) {
      if (!item.isDirectory) {
        await _deleteFile(
          FileEntry(item.path, item.size, item.modifiedMs),
          report,
        );
        continue;
      }
      if (!_allowed(item.path)) {
        report._skip(item.path, 'Outside the scanned storage');
        continue;
      }
      if (await FileSystemEntity.isLink(item.path) ||
          !await Directory(item.path).exists()) {
        report._skip(item.path, 'No longer there');
        continue;
      }
      switch (item.kind) {
        case JunkKind.thumbnails:
          if (p.basename(item.path).toLowerCase() != '.thumbnails') {
            report._skip(item.path, 'Not a thumbnail folder');
            continue;
          }
        case JunkKind.emptyFolder:
          if (treeHasContent(item.path)) {
            report._skip(item.path, 'No longer empty');
            continue;
          }
        default:
          report._skip(item.path, 'Unexpected folder');
          continue;
      }
      try {
        await Directory(item.path).delete(recursive: true);
        report.deleted.add(item.path);
        report.freedBytes += item.size;
      } on FileSystemException catch (e) {
        report._skip(item.path, e.osError?.message ?? e.message);
      }
    }
    return report;
  }

  bool _allowed(String path) {
    final normal = p.normalize(path);
    return p.isWithin(root, normal) && !isPrivatePath(root, normal);
  }

  Future<bool> _unchanged(FileEntry f) async {
    if (await FileSystemEntity.isLink(f.path)) return false;
    final stat = await FileStat.stat(f.path);
    return stat.type == FileSystemEntityType.file &&
        stat.size == f.size &&
        stat.modified.millisecondsSinceEpoch == f.modifiedMs;
  }

  Future<void> _deleteFile(FileEntry f, DeleteReport report) async {
    if (!_allowed(f.path)) {
      report._skip(f.path, 'Outside the scanned storage');
      return;
    }
    if (!await _unchanged(f)) {
      report._skip(f.path, 'Changed or removed since the scan');
      return;
    }
    try {
      await File(f.path).delete();
      report.deleted.add(f.path);
      report.freedBytes += f.size;
    } on FileSystemException catch (e) {
      report._skip(f.path, e.osError?.message ?? e.message);
    }
  }
}
