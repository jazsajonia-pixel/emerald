import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/saf_vault_storage.dart';
import '../ai/ai_config.dart' show secretStoreProvider, SecretStore;
import '../vault/vault_controller.dart';
import 'github_auth.dart';
import 'github_client.dart';
import 'sync_engine.dart';
import 'sync_state_store.dart';

/// Client ID of the GitHub App used for "Sign in with GitHub". It is public
/// (not a secret). CI injects it with
/// `--dart-define=SAPPHIRE_GITHUB_CLIENT_ID=...`; users can also paste their
/// own in the app.
const bundledGitHubClientId = String.fromEnvironment(
  'SAPPHIRE_GITHUB_CLIENT_ID',
);

enum SyncAuthMode { none, github, token }

/// Rough shape check so a Client ID, device code or partial copy is not
/// saved as a token.
bool looksLikeGitHubToken(String t) =>
    RegExp(r'^(github_pat_|ghp_|gho_|ghu_|ghs_)[A-Za-z0-9_]{8,}$').hasMatch(t);

/// Plain-language message for [e], specific to how the user connected.
String syncErrorMessage(SyncException e, SyncAuthMode mode) {
  if (e.code == SyncErrorCode.unauthorized && mode == SyncAuthMode.token) {
    return 'GitHub rejected the token. Make sure you copied the whole token, '
        'that it has not expired, and that it was not revoked. Or use '
        '"Sign in with GitHub" instead.';
  }
  return e.userMessage;
}

class SyncSettings {
  const SyncSettings({
    this.owner = '',
    this.repo = '',
    this.branch = 'main',
    this.hasToken = false,
    this.enabled = false,
    this.allowPublic = false,
    this.authMode = SyncAuthMode.none,
    this.login,
    this.clientId = '',
    this.autoSync = true,
    this.intervalMinutes = 2,
    this.mirrorDeletions = true,
  });

  final String owner;
  final String repo;
  final String branch;
  final bool hasToken;

  /// Sync is off unless the user turns it on.
  final bool enabled;

  /// The user explicitly accepted syncing notes to a public repository.
  final bool allowPublic;

  /// How Sapphire talks to GitHub: signed in with GitHub (OAuth device flow)
  /// or with a pasted personal access token.
  final SyncAuthMode authMode;

  /// GitHub username when signed in.
  final String? login;

  /// GitHub App client ID used for sign-in.
  final String clientId;

  /// Sync automatically (on open, on return, after edits, periodically).
  final bool autoSync;
  final int intervalMinutes;

  /// Deleting a note on one side deletes it on the other side.
  final bool mirrorDeletions;

  bool get signedIn => authMode != SyncAuthMode.none && hasToken;
  bool get hasRepo => owner.isNotEmpty && repo.isNotEmpty && branch.isNotEmpty;
  bool get configured => hasRepo && hasToken;
  String get repoName => '$owner/$repo';
}

/// A sign-in in progress: the code the user must enter on github.com.
class PendingSignIn {
  const PendingSignIn({required this.userCode, required this.verificationUri});
  final String userCode;
  final Uri verificationUri;
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
    this.pending,
    this.signingIn = false,
    this.repos,
    this.loadingRepos = false,
    this.automatic = false,
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

  final PendingSignIn? pending;
  final bool signingIn;

  /// Repositories the signed-in account lets Sapphire use.
  final List<InstalledRepo>? repos;
  final bool loadingRepos;

  /// The running (or last) sync was started automatically.
  final bool automatic;

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
    PendingSignIn? pending,
    bool clearPending = false,
    bool? signingIn,
    List<InstalledRepo>? repos,
    bool clearRepos = false,
    bool? loadingRepos,
    bool? automatic,
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
    pending: clearPending ? null : (pending ?? this.pending),
    signingIn: signingIn ?? this.signingIn,
    repos: clearRepos ? null : (repos ?? this.repos),
    loadingRepos: loadingRepos ?? this.loadingRepos,
    automatic: automatic ?? this.automatic,
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

typedef GitHubAuthFactory = GitHubAuth Function(String clientId);

final gitHubAuthFactoryProvider = Provider<GitHubAuthFactory>(
  (ref) =>
      (clientId) => GitHubAuth(clientId: clientId),
);

/// Whether automatic sync timers may run. Tests switch it off so syncs only
/// happen when a test asks for them.
final autoSyncRuntimeProvider = Provider<bool>((ref) => true);

final syncControllerProvider = NotifierProvider<SyncController, SyncUiState>(
  SyncController.new,
);

class SyncController extends Notifier<SyncUiState> {
  static const _kOwner = 'sync.github.owner';
  static const _kRepo = 'sync.github.repo';
  static const _kBranch = 'sync.github.branch';
  static const _kToken = 'sync.github.token';
  static const _kOAuth = 'sync.github.oauth';
  static const _kClientId = 'sync.github.clientId';
  static const _kLogin = 'sync.github.login';
  static const _kEnabled = 'sync.github.enabled';
  static const _kPublic = 'sync.github.allowPublic';
  static const _kAuto = 'sync.auto';
  static const _kInterval = 'sync.auto.minutes';
  static const _kMirror = 'sync.mirrorDeletions';

