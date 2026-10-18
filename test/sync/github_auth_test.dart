import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sapphire/features/sync/github_auth.dart';

http.Response _json(Object o) => http.Response(
  jsonEncode(o),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  final now = DateTime.utc(2026, 10, 18, 9);
  final code = DeviceCode(
    deviceCode: 'd',
    userCode: 'U',
    verificationUri: Uri.parse('https://github.com/login/device'),
    interval: const Duration(seconds: 5),
    expiresAt: now.add(const Duration(minutes: 15)),
  );

  test('polling honours slow_down and returns expiring tokens', () async {
    final waits = <Duration>[];
    var n = 0;
    final auth = GitHubAuth(
      clientId: 'Iv23liABCDEF123456',
      clock: () => now,
      sleep: (d) async => waits.add(d),
      client: MockClient((r) async {
        expect(r.url.toString(), 'https://github.com/login/oauth/access_token');
        expect(Uri.splitQueryString(r.body)['client_secret'], isNull);
        return switch (n++) {
          0 => _json({'error': 'authorization_pending'}),
          1 => _json({'error': 'slow_down', 'interval': 10}),
          _ => _json({
            'access_token': 'ghu_x',
            'refresh_token': 'ghr_y',
            'expires_in': 28800,
            'refresh_token_expires_in': 15897600,
          }),
        };
      }),
    );
    final t = (await auth.waitForToken(code))!;
    expect(waits, [
      const Duration(seconds: 5),
      const Duration(seconds: 5),
      const Duration(seconds: 10),
    ]);
    expect(t.accessToken, 'ghu_x');
    expect(t.expiresAt, now.add(const Duration(hours: 8)));
    expect(t.needsRefresh(now), isFalse);
    expect(t.needsRefresh(now.add(const Duration(hours: 8))), isTrue);
    final back = GitHubTokens.fromJson(jsonEncode(t.toJson()))!;
    expect(back.refreshToken, 'ghr_y');
    expect(back.expiresAt, t.expiresAt);
  });

  test(
    'denied, expired and disabled device flow map to clear errors',
    () async {
      for (final (err, code_) in [
        ('access_denied', AuthErrorCode.denied),
        ('expired_token', AuthErrorCode.expired),
        ('device_flow_disabled', AuthErrorCode.deviceFlowDisabled),
      ]) {
        final auth = GitHubAuth(
          clientId: 'Iv23liABCDEF123456',
          clock: () => now,
          sleep: (_) async {},
          client: MockClient((_) async => _json({'error': err})),
        );
        await expectLater(
          auth.waitForToken(code),
          throwsA(isA<AuthException>().having((e) => e.code, 'code', code_)),
        );
      }
    },
  );

  test('refresh uses grant_type=refresh_token without a secret', () async {
    late Map<String, String> body;
    final auth = GitHubAuth(
      clientId: 'Iv23liABCDEF123456',
      clock: () => now,
      client: MockClient((r) async {
        body = Uri.splitQueryString(r.body);
        return _json({'access_token': 'ghu_new', 'expires_in': 28800});
      }),
    );
    final t = await auth.refresh('ghr_old');
    expect(body, {
      'client_id': 'Iv23liABCDEF123456',
      'grant_type': 'refresh_token',
      'refresh_token': 'ghr_old',
    });
    expect(t.accessToken, 'ghu_new');
  });

  test('client ID validation', () {
    expect(GitHubAuth.validClientId('Iv23liABCDEF123456'), isTrue);
    expect(GitHubAuth.validClientId('x'), isFalse);
    expect(GitHubAuth.validClientId('has space in it'), isFalse);
  });
}
