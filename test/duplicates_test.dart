import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:space_sweep/src/scan/duplicates.dart';
import 'package:space_sweep/src/scan/walker.dart';

import 'helpers.dart';

void main() {
  late TempTree tree;
  setUp(() => tree = TempTree());
  tearDown(() => tree.dispose());

  List<DuplicateGroup> scan({int minSize = 1, bool hidden = false}) =>
      scanDuplicates(
        tree.root,
        DuplicateScanOptions(minSize: minSize, includeHidden: hidden),
        (_) {},
      );

  Set<String> names(DuplicateGroup g) => {
    for (final f in g.files) f.path.substring(tree.root.length + 1),
  };

  test('groups identical small files and ignores unique ones', () {
    tree.file('a/one.txt', bytesOf(500, 1));
    tree.file('b/copy of one.txt', bytesOf(500, 1));
    tree.file('c/other.txt', bytesOf(500, 2)); // same size, different content
    final groups = scan();
    expect(groups, hasLength(1));
    expect(names(groups.single), {'a/one.txt', 'b/copy of one.txt'});
    expect(groups.single.reclaimable, 500);
  });

  test(
    'large files that share samples but differ in the middle are not duplicates',
    () {
      final size = 400 * 1024;
      final base = bytesOf(size, 7);
      final tweaked = [...base];
      // Outside the start/middle/end samples, so only the full hash can tell.
      tweaked[100 * 1024] ^= 0xff;
      tree.file('x/big.bin', base);
      tree.file('y/big.bin', base);
      tree.file('z/almost.bin', tweaked);
      final groups = scan();
      expect(groups, hasLength(1));
      expect(names(groups.single), {'x/big.bin', 'y/big.bin'});
      expect(groups.single.size, size);
    },
  );

  test('three copies count as two reclaimable', () {
    for (final dir in ['p', 'q', 'r']) {
      tree.file('$dir/photo.jpg', bytesOf(100 * 1024, 3));
    }
    final groups = scan();
    expect(groups.single.files, hasLength(3));
    expect(groups.single.reclaimable, 2 * 100 * 1024);
  });

  test('empty files, files below minSize and hidden files are skipped', () {
    tree.file('e1', []);
    tree.file('e2', []);
    tree.file('small1', bytesOf(10, 1));
    tree.file('small2', bytesOf(10, 1));
    tree.file('.hidden/a', bytesOf(5000, 4));
    tree.file('.hidden/b', bytesOf(5000, 4));
    expect(scan(minSize: 100), isEmpty);
    expect(scan(minSize: 100, hidden: true), hasLength(1));
  });

  test('symlinks are not followed or reported', () {
    tree.file('real/a.bin', bytesOf(4096, 9));
    Link(tree.path('link.bin')).createSync(tree.path('real/a.bin'));
    Link(tree.path('linkdir')).createSync(tree.path('real'));
    expect(scan(), isEmpty);
  });

  test('other apps\' private folders are never scanned', () {
    tree.file('Android/data/com.app/files/a.bin', bytesOf(4096, 5));
    tree.file('Android/obb/com.app/b.bin', bytesOf(4096, 5));
    tree.file('Android/media/com.app/c.bin', bytesOf(4096, 6));
    tree.file('Download/c.bin', bytesOf(4096, 6));
    final groups = scan();
    expect(groups, hasLength(1));
    expect(names(groups.single), {
      'Android/media/com.app/c.bin',
      'Download/c.bin',
    });
    expect(isPrivatePath(tree.root, tree.path('Android/data/x')), isTrue);
    expect(isPrivatePath(tree.root, tree.path('Android/database')), isFalse);
  });

  test('groups are sorted by reclaimable space', () {
    tree.file('a1', bytesOf(2000, 1));
    tree.file('a2', bytesOf(2000, 1));
    tree.file('b1', bytesOf(9000, 2));
    tree.file('b2', bytesOf(9000, 2));
    final groups = scan();
    expect(groups.map((g) => g.size), [9000, 2000]);
  });

  group('autoSelect', () {
    test('keeps exactly one copy per group by the chosen rule', () {
      final old = DateTime(2020);
      final mid = DateTime(2022);
      final recent = DateTime(2024);
      tree.file('DCIM/Camera/IMG_1.jpg', bytesOf(3000, 1), modified: old);
      tree.file('WhatsApp/Media/IMG-1.jpg', bytesOf(3000, 1), modified: recent);
      tree.file('Download/x/IMG_1.jpg', bytesOf(3000, 1), modified: mid);
      final groups = scan();
      final group = groups.single;

      String keptBy(KeepRule rule) {
        final selected = autoSelect(groups, rule);
        final kept = group.files
            .where((f) => !selected.contains(f.path))
            .toList();
        expect(kept, hasLength(1));
        return kept.single.path.substring(tree.root.length + 1);
      }

      expect(keptBy(KeepRule.oldest), 'DCIM/Camera/IMG_1.jpg');
      expect(keptBy(KeepRule.newest), 'WhatsApp/Media/IMG-1.jpg');
      expect(keptBy(KeepRule.shortestPath), 'Download/x/IMG_1.jpg');
    });
  });
}
