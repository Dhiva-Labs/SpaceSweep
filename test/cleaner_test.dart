import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:space_sweep/src/clean/cleaner.dart';
import 'package:space_sweep/src/model/file_entry.dart';
import 'package:space_sweep/src/scan/duplicates.dart';
import 'package:space_sweep/src/scan/junk.dart';

import 'helpers.dart';

void main() {
  late TempTree tree;
  setUp(() => tree = TempTree());
  tearDown(() => tree.dispose());

  List<DuplicateGroup> scan() => scanDuplicates(
    [tree.root],
    const DuplicateScanOptions(minSize: 1),
    (_) {},
  );

  test('deletes the selected copies and keeps the rest', () async {
    tree.file('a/x.jpg', bytesOf(4000, 1));
    tree.file('b/x.jpg', bytesOf(4000, 1));
    tree.file('c/x.jpg', bytesOf(4000, 1));
    final groups = scan();
    final selected = autoSelect(groups, KeepRule.shortestPath);
    final report = await Cleaner(tree.root).deleteDuplicates(groups, selected);
    expect(report.deleted, hasLength(2));
    expect(report.freedBytes, 8000);
    expect(report.skipped, isEmpty);
    expect(File(tree.path('a/x.jpg')).existsSync(), isTrue);
    expect(File(tree.path('b/x.jpg')).existsSync(), isFalse);
  });

  test('refuses to delete every copy of a file', () async {
    tree.file('a/x.bin', bytesOf(4000, 1));
    tree.file('b/x.bin', bytesOf(4000, 1));
    final groups = scan();
    final all = {for (final f in groups.single.files) f.path};
    final report = await Cleaner(tree.root).deleteDuplicates(groups, all);
    expect(report.deleted, isEmpty);
    expect(report.skipped, hasLength(2));
    expect(File(tree.path('a/x.bin')).existsSync(), isTrue);
    expect(File(tree.path('b/x.bin')).existsSync(), isTrue);
  });

  test('keeps duplicates when the kept copy vanished after the scan', () async {
    tree.file('a/x.bin', bytesOf(4000, 1));
    tree.file('b/x.bin', bytesOf(4000, 1));
    final groups = scan();
    final keeper = pickKeeper(groups.single, KeepRule.shortestPath);
    final selected = autoSelect(groups, KeepRule.shortestPath);
    File(keeper.path).deleteSync();
    final report = await Cleaner(tree.root).deleteDuplicates(groups, selected);
    expect(report.deleted, isEmpty);
    expect(report.skipped.single.reason, contains('kept'));
    expect(File(selected.single).existsSync(), isTrue);
  });

  test(
    'keeps duplicates when the kept copy was edited after the scan',
    () async {
      tree.file('a/x.bin', bytesOf(4000, 1));
      tree.file('b/x.bin', bytesOf(4000, 1));
      final groups = scan();
      final keeper = pickKeeper(groups.single, KeepRule.shortestPath);
      final selected = autoSelect(groups, KeepRule.shortestPath);
      File(keeper.path).writeAsBytesSync(bytesOf(4001, 2));
      final report = await Cleaner(
        tree.root,
      ).deleteDuplicates(groups, selected);
      expect(report.deleted, isEmpty);
      expect(File(selected.single).existsSync(), isTrue);
    },
  );

  test('skips a selected file that changed since the scan', () async {
    final f = tree.file('big.mov', bytesOf(5000, 1));
    final entry = FileEntry(
      f.path,
      5000,
      f.statSync().modified.millisecondsSinceEpoch,
    );
    f.setLastModifiedSync(DateTime(2001));
    final report = await Cleaner(tree.root).deleteFiles([entry]);
    expect(report.deleted, isEmpty);
    expect(f.existsSync(), isTrue);
  });

  test(
    'never touches paths outside the root or in private app folders',
    () async {
      final outside = TempTree();
      addTearDown(outside.dispose);
      final stranger = outside.file('keep.bin', bytesOf(100, 1));
      final private = tree.file('Android/data/com.app/x.bin', bytesOf(100, 1));
      FileEntry entry(File f) =>
          FileEntry(f.path, 100, f.statSync().modified.millisecondsSinceEpoch);
      final report = await Cleaner(
        tree.root,
      ).deleteFiles([entry(stranger), entry(private)]);
      expect(report.deleted, isEmpty);
      expect(stranger.existsSync(), isTrue);
      expect(private.existsSync(), isTrue);
    },
  );

  test(
    'deletes junk folders, re-checking that empty folders are still empty',
    () async {
      tree.file('DCIM/.thumbnails/1.jpg', bytesOf(800, 1));
      tree.dir('Old/empty/inner');
      tree.dir('Later/empty');
      final items = scanJunk(tree.root);
      // A file appears in one "empty" folder after the scan.
      tree.file('Later/empty/new.txt', bytesOf(5, 1));
      final report = await Cleaner(tree.root).deleteJunk(items);
      expect(Directory(tree.path('DCIM/.thumbnails')).existsSync(), isFalse);
      expect(Directory(tree.path('DCIM')).existsSync(), isTrue);
      expect(Directory(tree.path('Old/empty')).existsSync(), isFalse);
      expect(File(tree.path('Later/empty/new.txt')).existsSync(), isTrue);
      expect(report.freedBytes, 800);
      expect(report.skipped.single.reason, 'No longer empty');
    },
  );
}
