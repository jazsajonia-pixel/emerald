import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/theme.dart';
import '../sync/github_client.dart';
import '../sync/proposal_inbox_screen.dart';
import '../sync/sync_controller.dart';
import '../vault/vault_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.onNavigate});

  final ValueChanged<AppDestination> onNavigate;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _eligibilityKey;
  int _proposalCount = 0;
  String? _proposalError;
  bool _checkingProposals = false;

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultControllerProvider);
    final sync = ref.watch(syncControllerProvider);
    _scheduleProposalCheck(sync, vault);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmeraldMark(size: 28),
            SizedBox(width: 10),
            Text('Emerald'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Your Markdown knowledge, local first.',
            style: theme.textTheme.titleMedium,
          ),
          if (_checkingProposals) ...[
            const SizedBox(height: 12),
            const Card(
              key: Key('home-proposals-checking'),
              child: ListTile(
                leading: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('Checking for AI proposals…'),
              ),
            ),
          ],
          if (_proposalCount > 0) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                key: const Key('home-proposals-banner'),
                leading: Icon(
                  Icons.inbox_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                title: Text(
                  '${_proposalCount} new AI ${_proposalCount == 1 ? 'proposal' : 'proposals'}',
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
                subtitle: Text(
                  'Review the suggested changes before anything is written.',
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                onTap: _openProposalInbox,
              ),
            ),
          ],
          if (_proposalError != null) ...[
            const SizedBox(height: 12),
            Card(
              key: const Key('home-proposals-error'),
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _proposalError!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _checkingProposals ? null : _retryProposals,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
              onTap: () => widget.onNavigate(AppDestination.notes),
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
              onTap: () => widget.onNavigate(d),
            ),
        ],
      ),
    );
  }

  void _scheduleProposalCheck(SyncUiState sync, VaultState vault) {
    final settings = sync.settings;
    if (!sync.loaded ||
        !settings.enabled ||
        !settings.configured ||
        vault is! VaultReady) {
      if (_eligibilityKey != null ||
          _proposalCount != 0 ||
          _proposalError != null) {
        _eligibilityKey = null;
        _proposalCount = 0;
        _proposalError = null;
      }
      _checkingProposals = false;
      return;
    }
    final key =
        '${vault.vault.id}|${settings.owner}/${settings.repo}@${settings.branch}';
    if (_eligibilityKey == key || _checkingProposals) return;
    _eligibilityKey = key;
    _checkingProposals = true;
    Future<void>.microtask(() => _checkProposals(key));
  }

  Future<void> _checkProposals(String key) async {
    try {
      final inbox = await ref
          .read(syncControllerProvider.notifier)
          .proposalInbox();
      final items = await inbox.load();
      if (!mounted || _eligibilityKey != key) return;
      setState(() {
        _proposalCount = items.where((item) => item.proposal != null).length;
        _proposalError = null;
      });
    } catch (e) {
      if (!mounted || _eligibilityKey != key) return;
      setState(() => _proposalError = _proposalMessage(e));
    } finally {
      if (mounted && _eligibilityKey == key) {
        setState(() => _checkingProposals = false);
      }
    }
  }

  String _proposalMessage(Object e) => switch (e) {
    SyncException() => e.userMessage,
    _ => 'Could not check for AI proposals. Check your connection and retry.',
  };

  void _retryProposals() {
    _eligibilityKey = null;
    _proposalError = null;
    _proposalCount = 0;
    setState(() {});
  }

  Future<void> _openProposalInbox() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProposalInboxScreen()),
    );
    if (!mounted) return;
    _retryProposals();
  }
}
