import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/library_service.dart';
import '../../theme.dart';
import 'artwork.dart';

Future<void> showAddToPlaylist(BuildContext context, Track track) {
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => AddToPlaylistSheet(track: track),
  );
}

class AddToPlaylistSheet extends StatelessWidget {
  final Track track;
  const AddToPlaylistSheet({super.key, required this.track});

  Future<void> _createAndAdd(BuildContext context) async {
    final library = context.read<LibraryService>();
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: MTheme.surfaceHigh,
        title: const Text('New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final id = await library.createPlaylist(name.trim());
    await library.addToPlaylist(id, track);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final playlists = library.playlists;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Add to playlist',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: () => _createAndAdd(context),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          if (playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No playlists yet — create your first one.',
                style: TextStyle(color: MTheme.textLow),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (_, i) {
                  final pl = playlists[i];
                  return ListTile(
                    leading: Artwork(url: pl.coverUrl, size: 44, radius: 8),
                    title: Text(pl.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${pl.tracks.length} songs',
                        style: TextStyle(color: MTheme.textLow, fontSize: 12)),
                    onTap: () async {
                      final added = await library.addToPlaylist(pl.id, track);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(added
                              ? 'Added to “${pl.name}”'
                              : 'Already in “${pl.name}”'),
                        ));
                      }
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
