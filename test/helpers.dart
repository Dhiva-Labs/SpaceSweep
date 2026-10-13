import 'dart:io';

import 'package:path/path.dart' as p;

/// A throwaway storage root, deleted after the test.
class TempTree {
  TempTree() : root = Directory.systemTemp.createTempSync('space_sweep_').path;

  final String root;

  String path(String relative) => p.join(root, relative);

  File file(String relative, List<int> bytes, {DateTime? modified}) {
    final f = File(path(relative))..createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    if (modified != null) f.setLastModifiedSync(modified);
    return f;
  }

  Directory dir(String relative) =>
      Directory(path(relative))..createSync(recursive: true);

  void dispose() => Directory(root).deleteSync(recursive: true);
}

List<int> bytesOf(int length, int seed) =>
    List.generate(length, (i) => (i * 31 + seed) & 0xff);
