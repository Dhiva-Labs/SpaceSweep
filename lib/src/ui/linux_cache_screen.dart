import 'package:flutter/material.dart';

import '../linux/linux_cache.dart';
import '../scan/background.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets.dart';

/// Linux counterpart of the app cache screen: per-app folders in
/// `~/.cache` and the desktop trash.
class LinuxCacheScreen extends StatefulWidget {
  const LinuxCacheScreen({
    super.key,
    required this.cacheDir,
    required this.trashDir,
  });

  final String cacheDir;
  final String trashDir;

  @override
  State<LinuxCacheScreen> createState() => _LinuxCacheScreenState();
}

class _LinuxCacheScreenState extends State<LinuxCacheScreen> {
  final _cancel = CancelToken();
  LinuxCacheScan? _scan;
  (int, int) _progress = (0, 0);
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _measure() async {
    setState(() {
      _scan = null;
      _progress = (0, 0);
    });
    try {
      final scan = await runInBackground<LinuxCacheScan, (int, int)>(
        linuxCacheScanTask(widget.cacheDir, widget.trashDir),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancel: _cancel,
      );
      if (mounted) setState(() => _scan = scan);
    } on ScanCancelled {
      // Screen closed.
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a delete off the UI thread, then re-measures.
  Future<void> _run(
    ScanTask<int, void> task,
    String Function(int freed) message,
  ) async {
    setState(() => _busy = true);
    try {
      final freed = await runInBackground<int, void>(task);
      if (mounted) _snack(message(freed));
    } catch (e) {
      if (mounted) _snack('Couldn\'t clear: $e');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _measure();
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _clearFolder(CacheFolder folder) async {
    final ok = await _confirm(
      'Clear ${folder.label}?',
      'Deletes ${formatBytes(folder.bytes)} of cached files. The app '
          'rebuilds what it needs; close it first for best results.',
      'Clear',
    );
    if (!ok) return;
    await _run(
      clearCacheFolderTask(widget.cacheDir, folder.path),
      (freed) => 'Freed ${formatBytes(freed)} from ${folder.label}',
    );
  }

  Future<void> _clearAll(LinuxCacheScan scan) async {
    final ok = await _confirm(
      'Clear all app caches?',
      'Deletes ${formatBytes(scan.cacheBytes)} across '
          '${plural(scan.folders.length, 'folder')}. Apps rebuild what they '
          'need, so the first launch of each may be a little slower.',
      'Clear all',
    );
    if (!ok) return;
    await _run(
      clearAllCachesTask(widget.cacheDir, [
        for (final f in scan.folders) f.path,
      ]),
      (freed) => 'Freed ${formatBytes(freed)} of cache',
    );
  }

  Future<void> _emptyTrash(LinuxCacheScan scan) async {
    final ok = await _confirm(
      'Empty the trash?',
      '${plural(scan.trashItems, 'item')} (${formatBytes(scan.trashBytes)}) '
          'will be deleted for good. This can\'t be undone.',
      'Empty trash',
    );
    if (!ok) return;
    await _run(
      emptyTrashTask(widget.trashDir),
      (freed) => 'Trash emptied · freed ${formatBytes(freed)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cache & trash'),
        actions: [
          if (scan != null)
            IconButton(
              tooltip: 'Measure again',
              onPressed: _busy ? null : _measure,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: scan == null
          ? ProgressPanel(
              title: 'Measuring caches…',
              detail: _progress.$2 == 0
                  ? ''
                  : '${_progress.$1} of ${_progress.$2} folders',
              fraction: _progress.$2 == 0 ? null : _progress.$1 / _progress.$2,
            )
          : _results(scan),
    );
  }

  Widget _results(LinuxCacheScan scan) {
    final text = Theme.of(context).textTheme;
    final colors = SweepColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SummaryCard(
          headline:
              '${formatBytes(scan.cacheBytes + scan.trashBytes)} to reclaim',
          detail:
              '${formatBytes(scan.cacheBytes)} of app cache · '
              '${formatBytes(scan.trashBytes)} in the trash',
          icon: Icons.cached,
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: ToneIcon(
                  Icons.delete_outline,
                  size: 42,
                  color: colors.pink,
                ),
                title: const Text('Trash'),
                subtitle: Text(
                  scan.trashItems == 0
                      ? 'Already empty'
                      : '${plural(scan.trashItems, 'item')} · ${formatBytes(scan.trashBytes)}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: _busy || scan.trashItems == 0
                      ? null
                      : () => _emptyTrash(scan),
                  child: const Text('Empty'),
                ),
              ),
              ListTile(
                leading: ToneIcon(
                  Icons.cleaning_services_outlined,
                  size: 42,
                  color: colors.lilac,
                ),
                title: const Text('All app caches'),
                subtitle: Text(
                  '${formatBytes(scan.cacheBytes)} in '
                  '${plural(scan.folders.length, 'folder')}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: _busy || scan.folders.isEmpty
                      ? null
                      : () => _clearAll(scan),
                  child: const Text('Clear all'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Caches by app', style: text.titleMedium),
        const SizedBox(height: 8),
        for (final folder in scan.folders)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: ToneIcon(
                Icons.folder_outlined,
                size: 40,
                color: colors.peach,
              ),
              title: Text(
                folder.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${formatBytes(folder.bytes)} · ~/.cache/${folder.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: TextButton(
                onPressed: _busy ? null : () => _clearFolder(folder),
                child: const Text('Clear'),
              ),
            ),
          ),
        if (scan.folders.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No app caches to clear.',
              textAlign: TextAlign.center,
              style: text.bodyLarge,
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Caches hold files apps can download or rebuild, so clearing them is '
          'safe. Close an app before clearing its cache for best results.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}
