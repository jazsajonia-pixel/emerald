import 'dart:convert';
import 'dart:typed_data';

import '../../core/vault/vault_path.dart';
import '../../data/vault_storage.dart';
import '../ai/proposals.dart';
import '../notes/note_repository.dart';
import 'git_hash.dart';
import 'github_client.dart';

/// Folder in the sync repository where the optional Emerald MCP server
/// (mcp-server/) stores AI proposals. Hidden, so sync never copies it into
/// the vault.
const remoteProposalsDir = '.emerald/proposals';
const _maxProposalBytes = 1024 * 1024;

/// A proposal file written by an external AI app through the MCP server.
/// Format: see mcp-server/src/proposals.ts (version 1).
class RemoteProposal {
  const RemoteProposal({
    required this.id,
    required this.kind,
    required this.path,
    required this.content,
    required this.summary,
    this.baseSha,
    this.createdAt,
    this.client,
  });

  final String id;
  final ProposalKind kind;
  final String path;
  final String content;
  final String summary;

  /// Git blob SHA of the note on GitHub when the AI proposed the change.
  final String? baseSha;
  final DateTime? createdAt;
  final String? client;

  /// Parses and validates a proposal file; null if it is not a valid,
  /// safe proposal (wrong format, unsafe path, too large).
  static RemoteProposal? parse(Uint8List bytes) {
    if (bytes.length > _maxProposalBytes) return null;
    Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    if (j['format'] != 'emerald-proposal' || j['version'] != 1) return null;
    final id = j['id'], kind = j['kind'], path = j['path'];
    final content = j['content'], summary = j['summary'], base = j['baseSha'];
    if (id is! String || path is! String || content is! String) return null;
    final k = switch (kind) {
      'create' => ProposalKind.create,
      'update' => ProposalKind.update,
      _ => null,
    };
    if (k == null) return null;
    String normalized;
    try {
      normalized = VaultPath.normalize(path);
    } on InvalidVaultPath {
      return null;
    }
    if (normalized != path || !VaultPath.isMarkdown(path)) return null;
    if (k == ProposalKind.update &&
        (base is! String || !RegExp(r'^[0-9a-f]{40}$').hasMatch(base))) {
      return null;
    }
    final created = j['createdAt'];
    final client = j['client'];
    return RemoteProposal(
      id: id,
      kind: k,
      path: path,
      content: content,
      summary: summary is String && summary.trim().isNotEmpty
          ? summary.trim()
          : '(no summary)',
      baseSha: base is String ? base : null,
      createdAt: created is String ? DateTime.tryParse(created) : null,
      client: client is String && client.isNotEmpty ? client : null,
    );
  }
}

enum InboxItemState {
  /// Can be approved: the note on this phone is exactly what the AI read.
  ready,

  /// The note on this phone differs from what the AI saw (or is missing, or
  /// a note with the name already exists). Only rejecting is offered.
  stale,

  /// The phone already has exactly the proposed text.
  alreadyApplied,

  /// The file is not a valid proposal.
  invalid,
}

class InboxItem {
  InboxItem({
    required this.file,
    required this.state,
    this.proposal,
    this.note,
    this.reason,
  });

  /// The proposal file on GitHub.
  final RemoteFile file;
  final InboxItemState state;
  final RemoteProposal? proposal;

  /// Diff-ready proposal for the AI Hub's card (state [InboxItemState.ready]).
  final NoteProposal? note;
  final String? reason;
}

/// Lists AI proposals stored on GitHub and applies the ones the user
/// approves to the local vault. Notes are written only through
/// [NoteRepository] (conflict-checked, history kept, creates never
/// overwrite). The proposal file on GitHub is removed after a decision.
/// The approved change reaches GitHub with the next "Sync now".
class RemoteProposalInbox {
  RemoteProposalInbox({
    required this.client,
    required this.branch,
    required this.vault,
    required this.storage,
    required this.repository,
  });

  final GitHubClient client;
  final String branch;
  final VaultHandle vault;
  final VaultStorage storage;
  final NoteRepository repository;

  static bool isProposalPath(String p) =>
      p.startsWith('$remoteProposalsDir/') &&
      p.endsWith('.json') &&
      !p.substring(remoteProposalsDir.length + 1).contains('/');

