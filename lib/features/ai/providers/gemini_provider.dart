import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../ai_types.dart';

/// Google Gemini API adapter (REST `models.generateContent`).
///
/// Verified against the official reference (October 2026):
/// - `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
/// - `GET  https://generativelanguage.googleapis.com/v1beta/models` (list)
/// - API key in the `x-goog-api-key` header (never in the URL, so it cannot
///   leak through logged URLs).
/// - Tools: `tools[].functionDeclarations[]` with `parametersJsonSchema`.
/// - Model turns are sent back exactly as received so that any
///   `thoughtSignature` fields on parts are preserved.
class GeminiProvider implements AiProvider {
  GeminiProvider({
    required String apiKey,
    required this.model,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client() {
    _apiKey = apiKey;
  }

  static const providerId = 'gemini';
  static final _base = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/',
  );

  late final String _apiKey;
  final String model;
  final http.Client _client;
  final Duration timeout;
  int _callCounter = 0;

  @override
  String get id => providerId;

  @override
  String get displayName => 'Google Gemini';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    text: true,
    toolUse: true,
    streaming: false, // the API supports it; Emerald does not use it yet
    listModels: true,
  );

  Map<String, String> get _headers => {
    'x-goog-api-key': _apiKey,
    'content-type': 'application/json',
  };

  static String _modelPath(String model) {
    final m = model.startsWith('models/') ? model.substring(7) : model;
    if (!RegExp(r'^[A-Za-z0-9._\-]+$').hasMatch(m)) {
      throw AiException(AiErrorCode.badRequest, 'invalid model name');
    }
    return 'models/$m';
  }

  @override
  Future<AiResponse> generate(AiRequest request) async {
    final uri = _base.resolve('${_modelPath(model)}:generateContent');
    final body = jsonEncode(buildRequestBody(request));
    final res = await _send(
      () => _client.post(uri, headers: _headers, body: body),
    );
    return parseResponse(_decode(res));
  }

  @override
  Future<List<AiModelInfo>> listModels() async {
    final out = <AiModelInfo>[];
    String? page;
    for (var i = 0; i < 10; i++) {
      final uri = _base
          .resolve('models')
          .replace(queryParameters: {'pageSize': '100', 'pageToken': ?page});
      final json = _decode(
        await _send(() => _client.get(uri, headers: _headers)),
      );
      for (final m in (json['models'] as List?) ?? const []) {
        if (m is! Map) continue;
        final methods = (m['supportedGenerationMethods'] as List?) ?? const [];
        if (!methods.contains('generateContent')) continue;
        final name = (m['name'] as String?) ?? '';
        final id = name.startsWith('models/') ? name.substring(7) : name;
        if (id.isEmpty) continue;
        out.add(
          AiModelInfo(id: id, displayName: (m['displayName'] as String?) ?? id),
        );
      }
      page = json['nextPageToken'] as String?;
      if (page == null || page.isEmpty) break;
    }
    return out;
  }

  // ---- Request building ---------------------------------------------------

