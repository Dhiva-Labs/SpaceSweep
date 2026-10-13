import 'package:flutter/material.dart';

import '../platform/storage_bridge.dart';
import '../util/format.dart';
import 'cache_screen.dart';
import 'duplicates_screen.dart';
import 'junk_screen.dart';
import 'large_files_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.bridge});

  final StorageBridge bridge;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _root;
  StorageInfo? _info;
  var _allFilesAccess = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final bridge = widget.bridge;
    final root = _root ?? await bridge.storageRoot();
    final info = await bridge.storageInfo();
    final access = await bridge.hasAllFilesAccess();
    if (!mounted) return;
    setState(() {
      _root = root;
      _info = info;
      _allFilesAccess = access;
    });
  }

  Future<void> _open(Widget Function(String root) screen) async {
    final root = _root;
    if (root == null) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen(root)));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = widget.bridge;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            const SliverAppBar.large(title: Text('SpaceSweep')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.list(
                children: [
                  _StorageCard(info: _info),
                  if (!_allFilesAccess) ...[
                    const SizedBox(height: 12),
                    _AccessCard(
                      onAllow: () async {
                        await bridge.requestAllFilesAccess();
                        await _refresh();
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Free up space', style: text.titleMedium),
                  const SizedBox(height: 12),
                  _ToolTile(
                    icon: Icons.file_copy_outlined,
                    color: const Color(0xFF7E57C2),
                    title: 'Duplicate files',
                    subtitle: 'Identical photos, videos and documents',
                    onTap: () => _open(
                      (root) => DuplicatesScreen(bridge: bridge, root: root),
                    ),
                  ),
                  _ToolTile(
                    icon: Icons.cached,
                    color: const Color(0xFF00897B),
                    title: 'App cache',
                    subtitle: 'Find and clear cache-heavy apps',
                    onTap: () => _open((_) => CacheScreen(bridge: bridge)),
                  ),
                  _ToolTile(
                    icon: Icons.cleaning_services_outlined,
                    color: const Color(0xFFEF6C00),
                    title: 'Junk files',
                    subtitle:
                        'Thumbnails, leftover APKs, temp files, empty folders',
                    onTap: () =>
                        _open((root) => JunkScreen(bridge: bridge, root: root)),
                  ),
                  _ToolTile(
                    icon: Icons.data_usage,
                    color: const Color(0xFF1E88E5),
                    title: 'Large files',
                    subtitle: 'See what takes up the most space',
                    onTap: () => _open(
                      (root) => LargeFilesScreen(bridge: bridge, root: root),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: text.bodySmall?.color,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Works offline. No ads, no tracking.',
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.info});

  final StorageInfo? info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final info = this.info;
    final media = [
      if (info?.imageBytes case final bytes? when bytes > 0) ('Images', bytes),
      if (info?.videoBytes case final bytes? when bytes > 0) ('Videos', bytes),
      if (info?.audioBytes case final bytes? when bytes > 0) ('Audio', bytes),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: info == null
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Internal storage', style: text.labelLarge),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: formatBytes(info.usedBytes),
                          style: text.displaySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: '  used of ${formatBytes(info.totalBytes)}',
                          style: text.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: info.usedFraction,
                      minHeight: 14,
                      color: info.usedFraction > 0.9
                          ? scheme.error
                          : scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${formatBytes(info.freeBytes)} free · '
                    '${(info.usedFraction * 100).round()}% used',
                    style: text.bodyMedium,
                  ),
                  if (media.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (label, bytes) in media)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('$label ${formatBytes(bytes)}'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Allow file access',
              style: text.titleMedium?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Needed to find duplicates, junk and large files. Everything '
              'stays on your phone.',
              style: text.bodyMedium?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onAllow, child: const Text('Allow')),
          ],
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ToneIcon(icon, color: color),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
