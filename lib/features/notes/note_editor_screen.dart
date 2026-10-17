import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/state_views.dart';
import '../../data/vault_storage.dart';
import '../vault/vault_controller.dart';
import 'markdown_preview.dart';
import 'note_codec.dart';
import 'note_repository.dart';

enum _ConflictChoice { saveCopy, reload, overwrite }

enum _LeaveChoice { save, discard }

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.path});

  final String path;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  late String _path = widget.path;
  NoteDocument? _doc;
  Object? _loadError;
  bool _preview = false;
  bool _saving = false;
  bool _externallyChanged = false;

  NoteRepository get _repo => ref.read(noteRepositoryProvider);

  VaultHandle? get _vault {
    final s = ref.read(vaultControllerProvider);
    return s is VaultReady ? s.vault : null;
  }

  bool get _dirty => _doc != null && _text.text != _doc!.text;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _text.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkExternalChange();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    final vault = _vault;
    if (vault == null) {
      setState(
        () => _loadError = VaultException(VaultErrorCode.permissionDenied),
      );
      return;
    }
    setState(() {
      _doc = null;
      _loadError = null;
    });
    try {
      final doc = await _repo.open(vault, _path);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _externallyChanged = false;
        _text.text = doc.text;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// After returning to the app, see whether another editor changed the file.
  Future<void> _checkExternalChange() async {
    final vault = _vault;
    final doc = _doc;
    if (vault == null || doc == null || _saving) return;
    try {
      final current = await _repo.open(vault, _path);
      if (!mounted || current.stamp.sha256 == doc.stamp.sha256) return;
      if (_dirty) {
        setState(() => _externallyChanged = true);
      } else {
        setState(() {
          _doc = current;
          _text.text = current.text;
        });
        _snack('Reloaded: the note was changed outside Emerald.');
      }
    } on Exception {
      // Reported when the user saves; nothing to do here.
    }
  }

  Future<bool> _save() async {
    final vault = _vault;
    final doc = _doc;
    if (vault == null || doc == null || _saving) return false;
    setState(() => _saving = true);
    Object? error;
    try {
      final saved = await _repo.save(vault, doc, _text.text);
      _applySaved(saved);
      _snack('Saved');
      return true;
    } on Exception catch (e) {
      error = e;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return false;
    if (error is VaultException) {
      if (error.code == VaultErrorCode.conflict) {
        return _resolveConflict(vault, doc);
      }
      if (error.code == VaultErrorCode.notFound) return _offerRecreate(vault);
    }
    return _fail(error);
  }

  bool _fail(Object e) {
    _snack('Not saved: ${describeVaultError(e)} Your text is still here.');
    return false;
  }

  void _applySaved(NoteDocument saved) {
    ref
        .read(vaultControllerProvider.notifier)
        .noteWritten(saved.path, saved.stamp);
    if (!mounted) return;
    setState(() {
      _path = saved.path;
      _doc = saved;
      _externallyChanged = false;
      if (_text.text != saved.text) _text.text = saved.text;
    });
  }

  Future<bool> _resolveConflict(VaultHandle vault, NoteDocument doc) async {
    final choice = await showDialog<_ConflictChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note changed outside Emerald'),
        content: const Text(
          'Another app changed this note after you opened it. Nothing has '
          'been saved yet. How do you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ConflictChoice.reload),
            child: const Text('Discard mine, load theirs'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ConflictChoice.overwrite),
            child: const Text('Overwrite theirs'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _ConflictChoice.saveCopy),
            child: const Text('Save mine as a copy'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return false;
    try {
      switch (choice) {
        case _ConflictChoice.saveCopy:
          final copy = await _repo.saveCopy(vault, doc, _text.text);
          _applySaved(copy);
          _snack('Your version was saved as "${copy.title}".');
          return true;
        case _ConflictChoice.reload:
          if (!await _confirm(
            'Discard your changes?',
            'Your unsaved edits will be lost and the other version loaded.',
            'Discard',
          )) {
            return false;
          }
          await _load();
          return true;
        case _ConflictChoice.overwrite:
          if (!await _confirm(
            'Overwrite the other version?',
            'The newer version from the other app will be replaced. A copy '
                'of it is kept in this note\'s history in Emerald.',
            'Overwrite',
          )) {
            return false;
          }
          _applySaved(await _repo.overwrite(vault, doc, _text.text));
          _snack('Saved');
          return true;
      }
    } on Exception catch (e) {
      return _fail(e);
    }
  }

  Future<bool> _offerRecreate(VaultHandle vault) async {
    final ok = await _confirm(
      'Note no longer exists',
      'This note was moved or deleted outside Emerald. Save your text as a '
          'new note at the same place?',
      'Save as new note',
    );
    if (!ok) return false;
    try {
      _applySaved(await _repo.recreate(vault, _path, _text.text));
      _snack('Saved');
      return true;
    } on Exception catch (e) {
      return _fail(e);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _onPop() async {
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save your changes before leaving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LeaveChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _LeaveChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _LeaveChoice.save && !await _save()) return;
    if (choice == _LeaveChoice.discard) _text.text = _doc!.text;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showHistory() async {
    final vault = _vault;
    if (vault == null) return;
    final entries = await ref.read(noteHistoryProvider).list(vault.id, _path);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => entries.isEmpty
          ? const SizedBox(
              height: 200,
              child: EmptyView(
                icon: Icons.history,
                title: 'No previous versions',
                message: 'Emerald keeps a copy each time it overwrites a note.',
              ),
            )
          : ListView(
              children: [
                const ListTile(
                  title: Text('Previous versions (kept on this device)'),
                ),
                for (final e in entries)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(
                      e.savedAt.toLocal().toString().substring(0, 19),
                    ),
                    subtitle: const Text('Tap to put this text in the editor'),
                    onTap: () async {
                      final bytes = await e.file.readAsBytes();
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _text.text = NoteCodec.decode(bytes).text;
                      _snack('Older version loaded. Save to keep it.');
                    },
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            (doc?.title ?? '') + (_dirty ? ' •' : ''),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (doc != null) ...[
              IconButton(
                tooltip: _preview ? 'Edit' : 'Preview',
                icon: Icon(
                  _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _preview = !_preview),
              ),
              if (!doc.readOnly)
                IconButton(
                  tooltip: 'Save',
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  onPressed: _dirty && !_saving ? _save : null,
                ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'history') _showHistory();
                  if (v == 'reload') _checkExternalChange();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'history',
                    child: Text('Previous versions'),
                  ),
                  PopupMenuItem(
                    value: 'reload',
                    child: Text('Check for outside changes'),
                  ),
                ],
              ),
            ],
          ],
        ),
        body: _body(doc),
      ),
    );
  }

  Widget _body(NoteDocument? doc) {
    final err = _loadError;
    if (err != null) {
      if (err is VaultException &&
          err.code == VaultErrorCode.permissionDenied) {
        return const PermissionDeniedView();
      }
      return ErrorView(
        title: 'Could not open note',
        message: describeVaultError(err),
        onRetry: _load,
      );
    }
    if (doc == null) return const LoadingView(label: 'Opening note…');
    final banners = <Widget>[
      if (doc.readOnly)
        MaterialBanner(
          content: Text(doc.decoded.readOnlyReason!),
          leading: const Icon(Icons.lock_outline),
          actions: const [SizedBox.shrink()],
        ),
      if (_externallyChanged)
        MaterialBanner(
          content: const Text(
            'This note was changed outside Emerald while you were editing.',
          ),
          leading: const Icon(Icons.warning_amber),
          actions: [TextButton(onPressed: _save, child: const Text('Resolve'))],
        ),
    ];
    final content = _preview || doc.readOnly
        ? MarkdownPreview(
            text: _text.text,
            onTapLink: (t, href) => _snack('Link: ${href ?? t}'),
          )
        : TextField(
            key: const Key('note-editor'),
            controller: _text,
            expands: true,
            maxLines: null,
            minLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', height: 1.4),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              hintText: 'Start writing Markdown…',
            ),
          );
    return Column(
      children: [
        ...banners,
        Expanded(child: content),
      ],
    );
  }
}