  static const intervals = [1, 2, 5, 15, 30];

  SecretStore get _store => ref.read(secretStoreProvider);

  Timer? _periodic;
  Timer? _debounce;
  bool _foreground = true;
  int _signInRun = 0;

  /// Completes to cut the wait between sign-in polls short (app resumed).
  Completer<void>? _pollWake;
  Timer? _pollTimer;

  Future<void> _pollSleep(Duration d) {
    final wake = _pollWake = Completer<void>();
    _pollTimer?.cancel();
    _pollTimer = Timer(d, _wakePoll);
    return wake.future;
  }

  /// Ends the current wait between sign-in polls now.
  void _wakePoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final w = _pollWake;
    if (w != null && !w.isCompleted) w.complete();
  }

  DateTime? _lastAuto;

  @override
  SyncUiState build() {
    ref.onDispose(() {
      _periodic?.cancel();
      _debounce?.cancel();
      _signInRun++;
      _wakePoll();
    });
    ref.listen(localEditsProvider, (_, _) => localChanged());
    ref.listen(vaultControllerProvider, (prev, next) {
      if (next is VaultReady && prev is! VaultReady) {
        Future.microtask(() async {
          await _loadLastSync();
          autoSync();
        });
      }
    });
    Future.microtask(_load);
    return const SyncUiState();
  }

  Future<SyncSettings> _readSettings() async {
    final pat = await _store.read(_kToken);
    final oauth = GitHubTokens.fromJson(await _store.read(_kOAuth));
    final mode = oauth != null
        ? SyncAuthMode.github
        : (pat != null && pat.isNotEmpty)
        ? SyncAuthMode.token
        : SyncAuthMode.none;
    final minutes = int.tryParse(await _store.read(_kInterval) ?? '') ?? 2;
    return SyncSettings(
      owner: await _store.read(_kOwner) ?? '',
      repo: await _store.read(_kRepo) ?? '',
      branch: await _store.read(_kBranch) ?? 'main',
      hasToken: mode != SyncAuthMode.none,
      enabled: await _store.read(_kEnabled) == 'yes',
      allowPublic: await _store.read(_kPublic) == 'yes',
      authMode: mode,
      login: await _store.read(_kLogin),
      clientId: await _store.read(_kClientId) ?? bundledGitHubClientId,
      autoSync: await _store.read(_kAuto) != 'no',
      intervalMinutes: intervals.contains(minutes) ? minutes : 2,
      mirrorDeletions: await _store.read(_kMirror) != 'no',
    );
  }

  Future<void> _refreshSettings() async {
    final s = await _readSettings();
    if (!ref.mounted) return;
    state = state.copyWith(settings: s);
    _schedule();
  }

  Future<void> _load() async {
    final s = await _readSettings();
    if (!ref.mounted) return;
    state = state.copyWith(loaded: true, settings: s);
    await _loadLastSync();
    _schedule();
    autoSync();
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

  // ---- Sign in with GitHub (device flow) ---------------------------------

  /// Starts sign-in and waits in the background until the user entered the
  /// code on github.com. Returns an error message or null.
  Future<String?> startSignIn({String? clientId}) async {
    final id = (clientId ?? state.settings.clientId).trim();
    if (!GitHubAuth.validClientId(id)) {
      const msg = 'Paste the Client ID of your Sapphire GitHub App first.';
      state = state.copyWith(message: msg);
      return msg;
    }
    await _store.write(_kClientId, id);
    final run = ++_signInRun;
    state = state.copyWith(
      signingIn: true,
      clearPending: true,
      clearMessage: true,
      settings: await _readSettings(),
    );
    final auth = ref.read(gitHubAuthFactoryProvider)(id);
    try {
      final code = await auth.start();
      if (run != _signInRun || !ref.mounted) return null;
      state = state.copyWith(
        pending: PendingSignIn(
          userCode: code.userCode,
          verificationUri: code.verificationUri,
        ),
      );
      final tokens = await auth.waitForToken(
        code,
        isCancelled: () => run != _signInRun || !ref.mounted,
        sleep: _pollSleep,
      );
      if (tokens == null || run != _signInRun || !ref.mounted) return null;
      // Save the sign-in first: the app may still be in the background with
      // no network, and the username can be fetched later.
      await _store.write(_kOAuth, jsonEncode(tokens.toJson()));
      await _store.delete(_kToken);
      await _fetchLogin(auth, tokens.accessToken);
      if (!ref.mounted) return null;
      state = state.copyWith(
        signingIn: false,
        clearPending: true,
        settings: await _readSettings(),
      );
      await loadRepos();
      return null;
    } on AuthException catch (e) {
      return _signInFailed(run, e.userMessage);
    } on SyncException catch (e) {
      return _signInFailed(run, e.userMessage);
    }
  }

  Future<void> _fetchLogin(GitHubAuth auth, String token) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _store.write(_kLogin, await auth.login(token));
        return;
      } on SyncException catch (e) {
        if (e.code != SyncErrorCode.network &&
            e.code != SyncErrorCode.timeout) {
          return;
        }
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
  }

