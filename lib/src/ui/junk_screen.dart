import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../clean/cleaner.dart';
import '../platform/storage_bridge.dart';
import '../scan/background.dart';
import '../scan/junk.dart';
import '../util/format.dart';
import 'widgets.dart';

class JunkScreen extends StatelessWidget {
  const JunkScreen({super.key, required this.bridge, required this.root});

  final StorageBridge bridge;
  final String root;

  @override
  Widget build(BuildContext context) {
    return AllFilesAccessGate(
      bridge: bridge,
      title: 'Junk files',
      child: _JunkBody(bridge: bridge, root: root),
    );
  }
}

IconData _junkIcon(JunkKind kind) => switch (kind) {
  JunkKind.thumbnails => Icons.photo_library_outlined,
  JunkKind.apk => Icons.android,
  JunkKind.temp => Icons.hourglass_empty,
  JunkKind.trashed => Icons.delete_sweep_outlined,
  JunkKind.emptyFolder => Icons.folder_off_outlined,
};

class _JunkBody extends StatefulWidget {
  const _JunkBody({required this.bridge, required this.root});

  final StorageBridge bridge;
  final String root;

  @override
  State<_JunkBody> createState() => _JunkBodyState();
}

class _JunkBodyState extends State<_JunkBody> {
  final _cancel = CancelToken();
  List<JunkItem>? _items;
  var _foldersScanned = 0;
  var _selected = <String>{};
  var _apks = <String, ApkInfo>{};
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

  Future<void> _scan() async {
    setState(() {
      _items = null;
      _foldersScanned = 0;
    });
    final List<JunkItem> items;
    try {
      items = await runInBackground<List<JunkItem>, int>(
        junkScanTask(widget.root),
        onProgress: (n) {
          if (mounted) setState(() => _foldersScanned = n);
        },
        cancel: _cancel,
      );
    } on ScanCancelled {
      return;
    }
    var apks = <String, ApkInfo>{};
    try {
      apks = await widget.bridge.apkInfo([
        for (final i in items)
          if (i.kind == JunkKind.apk) i.path,
      ]);
    } catch (_) {
      // Without package details installers are just not preselected.
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _apks = apks;
      _selected = {
        for (final i in items)
          if (_preselect(i)) i.path,
      };
    });
  }

  /// Safe-by-default picks: regenerable caches, stale temp files, empty
  /// folders and installers for apps that are already installed.
  bool _preselect(JunkItem item) => switch (item.kind) {
    JunkKind.thumbnails || JunkKind.temp || JunkKind.emptyFolder => true,
    JunkKind.apk => _apks[item.path]?.isInstalled ?? false,
    JunkKind.trashed => false,
  };

  Iterable<JunkItem> get _selectedItems =>
      (_items ?? const <JunkItem>[]).where((i) => _selected.contains(i.path));

  Future<void> _delete() async {
    final items = _selectedItems.toList();
    final bytes = items.fold<int>(0, (sum, i) => sum + i.size);
    final ok = await confirmDelete(context, count: items.length, bytes: bytes);
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    final report = await Cleaner(widget.root).deleteJunk(items);
    if (!mounted) return;
    final gone = report.deleted.toSet();
    setState(() {
      _deleting = false;
      _items = _items!.where((i) => !gone.contains(i.path)).toList();
      _selected.removeAll(gone);
    });
    await finishDelete(context, widget.bridge, report);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Junk files'),
        actions: [
          if (items != null)
            IconButton(
              tooltip: 'Scan again',
              onPressed: _scan,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: items == null
          ? ProgressPanel(
              title: 'Looking for junk…',
              detail: '${plural(_foldersScanned, 'folder')} checked',
            )
          : items.isEmpty
          ? const MessagePanel(
              icon: Icons.check_circle_outline,
              title: 'All clean',
              body:
                  'No thumbnail caches, leftover installers, temp files '
                  'or empty folders were found.',
            )
          : _results(items),
      bottomNavigationBar: items == null || items.isEmpty
          ? null
          : SelectionBar(
              count: _selected.length,
              bytes: _selectedItems.fold(0, (sum, i) => sum + i.size),
              busy: _deleting,
              onDelete: _delete,
            ),
    );
  }

  Widget _results(List<JunkItem> items) {
    final byKind = <JunkKind, List<JunkItem>>{};
    for (final i in items) {
      byKind.putIfAbsent(i.kind, () => []).add(i);
    }
    final total = items.fold<int>(0, (sum, i) => sum + i.size);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SummaryCard(
          headline: '${formatBytes(total)} of junk',
          detail:
              '${plural(items.length, 'item')} in ${plural(byKind.length, 'category', 'categories')}',
          icon: Icons.cleaning_services_outlined,
        ),
        const SizedBox(height: 12),
        for (final MapEntry(key: kind, value: group) in byKind.entries) ...[
          _categoryCard(kind, group),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _categoryCard(JunkKind kind, List<JunkItem> group) {
    final text = Theme.of(context).textTheme;
    final picked = group.where((i) => _selected.contains(i.path)).length;
    final size = group.fold<int>(0, (sum, i) => sum + i.size);
    final allValue = picked == 0
        ? false
        : (picked == group.length ? true : null);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: ToneIcon(_junkIcon(kind), size: 42),
          title: Text(junkLabel(kind)),
          subtitle: Text(
            kind == JunkKind.emptyFolder
                ? plural(group.length, 'folder')
                : '${plural(group.length, 'item')} · ${formatBytes(size)}',
          ),
          trailing: Checkbox(
            tristate: true,
            value: allValue,
            onChanged: (_) => setState(() {
              if (picked == group.length) {
                _selected.removeAll(group.map((i) => i.path));
              } else {
                _selected.addAll(group.map((i) => i.path));
              }
            }),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(junkDescription(kind), style: text.bodySmall),
            ),
            for (final item in group) _itemRow(item),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(JunkItem item) {
    final text = Theme.of(context).textTheme;
    final apk = _apks[item.path];
    final title = apk != null
        ? '${apk.label} ${apk.versionName}'.trim()
        : item.name;
    final where = displayPath(
      item.isDirectory ? item.path : p.dirname(item.path),
      widget.root,
    );
    return InkWell(
      onTap: () => setState(() {
        if (!_selected.remove(item.path)) _selected.add(item.path);
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
        child: Row(
          children: [
            Checkbox(
              value: _selected.contains(item.path),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selected.add(item.path);
                } else {
                  _selected.remove(item.path);
                }
              }),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    where,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (apk?.isInstalled ?? false) ...[
              const Tag('Installed'),
              const SizedBox(width: 8),
            ],
            if (item.kind != JunkKind.emptyFolder)
              Text(formatBytes(item.size), style: text.labelMedium),
          ],
        ),
      ),
    );
  }
}
