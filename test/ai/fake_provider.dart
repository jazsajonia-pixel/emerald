import 'package:sapphire/features/ai/ai_types.dart';

/// Scripted provider for tests: returns the queued responses in order and
/// records every request.
class FakeProvider implements AiProvider {
  FakeProvider(this.script);

  final List<Object> script; // AiResponse or AiException
  final List<AiRequest> requests = [];

  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake';
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
    text: true,
    toolUse: true,
    streaming: false,
    listModels: true,
  );

  @override
  Future<AiResponse> generate(AiRequest request) async {
    requests.add(request);
    if (script.isEmpty) {
      return const AiResponse(message: AssistantMessage(text: 'done'));
    }
    final next = script.removeAt(0);
    if (next is AiException) throw next;
    return next as AiResponse;
  }

  @override
  Future<List<AiModelInfo>> listModels() async => const [
    AiModelInfo(id: 'fake-1', displayName: 'Fake 1'),
  ];
}

AiResponse call(String name, Map<String, Object?> args, {String id = 'c1'}) =>
    AiResponse(
      message: AssistantMessage(
        toolCalls: [ToolCall(id: id, name: name, args: args)],
      ),
    );

AiResponse say(String text) =>
    AiResponse(message: AssistantMessage(text: text));