  JsonMap buildRequestBody(AiRequest r) {
    final contents = <JsonMap>[];
    final pendingResults = <JsonMap>[];
    void flushResults() {
      if (pendingResults.isEmpty) return;
      contents.add({'role': 'user', 'parts': List.of(pendingResults)});
      pendingResults.clear();
    }

    for (final m in r.messages) {
      switch (m) {
        case UserMessage(:final text):
          flushResults();
          contents.add({
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          });
        case AssistantMessage():
          flushResults();
          final raw = m.providerData;
          if (raw is JsonMap && raw['parts'] is List) {
            contents.add({'role': 'model', 'parts': raw['parts']});
          } else {
            contents.add({
              'role': 'model',
              'parts': [
                if (m.text.isNotEmpty) {'text': m.text},
                for (final c in m.toolCalls)
                  {
                    'functionCall': {'name': c.name, 'args': c.args},
                  },
              ],
            });
          }
        case ToolResultMessage():
          pendingResults.add({
            'functionResponse': {
              if (!m.callId.startsWith('local-')) 'id': m.callId,
              'name': m.name,
              'response': m.result,
            },
          });
      }
    }
    flushResults();
    return {
      'systemInstruction': {
        'parts': [
          {'text': r.system},
        ],
      },
      'contents': contents,
      if (r.tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final t in r.tools)
                {
                  'name': t.name,
                  'description': t.description,
                  'parametersJsonSchema': t.parameters,
                },
            ],
          },
        ],
    };
  }

  // ---- Response parsing ---------------------------------------------------

  AiResponse parseResponse(JsonMap json) {
    final feedback = json['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw AiException(AiErrorCode.blocked, '${feedback['blockReason']}');
    }
    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw AiException(AiErrorCode.invalidResponse, 'no candidates');
    }
    final cand = candidates.first;
    if (cand is! Map) throw AiException(AiErrorCode.invalidResponse);
    final finish = cand['finishReason'] as String?;
    final content = cand['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List || parts.isEmpty) {
      if (const {
        'SAFETY',
        'RECITATION',
        'BLOCKLIST',
        'PROHIBITED_CONTENT',
        'SPII',
      }.contains(finish)) {
        throw AiException(AiErrorCode.blocked, finish);
      }
      throw AiException(AiErrorCode.invalidResponse, 'empty content ($finish)');
    }
    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final p in parts) {
      if (p is! Map) continue;
      if (p['thought'] == true) continue; // thought summaries are not shown
      final t = p['text'];
      if (t is String) text.write(t);
      final fc = p['functionCall'];
      if (fc is Map) {
        final name = fc['name'];
        if (name is! String || name.isEmpty) {
          throw AiException(
            AiErrorCode.invalidResponse,
            'function call without name',
          );
        }
        final args = fc['args'];
        calls.add(
          ToolCall(
            id: (fc['id'] as String?) ?? 'local-${++_callCounter}',
            name: name,
            args: args is Map ? Map<String, Object?>.from(args) : const {},
          ),
        );
      }
    }
    final usage = json['usageMetadata'];
    return AiResponse(
      message: AssistantMessage(
        text: text.toString(),
        toolCalls: calls,
        providerData: <String, Object?>{'parts': parts},
      ),
      usage: usage is Map
          ? AiUsage(
              inputTokens: (usage['promptTokenCount'] as num?)?.toInt(),
              outputTokens: (usage['candidatesTokenCount'] as num?)?.toInt(),
            )
          : null,
    );
  }

  // ---- Transport and errors -------------------------------------------------

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

  /// Maps an HTTP error to [AiException]. Only Google's status strings are
  /// kept; the free-text message is not included in full, so nothing echoed
  /// from the request can leak into logs.
  static AiException mapError(int status, Object? json) {
    final err = json is Map ? json['error'] : null;
    final gStatus = err is Map ? err['status'] as String? : null;
    final message = err is Map ? (err['message'] as String? ?? '') : '';
    final details = err is Map ? jsonEncode(err['details'] ?? const []) : '';
    if (details.contains('API_KEY_INVALID') ||
        message.contains('API key not valid') ||
        status == 401 ||
        gStatus == 'UNAUTHENTICATED') {
      return AiException(AiErrorCode.unauthorized);
    }
    if (status == 403 || gStatus == 'PERMISSION_DENIED') {
      return AiException(AiErrorCode.unauthorized, 'permission denied');
    }
    if (status == 429 || gStatus == 'RESOURCE_EXHAUSTED') {
      return message.toLowerCase().contains('quota')
          ? AiException(AiErrorCode.quotaExceeded)
          : AiException(AiErrorCode.rateLimited);
    }
    if (status == 404 || gStatus == 'NOT_FOUND') {
      return AiException(AiErrorCode.badRequest, 'model not found');
    }
    if (status == 400 ||
        gStatus == 'INVALID_ARGUMENT' ||
        gStatus == 'FAILED_PRECONDITION') {
      return AiException(AiErrorCode.badRequest, gStatus ?? 'HTTP $status');
    }
    if (status >= 500) return AiException(AiErrorCode.server, 'HTTP $status');
    return AiException(AiErrorCode.invalidResponse, 'HTTP $status');
  }
}
