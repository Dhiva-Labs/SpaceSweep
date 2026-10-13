import 'package:flutter/material.dart';

import '../clean/cleaner.dart';
import '../model/file_entry.dart';
import '../model/scan_scope.dart';
import '../platform/storage_bridge.dart';
import '../scan/background.dart';
import '../scan/duplicates.dart';
import '../util/file_kind.dart';
import '../util/format.dart';
import 'widgets.dart';

class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({
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
      title: 'Duplicate files',
      child: _DuplicatesBody(bridge: bridge, scope: scope),
    );
  }
}

enum _Phase { intro, scanning, results }

const _minSizes = [1000, 10 * 1000, 100 * 1000, 1000 * 1000];

class _DuplicatesBody extends StatefulWidget {
  const _DuplicatesBody({required this.bridge, required this.scope});

  final StorageBridge bridge;
  final ScanScope scope;

  @override
  State<_DuplicatesBody> createState() => _DuplicatesBodyState();
}

class _DuplicatesBodyState extends State<_DuplicatesBody> {
  var _phase = _Phase.intro;
  DuplicateProgress? _progress;
  CancelToken? _cancel;
  var _groups = <DuplicateGroup>[];
  var _selected = <String>{};
  FileKind? _filter;
  var _minSize = 10 * 1000;
  var _includeHidden = false;
  var _rule = KeepRule.oldest;
  var _deleting = false;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    final cancel = _cancel = CancelToken();
    setState(() {
      _phase = _Phase.scanning;
      _progress = null;
    });
    try {
      final groups =
          await runInBackground<List<DuplicateGroup>, DuplicateProgress>(
            duplicateScanTask(
              widget.scope.roots,
              DuplicateScanOptions(
                minSize: _minSize,
                includeHidden: _includeHidden,
              ),
            ),
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
            cancel: cancel,
          );
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _selected = autoSelect(groups, _rule);
        _filter = null;
        _phase = _Phase.results;
      });
    } on ScanCancelled {
      if (mounted) setState(() => _phase = _Phase.intro);
    }
  }

  List<DuplicateGroup> get _visible => _filter == null
      ? _groups
      : _groups.where((g) => g.kind == _filter).toList();

  /// Only groups on screen can be deleted from; picks in filtered-out
  /// groups stay remembered but untouched.
  Iterable<FileEntry> get _selectedVisible sync* {
    for (final g in _visible) {
      for (final f in g.files) {
        if (_selected.contains(f.path)) yield f;
      }
    }
  }

  int get _selectedBytes => _selectedVisible.fold(0, (sum, f) => sum + f.size);

  void _toggle(DuplicateGroup group, FileEntry file) {
    setState(() {
      if (_selected.remove(file.path)) return;
      final keepsOne = group.files.any(
        (f) => f.path != file.path && !_selected.contains(f.path),
      );
      if (!keepsOne) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Keep at least one copy of each file'),
            ),
          );
        return;
      }
      _selected.add(file.path);
    });
  }

  void _applyRule(KeepRule rule) => setState(() {
    _rule = rule;
    _selected = autoSelect(_groups, rule);
  });

  Future<void> _delete() async {
    final count = _selectedVisible.length;
    final ok = await confirmDelete(
      context,
      count: count,
      bytes: _selectedBytes,
      noun: 'duplicate',
      note: 'One copy of every file is always kept.',
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    // Only the groups on screen, and only their picks: a filter must never
    // let a delete reach files the user can't see.
    final visible = _visible;
    final report = await Cleaner(
      widget.scope.base,
    ).deleteDuplicates(visible, {for (final f in _selectedVisible) f.path});
    if (!mounted) return;
    final gone = report.deleted.toSet();
    setState(() {
      _deleting = false;
      final filterStillUseful = _groups.any(
        (g) => g.kind == _filter && g.without(gone).files.length > 1,
      );
      if (!filterStillUseful) _filter = null;
      _groups = [
        for (final g in _groups)
          if (g.without(gone) case final left when left.files.length > 1) left,
      ];
      final remaining = {
        for (final g in _groups) ...g.files.map((f) => f.path),
      };
      _selected = _selected.intersection(remaining);
    });
    await finishDelete(context, widget.bridge, report);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicate files'),
        actions: [
          if (_phase == _Phase.results) ...[
            IconButton(
              tooltip: 'Scan again',
              onPressed: _scan,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<Object>(
              tooltip: 'Selection',
              icon: const Icon(Icons.checklist),
              onSelected: (v) => v is KeepRule
                  ? _applyRule(v)
                  : setState(() => _selected.clear()),
              itemBuilder: (_) => [
                for (final (rule, label) in [
                  (KeepRule.oldest, 'Keep the oldest copy'),
                  (KeepRule.newest, 'Keep the newest copy'),
                  (KeepRule.shortestPath, 'Keep the shortest path'),
                ])
                  CheckedPopupMenuItem(
                    value: rule,
                    checked: _rule == rule,
                    child: Text(label),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'none', child: Text('Select none')),
              ],
            ),
          ],
        ],
      ),
      body: switch (_phase) {
        _Phase.intro => _intro(),
        _Phase.scanning => _scanning(),
        _Phase.results => _results(),
      },
      bottomNavigationBar: _phase == _Phase.results && _groups.isNotEmpty
          ? SelectionBar(
              count: _selectedVisible.length,
              bytes: _selectedBytes,
              busy: _deleting,
              noun: 'file',
              onDelete: _delete,
            )
          : null,
    );
  }

  Widget _intro() {
    return MessagePanel(
      icon: Icons.file_copy_outlined,
      title: 'Find duplicate files',
      body:
          'Compares the actual content of your files, so copies are found '
          'even when they have different names.'
          '${widget.scope.coversBase ? '' : '\n\nLooks in ${widget.scope.rootNames}.'}',
      extra: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              ListTile(
                title: const Text('Ignore files smaller than'),
                trailing: DropdownButton<int>(
                  value: _minSize,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setState(() => _minSize = v!),
                  items: [
                    for (final size in _minSizes)
                      DropdownMenuItem(
                        value: size,
                        child: Text(formatBytes(size)),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Include hidden folders'),
                subtitle: const Text(
                  'Folders starting with a dot, usually app data',
                ),
                value: _includeHidden,
                onChanged: (v) => setState(() => _includeHidden = v),
              ),
            ],
          ),
        ),
      ),
      action: FilledButton.icon(
        onPressed: _scan,
        icon: const Icon(Icons.search),
        label: const Text('Scan for duplicates'),
      ),
    );
  }

  Widget _scanning() {
    final p = _progress;
    final (title, detail) = switch (p?.stage) {
      null => ('Starting…', ''),
      DuplicateStage.listing => (
        'Looking through your files…',
        '${p!.files} files found',
      ),
      DuplicateStage.sampling => (
        'Comparing files…',
        '${p!.done} of ${p.total} same-size files checked',
      ),
      DuplicateStage.hashing => (
        'Confirming duplicates…',
        '${formatBytes(p!.bytesDone)} of ${formatBytes(p.bytesTotal)} read',
      ),
    };
    return ProgressPanel(
      title: title,
      detail: detail,
      fraction: p?.fraction,
      onCancel: () => _cancel?.cancel(),
    );
  }

  Widget _results() {
    if (_groups.isEmpty) {
      return MessagePanel(
        icon: Icons.check_circle_outline,
        title: 'No duplicates found',
        body: 'Every file of ${formatBytes(_minSize)} or more is unique.',
        action: OutlinedButton(
          onPressed: () => setState(() => _phase = _Phase.intro),
          child: const Text('Change scan options'),
        ),
      );
    }
    final reclaimable = _groups.fold<int>(0, (sum, g) => sum + g.reclaimable);
    final extraCopies = _groups.fold<int>(
      0,
      (sum, g) => sum + g.files.length - 1,
    );
    final kinds = {for (final g in _groups) g.kind}.toList()
      ..sort((a, b) => a.index - b.index);
    final visible = _visible;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: visible.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return SummaryCard(
            headline: '${formatBytes(reclaimable)} can be freed',
            detail:
                '${plural(extraCopies, 'extra copy', 'extra copies')} '
                'in ${plural(_groups.length, 'group')}',
            icon: Icons.file_copy_outlined,
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
        final group = visible[i - 2];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _GroupCard(
            group: group,
            root: widget.scope.base,
            selected: _selected,
            onToggle: (f) => _toggle(group, f),
          ),
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.root,
    required this.selected,
    required this.onToggle,
  });

  final DuplicateGroup group;
  final String root;
  final Set<String> selected;
  final void Function(FileEntry) onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                FileThumb(group.files.first.path, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.files.first.name,
                        style: text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${plural(group.files.length, 'copy', 'copies')} · '
                        '${formatBytes(group.size)} each',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final file in group.files)
            InkWell(
              onTap: () => onToggle(file),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
                child: Row(
                  children: [
                    Checkbox(
                      value: selected.contains(file.path),
                      onChanged: (_) => onToggle(file),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayPath(file.path, root),
                            style: text.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            formatDate(file.modified),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (!selected.contains(file.path))
                      Tag('Keep', color: scheme.primary),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
