import 'dart:async';
import 'dart:convert';

import 'package:sapphire/features/ai/ai_types.dart';
import 'package:sapphire/features/ai/providers/gemini_provider.dart';
import 'package:sapphire/features/ai/tools/vault_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key = 'TEST-KEY-abc123';

Matcher throwsAi(AiErrorCode c) =>
    throwsA(isA<AiException>().having((e) => e.code, 'code', c));

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<http.Request> requests;
  GeminiProvider provider(
    FutureOr<http.Response> Function(http.Request) h, {
    Duration? timeout,
  }) {
    requests = [];
    return GeminiProvider(
      apiKey: _key,
      model: 'gemini-test',
      timeout: timeout ?? const Duration(seconds: 5),
      client: MockClient((r) async {
        requests.add(r);
        return h(r);
      }),
    );
  }

  final textReply = {
    'candidates': [
      {
        'content': {
          'role': 'model',
          'parts': [
            {'text': 'Hello '},
            {'text': 'there', 'thoughtSignature': 'c2ln'},
          ],
        },
        'finishReason': 'STOP',
      },
    ],
    'usageMetadata': {'promptTokenCount': 12, 'candidatesTokenCount': 3},
  };

  test('sends the documented request shape; key only in header', () async {
    final p = provider((_) => _json(textReply));
    final res = await p.generate(
      const AiRequest(
        system: 'sys',
        messages: [UserMessage('hi')],
        tools: VaultTools.specs,
      ),
    );
    final r = requests.single;
    expect(r.method, 'POST');
    expect(
      r.url.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent',
    );
    expect(r.url.toString(), isNot(contains(_key)));
    expect(r.headers['x-goog-api-key'], _key);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body['systemInstruction']['parts'][0]['text'], 'sys');
    expect(body['contents'], [
      {
        'role': 'user',
        'parts': [
          {'text': 'hi'},
        ],
      },
    ]);
    final decls = body['tools'][0]['functionDeclarations'] as List;
    expect(decls.map((d) => d['name']), contains('read_note'));
    expect(decls.first['parametersJsonSchema']['type'], 'object');
    expect(res.message.text, 'Hello there');
    expect(res.message.toolCalls, isEmpty);
    expect(res.usage!.inputTokens, 12);
  });

  test('parses function calls and echoes model parts verbatim', () async {
    final Map<String, dynamic> callReply = {
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'thought': true, 'text': 'thinking…'},
              {
                'functionCall': {
                  'id': 'call-1',
                  'name': 'search_notes',
                  'args': {'query': 'graph'},
                },
                'thoughtSignature': 'U0lH',
              },
            ],
          },
        },
      ],
    };
    final p = provider((_) => _json(callReply));
    final first = await p.generate(
      const AiRequest(system: 's', messages: [UserMessage('q')]),
    );
    expect(first.message.text, ''); // thought text is not shown
    final call = first.message.toolCalls.single;
    expect(call.id, 'call-1');
    expect(call.args, {'query': 'graph'});

    final p2 = provider((_) => _json(textReply));
    await p2.generate(
      AiRequest(
        system: 's',
        messages: [
          const UserMessage('q'),
          first.message,
          const ToolResultMessage(
            callId: 'call-1',
            name: 'search_notes',
            result: {'results': []},
          ),
        ],
      ),
    );
    final contents =
        (jsonDecode(requests.single.body) as Map)['contents'] as List;
    expect(contents[1]['role'], 'model');
    expect(
      contents[1]['parts'],
      callReply['candidates']![0]['content']['parts'],
    );
    expect(contents[2], {
      'role': 'user',
      'parts': [
        {
          'functionResponse': {
            'id': 'call-1',
            'name': 'search_notes',
            'response': {'results': []},
          },
        },
      ],
    });
  });

  test('parallel tool results are grouped into one user turn', () {
    final p = provider((_) => _json(textReply));
    final body = p.buildRequestBody(
      const AiRequest(
        system: 's',
        messages: [
          UserMessage('q'),
          AssistantMessage(
            toolCalls: [
              ToolCall(id: 'local-1', name: 'a', args: {}),
              ToolCall(id: 'local-2', name: 'b', args: {}),
            ],
          ),
          ToolResultMessage(callId: 'local-1', name: 'a', result: {'x': 1}),
          ToolResultMessage(callId: 'local-2', name: 'b', result: {'y': 2}),
        ],
      ),
    );
    final contents = body['contents'] as List;
    expect(contents, hasLength(3));
    expect((contents[2] as Map)['parts'], hasLength(2));
    // Locally generated ids are not sent.
    expect(jsonEncode(contents[2]), isNot(contains('local-')));
  });

  group('errors', () {
    test('invalid key (400 API_KEY_INVALID)', () async {
      final p = provider(
        (_) => _json({
          'error': {
            'code': 400,
            'message': 'API key not valid. Please pass a valid API key.',
            'status': 'INVALID_ARGUMENT',
            'details': [
              {'reason': 'API_KEY_INVALID'},
            ],
          },
        }, 400),
      );
      await expectLater(
        p.generate(const AiRequest(system: 's', messages: [UserMessage('q')])),
        throwsAi(AiErrorCode.unauthorized),
      );
    });

    test('rate limit vs quota (429)', () async {
      var p = provider(
        (_) => _json({
          'error': {
            'status': 'RESOURCE_EXHAUSTED',
            'message': 'Too many requests',
          },
        }, 429),
      );
      await expectLater(p.listModels(), throwsAi(AiErrorCode.rateLimited));
      p = provider(
        (_) => _json({
          'error': {
            'status': 'RESOURCE_EXHAUSTED',
            'message': 'You exceeded your current quota',
          },
        }, 429),
      );
      await expectLater(p.listModels(), throwsAi(AiErrorCode.quotaExceeded));
    });

    test('server error, unknown model, malformed body', () async {
      await expectLater(
        provider((_) => http.Response('oops', 503)).listModels(),
        throwsAi(AiErrorCode.server),
      );
      await expectLater(
        provider(
          (_) => _json({
            'error': {'status': 'NOT_FOUND'},
          }, 404),
        ).generate(const AiRequest(system: 's', messages: [UserMessage('q')])),
        throwsAi(AiErrorCode.badRequest),
      );
      await expectLater(
        provider(
          (_) => http.Response('<html>', 200),
        ).generate(const AiRequest(system: 's', messages: [UserMessage('q')])),
        throwsAi(AiErrorCode.invalidResponse),
      );
      await expectLater(
        provider(
          (_) => _json({'candidates': []}),
        ).generate(const AiRequest(system: 's', messages: [UserMessage('q')])),
        throwsAi(AiErrorCode.invalidResponse),
      );
    });

    test('blocked prompt and safety stop', () async {
      await expectLater(
        provider(
          (_) => _json({
            'promptFeedback': {'blockReason': 'SAFETY'},
          }),
        ).generate(const AiRequest(system: 's', messages: [UserMessage('q')])),
        throwsAi(AiErrorCode.blocked),
      );
      await expectLater(
        provider(
          (_) => _json({
            'candidates': [
              {'finishReason': 'SAFETY'},
            ],
          }),
        ).generate(const AiRequest(system: 's', messages: [UserMessage('q')])),
        throwsAi(AiErrorCode.blocked),
      );
    });

    test('timeout and network failure', () async {
      await expectLater(
        provider(
          (_) => Future.delayed(
            const Duration(seconds: 2),
            () => _json(textReply),
          ),
          timeout: const Duration(milliseconds: 50),
        ).generate(const AiRequest(system: 's', messages: [UserMessage('q')])),
        throwsAi(AiErrorCode.timeout),
      );
      await expectLater(
        provider(
          (_) => throw http.ClientException('no route'),
        ).generate(const AiRequest(system: 's', messages: [UserMessage('q')])),
        throwsAi(AiErrorCode.network),
      );
    });

    test('error messages never contain the API key', () async {
      final p = provider(
        (_) => _json({
          'error': {'message': 'bad key $_key', 'status': 'INVALID_ARGUMENT'},
        }, 400),
      );
      try {
        await p.generate(
          const AiRequest(system: 's', messages: [UserMessage('q')]),
        );
        fail('should throw');
      } on AiException catch (e) {
        expect(e.toString(), isNot(contains(_key)));
        expect(e.userMessage, isNot(contains(_key)));
        expect(e.message ?? '', isNot(contains(_key)));
      }
    });

    test('rejects odd model names before sending', () async {
      final p = GeminiProvider(
        apiKey: _key,
        model: '../x',
        client: MockClient((_) async => _json({})),
      );
      await expectLater(
        p.generate(const AiRequest(system: 's', messages: [UserMessage('q')])),
        throwsAi(AiErrorCode.badRequest),
      );
    });
  });

  test('listModels filters to generateContent and follows pages', () async {
    final p = provider((r) {
      expect(r.method, 'GET');
      expect(r.url.path, '/v1beta/models');
      if (r.url.queryParameters['pageToken'] == null) {
        return _json({
          'models': [
            {
              'name': 'models/gemini-a',
              'displayName': 'A',
              'supportedGenerationMethods': ['generateContent'],
            },
            {
              'name': 'models/embed',
              'supportedGenerationMethods': ['embedContent'],
            },
          ],
          'nextPageToken': 'p2',
        });
      }
      return _json({
        'models': [
          {
            'name': 'models/gemini-b',
            'supportedGenerationMethods': ['generateContent', 'countTokens'],
          },
        ],
      });
    });
    final models = await p.listModels();
    expect(models.map((m) => m.id), ['gemini-a', 'gemini-b']);
    expect(requests, hasLength(2));
    expect(requests.every((r) => r.headers['x-goog-api-key'] == _key), isTrue);
  });
}
