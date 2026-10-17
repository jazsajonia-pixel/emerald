import 'package:flutter/material.dart';

import '../../core/ui/state_views.dart';

class AiHubScreen extends StatelessWidget {
  const AiHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Hub')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          NotYetAvailable(feature: 'AI chat', phase: 'Phase 5'),
          SizedBox(height: 16),
          Text(
            'AI is optional. Emerald works fully offline without it. When it '
            'is added, nothing from your vault is sent to an AI provider '
            'unless you configure one and ask it a question, and any edit it '
            'proposes is shown for your approval first.',
          ),
        ],
      ),
    );
  }
}
