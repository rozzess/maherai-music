import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audio_handler.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../theme.dart';
import '../screens/artist_screen.dart';
import '../screens/playlist_screen.dart';
import 'add_to_playlist_sheet.dart';
import 'artwork.dart';

/// Long-press / "⋯" actions for a track.
Future<void> showTrackActions(BuildContext context, Track track) {
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    builder: (_) => TrackActionsSheet(track: track),
  );
}

class TrackActionsSheet extends StatelessWidget {
  final Track track;
  const TrackActionsSheet({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MaheraiAudioHandler>();
    final library = context.watch<LibraryService>();
    final downloads = context.watch<DownloadService>();
    final fav = library.isFavorite(track.id);
    final downloaded = downloads.isDownloaded(track.id);
    final downloading = downloads.isDownloading(track.id);

    void close() => Navigator.of(context).pop();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Artwork(url: track.thumbUrl, size: 52, radius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: MTheme.textMid, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(indent: 20, endIndent: 20),
          _Action(
            icon: Icons.play_circle_outline_rounded,
            label: 'Play next',
            onTap: () {
              handler.playNextInQueue(track);
              close();
            },
          ),
          _Action(
            icon: Icons.queue_music_rounded,
            label: 'Add to queue',
            onTap: () {
              handler.addToQueue(track);
              close();
            },
          ),
          _Action(
            icon: Icons.playlist_add_rounded,
            label: 'Add to playlist',
            onTap: () {
              close();
              showAddToPlaylist(context, track);
            },
          ),
          _Action(
            icon: fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            label: fav ? 'Remove from favorites' : 'Add to favorites',
            color: fav ? MTheme.accent : null,
            onTap: () {
              library.toggleFavorite(track);
              close();
            },
          ),
          _Action(
            icon: downloaded
                ? Icons.download_done_rounded
                : downloading
                    ? Icons.downloading_rounded
                    : Icons.download_rounded,
            label: downloaded
                ? 'Remove download'
                : downloading
                    ? 'Downloading…'
                    : 'Download',
            color: downloaded ? MTheme.accent : null,
            onTap: () {
              if (downloaded) {
                downloads.delete(track.id);
              } else if (!downloading) {
                downloads.download(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Downloading “${track.title}”')),
                );
              }
              close();
            },
          ),
          _Action(
            icon: Icons.radio_rounded,
            label: 'Start radio',
            onTap: () {
              handler.playSong(track);
              close();
            },
          ),
          if (track.albumId != null)
            _Action(
              icon: Icons.album_rounded,
              label: 'Go to album',
              onTap: () {
                close();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlaylistScreen(
                      browseId: track.albumId!, title: track.album ?? ''),
                ));
              },
            ),
          if (track.artistId != null)
            _Action(
              icon: Icons.person_rounded,
              label: 'Go to artist',
              onTap: () {
                close();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ArtistScreen(browseId: track.artistId!),
                ));
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _Action(
      {required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? MTheme.textMid),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      visualDensity: VisualDensity.compact,
    );
  }
}
