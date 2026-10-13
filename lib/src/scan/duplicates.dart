import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../model/file_entry.dart';
import '../util/file_kind.dart';
import 'background.dart';
import 'walker.dart';

/// Files with identical content. Every file in [files] has the same [size]
/// and SHA-256 [hash].
class DuplicateGroup {
  DuplicateGroup(this.hash, this.size, List<FileEntry> files)
    : files = List.unmodifiable(files);

  final String hash;
  final int size;
  final List<FileEntry> files;

  /// Space freed by keeping a single copy.
  int get reclaimable => size * (files.length - 1);

  FileKind get kind => kindOf(files.first.path);

  DuplicateGroup without(Set<String> paths) => DuplicateGroup(
    hash,
    size,
    files.where((f) => !paths.contains(f.path)).toList(),
  );
}

class DuplicateScanOptions {
  const DuplicateScanOptions({
    this.minSize = 10 * 1000,
    this.includeHidden = false,
  });

  final int minSize;
  final bool includeHidden;
}

enum DuplicateStage { listing, sampling, hashing }

class DuplicateProgress {
  const DuplicateProgress(
    this.stage, {
    this.files = 0,
    this.done = 0,
    this.total = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
  });

  final DuplicateStage stage;

  /// Files listed so far.
  final int files;

  /// Candidates processed / total in the current stage.
  final int done;
  final int total;

  /// Bytes hashed / total during [DuplicateStage.hashing].
  final int bytesDone;
  final int bytesTotal;

  double? get fraction {
    if (stage == DuplicateStage.hashing && bytesTotal > 0) {
      return bytesDone / bytesTotal;
    }
    if (stage == DuplicateStage.sampling && total > 0) return done / total;
    return null;
  }
}

/// Bytes read from each of the start, middle and end of a file in the cheap
/// first pass. Files no larger than three samples are hashed whole there.
const sampleBytes = 16 * 1024;
const _wholeFileLimit = 3 * sampleBytes;

ScanTask<List<DuplicateGroup>, DuplicateProgress> duplicateScanTask(
  String root,
  DuplicateScanOptions options,
) =>
    (emit) => scanDuplicates(root, options, emit);

/// Scans [root] and returns duplicate groups, largest saving first.
List<DuplicateGroup> scanDuplicates(
  String root,
  DuplicateScanOptions options,
  void Function(DuplicateProgress) emit,
) {
  final files = walkFiles(
    root,
    includeHidden: options.includeHidden,
    minSize: options.minSize < 1 ? 1 : options.minSize,
    onFile: (n) => emit(DuplicateProgress(DuplicateStage.listing, files: n)),
  ).toList();
  return groupDuplicates(files, onProgress: emit);
}

/// Groups [files] by content in three passes so most files are never read
/// in full: same size, then a hash of three 16 KB samples, then a full
/// SHA-256 of the remaining candidates. Empty files are ignored. Files that
/// can't be read, or change size while being read, are dropped.
List<DuplicateGroup> groupDuplicates(
  Iterable<FileEntry> files, {
  void Function(DuplicateProgress)? onProgress,
}) {
  final bySize = <int, List<FileEntry>>{};
  final seen = <String>{};
  for (final f in files) {
    if (f.size <= 0 || !seen.add(f.path)) continue;
    bySize.putIfAbsent(f.size, () => []).add(f);
  }
  final candidates = [
    for (final group in bySize.values)
      if (group.length > 1) ...group,
  ];

  // Pass 1: samples. Small files are read whole, so their key is final.
  final bySample = <String, List<FileEntry>>{};
  var done = 0;
  for (final f in candidates) {
    final digest = _sampleDigest(f);
    onProgress?.call(
      DuplicateProgress(
        DuplicateStage.sampling,
        files: seen.length,
        done: ++done,
        total: candidates.length,
      ),
    );
    if (digest == null) continue;
    bySample.putIfAbsent('${f.size}:$digest', () => []).add(f);
  }

  final groups = <DuplicateGroup>[];
  final needFullHash = <FileEntry>[];
  for (final MapEntry(key: key, value: group) in bySample.entries) {
    if (group.length < 2) continue;
    if (group.first.size <= _wholeFileLimit) {
      groups.add(DuplicateGroup(_digestOf(key), group.first.size, group));
    } else {
      needFullHash.addAll(group);
    }
  }

  // Pass 2: full hash for the large files that matched on samples.
  final bytesTotal = needFullHash.fold<int>(0, (sum, f) => sum + f.size);
  var bytesDone = 0;
  done = 0;
  final byHash = <String, List<FileEntry>>{};
  for (final f in needFullHash) {
    final digest = _fullDigest(f, (n) {
      bytesDone += n;
      onProgress?.call(
        DuplicateProgress(
          DuplicateStage.hashing,
          files: seen.length,
          done: done,
          total: needFullHash.length,
          bytesDone: bytesDone,
          bytesTotal: bytesTotal,
        ),
      );
    });
    done++;
    if (digest == null) continue;
    byHash.putIfAbsent('${f.size}:$digest', () => []).add(f);
  }
  for (final MapEntry(key: key, value: group) in byHash.entries) {
    if (group.length > 1) {
      groups.add(DuplicateGroup(_digestOf(key), group.first.size, group));
    }
  }

  groups.sort((a, b) => b.reclaimable.compareTo(a.reclaimable));
  return groups;
}

