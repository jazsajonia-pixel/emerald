import '../../core/vault/vault_path.dart';
import '../../data/vault_storage.dart';
import '../notes/note_repository.dart';

enum ProposalKind { create, update }

enum ProposalStatus { pending, applied, rejected, failed }

/// A change the AI wants to make. Nothing is written until the user
/// approves it in the UI.
class NoteProposal {
  NoteProposal({
    required this.id,
    required this.kind,
    required this.path,
    required this.newText,
    this.oldText,
    this.baseSha256,
    this.summary,
  });

  final int id;
  final ProposalKind kind;

  /// Target note path (for create: the path that would be created).
  final String path;
  final String newText;

  /// Content when the proposal was made (update only).
  final String? oldText;

  /// Hash of the file when the proposal was made; applying is refused if
  /// the note changed since.
  final String? baseSha256;
  final String? summary;
  ProposalStatus status = ProposalStatus.pending;
  String? error;

  String get title => VaultPath.title(path);
}

class ProposalResult {
  const ProposalResult(this.document);
  final NoteDocument document;
}

/// Applies approved proposals through the normal, conflict-safe note
/// repository (history is kept for updates; creates never overwrite).
class ProposalApplier {
  ProposalApplier(this._repo);
  final NoteRepository _repo;

  Future<NoteDocument> apply(VaultHandle vault, NoteProposal p) async {
    if (p.status != ProposalStatus.pending) {
      throw StateError('Proposal ${p.id} is not pending');
    }
    switch (p.kind) {
      case ProposalKind.create:
        return _repo.create(
          vault,
          VaultPath.parent(p.path),
          VaultPath.title(p.path),
          content: p.newText,
        );
      case ProposalKind.update:
        final current = await _repo.open(vault, p.path);
        if (current.stamp.sha256 != p.baseSha256) {
          throw VaultException(
            VaultErrorCode.conflict,
            'The note changed after the AI proposed this edit.',
          );
        }
        return _repo.save(vault, current, p.newText);
    }
  }
}
