import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:space_sweep/src/app.dart';
import 'package:space_sweep/src/platform/storage_bridge.dart';

import 'fake_bridge.dart';
import 'helpers.dart';

void main() {
  late TempTree tree;
  late FakeBridge bridge;
  setUp(() {
    tree = TempTree();
    bridge = FakeBridge(tree.root);
  });
  tearDown(() => tree.dispose());

  /// A Pixel-sized screen (412 x 915 dp).
  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  /// Lets real isolates and file I/O finish, then rebuilds.
  Future<void> settleIo(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('home shows storage use and the four tools', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(SpaceSweepApp(bridge: bridge));
    await tester.pumpAndSettle();
    expect(find.text('96 GB'), findsOneWidget);
    expect(find.text('of 128 GB used'), findsOneWidget);
    expect(find.text('32 GB free'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    // Used space split into apps, media and the rest (96 - 12 - 20 - 30).
    for (final part in [
      'Photos 12 GB',
      'Videos 20 GB',
      'Apps 30 GB',
      'Other 34 GB',
    ]) {
      expect(find.text(part), findsOneWidget);
    }
    for (final tool in [
      'Duplicate files',
      'App cache',
      'Junk files',
      'Large files',
    ]) {
      expect(find.text(tool), findsOneWidget);
    }
    expect(find.text('Allow file access'), findsNothing);
  });

  testWidgets('without usage access the ring is one segment with a prompt', (
    tester,
  ) async {
    bridge.usage = false;
    usePhone(tester);
    await tester.pumpWidget(SpaceSweepApp(bridge: bridge));
    await tester.pumpAndSettle();
    expect(find.text('Photos 12 GB'), findsNothing);
    await tester.tap(find.text('See what\'s using space'));
    await tester.pumpAndSettle();
    expect(bridge.usage, isTrue);
  });

  testWidgets('dark theme renders the home screen', (tester) async {
    usePhone(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(SpaceSweepApp(bridge: bridge));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('SpaceSweep'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).colorScheme.surface, const Color(0xFF0E0D13));
  });

  testWidgets('asks for file access when it is missing', (tester) async {
    bridge.allFiles = false;
    usePhone(tester);
    await tester.pumpWidget(SpaceSweepApp(bridge: bridge));
    await tester.pumpAndSettle();
    expect(find.text('Allow file access'), findsOneWidget);
    await tester.tap(find.text('Duplicate files'));
    await tester.pumpAndSettle();
    expect(find.text('Allow access to your files'), findsOneWidget);
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();
    expect(find.text('Find duplicate files'), findsOneWidget);
  });

  testWidgets('finds duplicates and deletes all but one copy', (tester) async {
    final old = DateTime(2021);
    tree.file('DCIM/Camera/song.mp3', bytesOf(50 * 1000, 1), modified: old);
    tree.file('Download/song (1).mp3', bytesOf(50 * 1000, 1));
    tree.file('Music/song.mp3', bytesOf(50 * 1000, 1));
    tree.file('Music/other.mp3', bytesOf(50 * 1000, 2));

    usePhone(tester);
    await tester.pumpWidget(SpaceSweepApp(bridge: bridge));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for duplicates'));
    await settleIo(
      tester,
      () => find.textContaining('can be freed').evaluate().isNotEmpty,
    );

    expect(find.text('100 KB can be freed'), findsOneWidget);
    expect(find.text('3 copies · 50 KB each'), findsOneWidget);
    // Oldest copy is kept by default.
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('2 files selected'), findsOneWidget);

    // Unticking the last remaining copy is refused.
    await tester.tap(find.text('DCIM/Camera/song.mp3'));
    await tester.pump();
    expect(find.text('Keep at least one copy of each file'), findsOneWidget);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 duplicates?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await settleIo(tester, () => bridge.scanned.isNotEmpty);

    expect(File(tree.path('DCIM/Camera/song.mp3')).existsSync(), isTrue);
    expect(File(tree.path('Download/song (1).mp3')).existsSync(), isFalse);
    expect(File(tree.path('Music/song.mp3')).existsSync(), isFalse);
    expect(File(tree.path('Music/other.mp3')).existsSync(), isTrue);
    expect(bridge.scanned, hasLength(2));
    expect(find.text('No duplicates found'), findsOneWidget);
  });

  testWidgets('deleting with a filter only touches the visible groups', (
    tester,
  ) async {
    tree.file('DCIM/clip.mp4', bytesOf(40 * 1000, 1), modified: DateTime(2020));
    tree.file('Download/clip.mp4', bytesOf(40 * 1000, 1));
    tree.file('DCIM/pic.jpg', bytesOf(30 * 1000, 2), modified: DateTime(2020));
    tree.file('Download/pic.jpg', bytesOf(30 * 1000, 2));

    usePhone(tester);
    await tester.pumpWidget(SpaceSweepApp(bridge: bridge));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for duplicates'));
    await settleIo(
      tester,
      () => find.textContaining('can be freed').evaluate().isNotEmpty,
    );
    expect(find.text('2 files selected'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Videos'));
    await tester.pumpAndSettle();
    expect(find.text('1 file selected'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await settleIo(tester, () => bridge.scanned.isNotEmpty);

    expect(File(tree.path('Download/clip.mp4')).existsSync(), isFalse);
    expect(File(tree.path('Download/pic.jpg')).existsSync(), isTrue);
    // The videos filter is gone with its last group; the image group remains.
    expect(find.text('1 file selected'), findsOneWidget);
    expect(find.text('pic.jpg'), findsOneWidget);
  });

  testWidgets('cache screen lists apps by cache and opens app settings', (
    tester,
  ) async {
    bridge.apps = const [
      AppCacheInfo(
        packageName: 'com.small',
        label: 'Small',
        cacheBytes: 2000000,
        dataBytes: 9000000,
        appBytes: 1,
        isSystem: false,
      ),
      AppCacheInfo(
        packageName: 'com.big',
        label: 'Big',
        cacheBytes: 900000000,
        dataBytes: 1200000000,
        appBytes: 1,
        isSystem: false,
      ),
      AppCacheInfo(
        packageName: 'android.sys',
        label: 'System thing',
        cacheBytes: 5000000,
        dataBytes: 5000000,
        appBytes: 1,
        isSystem: true,
      ),
    ];
    usePhone(tester);
    await tester.pumpWidget(SpaceSweepApp(bridge: bridge));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App cache'));
    await tester.pumpAndSettle();

    expect(find.text('902 MB of cache'), findsOneWidget);
    expect(find.text('System thing'), findsNothing);
    await tester.scrollUntilVisible(find.text('Small'), 200);
    final big = tester.getTopLeft(find.text('Big'));
    final small = tester.getTopLeft(find.text('Small'));
    expect(big.dy, lessThan(small.dy));

    await tester.tap(find.widgetWithText(TextButton, 'Clear').first);
    await tester.pumpAndSettle();
    expect(bridge.opened, ['com.big']);

    final trim = find.widgetWithText(FilledButton, 'Trim');
    await tester.ensureVisible(trim);
    await tester.pumpAndSettle();
    await tester.tap(trim);
    await tester.pumpAndSettle();
    expect(bridge.trimmed, 1);
    expect(find.text('Android cleared 5 MB of cached files'), findsOneWidget);
  });

  testWidgets('junk screen preselects safe junk only', (tester) async {
    final old = DateTime.now().subtract(const Duration(days: 5));
    tree.file('DCIM/.thumbnails/a.jpg', bytesOf(3000, 1));
    tree.file('Download/setup.apk', bytesOf(1000, 1));
    tree.file('Download/x.tmp', bytesOf(500, 1), modified: old);
    tree.file('Pictures/.trashed-1-x.jpg', bytesOf(800, 1));
    tree.file('Pictures/keep.jpg', bytesOf(800, 2));

    usePhone(tester);
    await tester.pumpWidget(SpaceSweepApp(bridge: bridge));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Junk files'));
    await settleIo(
      tester,
      () => find.textContaining('of junk').evaluate().isNotEmpty,
    );

    expect(find.text('5.3 KB of junk'), findsOneWidget);
    // Thumbnails + temp; the unknown APK and trashed media wait for the user.
    expect(find.text('2 items selected'), findsOneWidget);
    expect(find.text('Frees 3.5 KB'), findsOneWidget);
  });
}
