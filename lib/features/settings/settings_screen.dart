import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../vault/vault_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget this vault?'),
        content: const Text(
          'Emerald will stop using this folder and release its access. '
          'Your notes are not changed or deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forget vault'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(vaultControllerProvider.notifier).forget();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultControllerProvider);
    final controller = ref.read(vaultControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Vault folder'),
            subtitle: Text(
              vault is VaultReady ? vault.vault.name : 'No vault selected',
            ),
            trailing: TextButton(
              onPressed: controller.pick,
              child: Text(vault is VaultReady ? 'Change' : 'Choose'),
            ),
          ),
          if (vault is VaultReady)
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Forget vault'),
              subtitle: const Text('Releases access; files are untouched'),
              onTap: () => _forget(context, ref),
            ),
          const ListTile(
            leading: Icon(Icons.key_outlined),
            title: Text('AI providers'),
            subtitle: Text('Not available yet (Phase 5)'),
            enabled: false,
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Privacy'),
            subtitle: Text(
              'Emerald stores no notes of its own. Your Markdown files stay '
              'in the folder you choose. Previous versions of edited notes '
              'are kept privately on this device for recovery.',
            ),
          ),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Emerald',
            applicationLegalese: 'Local-first Markdown knowledge app.',
          ),
        ],
      ),
    );
  }
}
