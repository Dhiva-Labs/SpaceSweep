import 'package:path/path.dart' as p;

/// Formats a byte count with decimal (SI) units, matching how Android's
/// Settings app reports storage.
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  var number = value.toStringAsFixed(value >= 100 ? 0 : 1);
  if (number.endsWith('.0')) number = number.substring(0, number.length - 2);
  return '$number ${units[unit]}';
}

String plural(int count, String one, [String? many]) =>
    '$count ${count == 1 ? one : (many ?? '${one}s')}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Shows [path] relative to the storage root, e.g. `DCIM/Camera`.
String displayPath(String path, String root) {
  if (path == root) return 'Internal storage';
  if (p.isWithin(root, path)) return p.relative(path, from: root);
  return path;
}
