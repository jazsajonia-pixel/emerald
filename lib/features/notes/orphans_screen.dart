import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/state_views.dart';
import '../../core/vault/vault_path.dart';
import '../search/index_controller.dart';
import 'note_navigation.dart';

/// Notes without any explicit links in or out, plus notes containing broken
/// links.
class OrphansScreen extends ConsumerWidget {
  const OrphansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(indexControllerProvider);
    final orphans = idx.index.orphans;
    final withBroken = [
      for (final p in idx.index.notes.keys.toList()..sort())
        if (idx.index.brokenLinks(p).isNotEmpty) p,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Unlinked notes')),
      body: idx.building
          ? LoadingView(label: 'Indexing notes (${idx.done}/${idx.total})…')
          : ListView(
              children: [
                ListTile(
                  title: Text('Orphan notes (${orphans.length})'),
                  subtitle: const Text('No links to or from other notes'),
                ),
                if (orphans.isEmpty)
                  const ListTile(dense: true, title: Text('None')),
                for (final p in orphans)
                  ListTile(
                    leading: const Icon(Icons.radio_button_unchecked),
                    title: Text(VaultPath.title(p)),
                    subtitle: Text(p),
                    onTap: () => openNote(context, p),
                  ),
                const Divider(),
                ListTile(
                  title: Text('Notes with broken links (${withBroken.length})'),
                ),
                if (withBroken.isEmpty)
                  const ListTile(dense: true, title: Text('None')),
                for (final p in withBroken)
                  ListTile(
                    leading: const Icon(Icons.link_off),
                    title: Text(VaultPath.title(p)),
                    subtitle: Text(
                      idx.index
                          .brokenLinks(p)
                          .map((r) => r.link.target)
                          .join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => openNote(context, p),
                  ),
                if (idx.index.unreadable.isNotEmpty) ...[
                  const Divider(),
                  ListTile(
                    title: Text(
                      'Could not index (${idx.index.unreadable.length})',
                    ),
                    subtitle: Text(idx.index.unreadable.join(', ')),
                  ),
                ],
              ],
            ),
    );
  }
}
