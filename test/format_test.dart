import 'package:flutter_test/flutter_test.dart';
import 'package:space_sweep/src/util/format.dart';

void main() {
  test('formatBytes uses SI units and trims a trailing .0', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(999), '999 B');
    expect(formatBytes(1000), '1 KB');
    expect(formatBytes(1500), '1.5 KB');
    expect(formatBytes(50 * 1000 * 1000), '50 MB');
    expect(formatBytes(123456789), '123 MB');
    expect(formatBytes(1600 * 1000 * 1000), '1.6 GB');
    expect(formatBytes(128 * 1000 * 1000 * 1000), '128 GB');
    expect(formatBytes(2 * 1000 * 1000 * 1000 * 1000 * 1000), '2000 TB');
  });

  test('displayPath is relative to the storage root', () {
    const root = '/storage/emulated/0';
    expect(displayPath('$root/DCIM/Camera', root), 'DCIM/Camera');
    expect(displayPath(root, root), 'Internal storage');
    expect(displayPath('/elsewhere/x', root), '/elsewhere/x');
  });

  test('plural', () {
    expect(plural(1, 'file'), '1 file');
    expect(plural(2, 'file'), '2 files');
    expect(plural(2, 'copy', 'copies'), '2 copies');
  });
}
