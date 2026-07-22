import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/innertube.dart';
import '../../services/library_service.dart';
import '../../theme.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmers.dart';
import '../widgets/track_tile.dart';
import '../widgets/yt_card.dart';
import '../../services/audio_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<List<HomeSection>> _feed;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _feed = context.read<InnerTube>().home();
  }

  Future<void> _refresh() async {
    final next = context.read<InnerTube>().home();
    setState(() => _feed = next);
    await next;
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Late night vibes';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final library = context.watch<LibraryService>();
    final recents = library.recents;

    return RefreshIndicator(
      color: MTheme.accent,
      backgroundColor: MTheme.surfaceHigh,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [MTheme.accent, Color(0xFFFF8A5C)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.music_note_rounded,
                      size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('Maherai Music'),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _greeting(),
                style: TextStyle(fontSize: 14, color: MTheme.textMid),
              ),
            ),
          ),
          if (recents.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'Recently played'),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: recents.length.clamp(0, 12),
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final t = recents[i];
                    return YtCard(
                      size: 110,
                      item: YtItem(
                        kind: YtKind.song,
                        id: t.id,
                        title: t.title,
                        subtitle: t.artist,
                        thumbUrl: t.thumbUrl,
                        track: t,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: FutureBuilder<List<HomeSection>>(
              future: _feed,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Column(
                    children: [ShimmerCarousel(), ShimmerCarousel()],
                  );
                }
                final sections = snap.data ?? [];
                if (sections.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 48, color: MTheme.textLow),
                        const SizedBox(height: 12),
                        Text(
                          "Couldn't load the feed.\nPull down to retry.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MTheme.textMid),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final (i, section) in sections.indexed)
                      if (i == 0 &&
                          section.items
                              .every((it) => it.kind == YtKind.song))
                        _QuickPicks(section: section)
                      else
                        YtCarousel(section: section),
                  ],
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 160)),
        ],
      ),
    );
  }
}

/// First shelf rendered as a tappable vertical list — one-tap listening.
class _QuickPicks extends StatelessWidget {
  final HomeSection section;
  const _QuickPicks({required this.section});

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MaheraiAudioHandler>();
    final tracks =
        section.items.map((it) => it.track).whereType<Track>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.title.isEmpty ? 'Quick picks' : section.title,
          trailing: TextButton.icon(
            onPressed: () {
              if (tracks.isNotEmpty) handler.playQueue(tracks, radio: true);
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Play all'),
            style: TextButton.styleFrom(foregroundColor: MTheme.accent),
          ),
        ),
        for (final (i, t) in tracks.take(6).indexed)
          TrackTile(
            track: t,
            onTap: () => handler.playQueue(tracks, startIndex: i, radio: true),
          ),
      ],
    );
  }
}
