import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/scan_scope.dart';
import '../platform/linux_bridge.dart';
import '../platform/storage_bridge.dart';
import '../theme.dart';
import '../util/format.dart';
import 'cache_screen.dart';
import 'duplicates_screen.dart';
import 'junk_screen.dart';
import 'large_files_screen.dart';
import 'linux_cache_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.bridge});

  final StorageBridge bridge;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  ScanScope? _scope;
  StorageInfo? _info;
  var _allFilesAccess = true;
  var _usageAccess = true;

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
    final scope =
        _scope ??
        ScanScope(
          base: await bridge.storageRoot(),
          roots: await bridge.scanRoots(),
        );
    final info = await bridge.storageInfo();
    final files = await bridge.hasAllFilesAccess();
    final usage = await bridge.hasUsageAccess();
    if (!mounted) return;
    setState(() {
      _scope = scope;
      _info = info;
      _allFilesAccess = files;
      _usageAccess = usage;
    });
  }

  Future<void> _open(Widget Function(ScanScope scope) screen) async {
    final scope = _scope;
    if (scope == null) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen(scope)));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = widget.bridge;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final colors = SweepColors.of(context);
    final info = _info;
    final segments = info == null
        ? const <_Segment>[]
        : _breakdown(info, colors);

    Widget tile(
      int accent,
      IconData icon,
      String title,
      String subtitle,
      Widget Function(ScanScope) screen,
    ) => _ToolTile(
      color: colors.accents[accent],
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => _open(screen),
    );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Text(
                'SpaceSweep',
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),
              _HeroCard(
                info: info,
                segments: segments,
                label: bridge is LinuxStorageBridge
                    ? 'Home disk'
                    : 'Internal storage',
              ),
              const SizedBox(height: 12),
              if (segments.length > 1)
                _Legend(segments: segments)
              else if (info != null && !_usageAccess)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: bridge.openUsageAccessSettings,
                    icon: const Icon(Icons.donut_large, size: 18),
                    label: const Text('See what\'s using space'),
                  ),
                ),
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
              Text(
                'Free up space',
                style: text.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _TileRow(
                left: tile(
                  0,
                  Icons.file_copy_outlined,
                  'Duplicate files',
                  'Identical photos, videos & docs',
                  (scope) => DuplicatesScreen(bridge: bridge, scope: scope),
                ),
                right: bridge is LinuxStorageBridge
                    ? tile(
                        1,
                        Icons.cached,
                        'Cache & trash',
                        'App caches, thumbnails, trash',
                        (_) => LinuxCacheScreen(
                          cacheDir: bridge.cacheDir,
                          trashDir: bridge.trashDir,
                        ),
                      )
                    : tile(
                        1,
                        Icons.cached,
                        'App cache',
                        'Clear cache-heavy apps',
                        (_) => CacheScreen(bridge: bridge),
                      ),
              ),
              const SizedBox(height: 12),
              _TileRow(
                left: tile(
                  2,
                  Icons.cleaning_services_outlined,
                  'Junk files',
                  'Thumbnails, APKs, temp files',
                  (scope) => JunkScreen(bridge: bridge, scope: scope),
                ),
                right: tile(
                  3,
                  Icons.pie_chart_outline,
                  'Large files',
                  'What takes the most space',
                  (scope) => LargeFilesScreen(bridge: bridge, scope: scope),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Works offline. No ads, no tracking.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment {
  const _Segment(this.label, this.bytes, this.color);

  final String label;
  final int bytes;
  final Color color;
}

/// Splits used space into apps and media when usage access provides the
/// numbers; otherwise used space is a single segment. "Other" is whatever
/// is left: audio, documents, downloads and the system itself.
List<_Segment> _breakdown(StorageInfo info, SweepColors colors) {
  final used = info.usedBytes;
  final apps = info.appBytes;
  final photos = info.imageBytes;
  if (apps == null || photos == null) {
    return [_Segment('Used', used, colors.lilac)];
  }
  final videos = info.videoBytes ?? 0;
  final known = photos + videos + apps;
  // Apps' own media can be counted twice; never let the parts exceed the whole.
  final scale = known > used && known > 0 ? used / known : 1.0;
  int scaled(int v) => (v * scale).round();
  return [
    _Segment('Photos', scaled(photos), colors.lilac),
    _Segment('Videos', scaled(videos), colors.pink),
    _Segment('Apps', scaled(apps), colors.lime),
    _Segment('Other', math.max(0, used - scaled(known)), colors.peach),
  ];
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.info,
    required this.segments,
    required this.label,
  });

  final StorageInfo? info;
  final List<_Segment> segments;

  /// "Internal storage" on a phone, "Home disk" on the desktop.
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = SweepColors.of(context);
    final info = this.info;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.hero,
        borderRadius: BorderRadius.circular(28),
      ),
      child: info == null
          ? SizedBox(
              height: 116,
              child: Center(
                child: CircularProgressIndicator(color: colors.lilac),
              ),
            )
          : Row(
              children: [
                SizedBox.square(
                  dimension: 116,
                  child: CustomPaint(
                    painter: _RingPainter(
                      segments: segments,
                      total: info.totalBytes,
                      track: colors.heroTrack,
                    ),
                    child: Center(
                      child: Text(
                        '${(info.usedFraction * 100).round()}%',
                        style: TextStyle(
                          color: colors.onHero,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: colors.onHeroMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatBytes(info.usedBytes),
                        style: TextStyle(
                          color: colors.onHero,
                          fontSize: 30,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'of ${formatBytes(info.totalBytes)} used',
                        style: TextStyle(
                          color: colors.onHeroMuted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: SweepColors.dark.lilac.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${formatBytes(info.freeBytes)} free',
                          style: TextStyle(
                            color: colors.onHero,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.segments,
    required this.total,
    required this.track,
  });

  final List<_Segment> segments;
  final int total;
  final Color track;

  static const _stroke = 14.0;
  static const _gap = 0.04;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawArc(arc, 0, 2 * math.pi, false, paint..color = track);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final s in segments) {
      final sweep = 2 * math.pi * s.bytes / total;
      if (sweep <= 0) continue;
      final visible = sweep > _gap * 2 ? sweep - _gap : sweep;
      canvas.drawArc(arc, start, visible, false, paint..color = s.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.segments != segments || old.total != total || old.track != track;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.segments});

  final List<_Segment> segments;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final s in segments)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: s.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text('${s.label} ${formatBytes(s.bytes)}', style: style),
            ],
          ),
      ],
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
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
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Allow file access',
              style: text.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Needed to find duplicates, junk and large files. Everything '
              'stays on your phone.',
              style: text.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
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
