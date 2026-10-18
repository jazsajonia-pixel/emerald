import 'dart:convert';
import 'dart:typed_data';

import 'package:emerald/features/sync/git_hash.dart';
import 'package:emerald/features/sync/github_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory GitHub REST server implementing the endpoints Emerald uses,
/// with the documented semantics (sha required to update; mismatch → 409).
class FakeGitHub {
  FakeGitHub({
    Map<String, String> files = const {},
    this.isPrivate = true,
    this.canPush = true,
  }) {
    files.forEach(set);
  }

  final Map<String, Uint8List> files = {};
  bool isPrivate;
  bool canPush;
  bool empty = false;
  int? failStatus; // forces every request to fail with this status
  String? corruptBlob; // sha whose content is returned altered
  final List<http.Request> requests = [];
  final List<String> commits = [];

  /// Called before handling a PUT; lets tests simulate a concurrent edit.
  void Function(String path)? beforePut;

  /// Called before handling a DELETE; lets tests simulate a concurrent edit
  /// after the local proposal write but before its removal.
  void Function(String path)? beforeDelete;

  void set(String path, String content) =>
      files[path] = Uint8List.fromList(utf8.encode(content));
  String? text(String path) =>
      files[path] == null ? null : utf8.decode(files[path]!);

  late final http.Client mock = MockClient(_handle);

  GitHubClient client({String token = 'ghp_TESTTOKEN'}) =>
      GitHubClient(token: token, owner: 'me', repo: 'notes', client: mock);

  http.Response _j(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request r) async {
    requests.add(r);
    if (failStatus != null) return _j({'message': 'fail'}, failStatus!);
    final seg = r.url.pathSegments;
    if (seg.length < 3 ||
        seg[0] != 'repos' ||
        seg[1] != 'me' ||
        seg[2] != 'notes') {
      return _j({'message': 'Not Found'}, 404);
    }
    final rest = seg.sublist(3);
    if (r.method == 'GET' && rest.isEmpty) {
      return _j({
        'private': isPrivate,
        'default_branch': 'main',
        'permissions': {'admin': false, 'push': canPush, 'pull': true},
      });
    }
    if (r.method == 'GET' &&
        rest.length >= 3 &&
        rest[0] == 'git' &&
        rest[1] == 'trees') {
      if (empty) return _j({'message': 'Git Repository is empty.'}, 409);
      if (rest.sublist(2).join('/') != 'main') {
        return _j({'message': 'Not Found'}, 404);
      }
      return _j({
        'sha': 'tree',
        'truncated': false,
        'tree': [
          for (final e in files.entries)
            {
              'path': e.key,
              'mode': '100644',
              'type': 'blob',
              'sha': gitBlobSha(e.value),
              'size': e.value.length,
            },
          {'path': 'Folder', 'mode': '040000', 'type': 'tree', 'sha': 'x' * 40},
        ],
      });
    }
    if (r.method == 'GET' &&
        rest.length == 3 &&
        rest[0] == 'git' &&
        rest[1] == 'blobs') {
      for (final b in files.values) {
        if (gitBlobSha(b) == rest[2]) {
          final out = rest[2] == corruptBlob
              ? Uint8List.fromList([...b, 33])
              : b;
          return _j({
            'sha': rest[2],
            'size': out.length,
            'encoding': 'base64',
            'content': base64.encode(out),
          });
        }
      }
      return _j({'message': 'Not Found'}, 404);
    }
    if (r.method == 'PUT' && rest.isNotEmpty && rest[0] == 'contents') {
      final path = rest.sublist(1).join('/');
      beforePut?.call(path);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final current = files[path];
      final sha = body['sha'] as String?;
      if (current != null && sha == null) {
        return _j({'message': '"sha" wasn\'t supplied.'}, 422);
      }
      if (current != null && sha != gitBlobSha(current)) {
        return _j({'message': 'does not match'}, 409);
      }
      final bytes = base64.decode(body['content'] as String);
      files[path] = bytes;
      commits.add(body['message'] as String);
      return _j({
        'content': {'path': path, 'sha': gitBlobSha(bytes)},
        'commit': {'sha': 'c${commits.length}'},
      }, current == null ? 201 : 200);
    }
    if (r.method == 'DELETE' && rest.isNotEmpty && rest[0] == 'contents') {
      final path = rest.sublist(1).join('/');
      beforeDelete?.call(path);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final current = files[path];
      if (current == null) return _j({'message': 'Not Found'}, 404);
      if (body['sha'] != gitBlobSha(current)) {
        return _j({'message': 'does not match'}, 409);
      }
      files.remove(path);
      commits.add(body['message'] as String);
      return _j({
        'content': null,
        'commit': {'sha': 'c${commits.length}'},
      });
    }
    return _j({'message': 'Not Found'}, 404);
  }
}
