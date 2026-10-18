import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'github_client.dart';

/// Sign-in with GitHub using the OAuth **device flow**.
///
/// Why device flow: it needs only the public client ID of a GitHub App, never
/// a client secret, so nothing sensitive ships inside the APK. The user types
/// a short code on github.com, and GitHub returns a user access token that
/// can only reach the repositories the GitHub App is installed on — so
/// installing the app on just the notes repository limits Sapphire to it.
///
/// Endpoints (docs.github.com, "Generating a user access token for a GitHub
/// App" and "Refreshing user access tokens"):
/// - `POST https://github.com/login/device/code`        client_id
/// - `POST https://github.com/login/oauth/access_token` client_id,
///    device_code, grant_type=urn:ietf:params:oauth:grant-type:device_code
/// - refresh: same endpoint, grant_type=refresh_token (no client_secret is
///    needed for tokens created with the device flow)
/// - `GET /user`, `GET /user/installations`,
///   `GET /user/installations/{id}/repositories`
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresAt,
  });

  final String deviceCode;

  /// The short code the user enters on github.com (e.g. "WDJB-MJHT").
  final String userCode;
  final Uri verificationUri;
  final Duration interval;
  final DateTime expiresAt;
}

class GitHubTokens {
  const GitHubTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.refreshExpiresAt,
  });

  final String accessToken;
  final String? refreshToken;

  /// Null when the token does not expire.
  final DateTime? expiresAt;
  final DateTime? refreshExpiresAt;

  /// True when the access token expires within [margin].
  bool needsRefresh(
    DateTime now, {
    Duration margin = const Duration(minutes: 5),
  }) => expiresAt != null && now.add(margin).isAfter(expiresAt!);

  bool canRefresh(DateTime now) =>
      refreshToken != null &&
      (refreshExpiresAt == null || now.isBefore(refreshExpiresAt!));

  Map<String, Object?> toJson() => {
    'access': accessToken,
    'refresh': refreshToken,
    'expires': expiresAt?.toUtc().toIso8601String(),
    'refreshExpires': refreshExpiresAt?.toUtc().toIso8601String(),
  };

  static GitHubTokens? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      final access = j['access'];
      if (access is! String || access.isEmpty) return null;
      DateTime? d(Object? v) => v is String ? DateTime.tryParse(v) : null;
      return GitHubTokens(
        accessToken: access,
        refreshToken: j['refresh'] as String?,
        expiresAt: d(j['expires']),
        refreshExpiresAt: d(j['refreshExpires']),
      );
    } on Object {
      return null;
    }
  }

  static GitHubTokens fromResponse(Map<String, Object?> j, DateTime now) {
    int? secs(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    final exp = secs(j['expires_in']);
    final rexp = secs(j['refresh_token_expires_in']);
    return GitHubTokens(
      accessToken: j['access_token']! as String,
      refreshToken: j['refresh_token'] as String?,
      expiresAt: exp == null || exp <= 0
          ? null
          : now.add(Duration(seconds: exp)),
      refreshExpiresAt: rexp == null || rexp <= 0
          ? null
          : now.add(Duration(seconds: rexp)),
    );
  }
}

class InstalledRepo {
  const InstalledRepo({
    required this.owner,
    required this.name,
    required this.isPrivate,
    required this.defaultBranch,
  });
  final String owner;
  final String name;
  final bool isPrivate;
  final String defaultBranch;
  String get fullName => '$owner/$name';
}

enum AuthErrorCode {
  /// The user pressed "Cancel" on github.com.
  denied,

  /// The code expired before it was entered.
  expired,

  /// Device flow is not switched on for this GitHub App.
  deviceFlowDisabled,

  /// The client ID is wrong.
  badClient,
  network,
  invalidResponse,
}

class AuthException implements Exception {
  AuthException(this.code, [this.detail]);
  final AuthErrorCode code;
  final String? detail;

  String get userMessage => switch (code) {
    AuthErrorCode.denied => 'Sign-in was cancelled on GitHub.',
    AuthErrorCode.expired => 'The code expired. Start the sign-in again.',
    AuthErrorCode.deviceFlowDisabled =>
      'Device flow is off for this GitHub App. Open the app settings on '
          'GitHub, tick "Enable Device Flow" and save.',
    AuthErrorCode.badClient =>
      'GitHub does not know this Client ID. Copy it again from the '
          'GitHub App settings page.',
    AuthErrorCode.network => 'No connection to GitHub.',
    AuthErrorCode.invalidResponse => 'GitHub sent an unexpected answer.',
  };

