import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../vault/vault_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.onNavigate});

  final ValueChanged<AppDestination> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultControllerProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Emerald')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Your Markdown knowledge, local first.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 8),
          for (final d in [
            AppDestination.notes,
            AppDestination.graph,
            AppDestination.ai,
          ])
            ListTile(
              leading: Icon(d.icon),
              title: Text('Open ${d.label}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onNavigate(d),
            ),
        ],
      ),
    );
  }
}
