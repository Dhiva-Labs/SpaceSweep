import '../model/file_entry.dart';
import 'background.dart';
import 'walker.dart';

/// The biggest files of at least [minSize] bytes under [root], largest
/// first, capped at [limit].
List<FileEntry> scanLargeFiles(
  String root, {
  required int minSize,
  int limit = 500,
  void Function(int filesSeen)? onFile,
}) {
  final files = walkFiles(root, minSize: minSize, onFile: onFile).toList()
    ..sort((a, b) => b.size.compareTo(a.size));
  return files.length > limit ? files.sublist(0, limit) : files;
}

ScanTask<List<FileEntry>, int> largeFileScanTask(String root, int minSize) =>
    (emit) => scanLargeFiles(root, minSize: minSize, onFile: emit);