  @override
  String toString() => 'AuthException(${code.name})';
}

class GitHubAuth {
  GitHubAuth({
    required this.clientId,
    http.Client? client,
    Uri? webBase,
    Uri? apiBase,
    this.timeout = const Duration(seconds: 30),
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
  }) : _client = client ?? http.Client(),
       _web = webBase ?? Uri.parse('https://github.com/'),
       _api = apiBase ?? GitHubClient.defaultApi,
       _now = clock ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed;

  final String clientId;
  final http.Client _client;
  final Uri _web;
  final Uri _api;
  final Duration timeout;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  static bool validClientId(String id) =>
      RegExp(r'^[A-Za-z0-9._\-]{8,64}$').hasMatch(id.trim());

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, String> body,
  ) async {
    http.Response res;
    try {
      res = await _client
          .post(
            _web.resolve(path),
            headers: {'accept': 'application/json'},
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AuthException(AuthErrorCode.network);
    } on SocketException {
      throw AuthException(AuthErrorCode.network);
    } on http.ClientException {
      throw AuthException(AuthErrorCode.network);
    }
    Object? j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      j = null;
    }
    if (j is! Map<String, Object?>) {
      if (res.statusCode == 404) throw AuthException(AuthErrorCode.badClient);
      throw AuthException(
        AuthErrorCode.invalidResponse,
        'HTTP ${res.statusCode}',
      );
    }
    return j;
  }

  static Never _raise(String error) => throw AuthException(switch (error) {
    'access_denied' => AuthErrorCode.denied,
    'expired_token' || 'token_expired' => AuthErrorCode.expired,
    'device_flow_disabled' => AuthErrorCode.deviceFlowDisabled,
    'incorrect_client_credentials' ||
    'unauthorized_client' => AuthErrorCode.badClient,
    _ => AuthErrorCode.invalidResponse,
  }, error);

  /// Step 1: asks GitHub for a user code to show.
  Future<DeviceCode> start() async {
    final j = await _post('login/device/code', {'client_id': clientId.trim()});
    final err = j['error'];
    if (err is String) _raise(err);
    final device = j['device_code'], user = j['user_code'];
    if (device is! String || user is! String) {
      throw AuthException(AuthErrorCode.invalidResponse);
    }
    final interval = (j['interval'] as num?)?.toInt() ?? 5;
    final expires = (j['expires_in'] as num?)?.toInt() ?? 900;
    return DeviceCode(
      deviceCode: device,
      userCode: user,
      verificationUri: Uri.parse(
        (j['verification_uri'] as String?) ?? 'https://github.com/login/device',
      ),
      interval: Duration(seconds: interval < 1 ? 5 : interval),
      expiresAt: _now().add(Duration(seconds: expires)),
    );
  }

  /// Step 2: polls until the user approved the code. [isCancelled] stops
  /// polling quietly (returns null).
  Future<GitHubTokens?> waitForToken(
    DeviceCode code, {
    bool Function()? isCancelled,
  }) async {
    var interval = code.interval;
    while (true) {
      await _sleep(interval);
      if (isCancelled?.call() ?? false) return null;
      if (_now().isAfter(code.expiresAt)) {
        throw AuthException(AuthErrorCode.expired);
      }
      final j = await _post('login/oauth/access_token', {
        'client_id': clientId.trim(),
        'device_code': code.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      if (isCancelled?.call() ?? false) return null;
      final err = j['error'];
      if (err == 'authorization_pending') continue;
      if (err == 'slow_down') {
        final next = (j['interval'] as num?)?.toInt();
        interval = next != null
            ? Duration(seconds: next)
            : interval + const Duration(seconds: 5);
        continue;
      }
      if (err is String) _raise(err);
      if (j['access_token'] is! String) {
        throw AuthException(AuthErrorCode.invalidResponse);
      }
      return GitHubTokens.fromResponse(j, _now());
    }
  }

  /// Exchanges a refresh token for a new token pair.
  Future<GitHubTokens> refresh(String refreshToken) async {
    final j = await _post('login/oauth/access_token', {
      'client_id': clientId.trim(),
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });
    final err = j['error'];
    if (err is String) {
      // A rejected refresh token means the user has to sign in again.
      throw AuthException(
        err == 'bad_refresh_token'
            ? AuthErrorCode.expired
            : AuthErrorCode.denied,
        err,
      );
    }
    if (j['access_token'] is! String) {
      throw AuthException(AuthErrorCode.invalidResponse);
    }
    return GitHubTokens.fromResponse(j, _now());
  }

  Map<String, String> _headers(String token) => {
    'authorization': 'Bearer $token',
    'accept': 'application/vnd.github+json',
    'x-github-api-version': GitHubClient.apiVersion,
  };

  Future<Object?> _get(
    String token,
    List<String> path, [
    Map<String, String>? q,
  ]) async {
    final uri = _api.replace(
      pathSegments: [..._api.pathSegments.where((s) => s.isNotEmpty), ...path],
      queryParameters: q,
    );
    http.Response res;
    try {
      res = await _client.get(uri, headers: _headers(token)).timeout(timeout);
    } on TimeoutException {
      throw SyncException(SyncErrorCode.timeout);
    } on SocketException {
      throw SyncException(SyncErrorCode.network);
    } on http.ClientException {
      throw SyncException(SyncErrorCode.network);
    }
    final s = res.statusCode;
    if (s == 401) throw SyncException(SyncErrorCode.unauthorized);
    if (s == 403) throw SyncException(SyncErrorCode.forbidden);
    if (s == 404) throw SyncException(SyncErrorCode.notFound);
    if (s >= 500) throw SyncException(SyncErrorCode.server);
    if (s < 200 || s >= 300) throw SyncException(SyncErrorCode.invalidResponse);
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw SyncException(SyncErrorCode.invalidResponse);
    }
  }

  /// The signed-in GitHub username.
  Future<String> login(String token) async {
    final j = await _get(token, const ['user']);
    final login = j is Map ? j['login'] : null;
    if (login is! String) throw SyncException(SyncErrorCode.invalidResponse);
    return login;
  }

  static InstalledRepo? _repo(Object? r) {
    if (r is! Map) return null;
    final owner = r['owner'];
    final login = owner is Map ? owner['login'] : null;
    final name = r['name'];
    if (login is! String || name is! String) return null;
    return InstalledRepo(
      owner: login,
      name: name,
      isPrivate: r['private'] == true,
      defaultBranch: (r['default_branch'] as String?) ?? 'main',
    );
  }

  /// Repositories this token can use: those the GitHub App is installed on.
  /// For classic OAuth-app tokens (no installations) it falls back to the
  /// user's own repositories.
  Future<List<InstalledRepo>> repositories(String token) async {
    final out = <InstalledRepo>[];
    try {
      final inst = await _get(
        token,
        const ['user', 'installations'],
        {'per_page': '100'},
      );
      final list = inst is Map ? inst['installations'] : null;
      if (list is List) {
        for (final i in list) {
          final id = i is Map ? i['id'] : null;
          if (id is! num) continue;
          final repos = await _get(
            token,
            ['user', 'installations', '${id.toInt()}', 'repositories'],
            {'per_page': '100'},
          );
          final rl = repos is Map ? repos['repositories'] : null;
          if (rl is List) out.addAll(rl.map(_repo).nonNulls);
        }
        return _sorted(out);
      }
    } on SyncException catch (e) {
      if (e.code != SyncErrorCode.forbidden &&
          e.code != SyncErrorCode.notFound) {
        rethrow;
      }
    }
    final mine = await _get(
      token,
      const ['user', 'repos'],
      {'per_page': '100', 'affiliation': 'owner', 'sort': 'updated'},
    );
    if (mine is List) out.addAll(mine.map(_repo).nonNulls);
    return _sorted(out);
  }

  static List<InstalledRepo> _sorted(List<InstalledRepo> list) {
    final seen = <String>{};
    return [
      for (final r in list)
        if (seen.add(r.fullName.toLowerCase())) r,
    ]..sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );
  }
}
