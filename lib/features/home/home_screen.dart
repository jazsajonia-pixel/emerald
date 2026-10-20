import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/theme.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_screen.dart';
import '../vault/vault_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.onNavigate});

  final ValueChanged<AppDestination> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultControllerProvider);
    final sync = ref.watch(syncControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cards = <Widget>[
      _Hero(vault: vault),
      const SizedBox(height: 12),
      Row(
        children: [
          for (final d in [
            AppDestination.notes,
            AppDestination.graph,
            AppDestination.ai,
          ]) ...[
            Expanded(
              child: _QuickAction(
                icon: d.selectedIcon,
                label: 'Open ${d.label}',
                onTap: () => onNavigate(d),
              ),
            ),
            if (d != AppDestination.ai) const SizedBox(width: 10),
          ],
        ],
      ),
      const SizedBox(height: 12),
      _SyncCard(
        sync: sync,
        onOpen: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const SyncScreen())),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(switch (vault) {
            VaultReady(:final vault) => vault.name,
            VaultLoading() => 'Opening vault…',
            VaultAccessLost() => 'Vault access was lost',
            VaultFailure() => 'Vault could not be opened',
            VaultNone() => 'No vault selected',
          }),
          subtitle: Text(switch (vault) {
            VaultReady() => '${vault.notes.length} notes',
            VaultNone() =>
              'Choose a folder of Markdown notes in Brain. Your notes '
                  'stay ordinary .md files.',
            _ => 'Open Brain for details.',
          }),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onNavigate(AppDestination.notes),
        ),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SapphireMark(size: 28),
            SizedBox(width: 10),
            Text('Sapphire', style: TextStyle(letterSpacing: 0.4)),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: SapphireTheme.heroGlow),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Your Markdown knowledge, local first.',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < cards.length; i++)
              _Entrance(index: i, child: cards[i]),
          ],
        ),
      ),
    );
  }
}

/// Fades and lifts children in, staggered (skipped under reduced motion).
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: c),
      ),
      child: child,
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.vault});
  final VaultState vault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16275A), Color(0xFF0C1430)],
        ),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          const AnimatedSapphireMark(size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your second brain',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  vault is VaultReady
                      ? 'Notes on this phone, mirrored to GitHub so any AI '
                            'can read and update them.'
                      : 'Pick a notes folder to get started.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
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

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.sync, required this.onOpen});
  final SyncUiState sync;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = sync.settings;
    final ready = s.enabled && s.configured;
    final problem = sync.message != null && !sync.running;
    final (
      IconData icon,
      Color color,
      String title,
      String subtitle,
    ) = switch (null) {
      _ when !ready => (
        Icons.link_rounded,
        scheme.primary,
        'Connect GitHub',
        'Sign in and pick your notes repository to keep this folder '
            'and GitHub identical.',
      ),
      _ when sync.running => (
        Icons.sync_rounded,
        scheme.secondary,
        'Syncing with ${s.repoName}…',
        sync.total == 0
            ? 'Comparing notes'
            : '${sync.done}/${sync.total} ${sync.current}',
      ),
      _ when problem => (
        Icons.error_outline_rounded,
        scheme.error,
        'Sync needs attention',
        sync.message!,
      ),
      _ => (
        Icons.cloud_done_rounded,
        const Color(0xFF5BE0B3),
        'Synced with ${s.repoName}',
        '${sync.lastSync == null ? 'Not synced yet' : 'Last sync ${_ago(sync.lastSync!)}'}'
            '${s.autoSync ? ' · auto on detected changes' : ' · manual'}',
      ),
    };
    return Card(
      key: const Key('home-sync-card'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: sync.running
                    ? SizedBox.square(
                        key: const ValueKey('spin'),
                        dimension: 40,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: color,
                          ),
                        ),
                      )
                    : Container(
                        key: ValueKey(icon),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
