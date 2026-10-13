import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:space_sweep/src/scan/background.dart';
import 'package:space_sweep/src/scan/duplicates.dart';

import 'helpers.dart';

ScanTask<int, int> _countTo(int n) => (emit) {
  for (var i = 1; i <= n; i++) {
    emit(i);
  }
  return n;
};

ScanTask<int, int> _forever() => (emit) {
  var i = 0;
  while (true) {
    emit(i++);
    sleep(const Duration(milliseconds: 1));
  }
};

ScanTask<int, int> _fails() =>
    (_) => throw const FileSystemException('boom');

void main() {
  test('returns the task result and forwards progress', () async {
    final seen = <int>[];
    final result = await runInBackground<int, int>(
      _countTo(5),
      onProgress: seen.add,
      progressInterval: Duration.zero,
    );
    expect(result, 5);
    expect(seen, isNotEmpty);
  });

  test('cancel kills the isolate', () async {
    final cancel = CancelToken();
    final future = runInBackground<int, int>(_forever(), cancel: cancel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cancel.cancel();
    await expectLater(future, throwsA(isA<ScanCancelled>()));
  });

  test('task errors surface to the caller', () async {
    await expectLater(
      runInBackground<int, int>(_fails()),
      throwsA(isA<StateError>()),
    );
  });

  test('duplicate scan runs in the background', () async {
    final tree = TempTree();
    addTearDown(tree.dispose);
    tree.file('a', bytesOf(3000, 1));
    tree.file('b', bytesOf(3000, 1));
    final groups =
        await runInBackground<List<DuplicateGroup>, DuplicateProgress>(
          duplicateScanTask([
            tree.root,
          ], const DuplicateScanOptions(minSize: 1)),
        );
    expect(groups.single.files, hasLength(2));
  });
}
