import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'github_auth.dart';
import 'github_client.dart';
import 'sync_controller.dart';
import 'sync_engine.dart';

/// Opens [uri] in the browser; returns false if nothing could open it.
typedef UrlOpener = Future<bool> Function(Uri uri);

final urlOpenerProvider = Provider<UrlOpener>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Pre-filled "New GitHub App" page (docs: "Registering a GitHub App using
/// URL parameters"). The user only ticks "Enable Device Flow" and creates it.
Uri gitHubAppCreateUri(String suffix) =>
    Uri.https('github.com', '/settings/apps/new', {
      'name': 'Sapphire Sync $suffix',
      'description':
          'Two-way sync between the Sapphire Android app and one notes '
          'repository.',
      'url': 'https://github.com/jazsajonia-pixel/sapphire',
      'public': 'false',
      'webhook_active': 'false',
      'contents': 'write',
    });

/// Two-way GitHub sync: sign in with GitHub, pick the notes repository and
/// Sapphire keeps the phone folder and the repository identical.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _clientId = TextEditingController();
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController(text: 'main');
  final _token = TextEditingController();
  bool _initialised = false;
  bool _busy = false;
  bool _obscure = true;
  String? _status;
  bool _statusError = false;
  final _suffix = (math.Random().nextInt(0xFFFF) + 0x1000)
      .toRadixString(16)
      .toUpperCase();

  @override
  void dispose() {
    _clientId.dispose();
    _owner.dispose();
    _repo.dispose();
    _branch.dispose();
    _token.dispose();
    super.dispose();
  }

  void _init(SyncUiState s) {
    if (_initialised || !s.loaded) return;
    _initialised = true;
    _clientId.text = s.settings.clientId;
    _owner.text = s.settings.owner;
    _repo.text = s.settings.repo;
    _branch.text = s.settings.branch;
    if (s.settings.authMode == SyncAuthMode.github && s.repos == null) {
      Future.microtask(
        () => ref.read(syncControllerProvider.notifier).loadRepos(),
      );
    }
  }

  void _say(String? msg, {bool error = false}) => setState(() {
    _status = msg;
    _statusError = error;
  });

  Future<void> _open(Uri uri) async {
    final ok = await ref.read(urlOpenerProvider)(uri);
    if (!ok && mounted) {
      _say('Could not open the browser. Visit $uri', error: true);
    }
  }

  Future<void> _signIn() async {
    _say(null);
    final err = await ref
        .read(syncControllerProvider.notifier)
        .startSignIn(clientId: _clientId.text);
    // Errors are shown in the status card at the top.
    if (err != null && mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final err = await ref
        .read(syncControllerProvider.notifier)
        .configure(
          owner: _owner.text,
          repo: _repo.text,
          branch: _branch.text,
          token: _token.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) _token.clear();
    _say(err ?? 'Settings saved.', error: err != null);
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      final info = await ref
          .read(syncControllerProvider.notifier)
          .test(token: _token.text, owner: _owner.text, repo: _repo.text);
      if (!mounted) return;
      final ok = info.canPush && info.isPrivate;
      _say(
        !info.canPush
            ? 'Connected, but this token cannot write to the repository.'
            : info.isPrivate
            ? 'Connected: private repository with write access.'
            : 'Connected, but the repository is PUBLIC. Anyone could read '
                  'your notes.',
        error: !ok,
      );
    } on SyncException catch (e) {
      if (mounted) {
        final usingToken =
            _token.text.trim().isNotEmpty ||
            ref.read(syncControllerProvider).settings.authMode ==
                SyncAuthMode.token;
        _say(
          syncErrorMessage(
            e,
            usingToken ? SyncAuthMode.token : SyncAuthMode.github,
          ),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove GitHub sync?'),
        content: const Text(
          'Signs out and deletes the sync settings from this phone. Your notes '
          'and the GitHub repository are not changed.',
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
    _token.clear();
    _say('GitHub sync removed.');
  }

  Future<void> _setPublic(bool on) async {
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
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncControllerProvider);
    _init(s);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final st = s.settings;
    final ctrl = ref.read(syncControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub sync')),
      body: !s.loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusHeader(state: s, fmt: _fmt),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('sync-now'),
                  onPressed: s.running || !st.enabled || !st.configured
                      ? null
                      : () => ctrl.syncNow(),
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sync now'),
                ),
                if (s.lastReport != null) ...[
                  const SizedBox(height: 12),
                  _Report(report: s.lastReport!),
                ],
                const SizedBox(height: 20),
                _SectionTitle('GitHub account'),
                _account(s, scheme, theme),
                if (st.authMode == SyncAuthMode.github) ...[
                  const SizedBox(height: 20),
                  _SectionTitle('Notes repository'),
                  _repoPicker(s, scheme, theme),
                ],
                const SizedBox(height: 20),
                _SectionTitle('Sync'),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        key: const Key('sync-enabled'),
                        title: const Text('GitHub sync on'),
                        subtitle: Text(
                          st.enabled
                              ? 'Sync is on.'
                              : 'Sync is off. Nothing leaves this phone.',
                        ),
                        value: st.enabled,
                        onChanged: st.configured ? ctrl.setEnabled : null,
                      ),
                      SwitchListTile(
                        key: const Key('sync-auto'),
                        title: const Text('Sync automatically'),
                        subtitle: const Text(
                          'When the app opens, when you come back to it, a few '
                          'seconds after you edit, when you leave, and on a '
                          'timer while it is open.',
                        ),
                        value: st.autoSync,
                        onChanged: ctrl.setAutoSync,
                      ),
                      if (st.autoSync)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Check GitHub every',
                                style: theme.textTheme.bodyMedium,
                              ),
                              for (final m in SyncController.intervals)
                                ChoiceChip(
                                  key: Key('sync-interval-$m'),
                                  label: Text('$m min'),
                                  selected: st.intervalMinutes == m,
                                  onSelected: (_) => ctrl.setInterval(m),
                                ),
                            ],
                          ),
                        ),
                      SwitchListTile(
                        key: const Key('sync-mirror'),
                        title: const Text('Mirror deletions'),
                        subtitle: const Text(
                          'Deleting a note on one side deletes it on the other, '
                          'so both stay identical. Deleted notes stay in note '
                          'history; edits always win over deletions.',
                        ),
                        value: st.mirrorDeletions,
                        onChanged: ctrl.setMirrorDeletions,
                      ),
                      SwitchListTile(
                        key: const Key('sync-allow-public'),
                        title: const Text('Allow a public repository'),
                        subtitle: const Text(
                          'Not recommended for private notes.',
                        ),
                        value: st.allowPublic,
                        onChanged: st.hasRepo ? _setPublic : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: ExpansionTile(
                    key: const Key('sync-advanced'),
                    title: const Text('Use a personal access token instead'),
                    subtitle: const Text('Advanced: no GitHub App needed'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: _tokenForm(s),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    key: const Key('sync-status'),
                    style: TextStyle(
                      color: _statusError ? scheme.error : scheme.primary,
                    ),
                  ),
                ],
                if (st.hasToken || st.hasRepo) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const Key('sync-remove'),
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out and remove sync'),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _account(SyncUiState s, ColorScheme scheme, ThemeData theme) {
    final st = s.settings;
    if (s.pending != null) {
      final p = s.pending!;
      return Card(
        key: const Key('sync-device-code'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter this code on GitHub',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Center(
                child: SelectableText(
                  p.userCode,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 4,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('sync-open-device'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: p.userCode));
                  _open(p.verificationUri);
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Copy code & open GitHub'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Waiting for you to approve on GitHub… After approving, '
                      'just come back to Sapphire.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: ref
                        .read(syncControllerProvider.notifier)
                        .cancelSignIn,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (st.signedIn) {
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.person_rounded, color: scheme.onPrimaryContainer),
          ),
          title: Text(
            st.authMode == SyncAuthMode.github
                ? 'Signed in as @${st.login ?? 'GitHub user'}'
                : 'Using a personal access token',
          ),
          subtitle: Text(
            st.authMode == SyncAuthMode.github
                ? 'Sapphire can only reach repositories the GitHub App is '
                      'installed on.'
                : 'Token saved on this phone (encrypted).',
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign in with GitHub. Sapphire then keeps this notes folder and '
              'your notes repository identical — any AI with access to the '
              'repository can read and update your notes.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('sync-client-id'),
              controller: _clientId,
              decoration: const InputDecoration(
                labelText: 'GitHub App Client ID',
                hintText: 'Iv23li…',
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('sync-signin'),
              onPressed: s.signingIn ? null : _signIn,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in with GitHub'),
            ),
            if (s.message != null) ...[
              const SizedBox(height: 10),
              Text(
                s.message!,
                key: const Key('sync-signin-error'),
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              key: const Key('sync-setup-guide'),
              tilePadding: EdgeInsets.zero,
              initiallyExpanded:
                  bundledGitHubClientId.isEmpty && s.settings.clientId.isEmpty,
              title: const Text('One-time setup (2 minutes)'),
              children: [
                const _Step(
                  n: 1,
                  text:
                      'Create your private Sapphire GitHub App. The page opens '
                      'pre-filled; tick "Enable Device Flow", then press '
                      '"Create GitHub App".',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('sync-create-app'),
                    onPressed: () => _open(gitHubAppCreateUri(_suffix)),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Create the GitHub App'),
                  ),
                ),
                const _Step(
                  n: 2,
                  text:
                      'On the new app page, copy the "Client ID" and paste it '
                      'into the field above.',
                ),
                const _Step(
                  n: 3,
                  text:
                      'Choose "Install App" → your account → "Only select '
                      'repositories" → pick your notes repository.',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        _open(Uri.parse('https://github.com/settings/apps')),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open my GitHub Apps'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _repoPicker(SyncUiState s, ColorScheme scheme, ThemeData theme) {
    final ctrl = ref.read(syncControllerProvider.notifier);
    final st = s.settings;
    final repos = s.repos;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              st.hasRepo ? st.repoName : 'Choose your notes repository',
            ),
            subtitle: Text(
              st.hasRepo
                  ? 'Branch ${st.branch}'
                  : 'Only repositories the Sapphire GitHub App is installed '
                        'on are listed.',
            ),
            trailing: IconButton(
              key: const Key('sync-repos-refresh'),
              tooltip: 'Refresh repositories',
              onPressed: s.loadingRepos ? null : ctrl.loadRepos,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          if (s.loadingRepos) const LinearProgressIndicator(minHeight: 2),
          if (repos != null && repos.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No repositories yet. Install your Sapphire GitHub App on '
                    'the notes repository ("Only select repositories"), then '
                    'refresh.',
                    style: theme.textTheme.bodySmall,
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _open(Uri.parse('https://github.com/settings/apps')),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open my GitHub Apps'),
                  ),
                ],
              ),
            ),
          for (final r in repos ?? const <InstalledRepo>[])
            ListTile(
              key: Key('sync-repo-${r.fullName}'),
              leading: Icon(
                r.isPrivate ? Icons.lock_rounded : Icons.public_rounded,
                color: r.isPrivate ? scheme.primary : scheme.error,
              ),
              title: Text(r.fullName),
              subtitle: Text(r.isPrivate ? 'Private' : 'Public'),
              trailing: st.owner == r.owner && st.repo == r.name
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : null,
              onTap: () => ctrl.selectRepo(r),
            ),
        ],
      ),
    );
  }

  List<Widget> _tokenForm(SyncUiState s) {
    return [
      const Text(
        'Create a fine-grained personal access token on GitHub with access to '
        'only your notes repository and "Contents: Read and write".',
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('sync-owner'),
        controller: _owner,
        decoration: const InputDecoration(labelText: 'Owner'),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('sync-repo'),
        controller: _repo,
        decoration: const InputDecoration(labelText: 'Repository'),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('sync-branch'),
        controller: _branch,
        decoration: const InputDecoration(labelText: 'Branch'),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('sync-token'),
        controller: _token,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: s.settings.authMode == SyncAuthMode.token
              ? 'Token (saved — enter to replace)'
              : 'Token',
          suffixIcon: IconButton(
            tooltip: _obscure ? 'Show token' : 'Hide token',
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('sync-test'),
              onPressed: _busy ? null : _test,
              child: const Text('Test connection'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const Key('sync-save'),
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        letterSpacing: 1.2,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.state, required this.fmt});
  final SyncUiState state;
  final String Function(DateTime) fmt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = state;
    final st = s.settings;
    final String title;
    final String sub;
    if (s.running) {
      title = s.automatic ? 'Syncing automatically…' : 'Syncing…';
      sub = s.total == 0
          ? 'Comparing notes'
          : '${s.done}/${s.total} ${s.current}';
    } else if (!st.configured) {
      title = 'Not connected';
      sub = 'Sign in with GitHub and choose your notes repository.';
    } else if (!st.enabled) {
      title = 'Sync is off.';
      sub = st.repoName;
    } else {
      title = st.repoName;
      sub = s.lastSync == null
          ? 'Not synced yet'
          : 'Last successful sync: ${fmt(s.lastSync!)}';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(sub, style: theme.textTheme.bodySmall),
            if (s.running) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: s.total == 0 ? null : s.done / s.total,
              ),
            ],
            if (s.message != null && !s.running && st.signedIn) ...[
              const SizedBox(height: 10),
              Text(
                s.message!,
                key: const Key('sync-message'),
                style: TextStyle(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.report});
  final SyncReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final theme = Theme.of(context);
    final parts = [
      'Uploaded ${r.uploaded}',
      'Downloaded ${r.downloaded}',
      if (r.deletedLocal > 0) 'Deleted here ${r.deletedLocal}',
      if (r.deletedRemote > 0) 'Deleted on GitHub ${r.deletedRemote}',
      if (r.conflicts.isNotEmpty) 'Conflicts ${r.conflicts.length}',
    ];
    return Card(
      key: const Key('sync-report'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(parts.join(' · '), style: theme.textTheme.titleSmall),
            for (final c in r.conflicts)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  c.copyPath == null
                      ? 'Conflict: ${c.path} — kept this phone\'s version.'
                      : 'Conflict: ${c.path} — GitHub\'s version saved as '
                            '${c.copyPath}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            for (final f in r.failures)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  f,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            for (final n in r.notices)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(n, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
