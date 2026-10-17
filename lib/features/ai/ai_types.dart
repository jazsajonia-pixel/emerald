/// Provider-neutral AI types. Nothing in here knows about any specific
/// provider's wire format; adapters translate to and from these.
library;

/// JSON-compatible map used for tool arguments and results.
typedef JsonMap = Map<String, Object?>;

class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// `[a-z_]+`, stable across providers.
  final String name;
  final String description;

  /// JSON Schema (type: object) describing the arguments.
  final JsonMap parameters;
}

class ToolCall {
  const ToolCall({required this.id, required this.name, required this.args});

  /// Provider-supplied id, or a locally generated one.
  final String id;
  final String name;
  final JsonMap args;
}

sealed class AiMessage {
  const AiMessage();
}

class UserMessage extends AiMessage {
  const UserMessage(this.text);
  final String text;
}

class AssistantMessage extends AiMessage {
  const AssistantMessage({
    this.text = '',
    this.toolCalls = const [],
    this.providerData,
  });

  final String text;
  final List<ToolCall> toolCalls;

  /// Opaque provider data that must be sent back unchanged in later requests
  /// (e.g. Gemini thought signatures). Only the adapter that produced it may
  /// interpret it.
  final Object? providerData;
}

class ToolResultMessage extends AiMessage {
  const ToolResultMessage({
    required this.callId,
    required this.name,
    required this.result,
  });

  final String callId;
  final String name;
  final JsonMap result;
}

class AiRequest {
  const AiRequest({
    required this.system,
    required this.messages,
    this.tools = const [],
  });

  final String system;
  final List<AiMessage> messages;
  final List<ToolSpec> tools;
}

class AiUsage {
  const AiUsage({this.inputTokens, this.outputTokens});
  final int? inputTokens;
  final int? outputTokens;
}

class AiResponse {
  const AiResponse({required this.message, this.usage});
  final AssistantMessage message;
  final AiUsage? usage;
}

enum AiErrorCode {
  notConfigured,
  unauthorized,
  rateLimited,
  quotaExceeded,
  timeout,
  network,
  blocked,
  badRequest,
  server,
  invalidResponse,
  cancelled,
}

/// Error from an AI provider. [message] is safe to show and log: adapters
/// must never put API keys or note contents into it.
class AiException implements Exception {
  AiException(this.code, [this.message]);
  final AiErrorCode code;
  final String? message;

  String get userMessage => switch (code) {
    AiErrorCode.notConfigured => 'No AI provider is set up yet.',
    AiErrorCode.unauthorized =>
      'The API key was rejected. Check it in Settings → AI provider.',
    AiErrorCode.rateLimited =>
      'The provider is rate-limiting requests. Wait a moment and try again.',
    AiErrorCode.quotaExceeded =>
      'Your quota for this provider is used up. Check your plan or limits.',
    AiErrorCode.timeout => 'The provider did not answer in time.',
    AiErrorCode.network => 'No connection to the provider.',
    AiErrorCode.blocked => 'The provider declined to answer this request.',
    AiErrorCode.badRequest =>
      'The provider rejected the request${message == null ? '' : ': $message'}',
    AiErrorCode.server => 'The provider had a server error. Try again later.',
    AiErrorCode.invalidResponse => 'The provider sent an unexpected answer.',
    AiErrorCode.cancelled => 'Cancelled.',
  };

  @override
  String toString() => 'AiException(${code.name})';
}

/// What a provider adapter can actually do. Features that are not supported
/// are disabled in the UI rather than simulated.
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.text,
    required this.toolUse,
    required this.streaming,
    required this.listModels,
  });

  final bool text;
  final bool toolUse;
  final bool streaming;
  final bool listModels;
}

class AiModelInfo {
  const AiModelInfo({required this.id, required this.displayName});
  final String id;
  final String displayName;
}

/// One provider adapter (e.g. Gemini). Implementations are stateless apart
/// from configuration and must not log request or response bodies.
abstract interface class AiProvider {
  String get id;
  String get displayName;
  ProviderCapabilities get capabilities;

  Future<AiResponse> generate(AiRequest request);

  /// Lists models usable for chat. Must not consume generation quota.
  Future<List<AiModelInfo>> listModels();
}
