import 'dart:convert';

import 'package:sapphire/data/memory_vault_storage.dart';
import 'package:sapphire/data/vault_storage.dart';
import 'package:sapphire/features/ai/ai_config.dart';
import 'package:sapphire/features/sync/github_auth.dart';
import 'package:sapphire/features/sync/github_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

import '../helpers/app_harness.dart';
import 'fake_github.dart';

const _vault = VaultHandle(id: 'memory://vault', name: 'My Vault');
const _token = 'github_pat_SECRET_123';

Future<void> _tap(WidgetTester tester, Finder f) async {
  await _seek(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Fake github.com OAuth + REST endpoints for "Sign in with GitHub".
class FakeGitHubLogin {
  int polls = 0;
  final requests = <http.Request>[];
  bool installed = true;

  /// Number of token polls that fail with a dropped connection first.
  int failPolls = 0;

  /// When true, polling never completes (the user has not approved yet).
  bool hang = false;

  late final http.Client client = MockClient((r) async {
    requests.add(r);
    final path = r.url.path;
    http.Response json(Object o, [int status = 200]) => http.Response(
      jsonEncode(o),
      status,
      headers: {'content-type': 'application/json'},
    );
    if (r.method == 'POST' && path == '/login/device/code') {
      return json({
        'device_code': 'dev-123',
        'user_code': 'WDJB-MJHT',
        'verification_uri': 'https://github.com/login/device',
        'expires_in': 900,
        'interval': 5,
      });
    }
    if (r.method == 'POST' && path == '/login/oauth/access_token') {
      final body = Uri.splitQueryString(r.body);
      if (body['grant_type'] == 'refresh_token') {
        return json({
          'access_token': 'ghu_refreshed',
          'refresh_token': 'ghr_2',
          'expires_in': 28800,
        });
      }
      if (failPolls > 0) {
        failPolls--;
        throw http.ClientException('Software caused connection abort');
      }
      polls++;
      if (polls < 2) return json({'error': 'authorization_pending'});
      return json({
        'access_token': 'ghu_ACCESS',
        'refresh_token': 'ghr_REFRESH',
        'expires_in': 28800,
        'refresh_token_expires_in': 15897600,
      });
    }
    if (path == '/user') return json({'login': 'me'});
    if (path == '/user/installations') {
      return json({
        'installations': [
          if (installed) {'id': 7},
        ],
      });
    }
    if (path == '/user/installations/7/repositories') {
      return json({
        'repositories': [
          {
            'name': 'notes',
            'owner': {'login': 'me'},
            'private': true,
            'default_branch': 'main',
          },
        ],
      });
    }
    return json({'message': 'Not Found'}, 404);
  });

  GitHubAuth auth(String id) => GitHubAuth(
    clientId: id,
    client: client,
    sleep: (_) => hang ? Completer<void>().future : Future<void>.value(),
  );
}

/// Scrolls the sync screen until [f] is built and visible (looking from
/// the top). [settle] = false for screens with spinners.
Future<void> _seek(WidgetTester tester, Finder f, {bool settle = true}) async {
  Future<void> wait() => settle
      ? tester.pumpAndSettle()
      : tester.pump(const Duration(milliseconds: 50));
  if (f.evaluate().isEmpty) {
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, 6000));
    await wait();
    for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -180));
      await wait();
    }
  }
  await tester.ensureVisible(f);
  await wait();
}

Future<void> _openSync(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Settings'),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.text('GitHub sync'));
}

