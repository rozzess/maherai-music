import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audio_handler.dart';
import '../../services/innertube.dart';
import '../../theme.dart';
import '../mini_player.dart';
import '../widgets/shimmers.dart';
import '../widgets/track_tile.dart';
import '../widgets/yt_card.dart';

class ArtistScreen extends StatefulWidget {
  final String browseId;
  const ArtistScreen({super.key, required this.browseId});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late final Future<ArtistPage> _future =
      context.read<InnerTube>().artist(widget.browseId);
  bool _allSongs = false;

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MaheraiAudioHandler>();
    return Scaffold(
      bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      body: FutureBuilder<ArtistPage>(
        future: _future,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final artist = snap.data;
          final songs = artist?.topSongs ?? [];
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 300,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
                  centerTitle: true,
                  title: Text(
                    artist?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  background: artist == null || artist.thumbUrl.isEmpty
                      ? Container(color: MTheme.surface)
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: artist.thumbUrl,
                              fit: BoxFit.cover,
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    MTheme.bg.withValues(alpha: 0.6),
                                    MTheme.bg,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: MTheme.accent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                        ),
                        onPressed: songs.isEmpty
                            ? null
                            : () => handler.playQueue(songs, radio: true),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MTheme.textHigh,
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        onPressed: songs.isEmpty
                            ? null
                            : () => handler.playSong(songs.first),
                        icon: const Icon(Icons.radio_rounded, size: 18),
                        label: const Text('Radio'),
                      ),
                    ],
                  ),
                ),
              ),
              if (loading)
                const SliverToBoxAdapter(child: ShimmerTrackList(count: 5))
              else ...[
                if (songs.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: const Text('Top songs',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: _allSongs
                        ? songs.length
                        : songs.length.clamp(0, 5),
                    itemBuilder: (context, i) => TrackTile(
                      track: songs[i],
                      onTap: () =>
                          handler.playQueue(songs, startIndex: i, radio: true),
                    ),
                  ),
                  if (songs.length > 5 && !_allSongs)
                    SliverToBoxAdapter(
                      child: Center(
                        child: TextButton(
                          onPressed: () => setState(() => _allSongs = true),
                          child: Text('Show all ${songs.length} songs',
                              style: TextStyle(color: MTheme.textMid)),
                        ),
                      ),
                    ),
                ],
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      for (final shelf in artist?.shelves ?? <HomeSection>[])
                        YtCarousel(section: shelf),
                    ],
                  ),
                ),
                if ((artist?.description ?? '').isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('About',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(
                            artist!.description,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: MTheme.textMid, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }
}
