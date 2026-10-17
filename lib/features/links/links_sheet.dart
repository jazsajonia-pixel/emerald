import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vault/vault_path.dart';
import '../search/index_controller.dart';
import 'link_resolver.dart';

/// Backlinks and outgoing links of one note.
class LinksSheet extends ConsumerWidget {
  const LinksSheet({super.key, required this.path, required this.onOpen});

  final String path;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(indexControllerProvider);
    final index = state.index;
    final scheme = Theme.of(context).colorScheme;
    final back = index.backlinks(path);
    final out = index
        .outgoing(path)
        .where((r) => r.status != LinkStatus.attachment)
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, scroll) => ListView(
        controller: scroll,
        children: [
          if (state.building)
            ListTile(
              leading: const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Indexing notes (${state.done}/${state.total})…'),
            ),
          ListTile(
            title: Text('Backlinks (${back.length})'),
            subtitle: const Text('Notes that link to this one'),
          ),
          if (back.isEmpty)
            const ListTile(dense: true, title: Text('No backlinks')),
          for (final p in back)
            ListTile(
              leading: const Icon(Icons.subdirectory_arrow_left),
              title: Text(VaultPath.title(p)),
              subtitle: Text(p),
              onTap: () => onOpen(p),
            ),
          const Divider(),
          ListTile(title: Text('Outgoing links (${out.length})')),
          if (out.isEmpty)
            const ListTile(dense: true, title: Text('No links in this note')),
          for (final r in out)
            switch (r.status) {
              LinkStatus.resolved || LinkStatus.ambiguous => ListTile(
                leading: const Icon(Icons.arrow_outward),
                title: Text(VaultPath.title(r.targetPath!)),
                subtitle: Text(
                  r.status == LinkStatus.ambiguous
                      ? '${r.targetPath} (${r.candidates.length} notes share this name)'
                      : r.targetPath!,
                ),
                onTap: () => onOpen(r.targetPath!),
              ),
              _ => ListTile(
                leading: Icon(Icons.link_off, color: scheme.error),
                title: Text(r.link.target),
                subtitle: Text(
                  r.status == LinkStatus.outsideVault
                      ? 'Points outside the vault — not followed'
                      : 'Broken link: no such note',
                ),
              ),
            },
        ],
      ),
    );
  }
}
