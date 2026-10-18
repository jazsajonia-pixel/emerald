import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/state_views.dart';
import '../../core/vault/vault_path.dart';
import '../../data/vault_storage.dart';
import '../search/index_controller.dart';
import '../search/search_screen.dart';
import '../vault/vault_controller.dart';
import 'note_navigation.dart';
import 'orphans_screen.dart';

/// Vault browser: folders and Markdown notes of the current folder.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String _dir = VaultPath.root;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openNote(String path) => openNote(context, path);

  Future<String?> _askName(String title, String label) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _newNote(VaultReady s) async {
    final title = await _askName('New note', 'Title');
    if (title == null || title.trim().isEmpty || !mounted) return;
    try {
      final doc = await ref
          .read(noteRepositoryProvider)
          .create(s.vault, _dir, title);
      ref
          .read(indexControllerProvider.notifier)
          .updateNote(doc.path, doc.text, doc.stamp);
      ref
          .read(vaultControllerProvider.notifier)
          .noteWritten(doc.path, doc.stamp);
      if (mounted) await _openNote(doc.path);
    } on Exception catch (e) {
      _snack(describeVaultError(e));
    }
  }

  Future<void> _newFolder(VaultReady s) async {
    final name = await _askName('New folder', 'Folder name');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final path = VaultPath.join(_dir, name.trim());
      await ref.read(vaultStorageProvider).createDirectory(s.vault, path);
      ref.read(vaultControllerProvider.notifier).folderCreated(path);
    } on Exception catch (e) {
      _snack(describeVaultError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultControllerProvider);
    final controller = ref.read(vaultControllerProvider.notifier);
    if (state is VaultReady &&
        _dir.isNotEmpty &&
        !state.entries.any((e) => e.isDirectory && e.path == _dir)) {
      _dir = VaultPath.root; // folder vanished after a rescan
    }
    return PopScope(
      canPop: _dir.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _dir = VaultPath.parent(_dir));
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            state is VaultReady
                ? (_dir.isEmpty ? state.vault.name : VaultPath.basename(_dir))
                : 'Brain',
          ),
          leading: _dir.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Up one folder',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: () =>
                      setState(() => _dir = VaultPath.parent(_dir)),
                ),
          actions: [
            if (state is VaultReady) ...[
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                ),
              ),
              IconButton(
                tooltip: 'Rescan vault',
                icon: const Icon(Icons.refresh),
                onPressed: state.scanning ? null : controller.rescan,
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'folder') _newFolder(state);
                  if (v == 'orphans') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const OrphansScreen(),
                      ),
                    );
                  }
                  if (v == 'reindex') {
                    ref.read(indexControllerProvider.notifier).rebuild();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'folder', child: Text('New folder')),
                  PopupMenuItem(
                    value: 'orphans',
                    child: Text('Unlinked notes'),
                  ),
                  PopupMenuItem(value: 'reindex', child: Text('Rebuild index')),
                ],
              ),
            ],
          ],
        ),
        floatingActionButton: state is VaultReady
            ? FloatingActionButton.extended(
                onPressed: () => _newNote(state),
                icon: const Icon(Icons.add),
                label: const Text('New note'),
              )
            : null,
        body: switch (state) {
          VaultLoading() => const LoadingView(label: 'Opening vault…'),
          VaultNone() => EmptyView(
            icon: Icons.folder_open,
            title: 'No vault selected',
            message:
                'Choose a folder that contains (or will contain) your '
                'Markdown notes. Sapphire edits the files in place, so they '
                'stay usable in Obsidian and other editors.',
            action: FilledButton.icon(
              onPressed: controller.pick,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose vault folder'),
            ),
          ),
          VaultAccessLost() => PermissionDeniedView(
            onReselect: controller.pick,
          ),
          VaultFailure(:final message) => ErrorView(
            title: 'Could not open the vault',
            message: message,
            onRetry: controller.restore,
          ),
          VaultReady() => _Listing(
            state: state,
            dir: _dir,
            onOpenDir: (d) => setState(() => _dir = d),
            onOpenNote: _openNote,
            onRefresh: controller.rescan,
          ),
        },
      ),
    );
  }
}

class _Listing extends StatelessWidget {
  const _Listing({
    required this.state,
    required this.dir,
    required this.onOpenDir,
    required this.onOpenNote,
    required this.onRefresh,
  });

  final VaultReady state;
  final String dir;
  final ValueChanged<String> onOpenDir;
  final ValueChanged<String> onOpenNote;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final kids = state.childrenOf(dir);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: kids.isEmpty
          ? ListView(
              children: [
                SizedBox(
                  height: 360,
                  child: EmptyView(
                    icon: Icons.note_add_outlined,
                    title: dir.isEmpty
                        ? 'This vault has no notes yet'
                        : 'This folder is empty',
                    message: 'Tap "New note" to create one.',
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: kids.length,
              itemBuilder: (_, i) => _tile(kids[i]),
            ),
    );
  }

  Widget _tile(VaultEntry e) {
    if (e.isDirectory) {
      return ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(VaultPath.basename(e.path)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => onOpenDir(e.path),
      );
    }
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(VaultPath.title(e.path)),
      onTap: () => onOpenNote(e.path),
    );
  }
}
