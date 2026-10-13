import 'package:path/path.dart' as p;

/// A regular file as it looked when it was scanned.
///
/// [size] and [modifiedMs] are kept so a later delete can refuse to touch a
/// file that changed after the scan.
class FileEntry {
  const FileEntry(this.path, this.size, this.modifiedMs);

  final String path;
  final int size;
  final int modifiedMs;

  String get name => p.basename(path);
  String get parent => p.dirname(path);
  DateTime get modified => DateTime.fromMillisecondsSinceEpoch(modifiedMs);

  @override
  bool operator ==(Object other) =>
      other is FileEntry &&
      other.path == path &&
      other.size == size &&
      other.modifiedMs == modifiedMs;

  @override
  int get hashCode => Object.hash(path, size, modifiedMs);

  @override
  String toString() => 'FileEntry($path, $size)';
}
