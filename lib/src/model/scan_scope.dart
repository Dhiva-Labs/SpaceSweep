import 'package:path/path.dart' as p;

/// Where the file scans look.
class ScanScope {
  const ScanScope({required this.base, required this.roots});

  /// Paths are shown relative to this, and nothing outside it is ever
  /// deleted. Android: the shared storage root. Linux: the home folder.
  final String base;

  /// The folders actually walked: [base] itself on Android, the user's
  /// document and media folders on Linux.
  final List<String> roots;

  /// True when the whole of [base] is scanned.
  bool get coversBase => roots.length == 1 && p.equals(roots.single, base);

  /// "Documents, Downloads, Pictures" style list of the scanned folders.
  String get rootNames => roots.map(p.basename).join(', ');
}