  String? _signInFailed(int run, String message) {
    if (run != _signInRun || !ref.mounted) return null;
    state = state.copyWith(
      signingIn: false,
      clearPending: true,
      message: message,
    );
    return message;
  }

  void cancelSignIn() {
    _signInRun++;
    _wakePoll();
    state = state.copyWith(signingIn: false, clearPending: true);
  }

  /// Lists the repositories the GitHub App is installed on.
  Future<void> loadRepos() async {
    final s = state.settings;
    if (s.authMode != SyncAuthMode.github) return;
    state = state.copyWith(loadingRepos: true, clearMessage: true);
    try {
      final token = await _accessToken();
      final repos = await ref
          .read(gitHubAuthFactoryProvider)(s.clientId)
          .repositories(token);
      if (!ref.mounted) return;
      state = state.copyWith(loadingRepos: false, repos: repos);
    } on SyncException catch (e) {
      if (ref.mounted) {
        state = state.copyWith(loadingRepos: false, message: e.userMessage);
      }
    } on AuthException catch (e) {
      if (ref.mounted) {
        state = state.copyWith(loadingRepos: false, message: e.userMessage);
      }
    }
  }

  /// Uses [r] as the notes repository and turns automatic sync on.
  Future<void> selectRepo(InstalledRepo r) async {
    final old = state.settings;
    await _store.write(_kOwner, r.owner);
    await _store.write(_kRepo, r.name);
    await _store.write(_kBranch, r.defaultBranch);
    await _store.write(_kEnabled, 'yes');
    if (old.owner != r.owner || old.repo != r.name) {
      await _store.delete(_kPublic);
    }
    state = state.copyWith(clearMessage: true, settings: await _readSettings());
    await _loadLastSync();
    _schedule();
    unawaited(syncNow(automatic: true));
  }

  /// Returns a valid access token, refreshing an expiring sign-in token.
  Future<String> _accessToken() async {
    final oauth = GitHubTokens.fromJson(await _store.read(_kOAuth));
    if (oauth == null) {
      final pat = await _store.read(_kToken);
      if (pat == null || pat.isEmpty) {
        throw SyncException(SyncErrorCode.notConfigured);
      }
      return pat;
    }
    final now = DateTime.now();
    if (!oauth.needsRefresh(now)) return oauth.accessToken;
    if (!oauth.canRefresh(now)) {
      throw SyncException(SyncErrorCode.unauthorized, 'sign-in expired');
    }
    try {
      final fresh = await ref
          .read(gitHubAuthFactoryProvider)(state.settings.clientId)
          .refresh(oauth.refreshToken!);
      await _store.write(_kOAuth, jsonEncode(fresh.toJson()));
      return fresh.accessToken;
    } on AuthException catch (e) {
      if (e.code == AuthErrorCode.network) {
        throw SyncException(SyncErrorCode.network);
      }
      throw SyncException(SyncErrorCode.unauthorized, 'refresh failed');
    }
  }

