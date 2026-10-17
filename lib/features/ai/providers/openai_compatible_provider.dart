import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../ai_types.dart';

/// Adapter for servers implementing the OpenAI Chat Completions API
/// (`POST {base}/chat/completions`, `GET {base}/models`).
///
/// Verified against official docs (October 2026):
/// - OpenAI: base `https://api.openai.com/v1`, `Authorization: Bearer <key>`,
///   tools `[{type:function,function:{name,description,parameters}}]`,
///   `tool_calls[{id,type,function:{name,arguments(JSON string)}}]`,
///   tool results as `{role:tool,tool_call_id,content}`.
///   OpenAI notes that on its newest models function calling via Chat
///   Completions is limited (e.g. `gpt-6-luna` only with
///   `reasoning_effort: "none"`; Astra/Sol not at all) — see docs/AI.md.
/// - Ollama: OpenAI-compatible `/v1/chat/completions` with tools and
///   `/v1/models`; local base `http://localhost:11434/v1`, key ignored.
class OpenAiCompatibleProvider implements AiProvider {
  OpenAiCompatibleProvider({
    required String apiKey,
    required this.model,
    required this.baseUrl,
    this.reasoningEffort,
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
  }) : _client = client ?? http.Client() {
    _apiKey = apiKey;
    final err = validateBaseUrl(baseUrl);
    if (err != null) throw AiException(AiErrorCode.badRequest, err);
  }

  static const providerId = 'openai_compatible';
  static const defaultBaseUrl = 'https://api.openai.com/v1';

  late final String _apiKey;
  final String model;
  final String baseUrl;

  /// Sent as `reasoning_effort` only when set (not every server accepts it).
  final String? reasoningEffort;
  final http.Client _client;
  final Duration timeout;

  @override
  String get id => providerId;

