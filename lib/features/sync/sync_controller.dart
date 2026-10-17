import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/saf_vault_storage.dart';
import '../ai/ai_config.dart' show secretStoreProvider, SecretStore;
import '../vault/vault_controller.dart';
import 'github_client.dart';
import 'remote_proposals.dart';
import 'sync_engine.dart';
import 'sync_state_store.dart';

class SyncSettings {
  const SyncSettings({
    this.owner = '',
    this.repo = '',
    this.branch = 'main',
    this.hasToken = false,
    this.enabled = false,
    this.allowPublic = false,
  });

  final String owner;
  final String repo;
  final String branch;
  final bool hasToken;

  /// Sync is off unless the user turns it on.
  final bool enabled;

  /// The user explicitly accepted syncing notes to a public repository.
  final bool allowPublic;

  bool get configured =>
      owner.isNotEmpty && repo.isNotEmpty && branch.isNotEmpty && hasToken;
}

class SyncUiState {
  const SyncUiState({
    this.loaded = false,
    this.settings = const SyncSettings(),
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.current = '',
    this.lastReport,
    this.lastSync,
    this.message,
  });

  final bool loaded;
  final SyncSettings settings;
  final bool running;
  final int done;
  final int total;
  final String current;
  final SyncReport? lastReport;
  final DateTime? lastSync;

  /// A plain-language problem that stopped the last action (not a report).
  final String? message;

  SyncUiState copyWith({
    bool? loaded,
    SyncSettings? settings,
    bool? running,
    int? done,
    int? total,
    String? current,
    SyncReport? lastReport,
    DateTime? lastSync,
    String? message,
    bool clearMessage = false,
  }) => SyncUiState(
    loaded: loaded ?? this.loaded,
    settings: settings ?? this.settings,
    running: running ?? this.running,
    done: done ?? this.done,
    total: total ?? this.total,
    current: current ?? this.current,
    lastReport: lastReport ?? this.lastReport,
    lastSync: lastSync ?? this.lastSync,
    message: clearMessage ? null : (message ?? this.message),
  );
}

final syncStateStoreProvider = Provider<SyncStateStore>((ref) {
  final storage = ref.watch(vaultStorageProvider);
  if (storage is! SafVaultStorage) return MemorySyncStateStore();
  return FileSyncStateStore(() async => Directory(await storage.appFilesDir()));
});

typedef GitHubClientFactory = GitHubClient Function(
  String token,
  String owner,
  String repo,
);

final gitHubClientFactoryProvider = Provider<GitHubClientFactory>(
  (ref) =>
      (token, owner, repo) =>
          GitHubClient(token: token, owner: owner, repo: repo),
);

final syncControllerProvider = NotifierProvider<SyncController, SyncUiState>(
  SyncController.new,
);

class SyncController extends Notifier<SyncUiState> {
  static const _kOwner = 'sync.github.owner';
  static const _kRepo = 'sync.github.repo';
  static const _kBranch = 'sync.github.branch';
  static const _kToken = 'sync.github.token';
  static const _kEnabled = 'sync.github.enabled';
  static const _kPublic = 'sync.github.allowPublic';

  SecretStore get _store => ref.read(secretStoreProvider);

  @override
  SyncUiState build() {
    Future.microtask(_load);
    return const SyncUiState();
  }

  Future<SyncSettings> _readSettings() async {
    final token = await _store.read(_kToken);
    return SyncSettings(
      owner: await _store.read(_kOwner) ?? '',
      repo: await _store.read(_kRepo) ?? '',
      branch: await _store.read(_kBranch) ?? 'main',
      hasToken: token != null && token.isNotEmpty,
      enabled: await _store.read(_kEnabled) == 'yes',
      allowPublic: await _store.read(_kPublic) == 'yes',
    );
  }

  Future<void> _load() async {
    final s = await _readSettings();
    if (!ref.mounted) return;
    state = state.copyWith(loaded: true, settings: s);
    await _loadLastSync();
  }

  String? _scope(SyncSettings s) {
    final v = ref.read(vaultControllerProvider);
    if (v is! VaultReady) return null;
    return '${v.vault.id}|${s.owner}/${s.repo}@${s.branch}';
  }

  Future<void> _loadLastSync() async {
    final scope = _scope(state.settings);
    if (scope == null) return;
    final base = await ref.read(syncStateStoreProvider).load(scope);
    if (ref.mounted && base.lastSync != null) {
      state = state.copyWith(lastSync: base.lastSync);
    }
  }

