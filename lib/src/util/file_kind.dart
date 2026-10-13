import 'package:path/path.dart' as p;

enum FileKind { image, video, audio, document, archive, other }

const _kinds = <FileKind, Set<String>>{
  FileKind.image: {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'dng', //
  },
  FileKind.video: {
    'mp4', 'mkv', 'mov', '3gp', 'webm', 'avi', 'm4v', 'ts', //
  },
  FileKind.audio: {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'amr', 'wma', //
  },
  FileKind.document: {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'odt', //
    'ods', 'odp', 'csv', 'rtf', 'epub', 'md',
  },
  FileKind.archive: {
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'apk', 'apks', 'xapk', //
  },
};

FileKind kindOf(String path) {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  for (final entry in _kinds.entries) {
    if (entry.value.contains(ext)) return entry.key;
  }
  return FileKind.other;
}

String kindLabel(FileKind kind) => switch (kind) {
  FileKind.image => 'Images',
  FileKind.video => 'Videos',
  FileKind.audio => 'Audio',
  FileKind.document => 'Documents',
  FileKind.archive => 'Archives',
  FileKind.other => 'Other',
};
