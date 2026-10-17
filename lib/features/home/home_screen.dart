import 'package:flutter/material.dart';

import '../../app/home_shell.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onNavigate});

  final ValueChanged<AppDestination> onNavigate;

  @override
  Widget build(BuildContext context) {
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
              title: const Text('No vault selected'),
              subtitle: const Text(
                'Vault selection arrives in Phase 2. Your notes will stay '
                'as ordinary .md files in a folder you choose.',
              ),
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