  // ---- Personal access token (advanced) ----------------------------------

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
    final t = token?.trim() ?? '';
    if (t.isNotEmpty && !looksLikeGitHubToken(t)) {
      return 'That does not look like a GitHub token. Fine-grained tokens '
          'start with "github_pat_" (classic ones with "ghp_"). Copy the whole '
          'token from GitHub → Settings → Developer settings → Personal access '
          'tokens.';
    }
    final old = state.settings;
    await _store.write(_kOwner, owner);
    await _store.write(_kRepo, repo);
    await _store.write(_kBranch, branch);
    if (token != null && token.trim().isNotEmpty) {
      await _store.write(_kToken, token.trim());
      await _store.delete(_kOAuth);
      await _store.delete(_kLogin);
    }
    if (old.owner != owner || old.repo != repo) await _store.delete(_kPublic);
    state = state.copyWith(settings: await _readSettings(), clearMessage: true);
    await _loadLastSync();
    _schedule();
    return null;
  }

  Future<void> _flag(String key, bool on, {bool defaultOn = false}) async {
    if (defaultOn) {
      on ? await _store.delete(key) : await _store.write(key, 'no');
    } else {
      on ? await _store.write(key, 'yes') : await _store.delete(key);
    }
    await _refreshSettings();
  }

  Future<void> setEnabled(bool on) => _flag(_kEnabled, on);
  Future<void> setAllowPublic(bool on) => _flag(_kPublic, on);
  Future<void> setAutoSync(bool on) => _flag(_kAuto, on, defaultOn: true);
  Future<void> setMirrorDeletions(bool on) =>
      _flag(_kMirror, on, defaultOn: true);

  Future<void> setInterval(int minutes) async {
    if (!intervals.contains(minutes)) return;
    await _store.write(_kInterval, '$minutes');
    await _refreshSettings();
  }

  /// Signs out, deletes tokens and settings and forgets sync history for
  /// this vault. Notes and the GitHub repository are not touched.
  Future<void> remove() async {
    _signInRun++;
    final scope = _scope(state.settings);
    if (scope != null) await ref.read(syncStateStoreProvider).clear(scope);
    for (final k in [
      _kOwner,
      _kRepo,
      _kBranch,
      _kToken,
      _kOAuth,
      _kLogin,
      _kEnabled,
      _kPublic,
    ]) {
      await _store.delete(k);
    }
    _periodic?.cancel();
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
        : await _accessToken();
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

  // ---- Automatic sync ------------------------------------------------------

  bool get _autoReady {
    final s = state.settings;
    return ref.read(autoSyncRuntimeProvider) &&
        s.enabled &&
        s.configured &&
        s.autoSync;
  }

  void _schedule() {
    _periodic?.cancel();
    _periodic = null;
    if (!_autoReady || !_foreground) return;
    _periodic = Timer.periodic(
      Duration(minutes: state.settings.intervalMinutes),
      (_) => autoSync(),
    );
  }

  /// The app came to the foreground (or started): sync and resume the timer.
  void appResumed() {
    _foreground = true;
    _wakePoll();
    final st = state.settings;
    if (st.authMode == SyncAuthMode.github && !state.signingIn) {
      if (st.login == null) {
        Future.microtask(() async {
          try {
            await _fetchLogin(
              ref.read(gitHubAuthFactoryProvider)(st.clientId),
              await _accessToken(),
            );
            await _refreshSettings();
          } on Object {
            // Shown on the next sync attempt.
          }
        });
      }
      if (state.repos == null || state.message != null) {
        Future.microtask(loadRepos);
      }
    }
    _schedule();
    autoSync(minGap: const Duration(seconds: 20));
  }

  /// The app went to the background: push pending edits, stop the timer.
  void appPaused() {
    _foreground = false;
    _periodic?.cancel();
    _periodic = null;
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      autoSync();
    } else {
      autoSync(minGap: const Duration(seconds: 30));
    }
  }

  /// A note was saved on this phone: sync a few seconds later (debounced).
  void localChanged() {
    if (!_autoReady) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 6), autoSync);
  }

  /// Runs a quiet sync if automatic sync is on.
  void autoSync({Duration minGap = Duration.zero}) {
    if (!_autoReady || state.running) return;
    final now = DateTime.now();
    if (_lastAuto != null && now.difference(_lastAuto!) < minGap) return;
    if (ref.read(vaultControllerProvider) is! VaultReady) return;
    _lastAuto = now;
    unawaited(syncNow(automatic: true));
  }

  Future<SyncReport?> syncNow({bool automatic = false}) async {
    final s = state.settings;
    if (state.running) return null;
    if (!s.enabled || !s.configured) {
      if (!automatic) {
        state = state.copyWith(
          message: 'Connect GitHub and choose your notes repository first.',
        );
      }
      return null;
    }
    final v = ref.read(vaultControllerProvider);
    if (v is! VaultReady) {
      if (!automatic) state = state.copyWith(message: 'Open a vault first.');
      return null;
    }
    state = state.copyWith(
      running: true,
      automatic: automatic,
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
        mirrorDeletions: s.mirrorDeletions,
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
        state = state.copyWith(
          running: false,
          message: syncErrorMessage(e, s.authMode),
        );
      }
      return null;
    }
  }
}
