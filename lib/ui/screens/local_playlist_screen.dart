import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/audio_handler.dart';
import '../../services/library_service.dart';
import '../../theme.dart';
import '../mini_player.dart';
import '../widgets/artwork.dart';
import '../widgets/track_tile.dart';

/// A user-created playlist: reorderable, renamable, deletable.
class LocalPlaylistScreen extends StatelessWidget {
  final String playlistId;
  const LocalPlaylistScreen({super.key, required this.playlistId});

  Future<void> _rename(BuildContext context, String currentName) async {
    final library = context.read<LibraryService>();
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: MTheme.surfaceHigh,
        title: const Text('Rename playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await library.renamePlaylist(playlistId, name.trim());
    }
  }

  Future<void> _delete(BuildContext context, String name) async {
    final library = context.read<LibraryService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: MTheme.surfaceHigh,
        title: Text('Delete “$name”?'),
        content: const Text('This can’t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MTheme.accent),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await library.deletePlaylist(playlistId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final handler = context.read<MaheraiAudioHandler>();
    final pl = library.playlistById(playlistId);
    if (pl == null) {
      // Deleted while open.
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            color: MTheme.surfaceHigh,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'rename') _rename(context, pl.name);
              if (v == 'delete') _delete(context, pl.name);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
              children: [
                Artwork(url: pl.coverUrl, size: 96, radius: 16),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pl.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${pl.tracks.length} songs',
                          style: TextStyle(
                              fontSize: 13, color: MTheme.textMid)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: MTheme.accent,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: pl.tracks.isEmpty
                                ? null
                                : () => handler.playQueue(pl.tracks),
                            icon: const Icon(Icons.play_arrow_rounded,
                                size: 20),
                            label: const Text('Play'),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Shuffle',
                            onPressed: pl.tracks.isEmpty
                                ? null
                                : () {
                                    final shuffled = List.of(pl.tracks)
                                      ..shuffle();
                                    handler.playQueue(shuffled);
                                  },
                            icon: const Icon(Icons.shuffle_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          Expanded(
            child: pl.tracks.isEmpty
                ? Center(
                    child: Text(
                      'Add songs from search or any\ntrack’s “Add to playlist” action.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MTheme.textMid, height: 1.5),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: pl.tracks.length,
                    onReorder: (oldIndex, newIndex) => library
                        .reorderPlaylist(playlistId, oldIndex, newIndex),
                    itemBuilder: (context, i) {
                      final t = pl.tracks[i];
                      return Dismissible(
                        key: ValueKey('lp-${t.id}-$i'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) =>
                            library.removeFromPlaylist(playlistId, i),
                        background: Container(
                          color: MTheme.accent.withValues(alpha: 0.25),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline_rounded),
                        ),
                        child: TrackTile(
                          track: t,
                          onTap: () =>
                              handler.playQueue(pl.tracks, startIndex: i),
                          trailing: ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(Icons.drag_handle_rounded,
                                  color: MTheme.textLow, size: 20),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
