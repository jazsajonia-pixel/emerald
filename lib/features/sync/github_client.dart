import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum SyncErrorCode {
  notConfigured,
  unauthorized,
  forbidden,
  notFound,
  rateLimited,
  emptyRepository,
  remoteChanged,
  network,
  timeout,
  server,
  invalidResponse,
  tooLarge,
  truncated,
}

class SyncException implements Exception {
  SyncException(this.code, [this.detail]);
  final SyncErrorCode code;
  final String? detail;

  /// Errors after which continuing with other files makes no sense.
  bool get fatal => const {
    SyncErrorCode.unauthorized,
    SyncErrorCode.forbidden,
    SyncErrorCode.rateLimited,
    SyncErrorCode.network,
    SyncErrorCode.timeout,
    SyncErrorCode.notFound,
  }.contains(code);

  String get userMessage => switch (code) {
    SyncErrorCode.notConfigured => 'GitHub sync is not set up.',
    SyncErrorCode.unauthorized =>
      'GitHub rejected the token. Check it in Settings → GitHub sync.',
    SyncErrorCode.forbidden =>
      'The token is not allowed to do this. It needs Contents: Read and write '
          'for this repository.',
    SyncErrorCode.notFound =>
      'Repository or branch not found (or the token cannot see it).',
    SyncErrorCode.rateLimited => 'GitHub rate limit reached. Try again later.',
    SyncErrorCode.emptyRepository =>
      'The repository is empty. Add a README on GitHub first, then sync.',
    SyncErrorCode.remoteChanged =>
      'The file changed on GitHub during sync; it will be retried next time.',
    SyncErrorCode.network => 'No connection to GitHub.',
    SyncErrorCode.timeout => 'GitHub did not answer in time.',
    SyncErrorCode.server => 'GitHub had a server error. Try again later.',
    SyncErrorCode.invalidResponse => 'GitHub sent an unexpected answer.',
    SyncErrorCode.tooLarge => 'File too large to sync.',
    SyncErrorCode.truncated =>
      'The repository is too large to list in one request (over 100,000 '
          'entries or 7 MB). Use a smaller repository for notes.',
  };

  @override
  String toString() => 'SyncException(${code.name})';
}

class RemoteRepo {
  const RemoteRepo({
    required this.isPrivate,
    required this.canPush,
    required this.defaultBranch,
  });
  final bool isPrivate;
  final bool canPush;
  final String defaultBranch;
}

class RemoteFile {
  const RemoteFile({required this.path, required this.sha, required this.size});
  final String path;
  final String sha;
  final int size;
}

/// Minimal GitHub REST client for sync. Endpoints verified against
/// docs.github.com (REST API version 2022-11-28, supported until 2028-03-10):
/// - `GET  /repos/{o}/{r}` (Metadata: read) — privacy and push permission
/// - `GET  /repos/{o}/{r}/git/trees/{branch}?recursive=1` (Contents: read)
/// - `GET  /repos/{o}/{r}/git/blobs/{sha}` (Contents: read)
/// - `PUT  /repos/{o}/{r}/contents/{path}` (Contents: write) — must be serial
class GitHubClient {
  GitHubClient({
    required String token,
    required this.owner,
    required this.repo,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    Uri? apiBase,
  }) : _client = client ?? http.Client(),
       _api = apiBase ?? defaultApi {
    _token = token;
    if (!validName(owner) || !validName(repo)) {
      throw SyncException(SyncErrorCode.notConfigured, 'invalid owner/repo');
    }
  }

  static final defaultApi = Uri.parse('https://api.github.com/');

  /// Always [defaultApi] in the app; overridable only for API checks.
  final Uri _api;
  static const apiVersion = '2022-11-28';

  late final String _token;
  final String owner;
  final String repo;
  final http.Client _client;
  final Duration timeout;

  static bool validName(String s) =>
      RegExp(r'^[A-Za-z0-9_.\-]{1,100}$').hasMatch(s) && s != '.' && s != '..';

  static bool validBranch(String b) =>
      b.isNotEmpty &&
      b.length <= 250 &&
      !b.startsWith('/') &&
      !b.endsWith('/') &&
      !b.contains('..') &&
      RegExp(r'^[A-Za-z0-9_.\-/]+$').hasMatch(b);

  Map<String, String> get _headers => {
    'authorization': 'Bearer $_token',
    'accept': 'application/vnd.github+json',
    'x-github-api-version': apiVersion,
  };

  Uri _repoUri(List<String> segments, [Map<String, String>? query]) =>
      _api.replace(
        pathSegments: [
          ..._api.pathSegments.where((s) => s.isNotEmpty),
          'repos',
          owner,
          repo,
          ...segments,
        ],
        queryParameters: query,
      );

