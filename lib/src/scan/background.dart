import 'dart:async';
import 'dart:isolate';

/// Thrown by [runInBackground] when its [CancelToken] fires.
class ScanCancelled implements Exception {
  const ScanCancelled();

  @override
  String toString() => 'Scan cancelled';
}

class CancelToken {
  void Function()? _onCancel;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// A scan body run on a background isolate. It reports progress through
/// `emit`. Build tasks with top-level functions so the closure captures only
/// plain values; it is copied to the other isolate.
typedef ScanTask<R, P> = R Function(void Function(P progress) emit);

/// Runs [task] on a new isolate so file I/O never blocks the UI.
///
/// Progress is throttled to [progressInterval]. Cancelling [cancel] kills the
/// isolate at once and the future fails with [ScanCancelled].
Future<R> runInBackground<R, P>(
  ScanTask<R, P> task, {
  void Function(P progress)? onProgress,
  CancelToken? cancel,
  Duration progressInterval = const Duration(milliseconds: 80),
}) async {
  if (cancel?.isCancelled ?? false) throw const ScanCancelled();
  final done = Completer<R>();
  final port = RawReceivePort();
  port.handler = (Object? message) {
    if (done.isCompleted) return;
    switch (message) {
      case _Progress(:final value):
        onProgress?.call(value as P);
      case _Result(:final value):
        done.complete(value as R);
      case _Failure(:final error, :final stack):
        done.completeError(error, StackTrace.fromString(stack));
      case List(): // onError: [error, stack] as strings
        done.completeError(
          StateError('${message.first}'),
          StackTrace.fromString('${message.last}'),
        );
      default: // onExit without a result: killed
        done.completeError(const ScanCancelled());
    }
  };
  try {
    final isolate = await Isolate.spawn(
      _main<R, P>,
      _Job<R, P>(task, port.sendPort, progressInterval),
      onExit: port.sendPort,
      onError: port.sendPort,
    );
    cancel?._onCancel = () => isolate.kill(priority: Isolate.immediate);
    if (cancel?.isCancelled ?? false) isolate.kill(priority: Isolate.immediate);
    return await done.future;
  } finally {
    cancel?._onCancel = null;
    port.close();
  }
}

class _Job<R, P> {
  const _Job(this.task, this.port, this.interval);

  final ScanTask<R, P> task;
  final SendPort port;
  final Duration interval;
}

class _Progress {
  const _Progress(this.value);
  final Object? value;
}

class _Result {
  const _Result(this.value);
  final Object? value;
}

class _Failure {
  const _Failure(this.error, this.stack);
  final Object error;
  final String stack;
}

void _main<R, P>(_Job<R, P> job) {
  final clock = Stopwatch()..start();
  var last = -job.interval.inMicroseconds;
  final R result;
  try {
    result = job.task((progress) {
      final now = clock.elapsedMicroseconds;
      if (now - last < job.interval.inMicroseconds) return;
      last = now;
      job.port.send(_Progress(progress));
    });
  } catch (e, st) {
    job.port.send(
      _Failure(e is Exception || e is Error ? StateError('$e') : e, '$st'),
    );
    return;
  }
  Isolate.exit(job.port, _Result(result));
}
