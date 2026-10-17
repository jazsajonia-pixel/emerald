import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'github_client.dart';
import 'sync_controller.dart';
import 'sync_engine.dart';

/// Optional two-way sync with a GitHub repository the user owns.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController(text: 'main');
  final _token = TextEditingController();
  bool _initialised = false;
  bool _busy = false;
  bool _obscure = true;
  String? _status;
  bool _statusError = false;

  @override
  void dispose() {
    _owner.dispose();
    _repo.dispose();
    _branch.dispose();
    _token.dispose();
    super.dispose();
  }

  void _init(SyncUiState s) {
    if (_initialised || !s.loaded) return;
    _initialised = true;
    _owner.text = s.settings.owner;
    _repo.text = s.settings.repo;
    _branch.text = s.settings.branch;
  }

  void _show(String text, {bool error = false}) => setState(() {
    _status = text;
    _statusError = error;
  });

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      final info = await ref
          .read(syncControllerProvider.notifier)
          .test(token: _token.text, owner: _owner.text, repo: _repo.text);
      if (!mounted) return;
      if (!info.canPush) {
        _show(
          'Connected, but the token cannot write. Give it Contents: Read and write.',
          error: true,
        );
      } else if (!info.isPrivate) {
        _show(
          'Connected. WARNING: this repository is public — your notes would be visible to anyone.',
          error: true,
        );
      } else {
        _show(
          'Connected to a private repository with write access (default branch: ${info.defaultBranch}).',
        );
      }
    } on SyncException catch (e) {
      if (mounted) _show(e.userMessage, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final err = await ref
        .read(syncControllerProvider.notifier)
        .configure(
          owner: _owner.text,
          repo: _repo.text,
          branch: _branch.text,
          token: _token.text,
        );
    if (!mounted) return;
    if (err != null) return _show(err, error: true);
    _token.clear();
    _show('Saved. The token is stored encrypted on this device only.');
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove GitHub sync?'),
        content: const Text(
          'Deletes the token and sync settings from this phone. Your notes and '
          'the GitHub repository are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(syncControllerProvider.notifier).remove();
    if (!mounted) return;
    _owner.clear();
    _repo.clear();
    _branch.text = 'main';
    _show('Removed.');
  }

  Future<void> _allowPublic(bool on) async {
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sync to a public repository?'),
          content: const Text(
            'Everyone on the internet will be able to read every synced note.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Allow public'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(syncControllerProvider.notifier).setAllowPublic(on);
  }

  String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncControllerProvider);
    _init(s);
    final theme = Theme.of(context);
    final set = s.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub sync')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Optional. Syncs the Markdown notes of this vault with a private '
              'GitHub repository you own. Emerald works fully without it. '
              'Nothing is ever deleted by sync; conflicting edits are kept as '
              'conflict copies.',
              style: theme.textTheme.bodyMedium,
            ),
            SwitchListTile(
              key: const Key('sync-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable GitHub sync'),
              value: set.enabled,
              onChanged: s.running
                  ? null
                  : (v) =>
                        ref.read(syncControllerProvider.notifier).setEnabled(v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('sync-owner'),
                    controller: _owner,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Owner',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('/'),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('sync-repo'),
                    controller: _repo,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Repository',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sync-branch'),
              controller: _branch,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Branch',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sync-token'),
              controller: _token,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: set.hasToken
                    ? 'Token (saved — enter to replace)'
                    : 'Fine-grained token',
                helperText:
                    'GitHub → Settings → Developer settings → Fine-grained tokens. '
                    'Only this repository; Contents: Read and write; Metadata: Read.',
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show token' : 'Hide token',
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy || s.running ? null : _test,
                  child: const Text('Test connection'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || s.running ? null : _save,
                  child: const Text('Save settings'),
                ),
                if (set.hasToken)
                  TextButton(
                    onPressed: s.running ? null : _remove,
                    child: const Text('Remove'),
                  ),
              ],
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _status!,
                  style: TextStyle(
                    color: _statusError
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            const Divider(height: 32),
            FilledButton.icon(
              key: const Key('sync-now'),
              onPressed: s.running || !set.enabled || !set.configured
                  ? null
                  : () => ref.read(syncControllerProvider.notifier).syncNow(),
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            const SizedBox(height: 8),
            if (s.running) ...[
              LinearProgressIndicator(
                value: s.total == 0 ? null : s.done / s.total,
              ),
              const SizedBox(height: 4),
              Text(
                s.total == 0
                    ? 'Comparing…'
                    : 'Syncing ${s.done}/${s.total}: ${s.current}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ] else
              Text(
                !set.enabled
                    ? 'Sync is off.'
                    : s.lastSync == null
                    ? 'Not synced yet.'
                    : 'Last successful sync: ${_fmt(s.lastSync!)}',
              ),
            if (s.message != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    s.message!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            if (s.lastReport != null && !s.running)
              _ReportView(report: s.lastReport!),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow a public repository'),
              subtitle: const Text(
                'Off by default. Public repositories expose every synced note.',
              ),
              value: set.allowPublic,
              onChanged: s.running ? null : _allowPublic,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});
  final SyncReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Uploaded ${report.uploaded} · Downloaded ${report.downloaded} · '
            'Unchanged ${report.unchanged} · Conflicts ${report.conflicts.length}',
            style: theme.textTheme.titleSmall,
          ),
          for (final c in report.conflicts)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.call_split,
                color: theme.colorScheme.tertiary,
              ),
              title: Text('Conflict: ${c.path}'),
              subtitle: Text(
                c.copyPath == null
                    ? 'GitHub version could not be saved; nothing was changed.'
                    : 'GitHub\'s version saved as ${c.copyPath}. Your version is '
                          'unchanged and will be uploaded on the next sync.',
              ),
            ),
          for (final f in report.failures)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(f),
            ),
          for (final n in report.notices)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: Text(n),
            ),
        ],
      ),
    );
  }
}
