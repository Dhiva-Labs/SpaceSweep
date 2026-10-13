import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../platform/storage_bridge.dart';
import '../util/format.dart';
import 'widgets.dart';

const ownPackage = 'com.dhivalabs.space_sweep';

class CacheScreen extends StatefulWidget {
  const CacheScreen({super.key, required this.bridge});

  final StorageBridge bridge;

  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen> with WidgetsBindingObserver {
  var _loading = true;
  var _usageAccess = false;
  var _allFilesAccess = false;
  var _sdk = 0;
  var _apps = <AppCacheInfo>[];
  var _showSystem = false;
  var _busy = false;
  final _icons = <String, Future<Uint8List?>>{};

  /// App whose settings page we opened, with its cache size at that time.
  AppCacheInfo? _visiting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final bridge = widget.bridge;
    final usage = await bridge.hasUsageAccess();
    final allFiles = await bridge.hasAllFilesAccess();
    final sdk = await bridge.sdkInt();
    var apps = <AppCacheInfo>[];
    if (usage) {
      try {
        apps = [...await bridge.appCaches()];
      } catch (_) {
        // Shown as an empty list; the user can pull to retry.
      }
      apps.sort((a, b) => b.cacheBytes.compareTo(a.cacheBytes));
    }
    if (!mounted) return;
    final visited = _visiting;
    _visiting = null;
    setState(() {
      _usageAccess = usage;
      _allFilesAccess = allFiles;
      _sdk = sdk;
      _apps = apps;
      _loading = false;
    });
    if (visited != null) {
      final now = apps
          .where((a) => a.packageName == visited.packageName)
          .firstOrNull;
      if (now != null && now.cacheBytes < visited.cacheBytes) {
        final freed = visited.cacheBytes - now.cacheBytes;
        _snack('Freed ${formatBytes(freed)} from ${visited.label}');
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<AppCacheInfo> get _visible => [
    for (final a in _apps)
      if (a.cacheBytes > 0 && (_showSystem || !a.isSystem)) a,
  ];

  Future<void> _trim() async {
    setState(() => _busy = true);
    final result = await widget.bridge.trimCaches();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      _snack('Android declined: ${result.error}');
    } else if (result.freedBytes > 0) {
      _snack(
        'Android cleared ${formatBytes(result.freedBytes)} of cached files',
      );
    } else {
      _snack('Android found no cache it was willing to remove right now');
    }
    await _load(quiet: true);
  }

  Future<void> _clearExternal() async {
    final outcome = await widget.bridge.clearExternalAppCaches();
    if (!mounted) return;
    switch (outcome) {
      case ClearCacheOutcome.cleared:
        _snack('App cache folders cleared');
      case ClearCacheOutcome.failed:
        _snack('Android couldn\'t clear the cache folders');
      case ClearCacheOutcome.unsupported:
        _snack('Not available on this version of Android');
      case ClearCacheOutcome.cancelled:
        break;
    }
    await _load(quiet: true);
  }

  Future<void> _clearApp(AppCacheInfo app) async {
    if (app.packageName == ownPackage) {
      final freed = await widget.bridge.clearOwnCache();
      if (!mounted) return;
      _snack('Freed ${formatBytes(freed)}');
      await _load(quiet: true);
      return;
    }
    _visiting = app;
    await widget.bridge.openAppDetails(app.packageName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App cache')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final text = Theme.of(context).textTheme;
    final visible = _visible;
    final total = visible.fold<int>(0, (sum, a) => sum + a.cacheBytes);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_usageAccess)
          SummaryCard(
            headline: '${formatBytes(total)} of cache',
            detail: 'Spread across ${plural(visible.length, 'app')}',
            icon: Icons.cached,
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('See which apps hoard cache', style: text.titleMedium),
                  const SizedBox(height: 6),
                  const Text(
                    'Android only shares other apps\' cache sizes with apps '
                    'that have usage access. Turn it on for SpaceSweep in the '
                    'next screen.',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: widget.bridge.openUsageAccessSettings,
                    icon: const Icon(Icons.query_stats),
                    label: const Text('Allow usage access'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const ToneIcon(Icons.auto_delete_outlined, size: 42),
                title: const Text('Trim caches'),
                subtitle: const Text(
                  'Asks Android to delete cached files across all apps. '
                  'It clears the biggest caches first and may leave small ones.',
                ),
                isThreeLine: true,
                trailing: FilledButton.tonal(
                  onPressed: _busy ? null : _trim,
                  child: const Text('Trim'),
                ),
              ),
              if (_sdk >= 30)
                ListTile(
                  leading: const ToneIcon(
                    Icons.folder_delete_outlined,
                    size: 42,
                  ),
                  title: const Text('Clear app cache folders'),
                  subtitle: Text(
                    _allFilesAccess
                        ? 'Android asks you to confirm, then empties the cache '
                              'folders every app keeps in shared storage.'
                        : 'Needs all-files access, which you can allow from '
                              'Duplicate files or Junk files.',
                  ),
                  isThreeLine: true,
                  trailing: FilledButton.tonal(
                    onPressed: _allFilesAccess ? _clearExternal : null,
                    child: const Text('Clear'),
                  ),
                ),
            ],
          ),
        ),
        if (_usageAccess) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text('Apps by cache size', style: text.titleMedium),
              ),
              const Text('System apps'),
              Switch(
                value: _showSystem,
                onChanged: (v) => setState(() => _showSystem = v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final app in visible) _appTile(app),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No app has cached data right now.',
                textAlign: TextAlign.center,
                style: text.bodyLarge,
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Why not one tap for everything? Since Android 6 only system apps may '
          'delete another app\'s internal cache. Tap Clear next to an app to open '
          'its settings, then choose Storage › Clear cache. SpaceSweep measures '
          'what you freed when you come back.',
          style: text.bodySmall,
        ),
      ],
    );
  }

  Widget _appTile(AppCacheInfo app) {
    final icon = _icons.putIfAbsent(
      app.packageName,
      () => widget.bridge.appIcon(app.packageName),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: SizedBox.square(
          dimension: 40,
          child: FutureBuilder(
            future: icon,
            builder: (context, snap) => snap.data == null
                ? const Icon(Icons.android, size: 32)
                : Image.memory(snap.data!, gaplessPlayback: true),
          ),
        ),
        title: Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Cache ${formatBytes(app.cacheBytes)} · '
          'Data ${formatBytes(app.dataBytes > app.cacheBytes ? app.dataBytes - app.cacheBytes : 0)}',
        ),
        trailing: TextButton(
          onPressed: () => _clearApp(app),
          child: const Text('Clear'),
        ),
      ),
    );
  }
}