  @override
  String get displayName => 'OpenAI-compatible';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    text: true,
    toolUse: true, // depends on the model/server; errors are reported
    streaming: false,
    listModels: true,
  );

  /// HTTPS is required, except plain HTTP to this device itself (e.g. Ollama
  /// running in Termux). Returns an error message or null.
  static String? validateBaseUrl(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      return 'Enter a full URL, e.g. https://api.openai.com/v1';
    }
    if (u.userInfo.isNotEmpty || u.hasQuery || u.hasFragment) {
      return 'The URL must not contain credentials, a query or a fragment';
    }
    if (u.scheme == 'https') return null;
    if (u.scheme == 'http' && isLoopbackHost(u.host)) return null;
    return 'Use https:// (plain http is only allowed for localhost)';
  }

  static bool isLoopbackHost(String host) =>
      host == 'localhost' || host == '127.0.0.1';

  Uri _endpoint(String path) {
    final base = baseUrl.trim().endsWith('/')
        ? baseUrl.trim()
        : '${baseUrl.trim()}/';
    return Uri.parse(base).resolve(path);
  }

  Map<String, String> get _headers => {
    if (_apiKey.isNotEmpty) 'authorization': 'Bearer $_apiKey',
    'content-type': 'application/json',
  };

  @override
  Future<AiResponse> generate(AiRequest request) async {
    if (model.trim().isEmpty) {
      throw AiException(AiErrorCode.badRequest, 'no model selected');
    }
    final body = jsonEncode(buildRequestBody(request));
    final res = await _send(
      () => _client.post(
        _endpoint('chat/completions'),
        headers: _headers,
        body: body,
      ),
    );
    return parseResponse(_decode(res));
  }

  @override
  Future<List<AiModelInfo>> listModels() async {
    final json = _decode(
      await _send(() => _client.get(_endpoint('models'), headers: _headers)),
    );
    final data = json['data'];
    if (data is! List) {
      throw AiException(AiErrorCode.invalidResponse, 'no data');
    }
    return [
      for (final m in data)
        if (m is Map && m['id'] is String && (m['id'] as String).isNotEmpty)
          AiModelInfo(id: m['id'] as String, displayName: m['id'] as String),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  JsonMap buildRequestBody(AiRequest r) {
    final messages = <JsonMap>[
      {'role': 'system', 'content': r.system},
    ];
    for (final m in r.messages) {
      switch (m) {
        case UserMessage(:final text):
          messages.add({'role': 'user', 'content': text});
        case AssistantMessage(:final text, :final toolCalls):
          messages.add({
            'role': 'assistant',
            'content': text.isEmpty && toolCalls.isNotEmpty ? null : text,
            if (toolCalls.isNotEmpty)
              'tool_calls': [
                for (final c in toolCalls)
                  {
                    'id': c.id,
                    'type': 'function',
                    'function': {
                      'name': c.name,
                      'arguments': jsonEncode(c.args),
                    },
                  },
              ],
          });
        case ToolResultMessage(:final callId, :final result):
          messages.add({
            'role': 'tool',
            'tool_call_id': callId,
            'content': jsonEncode(result),
          });
      }
    }
    return {
      'model': model.trim(),
      'messages': messages,
      if (r.tools.isNotEmpty)
        'tools': [
          for (final t in r.tools)
            {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            },
        ],
      if (reasoningEffort != null && reasoningEffort!.trim().isNotEmpty)
        'reasoning_effort': reasoningEffort!.trim(),
    };
  }

  AiResponse parseResponse(JsonMap json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw AiException(AiErrorCode.invalidResponse, 'no choices');
    }
    final choice = choices.first as Map;
    final finish = choice['finish_reason'];
    final msg = choice['message'];
    if (msg is! Map) {
      throw AiException(AiErrorCode.invalidResponse, 'no message');
    }
    final content = msg['content'];
    final text = switch (content) {
      String s => s,
      List l =>
        l.whereType<Map>().map((p) => p['text']).whereType<String>().join(),
      _ => '',
    };
    final calls = <ToolCall>[];
    final raw = msg['tool_calls'];
    if (raw is List) {
      for (final (i, c) in raw.indexed) {
        if (c is! Map) continue;
        final fn = c['function'];
        if (fn is! Map || fn['name'] is! String) {
          throw AiException(
            AiErrorCode.invalidResponse,
            'tool call without name',
          );
        }
        calls.add(
          ToolCall(
            id: (c['id'] as String?) ?? 'call_$i',
            name: fn['name'] as String,
            args: _parseArgs(fn['arguments']),
          ),
        );
      }
    }
    final refusal = msg['refusal'];
    if (text.isEmpty && calls.isEmpty) {
      if (finish == 'content_filter' ||
          (refusal is String && refusal.isNotEmpty)) {
        throw AiException(AiErrorCode.blocked);
      }
      if (finish == 'length') {
        throw AiException(
          AiErrorCode.invalidResponse,
          'answer cut off (length)',
        );
      }
    }
    final usage = json['usage'];
    return AiResponse(
      message: AssistantMessage(text: text, toolCalls: calls),
      usage: usage is Map
          ? AiUsage(
              inputTokens: (usage['prompt_tokens'] as num?)?.toInt(),
              outputTokens: (usage['completion_tokens'] as num?)?.toInt(),
            )
          : null,
    );
  }

  /// Arguments are a JSON string per the OpenAI spec; some compatible
  /// servers send an object. Invalid JSON becomes `{}` and the tool reports
  /// the missing argument back to the model.
  static JsonMap _parseArgs(Object? a) {
    if (a is Map) return Map<String, Object?>.from(a);
    if (a is String && a.trim().isNotEmpty) {
      try {
        final v = jsonDecode(a);
        if (v is Map) return Map<String, Object?>.from(v);
      } on FormatException {
        // fall through
      }
    }
    return const {};
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw AiException(AiErrorCode.timeout);
    } on SocketException {
      throw AiException(AiErrorCode.network);
    } on http.ClientException {
      throw AiException(AiErrorCode.network);
    }
  }

  JsonMap _decode(http.Response res) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (json is Map<String, Object?>) return json;
      throw AiException(AiErrorCode.invalidResponse, 'not JSON');
    }
    throw mapError(res.statusCode, json);
  }

  /// Maps HTTP errors using status and the documented `error.code`/`type`
  /// fields only; free-text messages are not passed on.
  static AiException mapError(int status, Object? json) {
    final err = json is Map ? json['error'] : null;
    final code = err is Map ? '${err['code'] ?? ''}' : '';
    final type = err is Map ? '${err['type'] ?? ''}' : '';
    if (status == 401) return AiException(AiErrorCode.unauthorized);
    if (status == 403) {
      return AiException(AiErrorCode.unauthorized, 'permission denied');
    }
    if (status == 429) {
      const billing = {
        'insufficient_quota',
        'credit_balance_exhausted',
        'organization_spend_limit_exceeded',
        'project_spend_limit_exceeded',
        'organization_usage_limit_exceeded',
      };
      return billing.contains(code) || billing.contains(type)
          ? AiException(AiErrorCode.quotaExceeded)
          : AiException(AiErrorCode.rateLimited);
    }
    if (status == 404) {
      return AiException(AiErrorCode.badRequest, 'model or URL not found');
    }
    if (status == 400 || status == 422) {
      return AiException(
        AiErrorCode.badRequest,
        code.isNotEmpty && RegExp(r'^[a-z_]+$').hasMatch(code)
            ? code
            : 'HTTP $status',
      );
    }
    if (status >= 500) return AiException(AiErrorCode.server, 'HTTP $status');
    return AiException(AiErrorCode.invalidResponse, 'HTTP $status');
  }
}