  Future<List<InboxItem>> load() async {
    final files =
        (await client.listFiles(branch))
            .where((f) => isProposalPath(f.path))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final items = <InboxItem>[];
    var nextId = 1;
    for (final f in files) {
      if (f.size > _maxProposalBytes) {
        items.add(
          InboxItem(
            file: f,
            state: InboxItemState.invalid,
            reason: 'Too large.',
          ),
        );
        continue;
      }
      final p = RemoteProposal.parse(await client.getBlob(f.sha));
      if (p == null) {
        items.add(
          InboxItem(
            file: f,
            state: InboxItemState.invalid,
            reason: 'Not a valid Emerald proposal.',
          ),
        );
        continue;
      }
      items.add(await _evaluate(f, p, nextId++));
    }
    return items;
  }

  Future<NoteDocument?> _openLocal(String path) async {
    try {
      return await repository.open(vault, path);
    } on VaultException catch (e) {
      if (e.code == VaultErrorCode.notFound) return null;
      rethrow;
    }
  }

  Future<InboxItem> _evaluate(RemoteFile f, RemoteProposal p, int id) async {
    final local = await _openLocal(p.path);
    if (local != null && local.text == p.content) {
      return InboxItem(
        file: f,
        state: InboxItemState.alreadyApplied,
        proposal: p,
        reason: 'This note already has the proposed text.',
      );
    }
    switch (p.kind) {
      case ProposalKind.create:
        if (local != null) {
          return InboxItem(
            file: f,
            state: InboxItemState.stale,
            proposal: p,
            reason: 'A note with this name already exists on this phone.',
          );
        }
        return InboxItem(
          file: f,
          state: InboxItemState.ready,
          proposal: p,
          note: NoteProposal(
            id: id,
            kind: ProposalKind.create,
            path: p.path,
            newText: p.content,
            summary: p.summary,
          ),
        );
      case ProposalKind.update:
        if (local == null) {
          return InboxItem(
            file: f,
            state: InboxItemState.stale,
            proposal: p,
            reason: 'This note is not on this phone. Tap Sync now first.',
          );
        }
        if (gitBlobSha(local.bytes) != p.baseSha) {
          return InboxItem(
            file: f,
            state: InboxItemState.stale,
            proposal: p,
            reason:
                'The note on this phone differs from the version the AI read. '
                'Sync first, then ask the AI to redo the change if needed.',
          );
        }
        return InboxItem(
          file: f,
          state: InboxItemState.ready,
          proposal: p,
          note: NoteProposal(
            id: id,
            kind: ProposalKind.update,
            path: p.path,
            newText: p.content,
            oldText: local.text,
            baseSha256: local.stamp.sha256,
            summary: p.summary,
          ),
        );
    }
  }

  /// Writes the approved change to the vault, then removes the proposal
  /// file on GitHub. If removing fails, the note stays saved and the item
  /// shows up as "already applied" next time, so it can be removed then.
  Future<NoteDocument> approve(InboxItem item) async {
    final note = item.note;
    if (item.state != InboxItemState.ready || note == null) {
      throw StateError('Only ready proposals can be approved');
    }
    if (note.kind == ProposalKind.create) {
      final parent = VaultPath.parent(note.path);
      if (parent.isNotEmpty) await storage.createDirectory(vault, parent);
    }
    final doc = await ProposalApplier(repository).apply(vault, note);
    note.status = ProposalStatus.applied;
    await _remove(item, 'Approved in Emerald');
    return doc;
  }

  /// Rejects or clears a proposal: removes its file on GitHub. Notes are
  /// not touched.
  Future<void> dismiss(InboxItem item) => _remove(
    item,
    item.state == InboxItemState.alreadyApplied
        ? 'Applied'
        : 'Rejected in Emerald',
  );

  Future<void> _remove(InboxItem item, String why) => client.deleteFile(
    path: item.file.path,
    sha: item.file.sha,
    branch: branch,
    message:
        '$why: ${item.proposal?.path ?? item.file.path} (proposal ${item.proposal?.id ?? ''})'
            .trim(),
  );
}