String _digestOf(String key) => key.substring(key.indexOf(':') + 1);

/// SHA-256 of the file's start, middle and end samples, or of the whole file
/// when it is small enough that the samples would cover it anyway.
String? _sampleDigest(FileEntry f) {
  RandomAccessFile? raf;
  try {
    raf = File(f.path).openSync();
    final length = raf.lengthSync();
    if (length != f.size) return null;
    final Uint8List bytes;
    if (length <= _wholeFileLimit) {
      bytes = raf.readSync(length);
      if (bytes.length != length) return null;
    } else {
      final builder = BytesBuilder(copy: false);
      for (final offset in [
        0,
        length ~/ 2 - sampleBytes ~/ 2,
        length - sampleBytes,
      ]) {
        raf.setPositionSync(offset);
        final chunk = raf.readSync(sampleBytes);
        if (chunk.length != sampleBytes) return null;
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    }
    return sha256.convert(bytes).toString();
  } on FileSystemException {
    return null;
  } finally {
    raf?.closeSync();
  }
}

String? _fullDigest(FileEntry f, void Function(int bytes) onBytes) {
  RandomAccessFile? raf;
  try {
    raf = File(f.path).openSync();
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    final buffer = Uint8List(1 << 20);
    var total = 0;
    while (true) {
      final n = raf.readIntoSync(buffer);
      if (n <= 0) break;
      input.add(Uint8List.sublistView(buffer, 0, n));
      total += n;
      onBytes(n);
    }
    input.close();
    if (total != f.size) return null;
    return sink.value.toString();
  } on FileSystemException {
    return null;
  } finally {
    raf?.closeSync();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Strategies for choosing which copy in a group to keep.
enum KeepRule { oldest, newest, shortestPath }

/// Returns the paths to delete when keeping one copy per group by [rule].
/// The kept copy is never part of the result.
Set<String> autoSelect(Iterable<DuplicateGroup> groups, KeepRule rule) {
  final selected = <String>{};
  for (final group in groups) {
    final keep = pickKeeper(group, rule);
    for (final f in group.files) {
      if (f.path != keep.path) selected.add(f.path);
    }
  }
  return selected;
}

FileEntry pickKeeper(DuplicateGroup group, KeepRule rule) {
  int byPath(FileEntry a, FileEntry b) {
    final len = a.path.length.compareTo(b.path.length);
    return len != 0 ? len : a.path.compareTo(b.path);
  }

  final sorted = [...group.files]
    ..sort((a, b) {
      final primary = switch (rule) {
        KeepRule.oldest => a.modifiedMs.compareTo(b.modifiedMs),
        KeepRule.newest => b.modifiedMs.compareTo(a.modifiedMs),
        KeepRule.shortestPath => 0,
      };
      return primary != 0 ? primary : byPath(a, b);
    });
  return sorted.first;
}
