import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/vault_storage.dart';
import '../search/index_controller.dart';
import '../vault/vault_controller.dart';
import 'ai_config.dart';
import 'ai_types.dart';
import 'proposals.dart';
import 'tools/vault_tools.dart';

sealed class ChatEntry {
  const ChatEntry();
}

class UserEntry extends ChatEntry {
  const UserEntry(this.text);
  final String text;
}

class AssistantEntry extends ChatEntry {
  const AssistantEntry(this.text);
  final String text;
}

class ToolEntry extends ChatEntry {
  const ToolEntry(this.description, {this.failed = false});
  final String description;
  final bool failed;
}

class ProposalEntry extends ChatEntry {
  const ProposalEntry(this.proposal);
  final NoteProposal proposal;
}

class ErrorEntry extends ChatEntry {
  const ErrorEntry(this.message);
  final String message;
}

class ChatState {
  const ChatState({
    this.entries = const [],
    this.busy = false,
    this.sharedNotes = const {},
    this.revision = 0,
  });

  final List<ChatEntry> entries;
  final bool busy;

  /// Notes whose content was sent to the provider in this conversation.
  final Set<String> sharedNotes;

  /// Bumped when a proposal's status changes (proposals are mutable).
  final int revision;

  List<NoteProposal> get pendingProposals => [
    for (final e in entries)
      if (e is ProposalEntry && e.proposal.status == ProposalStatus.pending)
        e.proposal,
  ];

  ChatState copyWith({
    List<ChatEntry>? entries,
    bool? busy,
    Set<String>? sharedNotes,
    bool bump = false,
  }) => ChatState(
    entries: entries ?? this.entries,
    busy: busy ?? this.busy,
    sharedNotes: sharedNotes ?? this.sharedNotes,
    revision: bump ? revision + 1 : revision,
  );
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

const systemPrompt = '''
You are the assistant inside Sapphire, a local-first Markdown notes app. The
user's notes live in a vault folder on their phone. Use the tools to search
and read notes before answering questions about them, and cite note titles
you used. To change notes, use create_note or update_note: these only create
proposals that the user reviews and approves; say so instead of claiming the
change is done. Never invent note contents. Keep answers concise. Write
Markdown. Note links use the [[Note Title]] syntax.''';

class ChatController extends Notifier<ChatState> {
  static const maxSteps = 8;
  final List<AiMessage> _history = [];
  int _proposalIds = 0;
  int _generation = 0;

  @override
  ChatState build() => const ChatState();

  void _add(ChatEntry e) =>
      state = state.copyWith(entries: [...state.entries, e]);

  void clear() {
    _generation++;
    _history.clear();
    state = const ChatState();
  }

  Future<void> send(String text) async {
    final question = text.trim();
    if (question.isEmpty || state.busy) return;
    final vaultState = ref.read(vaultControllerProvider);
    _add(UserEntry(question));
    if (vaultState is! VaultReady) {
      _add(const ErrorEntry('Open a vault first (Brain tab).'));
      return;
    }
    final gen = ++_generation;
    state = state.copyWith(busy: true);
    try {
      final provider = await ref
          .read(aiConfigProvider.notifier)
          .createProvider();
      final tools = VaultTools(
        vault: vaultState.vault,
        index: ref.read(indexControllerProvider).index,
        repository: ref.read(noteRepositoryProvider),
        nextProposalId: () => ++_proposalIds,
      );
      _history.add(UserMessage(question));
      for (var step = 0; step < maxSteps; step++) {
        final res = await provider.generate(
          AiRequest(
            system: systemPrompt,
            messages: List.of(_history),
            tools: provider.capabilities.toolUse ? VaultTools.specs : const [],
          ),
        );
        if (gen != _generation) return;
        final msg = res.message;
        _history.add(msg);
        if (msg.text.trim().isNotEmpty) _add(AssistantEntry(msg.text.trim()));
        if (msg.toolCalls.isEmpty) break;
        for (final call in msg.toolCalls) {
          final before = tools.proposals.length;
          final result = await tools.execute(call);
          if (gen != _generation) return;
          _history.add(
            ToolResultMessage(callId: call.id, name: call.name, result: result),
          );
          _add(
            ToolEntry(
              describeToolCall(call, result),
              failed: result.containsKey('error'),
            ),
          );
          for (final p in tools.proposals.skip(before)) {
            _add(ProposalEntry(p));
          }
          state = state.copyWith(
            sharedNotes: {...state.sharedNotes, ...tools.sharedNotes},
          );
        }
        if (step == maxSteps - 1) {
          _add(const ErrorEntry('Stopped: the AI used too many steps.'));
        }
      }
    } on AiException catch (e) {
      if (gen == _generation) _add(ErrorEntry(e.userMessage));
    } on Exception {
      if (gen == _generation) {
        _add(
          const ErrorEntry('Unexpected error. Your notes were not changed.'),
        );
      }
    } finally {
      if (gen == _generation) state = state.copyWith(busy: false);
    }
  }

  /// Applies one approved proposal. Returns an error message or null.
  Future<String?> approve(NoteProposal p) async {
    final v = ref.read(vaultControllerProvider);
    if (v is! VaultReady) return 'Open the vault first.';
    try {
      final doc = await ProposalApplier(ref.read(noteRepositoryProvider))
          .apply(v.vault, p);
      p.status = ProposalStatus.applied;
      ref
          .read(indexControllerProvider.notifier)
          .updateNote(doc.path, doc.text, doc.stamp);
      ref
          .read(vaultControllerProvider.notifier)
          .noteWritten(doc.path, doc.stamp);
      _history.add(
        UserMessage(
          '[Sapphire] The user approved proposal ${p.id}; it was applied to ${doc.path}.',
        ),
      );
      state = state.copyWith(bump: true);
      return null;
    } on VaultException catch (e) {
      p.status = ProposalStatus.failed;
      p.error = describeVaultError(e);
      state = state.copyWith(bump: true);
      return p.error;
    }
  }

  void reject(NoteProposal p) {
    if (p.status != ProposalStatus.pending) return;
    p.status = ProposalStatus.rejected;
    _history.add(UserMessage('[Sapphire] The user rejected proposal ${p.id}.'));
    state = state.copyWith(bump: true);
  }
}

String describeToolCall(ToolCall c, JsonMap result) {
  final err = result['error'];
  final arg =
      (c.args['path'] ??
              c.args['query'] ??
              c.args['title'] ??
              c.args['folder'] ??
              '')
          .toString();
  final what = switch (c.name) {
    'search_notes' => 'Searched notes for "$arg"',
    'list_notes' => 'Listed notes${arg.isEmpty ? '' : ' in $arg'}',
    'read_note' => 'Read $arg',
    'find_backlinks' => 'Looked up backlinks of $arg',
    'find_related_notes' => 'Looked up notes related to $arg',
    'create_note' => 'Proposed a new note "$arg"',
    'update_note' => 'Proposed an edit to $arg',
    _ => 'Used ${c.name}',
  };
  return err == null ? what : '$what — failed: $err';
}
