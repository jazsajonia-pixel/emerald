import 'dart:convert';
import 'dart:typed_data';

import 'package:emerald/features/sync/git_hash.dart';
import 'package:emerald/features/sync/github_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_github.dart';

Matcher throwsSync(SyncErrorCode c) =>
    throwsA(isA<SyncException>().having((e) => e.code, 'code', c));

void main() {
  test('git blob hash matches git hash-object', () {
    // `printf 'hello\n' | git hash-object --stdin`
    expect(
      gitBlobSha(Uint8List.fromList(utf8.encode('hello\n'))),
      'ce013625030ba8dba906f756967f9e9ca394464a',
    );
    // Empty blob id, well known.
    expect(
      gitBlobSha(Uint8List(0)),
      'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391',
    );
  });

  test('headers, URL encoding, tree listing and blobs', () async {
    final gh = FakeGitHub(files: {'My Notes/a b.md': 'x'});
    final c = gh.client();
    final files = await c.listFiles('main');
    expect(files.single.path, 'My Notes/a b.md');
    final r = gh.requests.single;
    expect(
      r.url.toString(),
      'https://api.github.com/repos/me/notes/git/trees/main?recursive=1',
    );
    expect(r.headers['authorization'], 'Bearer ghp_TESTTOKEN');
    expect(r.headers['x-github-api-version'], '2022-11-28');
    expect(r.headers['accept'], 'application/vnd.github+json');
    expect(utf8.decode(await c.getBlob(files.single.sha)), 'x');

    await c.putFile(
      path: 'My Notes/new one.md',
      bytes: Uint8List.fromList([65]),
      branch: 'main',
      message: 'm',
    );
    expect(
      gh.requests.last.url.path,
      '/repos/me/notes/contents/My%20Notes/new%20one.md',
    );
    expect(gh.text('My Notes/new one.md'), 'A');
  });

  test('error mapping', () async {
    final gh = FakeGitHub();
    gh.failStatus = 401;
    await expectLater(
      gh.client().getRepo(),
      throwsSync(SyncErrorCode.unauthorized),
    );
    gh.failStatus = 403;
    await expectLater(
      gh.client().getRepo(),
      throwsSync(SyncErrorCode.forbidden),
    );
    gh.failStatus = 429;
    await expectLater(
      gh.client().getRepo(),
      throwsSync(SyncErrorCode.rateLimited),
    );
    gh.failStatus = 500;
    await expectLater(gh.client().getRepo(), throwsSync(SyncErrorCode.server));
    gh.failStatus = null;
    await expectLater(
      gh.client().listFiles('nope'),
      throwsSync(SyncErrorCode.notFound),
    );
    gh.empty = true;
    await expectLater(
      gh.client().listFiles('main'),
      throwsSync(SyncErrorCode.emptyRepository),
    );
  });

  test('403 with exhausted rate limit is reported as rate limit', () async {
    final c = GitHubClient(
      token: 't',
      owner: 'me',
      repo: 'notes',
      client: MockClient(
        (_) async => http.Response(
          '{"message":"API rate limit exceeded"}',
          403,
          headers: {'x-ratelimit-remaining': '0'},
        ),
      ),
    );
    await expectLater(c.getRepo(), throwsSync(SyncErrorCode.rateLimited));
  });

  test('stale sha on update is a remote change, not an overwrite', () async {
    final gh = FakeGitHub(files: {'a.md': 'v1'});
    await expectLater(
      gh.client().putFile(
        path: 'a.md',
        bytes: Uint8List(1),
        branch: 'main',
        message: 'm',
        previousSha: 'f' * 40,
      ),
      throwsSync(SyncErrorCode.remoteChanged),
    );
    await expectLater(
      gh.client().putFile(
        path: 'a.md',
        bytes: Uint8List(1),
        branch: 'main',
        message: 'm',
      ),
      throwsSync(SyncErrorCode.remoteChanged),
    );
    expect(gh.text('a.md'), 'v1');
  });

  test('truncated trees are refused', () async {
    final c = GitHubClient(
      token: 't',
      owner: 'me',
      repo: 'notes',
      client: MockClient(
        (_) async => http.Response('{"truncated":true,"tree":[]}', 200),
      ),
    );
    await expectLater(c.listFiles('main'), throwsSync(SyncErrorCode.truncated));
  });

  test('invalid names and branches rejected before any request', () {
    expect(
      () => GitHubClient(token: 't', owner: '../x', repo: 'r'),
      throwsSync(SyncErrorCode.notConfigured),
    );
    expect(GitHubClient.validBranch('feature/x'), isTrue);
    expect(GitHubClient.validBranch('../main'), isFalse);
    expect(GitHubClient.validBranch(''), isFalse);
  });

  test('token is never in error text', () async {
    final gh = FakeGitHub()..failStatus = 401;
    try {
      await gh.client(token: 'ghp_SUPERSECRET').getRepo();
    } on SyncException catch (e) {
      expect('$e ${e.userMessage} ${e.detail}', isNot(contains('SUPERSECRET')));
    }
  });
}
