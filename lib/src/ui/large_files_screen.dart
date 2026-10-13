import 'package:flutter/material.dart';

import '../clean/cleaner.dart';
import '../model/file_entry.dart';
import '../model/scan_scope.dart';
import '../platform/storage_bridge.dart';
import '../scan/background.dart';
import '../scan/large_files.dart';
import '../util/file_kind.dart';
import '../util/format.dart';
import 'widgets.dart';

class LargeFilesScreen extends StatelessWidget {
  const LargeFilesScreen({
    super.key,
    required this.bridge,
    required this.scope,
  });

  final StorageBridge bridge;
  final ScanScope scope;

  @override
  Widget build(BuildContext context) {
    return AllFilesAccessGate(
      bridge: bridge,
      title: 'Large files',
      child: _LargeFilesBody(bridge: bridge, scope: scope),
    );
  }
}

const _thresholds = [
  10 * 1000 * 1000,
  50 * 1000 * 1000,
  100 * 1000 * 1000,
  500 * 1000 * 1000,
];

class _LargeFilesBody extends StatefulWidget {
  const _LargeFilesBody({required this.bridge, required this.scope});

  final StorageBridge bridge;
  final ScanScope scope;

  @override
  State<_LargeFilesBody> createState() => _LargeFilesBodyState();
}

class _LargeFilesBodyState extends State<_LargeFilesBody> {
  final _cancel = CancelToken();
  List<FileEntry>? _files;
  var _filesSeen = 0;
  var _threshold = _thresholds[1];
  FileKind? _filter;
  final _selected = <String>{};
  var _deleting = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  /// Scans once at the smallest threshold; changing it just filters.
  Future<void> _scan() async {
    setState(() {
      _files = null;
      _filesSeen = 0;
      _selected.clear();
    });
    try {
      final files = await runInBackground<List<FileEntry>, int>(
        largeFileScanTask(widget.scope.roots, _thresholds.first),
        onProgress: (n) {
          if (mounted) setState(() => _filesSeen = n);
        },
        cancel: _cancel,
      );
      if (mounted) setState(() => _files = files);
    } on ScanCancelled {
      // Screen closed.
    }
  }

  List<FileEntry> get _visible => [
    for (final f in _files ?? const <FileEntry>[])
      if (f.size >= _threshold &&
          (_filter == null || kindOf(f.path) == _filter))
        f,
  ];

  /// Only what is on screen can be deleted; filtered-out picks stay
  /// remembered but untouched.
  Iterable<FileEntry> get _selectedFiles =>
      _visible.where((f) => _selected.contains(f.path));

  Future<void> _delete() async {
    final files = _selectedFiles.toList();
    final bytes = files.fold<int>(0, (sum, f) => sum + f.size);
    final ok = await confirmDelete(
      context,
      count: files.length,
      bytes: bytes,
      noun: 'file',
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    final report = await Cleaner(widget.scope.base).deleteFiles(files);
    if (!mounted) return;
    final gone = report.deleted.toSet();
    setState(() {
      _deleting = false;
      _files = _files!.where((f) => !gone.contains(f.path)).toList();
      _selected.removeAll(gone);
    });
    await finishDelete(context, widget.bridge, report);
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Large files'),
        actions: [
          if (files != null)
            IconButton(
              tooltip: 'Scan again',
              onPressed: _scan,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: files == null
          ? ProgressPanel(
              title: 'Measuring your files…',
              detail: '${plural(_filesSeen, 'file')} checked',
            )
          : _results(),
      bottomNavigationBar: files == null || files.isEmpty
          ? null
          : SelectionBar(
              count: _selectedFiles.length,
              bytes: _selectedFiles.fold(0, (sum, f) => sum + f.size),
              busy: _deleting,
              noun: 'file',
              onDelete: _delete,
            ),
    );
  }

  Widget _results() {
    final text = Theme.of(context).textTheme;
    final visible = _visible;
    final total = visible.fold<int>(0, (sum, f) => sum + f.size);
    final kinds = {for (final f in _files!) kindOf(f.path)}.toList()
      ..sort((a, b) => a.index - b.index);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: visible.length + 2 + (visible.isEmpty ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SummaryCard(
                headline: formatBytes(total),
                detail:
                    '${plural(visible.length, 'file')} over ${formatBytes(_threshold)}',
                icon: Icons.data_usage,
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: [
                  for (final t in _thresholds)
                    ButtonSegment(value: t, label: Text(formatBytes(t))),
                ],
                selected: {_threshold},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _threshold = v.first),
              ),
            ],
          );
        }
        if (i == 1) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final kind in kinds) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: Icon(kindIcon(kind), size: 18),
                    label: Text(kindLabel(kind)),
                    selected: _filter == kind,
                    onSelected: (_) => setState(() => _filter = kind),
                  ),
                ],
              ],
            ),
          );
        }
        if (visible.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No files this large.',
              style: text.bodyLarge,
              textAlign: TextAlign.center,
            ),
          );
        }
        final file = visible[i - 2];
        final checked = _selected.contains(file.path);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => setState(
              () => checked
                  ? _selected.remove(file.path)
                  : _selected.add(file.path),
            ),
            leading: FileThumb(file.path),
            title: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${formatBytes(file.size)} · ${displayPath(file.parent, widget.scope.base)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Checkbox(
              value: checked,
              onChanged: (_) => setState(
                () => checked
                    ? _selected.remove(file.path)
                    : _selected.add(file.path),
              ),
            ),
          ),
        );
      },
    );
  }
}
