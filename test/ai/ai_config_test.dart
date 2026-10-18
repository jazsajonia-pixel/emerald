import 'package:sapphire/features/ai/ai_config.dart';
import 'package:sapphire/features/ai/ai_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_provider.dart';

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MemorySecretStore store;
  late ProviderContainer c;
  late List<ProviderSettings> built;

  Future<void> start([Map<String, String>? initial]) async {
    store = MemorySecretStore(initial);
    built = [];
    c = ProviderContainer.test(
      overrides: [
        secretStoreProvider.overrideWithValue(store),
        aiProviderFactoryProvider.overrideWithValue((s) {
          built.add(s);
          return FakeProvider([]);
        }),
      ],
    );
    c.listen(aiConfigProvider, (_, _) {});
    await settle();
  }

  AiConfigController ctl() => c.read(aiConfigProvider.notifier);
  AiConfig cfg() => c.read(aiConfigProvider);

  test(
    'switching providers keeps each provider\'s settings and keys',
    () async {
      await start();
      await ctl().configure(
        providerId: 'gemini',
        model: 'g-1',
        apiKey: 'G-KEY',
      );
      await ctl().configure(
        providerId: 'openai_compatible',
        model: 'gpt-6-luna',
        apiKey: 'O-KEY',
        baseUrl: 'https://api.openai.com/v1',
        reasoningEffort: 'none',
      );
      expect(cfg().providerId, 'openai_compatible');
      await ctl().createProvider();
      expect(built.last.apiKey, 'O-KEY');
      expect(built.last.reasoningEffort, 'none');

      await ctl().configure(providerId: 'gemini', model: 'g-1');
      await ctl().createProvider();
      expect(built.last.providerId, 'gemini');
      expect(built.last.apiKey, 'G-KEY');
      expect(built.last.baseUrl, isNull);
      // Only settings keys are stored; nothing else.
      expect(store.values.keys.every((k) => k.startsWith('ai.')), isTrue);
    },
  );

  test('legacy Phase 5 model key is still read for Gemini', () async {
    await start({
      'ai.provider': 'gemini',
      'ai.model': 'old-model',
      'ai.gemini.apiKey': 'k',
    });
    expect(cfg().model, 'old-model');
    expect(cfg().ready, isTrue);
  });

  test(
    'localhost OpenAI-compatible server needs no key; remote does',
    () async {
      await start();
      await ctl().configure(
        providerId: 'openai_compatible',
        model: 'llama',
        baseUrl: 'http://localhost:11434/v1',
      );
      expect(cfg().hasKey, isFalse);
      expect(cfg().ready, isTrue);
      await ctl().createProvider();
      expect(built.last.apiKey, '');

      await ctl().configure(
        providerId: 'openai_compatible',
        model: 'llama',
        baseUrl: 'https://example.com/v1',
      );
      expect(cfg().ready, isFalse);
      await expectLater(ctl().createProvider(), throwsA(isA<AiException>()));
    },
  );

  test('remove deletes only the active provider', () async {
    await start();
    await ctl().configure(providerId: 'gemini', model: 'g', apiKey: 'G');
    await ctl().configure(
      providerId: 'openai_compatible',
      model: 'o',
      apiKey: 'O',
      baseUrl: 'https://api.openai.com/v1',
    );
    await ctl().removeProvider();
    expect(cfg().providerId, isNull);
    expect(store.values['ai.gemini.apiKey'], 'G');
    expect(store.values.containsKey('ai.openai_compatible.apiKey'), isFalse);
  });

  test('settings toString never includes the key', () {
    const s = ProviderSettings(
      providerId: 'gemini',
      apiKey: 'TOPSECRET',
      model: 'm',
    );
    expect(s.toString(), isNot(contains('TOPSECRET')));
  });
}
