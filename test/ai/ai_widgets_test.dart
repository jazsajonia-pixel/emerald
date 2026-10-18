import 'dart:convert';

import 'package:sapphire/data/memory_vault_storage.dart';
import 'package:sapphire/data/vault_storage.dart';
import 'package:sapphire/features/ai/ai_config.dart';
import 'package:sapphire/features/ai/ai_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import 'fake_provider.dart';

const _vault = VaultHandle(id: 'memory://vault', name: 'My Vault');
const _key = 'MY-SECRET-KEY-123';

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openAi(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('AI Hub'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'settings: save key securely, never display it, test connection',
    (tester) async {
      final secrets = MemorySecretStore();
      final keys = <String>[];
      await pumpSapphire(
        tester,
        secrets: secrets,
        aiFactory: (s) {
          keys.add(s.apiKey);
          return FakeProvider([]);
        },
      );
      await _openAi(tester);
      await tester.tap(find.text('Set up a provider'));
      await tester.pumpAndSettle();
      expect(find.text('AI provider'), findsOneWidget);

      // Saving without a key is refused.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an API key first.'), findsOneWidget);
      expect(secrets.values, isEmpty);

      await tester.enterText(find.byKey(const Key('api-key-field')), _key);
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(keys, [_key]);
      expect(find.textContaining('Connection works'), findsOneWidget);
      expect(find.text('fake-1'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(secrets.values['ai.gemini.apiKey'], _key);
      expect(secrets.values['ai.provider'], 'gemini');
      // The field is cleared and the key is not rendered anywhere.
      expect(find.textContaining(_key), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('api-key-field')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.textContaining('saved'), findsWidgets);

      // Remove deletes the key after confirmation.
      await tester.ensureVisible(find.text('Remove key'));
      await tester.tap(find.text('Remove key'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(secrets.values.containsKey('ai.gemini.apiKey'), isFalse);
    },
  );

  testWidgets('settings: connection errors are shown in plain language', (
    tester,
  ) async {
    await pumpSapphire(tester, aiFactory: (s) => _FailingProvider());
    await _openAi(tester);
    await tester.tap(find.text('Set up a provider'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key-field')), 'bad');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(
      find.text(AiException(AiErrorCode.unauthorized).userMessage),
      findsOneWidget,
    );
  });

  testWidgets('settings: OpenAI-compatible base URL rules', (tester) async {
    final secrets = MemorySecretStore();
    final built = <ProviderSettings>[];
    await pumpSapphire(
      tester,
      secrets: secrets,
      aiFactory: (s) {
        built.add(s);
        return FakeProvider([]);
      },
    );
    await _openAi(tester);
    await tester.tap(find.text('Set up a provider'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('base-url-field')), findsNothing);
    await tester.tap(find.text('Google Gemini'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI-compatible').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('base-url-field')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('base-url-field')))
          .controller!
          .text,
      'https://api.openai.com/v1',
    );

    // Plain http to another machine is refused.
    await tester.enterText(
      find.byKey(const Key('base-url-field')),
      'http://192.168.1.9:11434/v1',
    );
    await tester.enterText(find.byKey(const Key('model-field')), 'llama3');
    await _tapVisible(tester, find.text('Save'));
    expect(
      find.textContaining('plain http is only allowed for localhost'),
      findsOneWidget,
    );
    expect(secrets.values, isEmpty);

    // A server on this phone needs no key.
    await tester.enterText(
      find.byKey(const Key('base-url-field')),
      'http://localhost:11434/v1',
    );
    await tester.pumpAndSettle();
    expect(find.text('API key (optional for localhost)'), findsOneWidget);
    await _tapVisible(tester, find.text('Test connection'));
    expect(built.single.baseUrl, 'http://localhost:11434/v1');
    expect(built.single.apiKey, isEmpty);
    await _tapVisible(tester, find.text('Save'));
    expect(secrets.values['ai.provider'], 'openai_compatible');
    expect(
      secrets.values['ai.openai_compatible.baseUrl'],
      'http://localhost:11434/v1',
    );
    expect(secrets.values.containsKey('ai.openai_compatible.apiKey'), isFalse);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Ask about your notes'), findsNothing); // no vault yet
    expect(find.text('Open a vault first'), findsOneWidget);
  });

  testWidgets('chat: consent, proposal preview, approve and reject', (
    tester,
  ) async {
    final storage = MemoryVaultStorage(
      files: {'Plan.md': 'Milestones.'},
      remembered: _vault,
    );
    final fake = FakeProvider([
      call('read_note', {'path': 'Plan.md'}),
      call('update_note', {
        'path': 'Plan.md',
        'new_content': 'Milestones.\n- M1',
        'summary': 'Add M1',
      }, id: 'c2'),
      say('I proposed adding **M1**.'),
    ]);
    await pumpSapphire(
      tester,
      storage: storage,
      secrets: MemorySecretStore({
        'ai.provider': 'gemini',
        'ai.model': 'm',
        'ai.gemini.apiKey': _key,
      }),
      aiFactory: (s) => fake,
    );
    await _openAi(tester);
    expect(find.text('Ask about your notes'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ai-input')),
      'Improve my plan',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    // Consent first; cancelling sends nothing.
    expect(find.text('Send notes to an AI provider?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.requests, isEmpty);

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(fake.requests, isNotEmpty);
    expect(
      find.textContaining('Sent to Google Gemini: 1 note'),
      findsOneWidget,
    );
    expect(find.text('Proposed edit: Plan.md'), findsOneWidget);
    expect(find.text('+ - M1'), findsOneWidget);
    expect(utf8.decode(storage.bytesOf('Plan.md')!), 'Milestones.');

    await tester.tap(find.text('Approve & save'));
    await tester.pumpAndSettle();
    expect(utf8.decode(storage.bytesOf('Plan.md')!), 'Milestones.\n- M1');
    expect(find.text('Applied'), findsOneWidget);
  });

  testWidgets('chat: bulk apply requires explicit confirmation', (
    tester,
  ) async {
    final storage = MemoryVaultStorage(
      files: {'A.md': 'a'},
      remembered: _vault,
    );
    final fake = FakeProvider([
      call('create_note', {'title': 'One', 'content': '1'}),
      call('create_note', {'title': 'Two', 'content': '2'}, id: 'c2'),
      say('Two notes proposed.'),
    ]);
    await pumpSapphire(
      tester,
      storage: storage,
      secrets: MemorySecretStore({
        'ai.provider': 'gemini',
        'ai.model': 'm',
        'ai.gemini.apiKey': _key,
        'ai.consent': 'yes',
      }),
      aiFactory: (s) => fake,
    );
    await _openAi(tester);
    await tester.enterText(find.byKey(const Key('ai-input')), 'make notes');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(
      find.text('2 proposed changes are waiting for review.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Review & apply all'));
    await tester.pumpAndSettle();
    expect(find.text('Apply 2 changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(storage.bytesOf('One.md'), isNull);

    await tester.tap(find.text('Review & apply all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply all'));
    await tester.pumpAndSettle();
    expect(utf8.decode(storage.bytesOf('One.md')!), '1');
    expect(utf8.decode(storage.bytesOf('Two.md')!), '2');
  });

  testWidgets('chat: reject leaves the vault unchanged', (tester) async {
    final storage = MemoryVaultStorage(
      files: {'A.md': 'a'},
      remembered: _vault,
    );
    final fake = FakeProvider([
      call('update_note', {'path': 'A.md', 'new_content': 'changed'}),
      say('Proposed.'),
    ]);
    await pumpSapphire(
      tester,
      storage: storage,
      secrets: MemorySecretStore({
        'ai.provider': 'gemini',
        'ai.model': 'm',
        'ai.gemini.apiKey': _key,
        'ai.consent': 'yes',
      }),
      aiFactory: (s) => fake,
    );
    await _openAi(tester);
    await tester.enterText(find.byKey(const Key('ai-input')), 'edit');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Rejected — nothing changed'), findsOneWidget);
    expect(utf8.decode(storage.bytesOf('A.md')!), 'a');
  });
}

class _FailingProvider extends FakeProvider {
  _FailingProvider() : super([]);
  @override
  Future<List<AiModelInfo>> listModels() async =>
      throw AiException(AiErrorCode.unauthorized);
}
