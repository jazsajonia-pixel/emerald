import 'dart:convert';

import 'package:emerald/data/memory_vault_storage.dart';
import 'package:emerald/data/vault_storage.dart';
import 'package:emerald/features/ai/ai_config.dart';
import 'package:emerald/features/ai/ai_types.dart';
import 'package:emerald/features/ai/chat_controller.dart';
import 'package:emerald/features/ai/proposals.dart';
import 'package:emerald/features/search/index_controller.dart';
import 'package:emerald/features/vault/vault_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_provider.dart';

const vault = VaultHandle(id: 'memory://vault', name: 'V');
const secretKey = 'SECRET-KEY-xyz';

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MemoryVaultStorage storage;
  late ProviderContainer c;
  late FakeProvider fake;
  late List<String> keysSeen;

  Future<void> setUpWith(List<Object> script) async {
    storage = MemoryVaultStorage(
      files: {'Plan.md': 'Milestones.', 'Home.md': 'See [[Plan]]'},
      remembered: vault,
    );
    fake = FakeProvider(script);
    keysSeen = [];
    c = ProviderContainer.test(
      overrides: [
        vaultStorageProvider.overrideWithValue(storage),
        secretStoreProvider.overrideWithValue(
          MemorySecretStore({
            'ai.provider': 'gemini',
            'ai.model': 'm',
            'ai.gemini.apiKey': secretKey,
          }),
        ),
        aiProviderFactoryProvider.overrideWithValue((s) {
          keysSeen.add(s.apiKey);
          return fake;
        }),
      ],
    );
    c.listen(indexControllerProvider, (_, _) {});
    c.listen(aiConfigProvider, (_, _) {});
    await settle();
  }

  ChatState chat() => c.read(chatControllerProvider);
  ChatController ctl() => c.read(chatControllerProvider.notifier);
  String file(String p) => utf8.decode(storage.bytesOf(p)!);

  test('config loads from the secret store without exposing the key', () async {
    await setUpWith([]);
    final cfg = c.read(aiConfigProvider);
    expect(cfg.ready, isTrue);
    expect(cfg.hasKey, isTrue);
    expect(cfg.model, 'm');
  });

  test('tool loop: read, answer, and record shared notes', () async {
    await setUpWith([
      call('read_note', {'path': 'Plan.md'}),
      say('Your plan says: Milestones.'),
    ]);
    await ctl().send('What is my plan?');
    expect(keysSeen, [secretKey]);
    expect(chat().busy, isFalse);
    expect(chat().sharedNotes, {'Plan.md'});
    expect(
      chat().entries.whereType<AssistantEntry>().single.text,
      contains('Milestones'),
    );
    expect(
      chat().entries.whereType<ToolEntry>().single.description,
      'Read Plan.md',
    );
    // Second request carries the tool result back to the model.
    final second = fake.requests[1].messages;
    expect(second.last, isA<ToolResultMessage>());
    expect((second.last as ToolResultMessage).result['content'], 'Milestones.');
    // The key never appears in anything the model or UI sees.
    for (final r in fake.requests) {
      expect(
        jsonEncode(r.system) + r.messages.map((m) => m.toString()).join(),
        isNot(contains(secretKey)),
      );
    }
    for (final e in chat().entries) {
      if (e is AssistantEntry) expect(e.text, isNot(contains(secretKey)));
    }
  });

  test('approved edit is written; rejected edit is not', () async {
    await setUpWith([
      call('update_note', {
        'path': 'Plan.md',
        'new_content': 'Milestones.\n- M1',
      }),
      call('create_note', {'title': 'Ideas', 'content': 'x'}, id: 'c2'),
      say('I proposed two changes.'),
    ]);
    await ctl().send('Improve my plan');
    final proposals = chat().pendingProposals;
    expect(proposals, hasLength(2));
    expect(file('Plan.md'), 'Milestones.'); // nothing written yet
    expect(storage.bytesOf('Ideas.md'), isNull);

    expect(await ctl().approve(proposals[0]), isNull);
    expect(file('Plan.md'), 'Milestones.\n- M1');
    expect(proposals[0].status, ProposalStatus.applied);
    expect(
      c.read(indexControllerProvider).index.notes['Plan.md']!.text,
      contains('M1'),
    );

    ctl().reject(proposals[1]);
    expect(proposals[1].status, ProposalStatus.rejected);
    expect(storage.bytesOf('Ideas.md'), isNull);
    expect(chat().pendingProposals, isEmpty);
  });

  test('approval is refused if the note changed after the proposal', () async {
    await setUpWith([
      call('update_note', {'path': 'Plan.md', 'new_content': 'AI version'}),
      say('ok'),
    ]);
    await ctl().send('edit');
    storage.setFile('Plan.md', 'User edit');
    final err = await ctl().approve(chat().pendingProposals.single);
    expect(err, isNotNull);
    expect(file('Plan.md'), 'User edit');
  });

  test('provider errors are shown and leave notes untouched', () async {
    await setUpWith([AiException(AiErrorCode.rateLimited)]);
    await ctl().send('hi');
    expect(chat().entries.last, isA<ErrorEntry>());
    expect(
      (chat().entries.last as ErrorEntry).message,
      AiException(AiErrorCode.rateLimited).userMessage,
    );
    expect(chat().busy, isFalse);
    expect(file('Plan.md'), 'Milestones.');
  });

  test('stops after maxSteps tool rounds', () async {
    await setUpWith([
      for (var i = 0; i < ChatController.maxSteps + 2; i++)
        call('list_notes', {}, id: 'c$i'),
    ]);
    await ctl().send('loop');
    expect(fake.requests, hasLength(ChatController.maxSteps));
    expect(chat().entries.last, isA<ErrorEntry>());
  });

  test('not configured gives a clear error', () async {
    storage = MemoryVaultStorage(files: {'A.md': ''}, remembered: vault);
    c = ProviderContainer.test(
      overrides: [
        vaultStorageProvider.overrideWithValue(storage),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
      ],
    );
    c.listen(aiConfigProvider, (_, _) {});
    c.listen(vaultControllerProvider, (_, _) {});
    await settle();
    await c.read(chatControllerProvider.notifier).send('hi');
    expect(c.read(chatControllerProvider).entries.last, isA<ErrorEntry>());
  });

  test('clear resets the conversation', () async {
    await setUpWith([say('hello')]);
    await ctl().send('hi');
    ctl().clear();
    expect(chat().entries, isEmpty);
    expect(chat().sharedNotes, isEmpty);
  });
}
