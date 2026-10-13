import 'dart:io';

import 'package:flutter/material.dart';

import '../clean/cleaner.dart';
import '../platform/storage_bridge.dart';
import '../theme.dart';
import '../util/file_kind.dart';
import '../util/format.dart';

IconData kindIcon(FileKind kind) => switch (kind) {
  FileKind.image => Icons.image_outlined,
  FileKind.video => Icons.movie_outlined,
  FileKind.audio => Icons.music_note_outlined,
  FileKind.document => Icons.description_outlined,
  FileKind.archive => Icons.folder_zip_outlined,
  FileKind.other => Icons.insert_drive_file_outlined,
};

/// Accent per file kind, matching the storage legend on the home screen.
Color kindColor(BuildContext context, FileKind kind) {
  final colors = SweepColors.of(context);
  return switch (kind) {
    FileKind.image => colors.lilac,
    FileKind.video => colors.pink,
    FileKind.audio => colors.lime,
    FileKind.document => colors.peach,
    FileKind.archive ||
    FileKind.other => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

/// A square preview: the image itself for pictures, an icon otherwise.
class FileThumb extends StatelessWidget {
  const FileThumb(this.path, {super.key, this.size = 44});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kind = kindOf(path);
    final tint = kindColor(context, kind);
    final icon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(kindIcon(kind), color: tint, size: size * 0.5),
    );
    if (kind != FileKind.image) return icon;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * dpr).round(),
        errorBuilder: (_, _, _) => icon,
      ),
    );
  }
}

/// Icon in a tinted rounded square, used for headers and tool tiles.
class ToneIcon extends StatelessWidget {
  const ToneIcon(this.icon, {super.key, this.size = 48, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = color ?? scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: base, size: size * 0.52),
    );
  }
}

/// Centered explainer with an optional action, for intros and empty states.
class MessagePanel extends StatelessWidget {
  const MessagePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToneIcon(icon, size: 84),
            const SizedBox(height: 20),
            Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
            if (extra != null) ...[const SizedBox(height: 20), extra!],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

class ProgressPanel extends StatelessWidget {
  const ProgressPanel({
    super.key,
    required this.title,
    required this.detail,
    this.fraction,
    this.onCancel,
  });

  final String title;
  final String detail;
  final double? fraction;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CircularProgressIndicator(value: fraction, strokeWidth: 7),
            ),
            const SizedBox(height: 28),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(detail, style: text.bodyMedium, textAlign: TextAlign.center),
            if (onCancel != null) ...[
              const SizedBox(height: 24),
              OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom bar showing what is selected and the delete action.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.bytes,
    required this.onDelete,
    this.busy = false,
    this.noun = 'item',
  });

  final int count;
  final int bytes;
  final VoidCallback onDelete;
  final bool busy;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${plural(count, noun)} selected',
                      style: text.titleSmall,
                    ),
                    Text('Frees ${formatBytes(bytes)}', style: text.bodySmall),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: count == 0 || busy ? null : onDelete,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmDelete(
  BuildContext context, {
  required int count,
  required int bytes,
  String noun = 'item',
  String? note,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.delete_forever_outlined),
      title: Text('Delete ${plural(count, noun)}?'),
      content: Text(
        [
          'This frees ${formatBytes(bytes)}. Deleted files can\'t be recovered.',
          ?note,
        ].join('\n\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Runs the media scan for deleted paths and reports the outcome.
Future<void> finishDelete(
  BuildContext context,
  StorageBridge bridge,
  DeleteReport report,
) async {
  try {
    await bridge.mediaScan(report.deleted);
  } catch (_) {
    // Galleries catch up on their own; the files are gone either way.
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final skipped = report.skipped.length;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        [
          'Deleted ${plural(report.deleted.length, 'item')} · freed ${formatBytes(report.freedBytes)}',
          if (skipped > 0) '$skipped skipped',
        ].join(' · '),
      ),
      action: skipped == 0
          ? null
          : SnackBarAction(
              label: 'Details',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Skipped'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final s in report.skipped)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.path.split('/').last),
                            subtitle: Text(s.reason),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}

/// Shows [child] (a full screen) only once all-files access is granted,
/// re-checking when the user comes back from the system settings screen.
/// Until then it shows its own screen titled [title].
class AllFilesAccessGate extends StatefulWidget {
  const AllFilesAccessGate({
    super.key,
    required this.bridge,
    required this.title,
    required this.child,
  });

  final StorageBridge bridge;
  final String title;
  final Widget child;

  @override
  State<AllFilesAccessGate> createState() => _AllFilesAccessGateState();
}

class _AllFilesAccessGateState extends State<AllFilesAccessGate>
    with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final granted = await widget.bridge.hasAllFilesAccess();
    if (mounted && granted != _granted) setState(() => _granted = granted);
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == true) return widget.child;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _granted == null
          ? const Center(child: CircularProgressIndicator())
          : MessagePanel(
              icon: Icons.folder_open_outlined,
              title: 'Allow access to your files',
              body:
                  'SpaceSweep needs permission to read and delete files in your '
                  'storage to find duplicates, junk and large files. Everything '
                  'happens on your phone; nothing is uploaded.',
              action: FilledButton.icon(
                onPressed: () async {
                  await widget.bridge.requestAllFilesAccess();
                  await _check();
                },
                icon: const Icon(Icons.lock_open),
                label: const Text('Allow access'),
              ),
            ),
    );
  }
}

/// Small rounded label, e.g. "Keep" or "Installed".
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: base,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Big headline card at the top of a results list.
/// Headline card at the top of a results list, in the dark hero style
/// shared with the home screen.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.headline,
    required this.detail,
    this.icon,
  });

  final String headline;
  final String detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = SweepColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.hero,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    color: colors.onHero,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(color: colors.onHeroMuted, fontSize: 14),
                ),
              ],
            ),
          ),
          if (icon != null)
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: SweepColors.dark.lilac.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: SweepColors.dark.lilac),
            ),
        ],
      ),
    );
  }
}
