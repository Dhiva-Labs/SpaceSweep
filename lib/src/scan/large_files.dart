import '../model/file_entry.dart';
import 'background.dart';
import 'walker.dart';

/// The biggest files of at least [minSize] bytes under [roots], largest
/// first, capped at [limit].
List<FileEntry> scanLargeFiles(
  List<String> roots, {
  required int minSize,
  int limit = 500,
  void Function(int filesSeen)? onFile,
}) {
  final files = walkRoots(roots, minSize: minSize, onFile: onFile).toList()
    ..sort((a, b) => b.size.compareTo(a.size));
  return files.length > limit ? files.sublist(0, limit) : files;
}

ScanTask<List<FileEntry>, int> largeFileScanTask(
  List<String> roots,
  int minSize,
) =>
    (emit) => scanLargeFiles(roots, minSize: minSize, onFile: emit);