  Future<RemoteRepo> getRepo() async {
    final j = await _json(
      () => _client.get(_repoUri(const []), headers: _headers),
    );
    final perms = j['permissions'];
    return RemoteRepo(
      isPrivate: j['private'] == true,
      canPush: perms is Map && perms['push'] == true,
      defaultBranch: (j['default_branch'] as String?) ?? 'main',
    );
  }

  /// All blobs on [branch]. Throws [SyncErrorCode.emptyRepository] for a
  /// repository without commits.
  Future<List<RemoteFile>> listFiles(String branch) async {
    if (!validBranch(branch)) {
      throw SyncException(SyncErrorCode.notConfigured, 'branch');
    }
    final j = await _json(
      () => _client.get(
        _repoUri(['git', 'trees', branch], {'recursive': '1'}),
        headers: _headers,
      ),
      emptyRepoOn409: true,
    );
    if (j['truncated'] == true) throw SyncException(SyncErrorCode.truncated);
    final tree = j['tree'];
    if (tree is! List) throw SyncException(SyncErrorCode.invalidResponse);
    return [
      for (final e in tree)
        if (e is Map &&
            e['type'] == 'blob' &&
            e['path'] is String &&
            e['sha'] is String)
          RemoteFile(
            path: e['path'] as String,
            sha: e['sha'] as String,
            size: (e['size'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  Future<Uint8List> getBlob(String sha) async {
    if (!RegExp(r'^[0-9a-f]{40,64}$').hasMatch(sha)) {
      throw SyncException(SyncErrorCode.invalidResponse, 'sha');
    }
    final j = await _json(
      () => _client.get(_repoUri(['git', 'blobs', sha]), headers: _headers),
    );
    final content = j['content'];
    if (content is! String || j['encoding'] != 'base64') {
      throw SyncException(SyncErrorCode.invalidResponse, 'blob encoding');
    }
    try {
      return base64.decode(content.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw SyncException(SyncErrorCode.invalidResponse, 'base64');
    }
  }

  /// Creates ([previousSha] == null) or updates a file with one commit.
  /// Returns the new blob SHA. GitHub refuses (409/422) if the file changed
  /// since [previousSha], which is reported as [SyncErrorCode.remoteChanged].
  Future<String> putFile({
    required String path,
    required Uint8List bytes,
    required String branch,
    required String message,
    String? previousSha,
  }) async {
    final body = jsonEncode({
      'message': message,
      'content': base64.encode(bytes),
      'branch': branch,
      'sha': ?previousSha,
    });
    final j = await _json(
      () => _client.put(
        _repoUri(['contents', ...path.split('/')]),
        headers: {..._headers, 'content-type': 'application/json'},
        body: body,
      ),
      conflictOn409: true,
    );
    final content = j['content'];
    final sha = content is Map ? content['sha'] : null;
    if (sha is! String) {
      throw SyncException(SyncErrorCode.invalidResponse, 'no sha');
    }
    return sha;
  }

  Future<Map<String, Object?>> _json(
    Future<http.Response> Function() call, {
    bool emptyRepoOn409 = false,
    bool conflictOn409 = false,
  }) async {
    http.Response res;
    try {
      res = await call().timeout(timeout);
    } on TimeoutException {
      throw SyncException(SyncErrorCode.timeout);
    } on SocketException {
      throw SyncException(SyncErrorCode.network);
    } on http.ClientException {
      throw SyncException(SyncErrorCode.network);
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      json = null;
    }
    final s = res.statusCode;
    if (s >= 200 && s < 300) {
      if (json is Map<String, Object?>) return json;
      throw SyncException(SyncErrorCode.invalidResponse);
    }
    final message = json is Map ? '${json['message'] ?? ''}'.toLowerCase() : '';
    if (s == 401) throw SyncException(SyncErrorCode.unauthorized);
    if (s == 429 ||
        ((s == 403) &&
            (res.headers['x-ratelimit-remaining'] == '0' ||
                message.contains('rate limit')))) {
      throw SyncException(SyncErrorCode.rateLimited);
    }
    if (s == 403) throw SyncException(SyncErrorCode.forbidden);
    if (s == 404) throw SyncException(SyncErrorCode.notFound);
    if (s == 409 && emptyRepoOn409) {
      throw SyncException(SyncErrorCode.emptyRepository);
    }
    if ((s == 409 || s == 422) && conflictOn409) {
      throw SyncException(SyncErrorCode.remoteChanged);
    }
    if (s >= 500) throw SyncException(SyncErrorCode.server, 'HTTP $s');
    throw SyncException(SyncErrorCode.invalidResponse, 'HTTP $s');
  }
}