void main() {
  late FakeGitHub gh;

  late FakeGitHubLogin login;
  late List<Uri> opened;

  Future<MemorySecretStore> setUpApp(
    WidgetTester tester, {
    bool private = true,
  }) async {
    login = FakeGitHubLogin();
    opened = [];
    gh = FakeGitHub(files: {'Remote.md': 'from github'}, isPrivate: private);
    final secrets = MemorySecretStore();
    await pumpSapphire(
      tester,
      storage: MemoryVaultStorage(
        files: {'Local.md': 'from phone'},
        remembered: _vault,
      ),
      secrets: secrets,
      gitHubFactory: (t, o, r) =>
          GitHubClient(token: t, owner: o, repo: r, client: gh.mock),
      gitHubAuthFactory: (id) => login.auth(id),
      urlOpener: (u) async {
        opened.add(u);
        return true;
      },
    );
    return secrets;
  }

  Future<void> fillAndSave(WidgetTester tester) async {
    if (find.byKey(const Key('sync-owner')).evaluate().isEmpty) {
      await _tap(tester, find.text('Use a personal access token instead'));
    }
    await tester.enterText(find.byKey(const Key('sync-owner')), 'me');
    await tester.enterText(find.byKey(const Key('sync-repo')), 'notes');
    await tester.enterText(find.byKey(const Key('sync-token')), _token);
    await _tap(tester, find.byKey(const Key('sync-save')));
  }

  testWidgets('set up, enable and sync with a private repository', (
    tester,
  ) async {
    final secrets = await setUpApp(tester);
    await _openSync(tester);
    expect(find.text('Not connected'), findsOneWidget);

    await fillAndSave(tester);
    expect(secrets.values['sync.github.token'], _token);
    expect(find.textContaining(_token), findsNothing);
    expect(find.text('Token (saved — enter to replace)'), findsOneWidget);

    await _tap(tester, find.text('Test connection'));
    expect(
      find.textContaining('private repository with write access'),
      findsOneWidget,
    );

    // Sync now is disabled until sync is enabled.
    await _seek(tester, find.byKey(const Key('sync-now')));
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('sync-now'))).onPressed,
      isNull,
    );
    await _tap(tester, find.byKey(const Key('sync-enabled')));
    await _tap(tester, find.byKey(const Key('sync-now')));
    expect(find.textContaining('Uploaded 1 · Downloaded 1'), findsOneWidget);
    expect(gh.text('Local.md'), 'from phone');
    expect(find.textContaining('Last successful sync'), findsOneWidget);

    // Downloaded note appears in Brain after the automatic rescan.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Brain'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Remote'), findsOneWidget);
  });

  testWidgets('public repositories are refused unless explicitly allowed', (
    tester,
  ) async {
    await setUpApp(tester, private: false);
    await _openSync(tester);
    await fillAndSave(tester);
    await _tap(tester, find.byKey(const Key('sync-enabled')));
    await _tap(tester, find.byKey(const Key('sync-now')));
    expect(find.textContaining('This repository is PUBLIC'), findsOneWidget);
    expect(gh.requests.where((r) => r.method == 'PUT'), isEmpty);

    await _tap(tester, find.text('Allow a public repository'));
    expect(find.text('Sync to a public repository?'), findsOneWidget);
    await _tap(tester, find.text('Allow public'));
    await _tap(tester, find.byKey(const Key('sync-now')));
    expect(gh.text('Local.md'), 'from phone');
  });

  testWidgets('remove deletes the token but no notes', (tester) async {
    final secrets = await setUpApp(tester);
    await _openSync(tester);
    await fillAndSave(tester);
    await _tap(tester, find.byKey(const Key('sync-remove')));
    await _tap(tester, find.widgetWithText(FilledButton, 'Remove'));
    expect(secrets.values.keys.where((k) => k.startsWith('sync.')), isEmpty);
    expect(gh.text('Remote.md'), 'from github');
  });

  testWidgets('bad token shows a plain-language error', (tester) async {
    await setUpApp(tester);
    gh.failStatus = 401;
    await _openSync(tester);
    await fillAndSave(tester);
    await _tap(tester, find.text('Test connection'));
    expect(find.textContaining('GitHub rejected the token'), findsOneWidget);
  });

  testWidgets('sign in with GitHub, pick the notes repo and it syncs', (
    tester,
  ) async {
    final secrets = await setUpApp(tester);
    await _openSync(tester);
    expect(find.text('Not connected'), findsOneWidget);

    // A malformed client ID is refused before contacting GitHub.
    await tester.enterText(find.byKey(const Key('sync-client-id')), 'x');
    await _tap(tester, find.byKey(const Key('sync-signin')));
    expect(find.textContaining('Paste the Client ID'), findsOneWidget);
    expect(login.requests, isEmpty);

    // The setup guide opens the pre-filled GitHub App page.
    await _tap(tester, find.byKey(const Key('sync-create-app')));
    expect(opened.single.path, '/settings/apps/new');
    expect(opened.single.queryParameters['contents'], 'write');
    expect(opened.single.queryParameters['webhook_active'], 'false');

    await tester.enterText(
      find.byKey(const Key('sync-client-id')),
      'Iv23liABCDEF123456',
    );
    await _tap(tester, find.byKey(const Key('sync-signin')));
    await tester.pumpAndSettle();
    await _seek(tester, find.text('Signed in as @me'));
    expect(find.text('Signed in as @me'), findsOneWidget);
    expect(login.polls, 2); // pending once, then approved
    expect(secrets.values['sync.github.oauth'], contains('ghu_ACCESS'));
    expect(secrets.values['sync.github.token'], isNull);
    expect(find.textContaining('ghu_ACCESS'), findsNothing);

    // Only repositories the GitHub App is installed on are offered.
    final repo = find.byKey(const Key('sync-repo-me/notes'));
    await _seek(tester, repo);
    expect(repo, findsOneWidget);
    await _tap(tester, repo);
    await tester.pumpAndSettle();
    expect(secrets.values['sync.github.repo'], 'notes');
    expect(secrets.values['sync.github.enabled'], 'yes');
    // Choosing the repository runs the first sync right away.
    expect(gh.text('Local.md'), 'from phone');
    await _seek(tester, find.byKey(const Key('sync-report')));
    expect(find.textContaining('Uploaded 1 · Downloaded 1'), findsOneWidget);
  });

  testWidgets('device code is shown while waiting for approval', (
    tester,
  ) async {
    await setUpApp(tester);
    login.hang = true; // the user has not approved yet
    await _openSync(tester);
    await tester.enterText(
      find.byKey(const Key('sync-client-id')),
      'Iv23liABCDEF123456',
    );
    await _seek(tester, find.byKey(const Key('sync-signin')));
    await tester.tap(find.byKey(const Key('sync-signin')));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await _seek(tester, find.text('WDJB-MJHT'), settle: false);
    expect(find.text('WDJB-MJHT'), findsOneWidget);
    await _seek(
      tester,
      find.byKey(const Key('sync-open-device')),
      settle: false,
    );
    await tester.tap(find.byKey(const Key('sync-open-device')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(opened.last.toString(), 'https://github.com/login/device');
    await _seek(tester, find.text('Cancel'), settle: false);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('WDJB-MJHT'), findsNothing);
    expect(find.byKey(const Key('sync-signin')), findsOneWidget);
  });

  testWidgets('no installation explains how to install the app', (
    tester,
  ) async {
    await setUpApp(tester);
    login.installed = false;
    await _openSync(tester);
    await tester.enterText(
      find.byKey(const Key('sync-client-id')),
      'Iv23liABCDEF123456',
    );
    await _tap(tester, find.byKey(const Key('sync-signin')));
    await tester.pumpAndSettle();
    await _seek(tester, find.textContaining('No repositories yet'));
    expect(find.textContaining('No repositories yet'), findsOneWidget);
  });

  testWidgets('a Client ID or code pasted as token is refused', (tester) async {
    final secrets = await setUpApp(tester);
    await _openSync(tester);
    await _tap(tester, find.text('Use a personal access token instead'));
    await tester.enterText(find.byKey(const Key('sync-owner')), 'me');
    await tester.enterText(find.byKey(const Key('sync-repo')), 'notes');
    await tester.enterText(
      find.byKey(const Key('sync-token')),
      'Iv23liABCDEF123456',
    );
    await _tap(tester, find.byKey(const Key('sync-save')));
    expect(
      find.textContaining('does not look like a GitHub token'),
      findsOneWidget,
    );
    expect(secrets.values['sync.github.token'], isNull);
  });

  testWidgets('sign-in survives the network dropping while in the browser', (
    tester,
  ) async {
    final secrets = await setUpApp(tester);
    login.failPolls = 3; // e.g. "connection abort" while backgrounded
    await _openSync(tester);
    await tester.enterText(
      find.byKey(const Key('sync-client-id')),
      'Iv23liABCDEF123456',
    );
    await _tap(tester, find.byKey(const Key('sync-signin')));
    await tester.pumpAndSettle();
    expect(secrets.values['sync.github.oauth'], contains('ghu_ACCESS'));
    await _seek(tester, find.text('Signed in as @me'));
    expect(find.text('Signed in as @me'), findsOneWidget);
  });
}
