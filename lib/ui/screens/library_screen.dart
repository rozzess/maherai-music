import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audio_handler.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_tile.dart';
import 'local_playlist_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _createPlaylist() async {
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
    if (name != null && name.trim().isNotEmpty && mounted) {
      await context.read<LibraryService>().createPlaylist(name.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Library',
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 28),
                  tooltip: 'New playlist',
                  onPressed: _createPlaylist,
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            indicatorColor: MTheme.accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: MTheme.textHigh,
            unselectedLabelColor: MTheme.textLow,
            labelStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Playlists'),
              Tab(text: 'Favorites'),
              Tab(text: 'Downloads'),
              Tab(text: 'History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _PlaylistsTab(),
                _FavoritesTab(),
                _DownloadsTab(),
                _HistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<LibraryService>().playlists;
    if (playlists.isEmpty) {
      return _EmptyState(
        icon: Icons.queue_music_rounded,
        message: 'Create playlists with the + button\nand build your own mixes.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, i) {
        final pl = playlists[i];
        return InkWell(
          borderRadius: BorderRadius.circular(MTheme.radiusCard),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LocalPlaylistScreen(playlistId: pl.id),
          )),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (_, c) => Artwork(
                    url: pl.coverUrl,
                    size: c.maxWidth,
                    radius: MTheme.radiusCard,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(pl.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              Text('${pl.tracks.length} songs',
                  style: TextStyle(fontSize: 12, color: MTheme.textLow)),
            ],
          ),
        );
      },
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<LibraryService>().favorites;
    final handler = context.read<MaheraiAudioHandler>();
    if (favorites.isEmpty) {
      return _EmptyState(
        icon: Icons.favorite_border_rounded,
        message: 'Songs you ♥ end up here.',
      );
    }
    return _TrackListWithPlayAll(tracks: favorites, handler: handler);
  }
}

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final tracks = downloads.all;
    final handler = context.read<MaheraiAudioHandler>();
    if (tracks.isEmpty && downloads.active.isEmpty) {
      return _EmptyState(
        icon: Icons.download_rounded,
        message:
            'Downloaded songs play offline —\nno connection needed.',
      );
    }
    return _TrackListWithPlayAll(tracks: tracks, handler: handler);
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final recents = context.watch<LibraryService>().recents;
    final handler = context.read<MaheraiAudioHandler>();
    if (recents.isEmpty) {
      return _EmptyState(
        icon: Icons.history_rounded,
        message: 'Your listening history appears here.',
      );
    }
    return _TrackListWithPlayAll(tracks: recents, handler: handler);
  }
}

class _TrackListWithPlayAll extends StatelessWidget {
  final List<Track> tracks;
  final MaheraiAudioHandler handler;
  const _TrackListWithPlayAll({required this.tracks, required this.handler});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 160),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: MTheme.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => handler.playQueue(tracks),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play all'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: MTheme.textHigh,
                  side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  final shuffled = List.of(tracks)..shuffle();
                  handler.playQueue(shuffled);
                },
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle'),
              ),
            ],
          ),
        ),
        for (final (i, t) in tracks.indexed)
          TrackTile(
            track: t,
            onTap: () => handler.playQueue(tracks, startIndex: i),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: MTheme.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: MTheme.accent),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: MTheme.textMid, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
