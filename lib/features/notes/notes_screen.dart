import 'package:flutter/material.dart';

import '../../core/ui/state_views.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Brain')),
      body: const EmptyView(
        icon: Icons.folder_open,
        title: 'No vault selected',
        message:
            'Choosing a vault folder, browsing notes, and editing are not '
            'available yet (planned for Phase 2).',
      ),
    );
  }
}
