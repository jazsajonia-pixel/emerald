import 'package:flutter/material.dart';

import '../../core/ui/state_views.dart';

class GraphScreen extends StatelessWidget {
  const GraphScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Graph')),
      body: const EmptyView(
        icon: Icons.hub_outlined,
        title: 'No graph yet',
        message:
            'The graph of links between your notes is not available yet '
            '(planned for Phase 4).',
      ),
    );
  }
}
