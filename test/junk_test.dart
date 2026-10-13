import 'package:flutter_test/flutter_test.dart';
import 'package:space_sweep/src/scan/junk.dart';

import 'helpers.dart';

void main() {
  late TempTree tree;
  setUp(() => tree = TempTree());
  tearDown(() => tree.dispose());

  final old = DateTime.now().subtract(const Duration(days: 3));

  Map<JunkKind, Set<String>> scan() {
    final out = <JunkKind, Set<String>>{};
    for (final item in scanJunk(tree.root)) {
      out
          .putIfAbsent(item.kind, () => {})
          .add(item.path.substring(tree.root.length + 1));
    }
    return out;
  }

  test('finds each kind of junk', () {
    tree.file('DCIM/.thumbnails/1.jpg', bytesOf(800, 1));
    tree.file('Download/app.apk', bytesOf(300, 2));
    tree.file('Download/bundle.XAPK', bytesOf(300, 2));
    tree.file('Download/movie.mp4.crdownload', bytesOf(100, 3), modified: old);
    tree.file('Documents/~\$report.docx', bytesOf(10, 3), modified: old);
    tree.file('Pictures/.trashed-1700000000-cat.jpg', bytesOf(100, 4));
    tree.dir('Projects/empty/nested');
    tree.file('Projects/keep/readme.txt', bytesOf(5, 5));

    final junk = scan();
    expect(junk[JunkKind.thumbnails], {'DCIM/.thumbnails'});
    expect(junk[JunkKind.apk], {'Download/app.apk', 'Download/bundle.XAPK'});
    expect(junk[JunkKind.temp], {
      'Download/movie.mp4.crdownload',
      'Documents/~\$report.docx',
    });
    expect(junk[JunkKind.trashed], {'Pictures/.trashed-1700000000-cat.jpg'});
    // Only the topmost empty folder is reported.
    expect(junk[JunkKind.emptyFolder], {'Projects/empty'});
  });

  test('thumbnail folder size is the total of its files', () {
    tree.file('DCIM/.thumbnails/a', bytesOf(1000, 1));
    tree.file('DCIM/.thumbnails/sub/b', bytesOf(500, 1));
    final item = scanJunk(tree.root).single;
    expect(item.isDirectory, isTrue);
    expect(item.size, 1500);
  });

  test('recent temp files are left alone (could be an active download)', () {
    tree.file('Download/now.part', bytesOf(100, 1));
    tree.file('Download/old.part', bytesOf(100, 1), modified: old);
    expect(scan()[JunkKind.temp], {'Download/old.part'});
  });

  test('standard, hidden and Android folders are never reported as empty', () {
    tree.dir('Movies');
    tree.dir('Music/Old album');
    tree.dir('.config/empty');
    tree.dir('Android/media/com.app');
    tree.dir('Stuff/.hiddenempty');
    tree.file('Stuff/notes.txt', bytesOf(5, 1));
    final empties = scan()[JunkKind.emptyFolder] ?? {};
    // Music itself stays; its empty child is reported instead.
    expect(empties, {'Music/Old album'});
  });

  test('folders that system tools fill on their own are never junk', () {
    tree.dir('Pictures/Screenshots');
    tree.dir('Videos/Screencasts');
    tree.dir('DCIM/Camera');
    tree.dir('Pictures/Old trip');
    // Videos holds nothing but a kept folder, so it is not empty either.
    tree.dir('Stuff/.config');
    expect(scan()[JunkKind.emptyFolder], {'Pictures/Old trip'});
  });

  test('folders holding only a .nomedia file are not empty', () {
    tree.file('Pictures/Private/.nomedia', []);
    expect(scan()[JunkKind.emptyFolder], isNull);
  });

  test('installers inside private app folders are ignored', () {
    tree.file('Android/data/com.store/files/update.apk', bytesOf(100, 1));
    tree.file('Android/media/org.telegram/Telegram/app.apk', bytesOf(100, 1));
    expect(scan()[JunkKind.apk], {
      'Android/media/org.telegram/Telegram/app.apk',
    });
  });
}
