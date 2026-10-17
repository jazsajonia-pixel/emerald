import '../../../core/vault/vault_path.dart';
import '../../../data/vault_storage.dart';
import '../../notes/note_repository.dart';
import '../../search/vault_index.dart';
import '../ai_types.dart';
import '../proposals.dart';

/// Narrow, vault-scoped tools offered to AI providers.
///
/// - Every path argument is validated with [VaultPath] and must be a note
///   that exists in the current index, so the AI can never reach files
///   outside the selected vault (or non-Markdown files).
/// - `create_note` / `update_note` only record a [NoteProposal]; the user
///   must approve it before anything is written. There is no delete tool.
/// - Every note whose content is returned is recorded in [sharedNotes] so the
///   UI can show exactly what was sent to the provider.
class VaultTools {
  VaultTools({
    required this.vault,
    required this.index,
    required this.repository,
    required this.nextProposalId,
    this.maxReadChars = 20000,
    this.maxProposals = 10,
  });

  final VaultHandle vault;
  final VaultIndex index;
  final NoteRepository repository;
  final int Function() nextProposalId;
  final int maxReadChars;
  final int maxProposals;

  final Set<String> sharedNotes = {};
  final List<NoteProposal> proposals = [];

  static const specs = <ToolSpec>[
    ToolSpec(
      name: 'search_notes',
      description:
          'Full-text search over note titles and contents in the user\'s '
          'vault. Returns paths, titles and short snippets.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Words to search for'},
          'limit': {'type': 'integer', 'description': 'Max results (1-10)'},
        },
        'required': ['query'],
      },
    ),
    ToolSpec(
      name: 'list_notes',
      description: 'Lists note paths, optionally only inside one folder.',
      parameters: {
        'type': 'object',
        'properties': {
          'folder': {
            'type': 'string',
            'description': 'Vault-relative folder, empty for all',
          },
        },
      },
    ),
    ToolSpec(
      name: 'read_note',
      description: 'Returns the Markdown content of one note.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Note path from a search'},
        },
        'required': ['path'],
      },
    ),
    ToolSpec(
      name: 'find_backlinks',
      description: 'Lists notes that link to the given note.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
      },
    ),
    ToolSpec(
      name: 'find_related_notes',
      description:
          'Notes related to the given note through explicit links: notes it '
          'links to, notes linking to it, and notes sharing link targets.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
      },
    ),
    ToolSpec(
      name: 'create_note',
      description:
          'Proposes a new note. The user reviews and must approve it; it is '
          'not created until then. Never overwrites an existing note.',
      parameters: {
        'type': 'object',
        'properties': {
          'folder': {'type': 'string', 'description': 'Folder, empty = root'},
          'title': {'type': 'string'},
          'content': {'type': 'string', 'description': 'Markdown content'},
          'summary': {'type': 'string', 'description': 'Why, in one line'},
        },
        'required': ['title', 'content'],
      },
    ),
    ToolSpec(
      name: 'update_note',
      description:
          'Proposes replacing the full content of an existing note. Read the '
          'note first. The user reviews a diff and must approve it.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'new_content': {
            'type': 'string',
            'description': 'Complete new Markdown content',
          },
          'summary': {'type': 'string', 'description': 'What changed'},
        },
        'required': ['path', 'new_content'],
      },
    ),
  ];

  /// Executes a tool call. Never throws: errors are returned to the model as
  /// `{"error": ...}` so it can recover.
  Future<JsonMap> execute(ToolCall call) async {
    try {
      return switch (call.name) {
        'search_notes' => _search(call.args),
        'list_notes' => _list(call.args),
        'read_note' => await _read(call.args),
        'find_backlinks' => _backlinks(call.args),
        'find_related_notes' => _related(call.args),
        'create_note' => await _create(call.args),
        'update_note' => await _update(call.args),
        _ => {'error': 'Unknown tool ${call.name}'},
      };
    } on _ToolError catch (e) {
      return {'error': e.message};
    } on VaultException catch (e) {
      return {'error': 'Storage error: ${e.code.name}'};
    }
  }

  String _string(JsonMap args, String key, {bool required = true}) {
    final v = args[key];
    if (v is String) return v;
    if (v == null && !required) return '';
    throw _ToolError('Missing or invalid "$key"');
  }

  /// Validates [raw] and requires it to be an existing note in the index.
  String _notePath(String raw) {
    String p;
    try {
      p = VaultPath.normalize(raw.trim());
    } on InvalidVaultPath catch (e) {
      throw _ToolError('Invalid path: ${e.reason}');
    }
    if (!VaultPath.isMarkdown(p) && index.notes.containsKey('$p.md')) {
      p = '$p.md';
    }
    if (!index.notes.containsKey(p)) {
      // Allow a bare title if it resolves unambiguously.
      final byTitle = index.notes.keys
          .where(
            (k) => VaultPath.title(k).toLowerCase() == raw.trim().toLowerCase(),
          )
          .toList();
      if (byTitle.length == 1) return byTitle.single;
      throw _ToolError('No note at "$raw". Use search_notes to find paths.');
    }
    return p;
  }

  JsonMap _search(JsonMap a) {
    final q = _string(a, 'query');
    final limit = ((a['limit'] as num?)?.toInt() ?? 8).clamp(1, 10);
    return {
      'results': [
        for (final h in index.search(q, limit: limit))
          {
            'path': h.path,
            'title': VaultPath.title(h.path),
            'snippet': ?h.snippet,
          },
      ],
    };
  }

  JsonMap _list(JsonMap a) {
    var folder = _string(a, 'folder', required: false).trim();
    if (folder.isNotEmpty) {
      try {
        folder = VaultPath.normalize(folder);
      } on InvalidVaultPath catch (e) {
        throw _ToolError('Invalid folder: ${e.reason}');
      }
    }
    final all =
        index.notes.keys
            .where((p) => folder.isEmpty || p.startsWith('$folder/'))
            .toList()
          ..sort();
    return {'notes': all.take(200).toList(), 'total': all.length};
  }

  Future<JsonMap> _read(JsonMap a) async {
    final p = _notePath(_string(a, 'path'));
    final doc = await repository.open(vault, p);
    sharedNotes.add(p);
    final truncated = doc.text.length > maxReadChars;
    return {
      'path': p,
      'content': truncated ? doc.text.substring(0, maxReadChars) : doc.text,
      if (truncated) 'truncated': true,
    };
  }

  JsonMap _backlinks(JsonMap a) {
    final p = _notePath(_string(a, 'path'));
    return {'path': p, 'backlinks': index.backlinks(p)};
  }

  JsonMap _related(JsonMap a) {
    final p = _notePath(_string(a, 'path'));
    final out = index.linkedTargets(p);
    final back = index.backlinks(p).toSet();
    final shared = <String, int>{};
    for (final other in index.notes.keys) {
      if (other == p) continue;
      final common = index.linkedTargets(other).intersection(out).length;
      if (common > 0) shared[other] = common;
    }
    final sharedSorted = shared.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    return {
      'path': p,
      'links_to': out.toList()..sort(),
      'linked_from': back.toList()..sort(),
      'shares_links_with': [for (final e in sharedSorted.take(10)) e.key],
      'basis': 'explicit links only (no semantic analysis)',
    };
  }

  void _checkProposalLimit() {
    if (proposals.length >= maxProposals) {
      throw _ToolError('Too many proposals in this conversation.');
    }
  }

  Future<JsonMap> _create(JsonMap a) async {
    _checkProposalLimit();
    final title = _string(a, 'title');
    final content = _string(a, 'content');
    var folder = _string(a, 'folder', required: false).trim();
    String path;
    try {
      folder = VaultPath.normalize(folder);
      path = VaultPath.join(folder, VaultPath.fileNameForTitle(title));
    } on InvalidVaultPath catch (e) {
      throw _ToolError('Invalid title or folder: ${e.reason}');
    }
    if (index.notes.containsKey(path)) {
      throw _ToolError('A note already exists at $path; use update_note.');
    }
    final p = NoteProposal(
      id: nextProposalId(),
      kind: ProposalKind.create,
      path: path,
      newText: content,
      summary: a['summary'] as String?,
    );
    proposals.add(p);
    return {
      'proposal_id': p.id,
      'status': 'pending_user_approval',
      'path': path,
      'note': 'Not created yet. The user will review it.',
    };
  }

  Future<JsonMap> _update(JsonMap a) async {
    _checkProposalLimit();
    final p = _notePath(_string(a, 'path'));
    final newText = _string(a, 'new_content');
    final doc = await repository.open(vault, p);
    if (doc.readOnly) throw _ToolError('This note is read-only in Emerald.');
    sharedNotes.add(p);
    if (doc.text == newText) {
      return {'status': 'no_change', 'path': p};
    }
    final proposal = NoteProposal(
      id: nextProposalId(),
      kind: ProposalKind.update,
      path: p,
      oldText: doc.text,
      newText: newText,
      baseSha256: doc.stamp.sha256,
      summary: a['summary'] as String?,
    );
    proposals.add(proposal);
    return {
      'proposal_id': proposal.id,
      'status': 'pending_user_approval',
      'path': p,
      'note': 'Not applied yet. The user will review a diff.',
    };
  }
}

class _ToolError implements Exception {
  _ToolError(this.message);
  final String message;
}