  /// Validates and stores settings. Returns an error message or null.
  Future<String?> configure({
    required String owner,
    required String repo,
    required String branch,
    String? token,
  }) async {
    owner = owner.trim();
    repo = repo.trim();
    branch = branch.trim();
    if (!GitHubClient.validName(owner) || !GitHubClient.validName(repo)) {
      return 'Enter the repository owner and name, e.g. octocat / notes.';
    }
    if (!GitHubClient.validBranch(branch)) return 'Enter a valid branch name.';
    final hasToken =
        (token?.trim().isNotEmpty ?? false) || state.settings.hasToken;
    if (!hasToken) return 'Enter a token first.';
    final old = state.settings;
    await _store.write(_kOwner, owner);
    await _store.write(_kRepo, repo);
    await _store.write(_kBranch, branch);
    if (token != null && token.trim().isNotEmpty) {
      await _store.write(_kToken, token.trim());
    }
    if (old.owner != owner || old.repo != repo) await _store.delete(_kPublic);
    state = state.copyWith(settings: await _readSettings(), clearMessage: true);
    await _loadLastSync();
    return null;
  }

  Future<void> setEnabled(bool on) async {
    if (on) {
      await _store.write(_kEnabled, 'yes');
    } else {
      await _store.delete(_kEnabled);
    }
    state = state.copyWith(settings: await _readSettings());
  }

  Future<void> setAllowPublic(bool on) async {
    if (on) {
      await _store.write(_kPublic, 'yes');
    } else {
      await _store.delete(_kPublic);
    }
    state = state.copyWith(settings: await _readSettings());
  }

  /// Deletes the token and settings and forgets sync history for this vault.
  /// Notes and the GitHub repository are not touched.
  Future<void> remove() async {
    final scope = _scope(state.settings);
    if (scope != null) await ref.read(syncStateStoreProvider).clear(scope);
    for (final k in [_kOwner, _kRepo, _kBranch, _kToken, _kEnabled, _kPublic]) {
      await _store.delete(k);
    }
    state = SyncUiState(loaded: true, settings: await _readSettings());
  }

  Future<GitHubClient> _client({
    String? tokenOverride,
    String? owner,
    String? repo,
  }) async {
    final s = state.settings;
    final token = (tokenOverride?.trim().isNotEmpty ?? false)
        ? tokenOverride!.trim()
        : await _store.read(_kToken);
    if (token == null || token.isEmpty) {
      throw SyncException(SyncErrorCode.notConfigured);
    }
    return ref.read(gitHubClientFactoryProvider)(
      token,
      owner ?? s.owner,
      repo ?? s.repo,
    );
  }

  /// Checks access without changing anything.
  Future<RemoteRepo> test({
    String? token,
    required String owner,
    required String repo,
  }) async {
    final c = await _client(
      tokenOverride: token,
      owner: owner.trim(),
      repo: repo.trim(),
    );
    return c.getRepo();
  }

  /// Inbox of AI proposals written by the optional MCP server. Requires
  /// sync to be on and configured and a vault to be open.
  Future<RemoteProposalInbox> proposalInbox() async {
    final s = state.settings;
    final v = ref.read(vaultControllerProvider);
    if (!s.enabled || !s.configured || v is! VaultReady) {
      throw SyncException(SyncErrorCode.notConfigured);
    }
    return RemoteProposalInbox(
      client: await _client(),
      branch: s.branch,
      vault: v.vault,
      storage: ref.read(vaultStorageProvider),
      repository: ref.read(noteRepositoryProvider),
    );
  }

  Future<SyncReport?> syncNow() async {
    final s = state.settings;
    if (state.running) return null;
    if (!s.enabled || !s.configured) {
      state = state.copyWith(
        message: 'Turn on GitHub sync and complete the settings first.',
      );
      return null;
    }
    final v = ref.read(vaultControllerProvider);
    if (v is! VaultReady) {
      state = state.copyWith(message: 'Open a vault first.');
      return null;
    }
    state = state.copyWith(
      running: true,
      done: 0,
      total: 0,
      current: '',
      clearMessage: true,
    );
    final scope = _scope(s)!;
    final store = ref.read(syncStateStoreProvider);
    try {
      final client = await _client();
      final info = await client.getRepo();
      if (!info.canPush) throw SyncException(SyncErrorCode.forbidden);
      if (!info.isPrivate && !s.allowPublic) {
        state = state.copyWith(
          running: false,
          message:
              'This repository is PUBLIC: anyone could read your notes. Make it '
              'private on GitHub, or explicitly allow public sync in settings.',
        );
        return null;
      }
      final base = await store.load(scope);
      final engine = SyncEngine(
        vault: v.vault,
        storage: ref.read(vaultStorageProvider),
        history: ref.read(noteHistoryProvider),
        client: client,
        branch: s.branch,
      );
      final report = await engine.run(
        base,
        onProgress: (d, t, p) {
          if (ref.mounted) {
            state = state.copyWith(done: d, total: t, current: p);
          }
        },
      );
      await store.save(scope, base);
      if (!ref.mounted) return report;
      state = state.copyWith(
        running: false,
        lastReport: report,
        lastSync: base.lastSync,
        message: report.fatal?.userMessage,
      );
      if (report.changedLocalFiles) {
        await ref.read(vaultControllerProvider.notifier).rescan();
      }
      return report;
    } on SyncException catch (e) {
      if (ref.mounted) {
        state = state.copyWith(running: false, message: e.userMessage);
      }
      return null;
    }
  }
}
