import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.folder_outlined),
            title: Text('Vault'),
            subtitle: Text('Not available yet (Phase 2)'),
            enabled: false,
          ),
          ListTile(
            leading: Icon(Icons.key_outlined),
            title: Text('AI providers'),
            subtitle: Text('Not available yet (Phase 5)'),
            enabled: false,
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Privacy'),
            subtitle: Text(
              'Emerald stores no notes of its own. Your Markdown files stay '
              'in the folder you choose.',
            ),
          ),
          AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Emerald',
            applicationLegalese: 'Local-first Markdown knowledge app.',
          ),
        ],
      ),
    );
  }
}
