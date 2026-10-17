import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/state_views.dart';
import '../../core/vault/vault_path.dart';
import '../notes/markdown_preview.dart';
import '../vault/vault_controller.dart';
import 'ai_config.dart';
import 'ai_settings_screen.dart';
import 'chat_controller.dart';
import 'proposal_card.dart';
import 'proposals.dart';

class AiHubScreen extends ConsumerStatefulWidget {
  const AiHubScreen({super.key});

  @override
  ConsumerState<AiHubScreen> createState() => _AiHubScreenState();
}

class _AiHubScreenState extends ConsumerState<AiHubScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _ensureConsent(AiConfig cfg) async {
    if (cfg.consented) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send notes to an AI provider?'),
        content: Text(
          '${cfg.info?.dataNotice ?? ''}\n\nEmerald only sends your question, '
          'note titles from searches, and the notes the AI chooses to read. '
          'The AI cannot change notes without your approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(aiConfigProvider.notifier).setConsent(true);
    return ok == true;
  }

  Future<void> _send(AiConfig cfg) async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (!await _ensureConsent(cfg)) return;
    _input.clear();
    await ref.read(chatControllerProvider.notifier).send(text);
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _approve(NoteProposal p) async {
    final err = await ref.read(chatControllerProvider.notifier).approve(p);
    _snack(err ?? 'Saved ${p.path}');
  }

  Future<void> _approveAll(List<NoteProposal> pending) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apply ${pending.length} changes?'),
        content: Text(
          'This writes all pending proposals to your vault:\n'
          '${pending.map((p) => '• ${p.kind == ProposalKind.create ? 'Create' : 'Edit'} ${p.path}').join('\n')}\n\n'
          'Edited notes keep their previous version in history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    var failed = 0;
    for (final p in pending) {
      final err = await ref.read(chatControllerProvider.notifier).approve(p);
      if (err != null) failed++;
    }
    _snack(
      failed == 0
          ? 'All changes applied'
          : '$failed change(s) could not be applied',
    );
  }

  void _openSettings() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(aiConfigProvider);
    final chat = ref.watch(chatControllerProvider);
    final vault = ref.watch(vaultControllerProvider);
    final pending = chat.pendingProposals;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Hub'),
        actions: [
          if (chat.entries.isNotEmpty)
            IconButton(
              tooltip: 'New conversation',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: chat.busy
                  ? null
                  : ref.read(chatControllerProvider.notifier).clear,
            ),
          IconButton(
            tooltip: 'AI provider settings',
            icon: const Icon(Icons.tune),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: !cfg.loaded
          ? const LoadingView()
          : !cfg.ready
          ? EmptyView(
              icon: Icons.auto_awesome_outlined,
              title: 'AI is optional and off',
              message:
                  'Emerald works fully without AI. To ask questions about your '
                  'notes, add your own API key for a supported provider. '
                  'Nothing is sent anywhere until you do.',
              action: FilledButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.key_outlined),
                label: const Text('Set up a provider'),
              ),
            )
          : vault is! VaultReady
          ? const EmptyView(
              icon: Icons.folder_open,
              title: 'Open a vault first',
              message: 'Choose a vault folder in Brain so the AI has notes to work with.',
            )
          : Column(
              children: [
                if (chat.sharedNotes.isNotEmpty)
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.outbox_outlined, size: 20),
                      title: Text(
                        'Sent to ${cfg.info?.name ?? 'provider'}: ${chat.sharedNotes.length} note(s)',
                      ),
                      subtitle: Text(
                        chat.sharedNotes.map(VaultPath.title).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                if (pending.length > 1)
                  MaterialBanner(
                    content: Text(
                      '${pending.length} proposed changes are waiting for review.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => _approveAll(pending),
                        child: const Text('Review & apply all'),
                      ),
                    ],
                  ),
                Expanded(
                  child: chat.entries.isEmpty
                      ? EmptyView(
                          icon: Icons.chat_outlined,
                          title: 'Ask about your notes',
                          message:
                              'Using ${cfg.info?.name} (${cfg.model}). The AI can search and '
                              'read notes and propose edits for your approval.',
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(12),
                          itemCount: chat.entries.length + (chat.busy ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == chat.entries.length) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Thinking…'),
                                  ],
                                ),
                              );
                            }
                            return _entry(chat.entries[i]);
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('ai-input'),
                            controller: _input,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText: 'Ask about your notes…',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Send',
                          icon: const Icon(Icons.send),
                          onPressed: chat.busy ? null : () => _send(cfg),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _entry(ChatEntry e) {
    final scheme = Theme.of(context).colorScheme;
    return switch (e) {
      UserEntry(:final text) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: TextStyle(color: scheme.onPrimaryContainer)),
        ),
      ),
      AssistantEntry(:final text) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: MarkdownPreview(
          text: text,
          shrinkWrap: true,
          onTapLink: (_, _) {},
        ),
      ),
      ToolEntry(:final description, :final failed) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              failed ? Icons.warning_amber : Icons.manage_search,
              size: 16,
              color: failed ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
      ProposalEntry(:final proposal) => ProposalCard(
        proposal: proposal,
        onApprove: () => _approve(proposal),
        onReject: () =>
            ref.read(chatControllerProvider.notifier).reject(proposal),
      ),
      ErrorEntry(:final message) => Card(
        color: scheme.errorContainer,
        child: ListTile(
          leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
          title: Text(
            message,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ),
      ),
    };
  }
}
