import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_sweep/src/linux/linux_cache.dart';
import 'package:space_sweep/src/platform/linux_bridge.dart';
import 'package:space_sweep/src/theme.dart';
import 'package:space_sweep/src/ui/linux_cache_screen.dart';

import 'helpers.dart';

void main() {
  late TempTree tree;
  setUp(() => tree = TempTree());
  tearDown(() => tree.dispose());

  group('userDirs', () {
    test('reads user-dirs.dirs and drops disabled or outside folders', () {
      const config = '''
# written by xdg-user-dirs-update
XDG_DESKTOP_DIR="\$HOME/Bureau"
XDG_DOWNLOAD_DIR="\$HOME/Téléchargements"
XDG_TEMPLATES_DIR="\$HOME/Modèles"
XDG_DOCUMENTS_DIR="\$HOME"
XDG_MUSIC_DIR="/mnt/music"
XDG_PICTURES_DIR="\$HOME/Images"
''';
      expect(userDirs('/home/ana', config), [
        '/home/ana/Bureau',
        '/home/ana/Téléchargements',
        '/home/ana/Images',
        '/home/ana/Videos',
      ]);
    });

    test('falls back to the English defaults', () {
      expect(userDirs('/home/ana/', null), [
        '/home/ana/Desktop',
        '/home/ana/Documents',
        '/home/ana/Downloads',
        '/home/ana/Music',
        '/home/ana/Pictures',
        '/home/ana/Videos',
      ]);
    });
  });

  group('LinuxStorageBridge', () {
    test('uses the real home and ~/.cache inside a snap', () {
      final bridge = LinuxStorageBridge(
        environment: {
          'SNAP': '/snap/spacesweep/1',
          'HOME': '/home/ana/snap/spacesweep/1',
          'SNAP_REAL_HOME': '/home/ana',
          'XDG_CACHE_HOME': '/home/ana/snap/spacesweep/1/.cache',
        },
      );
      expect(bridge.home, '/home/ana');
      expect(bridge.cacheDir, '/home/ana/.cache');
      expect(bridge.trashDir, '/home/ana/.local/share/Trash');
    });

    test('honours XDG variables outside a snap', () {
      final bridge = LinuxStorageBridge(
        environment: {
          'HOME': '/home/ana',
          'XDG_CACHE_HOME': '/data/cache',
          'XDG_DATA_HOME': '/data/share',
        },
      );
      expect(bridge.cacheDir, '/data/cache');
      expect(bridge.trashDir, '/data/share/Trash');
    });

    test('scans only the user folders that exist', () async {
      tree.dir('Documents');
      tree.dir('Pictures');
      tree.dir('code/project');
      final bridge = LinuxStorageBridge(environment: {'HOME': tree.root});
      expect(await bridge.scanRoots(), [
        tree.path('Documents'),
        tree.path('Pictures'),
      ]);
    });

    test('reports real disk size via statvfs', () async {
      final info = await LinuxStorageBridge(
        environment: {'HOME': tree.root},
      ).storageInfo();
      expect(info.totalBytes, greaterThan(0));
      expect(info.freeBytes, inInclusiveRange(0, info.totalBytes));
    });
  });

  group('caches and trash', () {
    String cache(String rel) => tree.path('.cache/$rel');

    test('measures cache folders largest first and the trash', () {
      tree.file('.cache/mozilla/a/b.bin', bytesOf(5000, 1));
      tree.file('.cache/pip/x.whl', bytesOf(1200, 1));
      tree.file('.cache/motd.legal-displayed', []);
      tree.dir('.cache/empty');
      tree.file('.local/share/Trash/files/old.pdf', bytesOf(700, 1));
      tree.file('.local/share/Trash/files/dir/x', bytesOf(300, 1));
      tree.file('.local/share/Trash/info/old.pdf.trashinfo', bytesOf(50, 1));
      final scan = scanLinuxCaches(
        tree.path('.cache'),
        tree.path('.local/share/Trash'),
      );
      expect(scan.folders.map((f) => (f.label, f.bytes)), [
        ('Firefox', 5000),
        ('pip (Python packages)', 1200),
      ]);
      expect(scan.trashItems, 2);
      expect(scan.trashBytes, 1000);
    });

    test('clearing a folder empties it, keeps it, and never follows links', () {
      final outside = tree.file('important/keep.txt', bytesOf(100, 1));
      tree.file('.cache/app/data.bin', bytesOf(4000, 1));
      tree.file('.cache/app/sub/more.bin', bytesOf(1000, 1));
      Link(cache('app/link-to-important')).createSync(tree.path('important'));
      final freed = clearCacheFolder(tree.path('.cache'), cache('app'));
      expect(freed, 5000);
      expect(Directory(cache('app')).existsSync(), isTrue);
      expect(Directory(cache('app')).listSync(), isEmpty);
      expect(outside.existsSync(), isTrue);
    });

    test('refuses anything that is not a folder directly in the cache dir', () {
      tree.file('.cache/app/sub/x', bytesOf(10, 1));
      tree.file('Documents/x', bytesOf(10, 1));
      Link(cache('sneaky')).createSync(tree.path('Documents'));
      for (final bad in [
        cache('app/sub'),
        tree.path('Documents'),
        cache('sneaky'),
        cache('../Documents'),
      ]) {
        expect(
          () => clearCacheFolder(tree.path('.cache'), bad),
          throwsArgumentError,
          reason: bad,
        );
      }
      expect(File(tree.path('Documents/x')).existsSync(), isTrue);
      expect(File(cache('app/sub/x')).existsSync(), isTrue);
    });

    test(
      'emptying the trash removes files and their info, keeps the folders',
      () {
        tree.file('.local/share/Trash/files/old.pdf', bytesOf(700, 1));
        tree.file('.local/share/Trash/info/old.pdf.trashinfo', bytesOf(50, 1));
        final trash = tree.path('.local/share/Trash');
        expect(emptyTrash(trash), 750);
        expect(Directory('$trash/files').listSync(), isEmpty);
        expect(Directory('$trash/info').listSync(), isEmpty);
        expect(() => emptyTrash(tree.path('Documents')), throwsArgumentError);
      },
    );
  });

  testWidgets('cache screen lists caches and clears one', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    tree.file('.cache/mozilla/a.bin', bytesOf(6000, 1));
    tree.file('.cache/thumbnails/normal/t.png', bytesOf(2000, 1));
    tree.file('.local/share/Trash/files/x', bytesOf(1000, 1));

    Future<void> settle(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: sweepTheme(Brightness.light),
        home: LinuxCacheScreen(
          cacheDir: tree.path('.cache'),
          trashDir: tree.path('.local/share/Trash'),
        ),
      ),
    );
    await settle(() => find.text('9 KB to reclaim').evaluate().isNotEmpty);
    expect(find.text('9 KB to reclaim'), findsOneWidget);
    expect(find.text('Firefox'), findsOneWidget);
    expect(find.text('Thumbnails'), findsOneWidget);
    expect(find.text('1 item · 1 KB'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Clear').first);
    await tester.pumpAndSettle();
    expect(find.text('Clear Firefox?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    // Snackbar first, then the re-measured totals (2 KB thumbnails + 1 KB trash).
    await settle(() => find.text('3 KB to reclaim').evaluate().isNotEmpty);
    expect(find.text('Freed 6 KB from Firefox'), findsOneWidget);
    expect(find.text('Firefox'), findsNothing);
    expect(File(tree.path('.cache/mozilla/a.bin')).existsSync(), isFalse);
    expect(File(tree.path('.local/share/Trash/files/x')).existsSync(), isTrue);
  });
}
