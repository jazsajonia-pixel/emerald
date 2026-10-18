import 'dart:async';
import 'dart:convert';

import 'package:sapphire/features/ai/ai_types.dart';
import 'package:sapphire/features/ai/providers/openai_compatible_provider.dart';
import 'package:sapphire/features/ai/tools/vault_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key = 'sk-test-SECRET-999';

Matcher throwsAi(AiErrorCode c) =>
    throwsA(isA<AiException>().having((e) => e.code, 'code', c));

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const _q = AiRequest(system: 's', messages: [UserMessage('q')]);

void main() {
  late List<http.Request> requests;
  OpenAiCompatibleProvider provider(
    FutureOr<http.Response> Function(http.Request) h, {
    String base = 'https://api.openai.com/v1',
    String key = _key,
    String? effort,
    Duration timeout = const Duration(seconds: 5),
  }) {
    requests = [];
    return OpenAiCompatibleProvider(
      apiKey: key,
      model: 'gpt-test',
      baseUrl: base,
      reasoningEffort: effort,
      timeout: timeout,
      client: MockClient((r) async {
        requests.add(r);
        return h(r);
      }),
    );
  }

  Map<String, Object?> reply({
    String? content,
    List<Object?>? toolCalls,
    String finish = 'stop',
  }) => {
    'choices': [
      {
        'index': 0,
        'message': {
          'role': 'assistant',
          'content': content,
          'tool_calls': ?toolCalls,
        },
        'finish_reason': finish,
      },
    ],
    'usage': {'prompt_tokens': 7, 'completion_tokens': 2},
  };

  test('request shape follows the Chat Completions reference', () async {
    final p = provider((_) => _json(reply(content: 'Hi')), effort: 'none');
    final res = await p.generate(
      const AiRequest(
        system: 'sys',
        messages: [UserMessage('hello')],
        tools: VaultTools.specs,
      ),
    );
    final r = requests.single;
    expect(r.method, 'POST');
    expect(r.url.toString(), 'https://api.openai.com/v1/chat/completions');
    expect(r.headers['authorization'], 'Bearer $_key');
    expect(r.url.toString(), isNot(contains(_key)));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body['model'], 'gpt-test');
    expect(body['messages'], [
      {'role': 'system', 'content': 'sys'},
      {'role': 'user', 'content': 'hello'},
    ]);
    final tool = (body['tools'] as List).first as Map;
    expect(tool['type'], 'function');
    expect(tool['function']['name'], 'search_notes');
    expect(tool['function']['parameters']['type'], 'object');
    expect(body['reasoning_effort'], 'none');
    expect(res.message.text, 'Hi');
    expect(res.usage!.inputTokens, 7);
  });

  test(
    'reasoning_effort is omitted unless set; base URL with trailing slash',
    () async {
      final p = provider(
        (_) => _json(reply(content: 'ok')),
        base: 'http://localhost:11434/v1/',
        key: '',
      );
      await p.generate(_q);
      expect(
        requests.single.url.toString(),
        'http://localhost:11434/v1/chat/completions',
      );
      expect(
        jsonDecode(requests.single.body) as Map,
        isNot(contains('reasoning_effort')),
      );
      expect(requests.single.headers.containsKey('authorization'), isFalse);
    },
  );

  test('tool calls round-trip with tool_call_id', () async {
    final p = provider(
      (_) => _json(
        reply(
          finish: 'tool_calls',
          toolCalls: [
            {
              'id': 'call_A',
              'type': 'function',
              'function': {
                'name': 'read_note',
                'arguments': '{"path":"Plan.md"}',
              },
            },
            {
              'id': 'call_B',
              'type': 'function',
              'function': {
                'name': 'list_notes',
                'arguments': {'folder': ''},
              }, // object form (some servers)
            },
          ],
        ),
      ),
    );
    final first = await p.generate(_q);
    expect(first.message.toolCalls.map((c) => c.id), ['call_A', 'call_B']);
    expect(first.message.toolCalls.first.args, {'path': 'Plan.md'});
    expect(first.message.toolCalls.last.args, {'folder': ''});

    final body = p.buildRequestBody(
      AiRequest(
        system: 's',
        messages: [
          const UserMessage('q'),
          first.message,
          const ToolResultMessage(
            callId: 'call_A',
            name: 'read_note',
            result: {'content': 'x'},
          ),
        ],
      ),
    );
    final msgs = body['messages'] as List;
    expect(msgs[2], {
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        {
          'id': 'call_A',
          'type': 'function',
          'function': {'name': 'read_note', 'arguments': '{"path":"Plan.md"}'},
        },
        {
          'id': 'call_B',
          'type': 'function',
          'function': {'name': 'list_notes', 'arguments': '{"folder":""}'},
        },
      ],
    });
    expect(msgs[3], {
      'role': 'tool',
      'tool_call_id': 'call_A',
      'content': '{"content":"x"}',
    });
  });

  test(
    'invalid argument JSON becomes empty args instead of crashing',
    () async {
      final p = provider(
        (_) => _json(
          reply(
            toolCalls: [
              {
                'id': 'c',
                'type': 'function',
                'function': {'name': 'read_note', 'arguments': '{not json'},
              },
            ],
          ),
        ),
      );
      expect((await p.generate(_q)).message.toolCalls.single.args, isEmpty);
    },
  );

  group('errors', () {
    test('401 and 403', () async {
      await expectLater(
        provider(
          (_) => _json({
            'error': {'message': 'Incorrect API key provided: $_key'},
          }, 401),
        ).generate(_q),
        throwsAi(AiErrorCode.unauthorized),
      );
      await expectLater(
        provider((_) => _json({}, 403)).listModels(),
        throwsAi(AiErrorCode.unauthorized),
      );
    });

    test('429 rate limit vs billing codes', () async {
      await expectLater(
        provider(
          (_) => _json({
            'error': {'type': 'requests', 'code': 'rate_limit_exceeded'},
          }, 429),
        ).generate(_q),
        throwsAi(AiErrorCode.rateLimited),
      );
      for (final code in [
        'insufficient_quota',
        'credit_balance_exhausted',
        'project_spend_limit_exceeded',
      ]) {
        await expectLater(
          provider(
            (_) => _json({
              'error': {'type': 'insufficient_quota', 'code': code},
            }, 429),
          ).generate(_q),
          throwsAi(AiErrorCode.quotaExceeded),
        );
      }
    });

    test('400/404/5xx/malformed', () async {
      await expectLater(
        provider(
          (_) => _json({
            'error': {'code': 'model_not_found'},
          }, 404),
        ).generate(_q),
        throwsAi(AiErrorCode.badRequest),
      );
      await expectLater(
        provider(
          (_) => _json({
            'error': {'code': 'invalid_value'},
          }, 400),
        ).generate(_q),
        throwsAi(AiErrorCode.badRequest),
      );
      await expectLater(
        provider((_) => http.Response('busy', 503)).generate(_q),
        throwsAi(AiErrorCode.server),
      );
      await expectLater(
        provider((_) => http.Response('nope', 200)).generate(_q),
        throwsAi(AiErrorCode.invalidResponse),
      );
      await expectLater(
        provider((_) => _json({'choices': []})).generate(_q),
        throwsAi(AiErrorCode.invalidResponse),
      );
    });

    test('content filter / refusal', () async {
      await expectLater(
        provider((_) => _json(reply(finish: 'content_filter'))).generate(_q),
        throwsAi(AiErrorCode.blocked),
      );
      await expectLater(
        provider(
          (_) => _json({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'refusal': 'I cannot',
                },
                'finish_reason': 'stop',
              },
            ],
          }),
        ).generate(_q),
        throwsAi(AiErrorCode.blocked),
      );
    });

    test('timeout and network', () async {
      await expectLater(
        provider(
          (_) => Future.delayed(
            const Duration(seconds: 1),
            () => _json(reply(content: 'x')),
          ),
          timeout: const Duration(milliseconds: 30),
        ).generate(_q),
        throwsAi(AiErrorCode.timeout),
      );
      await expectLater(
        provider((_) => throw http.ClientException('down')).generate(_q),
        throwsAi(AiErrorCode.network),
      );
    });

    test('key never in error text', () async {
      try {
        await provider(
          (_) => _json({
            'error': {
              'message': 'Incorrect API key provided: $_key',
              'code': 'invalid_api_key',
            },
          }, 400),
        ).generate(_q);
        fail('should throw');
      } on AiException catch (e) {
        expect('${e.userMessage} ${e.message} $e', isNot(contains(_key)));
      }
    });
  });

  test('listModels parses data[] and sorts', () async {
    final p = provider((r) {
      expect(r.url.toString(), 'https://api.openai.com/v1/models');
      return _json({
        'object': 'list',
        'data': [
          {'id': 'b-model', 'object': 'model', 'created': 1, 'owned_by': 'x'},
          {'id': 'a-model', 'object': 'model', 'created': 1, 'owned_by': 'x'},
        ],
      });
    });
    expect((await p.listModels()).map((m) => m.id), ['a-model', 'b-model']);
  });

  test('base URL validation: https required except localhost', () {
    expect(
      OpenAiCompatibleProvider.validateBaseUrl('https://api.openai.com/v1'),
      isNull,
    );
    expect(
      OpenAiCompatibleProvider.validateBaseUrl('http://localhost:11434/v1'),
      isNull,
    );
    expect(
      OpenAiCompatibleProvider.validateBaseUrl('http://127.0.0.1:8080/v1'),
      isNull,
    );
    expect(
      OpenAiCompatibleProvider.validateBaseUrl('http://192.168.1.5:11434/v1'),
      isNotNull,
    );
    expect(OpenAiCompatibleProvider.validateBaseUrl('ftp://x'), isNotNull);
    expect(
      OpenAiCompatibleProvider.validateBaseUrl('api.openai.com'),
      isNotNull,
    );
    expect(
      OpenAiCompatibleProvider.validateBaseUrl('https://user:pw@host/v1'),
      isNotNull,
    );
    expect(
      OpenAiCompatibleProvider.validateBaseUrl('https://host/v1?key=1'),
      isNotNull,
    );
    expect(
      () => OpenAiCompatibleProvider(
        apiKey: '',
        model: 'm',
        baseUrl: 'http://evil.example/v1',
      ),
      throwsAi(AiErrorCode.badRequest),
    );
  });
}
