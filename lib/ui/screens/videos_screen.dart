import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/innertube.dart';
import '../../theme.dart';
import '../../util/fmt.dart';
import '../widgets/artwork.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmers.dart';
import 'video_player_screen.dart';

/// YouTube videos tab: search any video, or browse curated rows.
/// Videos play with picture in the in-app video player (progressive MP4).
class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen>
    with AutomaticKeepAliveClientMixin {
  static const _sections = [
    ('Trending now', 'trending videos today'),
    ('Music videos', 'official music video 2026'),
    ('Live performances', 'live performance concert'),
    ('Podcasts & talks', 'podcast full episode'),
  ];

  final TextEditingController _controller = TextEditingController();
  Future<List<YtItem>>? _searchResults;
  Future<List<(String, List<YtItem>)>>? _feed;
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _feed = _loadFeed();
  }

  Future<List<(String, List<YtItem>)>> _loadFeed() async {
    final innertube = context.read<InnerTube>();
    final out = <(String, List<YtItem>)>[];
    for (final (title, query) in _sections) {
      try {
        final items = await innertube.searchFiltered(query, YtKind.video);
        if (items.isNotEmpty) out.add((title, items.take(10).toList()));
      } catch (_) {}
    }
    return out;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _query = q;
      _searchResults =
          context.read<InnerTube>().searchFiltered(q, YtKind.video);
    });
  }

  void _open(YtItem item) {
    final track = item.track;
    if (track == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(video: track),
    ));
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search YouTube videos…',
                hintStyle: TextStyle(color: MTheme.textLow),
                prefixIcon:
                    Icon(Icons.smart_display_outlined, color: MTheme.textLow),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: MTheme.textLow, size: 20),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _query = '';
                            _searchResults = null;
                          });
                        },
                      ),
                filled: true,
                fillColor: MTheme.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Expanded(
            child: _query.isNotEmpty ? _searchList() : _feedList(),
          ),
        ],
      ),
    );
  }

  Widget _searchList() {
    return FutureBuilder<List<YtItem>>(
      future: _searchResults,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SingleChildScrollView(child: ShimmerTrackList());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Text('No videos found for “$_query”',
                style: TextStyle(color: MTheme.textMid)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 160, top: 4),
          itemCount: items.length,
          itemBuilder: (_, i) => _VideoRow(item: items[i], onTap: _open),
        );
      },
    );
  }

  Widget _feedList() {
    return FutureBuilder<List<(String, List<YtItem>)>>(
      future: _feed,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SingleChildScrollView(
            child: Column(children: [ShimmerTrackList(count: 3), ShimmerTrackList(count: 3)]),
          );
        }
        final sections = snap.data ?? [];
        if (sections.isEmpty) {
          return Center(
            child: Text("Couldn't load videos.\nCheck your connection.",
                textAlign: TextAlign.center,
                style: TextStyle(color: MTheme.textMid)),
          );
        }
        return RefreshIndicator(
          color: MTheme.accent,
          backgroundColor: MTheme.surfaceHigh,
          onRefresh: () async {
            final next = _loadFeed();
            setState(() => _feed = next);
            await next;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 160),
            children: [
              for (final (title, items) in sections) ...[
                SectionHeader(title: title),
                for (final item in items.take(5))
                  _VideoRow(item: item, onTap: _open),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _VideoRow extends StatelessWidget {
  final YtItem item;
  final void Function(YtItem) onTap;
  const _VideoRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final duration = item.track?.duration;
    return InkWell(
      onTap: () => onTap(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                SizedBox(
                  width: 140,
                  height: 79,
                  child: Artwork(url: item.thumbUrl, size: 140, radius: 10),
                ),
                if (duration != null)
                  Container(
                    margin: const EdgeInsets.all(4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      fmtDuration(duration),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: MTheme.textLow),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
