import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audio_handler.dart';
import '../../services/download_service.dart';
import '../../services/innertube.dart';
import '../../theme.dart';
import '../mini_player.dart';
import '../widgets/artwork.dart';
import '../widgets/shimmers.dart';
import '../widgets/track_tile.dart';

/// Remote YouTube Music playlist or album page.
class PlaylistScreen extends StatefulWidget {
  final String browseId;
  final String title;
  const PlaylistScreen({super.key, required this.browseId, this.title = ''});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final Future<RemotePlaylist> _future =
      context.read<InnerTube>().playlist(widget.browseId);

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MaheraiAudioHandler>();
    return Scaffold(
      bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      body: FutureBuilder<RemotePlaylist>(
        future: _future,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final pl = snap.data;
          final tracks = pl?.tracks ?? [];
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 340,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Padding(
                    padding: const EdgeInsets.only(top: 90),
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Artwork(
                            url: pl?.thumbUrl ?? '',
                            size: 172,
                            radius: 20,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            pl?.title ?? widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        if ((pl?.subtitle ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            pl!.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13, color: MTheme.textMid),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: MTheme.accent,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: tracks.isEmpty
                              ? null
                              : () => handler.playQueue(tracks),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MTheme.textHigh,
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.2)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: tracks.isEmpty
                              ? null
                              : () {
                                  final shuffled = List.of(tracks)..shuffle();
                                  handler.playQueue(shuffled);
                                },
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: const Text('Shuffle'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.outlined(
                        style: IconButton.styleFrom(
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        tooltip: 'Download all',
                        onPressed: tracks.isEmpty
                            ? null
                            : () {
                                final downloads =
                                    context.read<DownloadService>();
                                for (final t in tracks) {
                                  downloads.download(t);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Downloading ${tracks.length} songs')),
                                );
                              },
                        icon: const Icon(Icons.download_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              if (loading)
                const SliverToBoxAdapter(child: ShimmerTrackList())
              else if (tracks.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Center(
                      child: Text("Couldn't load this playlist.",
                          style: TextStyle(color: MTheme.textMid)),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => TrackTile(
                    track: tracks[i],
                    showDuration: true,
                    onTap: () => handler.playQueue(tracks, startIndex: i),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}
