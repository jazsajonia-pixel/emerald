import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/vault_storage.dart';
import '../ai/proposal_card.dart';
import '../vault/vault_controller.dart';
import 'github_client.dart';
import 'remote_proposals.dart';
import 'sync_controller.dart';

/// Review screen for changes proposed by AI apps (ChatGPT, Claude,
/// Perplexity, Manus …) through the optional Emerald MCP server. Nothing is
/// written to a note until the user taps Approve & save.
class ProposalInboxScreen extends ConsumerStatefulWidget {
  const ProposalInboxScreen({super.key});

  @override
  ConsumerState<ProposalInboxScreen> createState() =>
      _ProposalInboxScreenState();
}

class _ProposalInboxScreenState extends ConsumerState<ProposalInboxScreen> {
  RemoteProposalInbox? _inbox;
  List<InboxItem>? _items;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _message(Object e) => switch (e) {
    SyncException() => e.userMessage,
    VaultException(code: VaultErrorCode.conflict) =>
      'The note changed on this phone in the meantime. Nothing was written.',
    VaultException(code: VaultErrorCode.alreadyExists) =>
      'A note with this name already exists. Nothing was written.',
    VaultException() => 'Could not write the note (${e.code.name}).',
    _ => 'Something went wrong.',
  };

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _inbox ??= await ref
          .read(syncControllerProvider.notifier)
          .proposalInbox();
      final items = await _inbox!.load();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    }
    await _load();
  }

  Future<void> _approve(InboxItem item) => _run(() async {
    await _inbox!.approve(item);
    await ref.read(vaultControllerProvider.notifier).rescan();
  }, 'Saved ${item.proposal!.path}. Tap Sync now to upload it to GitHub.');

  Future<void> _dismiss(InboxItem item, String done) =>
      _run(() => _inbox!.dismiss(item), done);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI app proposals'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Changes suggested by AI apps connected through the Emerald MCP '
            'server. Review each diff; nothing changes until you approve. '
            'Approved changes are uploaded with the next Sync now.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          if (items != null && items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No proposals are waiting.'),
            ),
          if (items != null)
            for (final item in items) _buildItem(context, item),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, InboxItem item) {
    final p = item.proposal;
    final source = [
      if (p?.client != null) p!.client!,
      if (p?.createdAt != null) _fmt(p!.createdAt!),
    ].join(' · ');
    if (item.state == InboxItemState.ready) {
      return Column(
        key: ValueKey(item.file.path),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (source.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                source,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ProposalCard(
            proposal: item.note!,
            onApprove: () => _busy ? null : _approve(item),
            onReject: () => _busy ? null : _dismiss(item, 'Proposal rejected.'),
          ),
        ],
      );
    }
    final (label, done) = switch (item.state) {
      InboxItemState.alreadyApplied => ('Remove from list', 'Removed.'),
      _ => ('Reject', 'Proposal rejected.'),
    };
    return Card(
      key: ValueKey(item.file.path),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p?.path ?? item.file.path,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (p != null) Text(p.summary),
            const SizedBox(height: 4),
            Text(
              item.reason ?? '',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => _dismiss(item, done),
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
