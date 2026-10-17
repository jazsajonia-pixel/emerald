import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/state_views.dart';
import '../../core/vault/vault_path.dart';
import '../notes/note_navigation.dart';
import 'index_controller.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(indexControllerProvider);
    final hits = idx.index.search(_query.text);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('search-field'),
          controller: _query,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search titles and text',
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_query.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.clear),
              onPressed: () => setState(_query.clear),
            ),
        ],
        bottom: idx.building
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: _query.text.trim().isEmpty
          ? EmptyView(
              icon: Icons.search,
              title: 'Search your vault',
              message: idx.building
                  ? 'Indexing notes (${idx.done}/${idx.total})…'
                  : '${idx.index.notes.length} notes indexed.',
            )
          : hits.isEmpty
          ? const EmptyView(icon: Icons.search_off, title: 'No matching notes')
          : ListView.builder(
              itemCount: hits.length,
              itemBuilder: (_, i) {
                final h = hits[i];
                final dir = VaultPath.parent(h.path);
                return ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(VaultPath.title(h.path)),
                  subtitle: Text(
                    [
                      if (dir.isNotEmpty) dir,
                      if (h.snippet != null) h.snippet!,
                    ].join('\n'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: dir.isNotEmpty && h.snippet != null,
                  onTap: () => openNote(context, h.path),
                );
              },
            ),
    );
  }
}
