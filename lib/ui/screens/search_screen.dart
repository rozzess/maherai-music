import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/audio_handler.dart';
import '../../services/innertube.dart';
import '../../services/library_service.dart';
import '../../theme.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmers.dart';
import '../widgets/track_tile.dart';
import '../widgets/yt_card.dart';

enum _SearchFilter { all, songs, videos, albums, artists, playlists }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  List<String> _suggestions = [];
  bool _typing = false;
  String _submitted = '';
  _SearchFilter _filter = _SearchFilter.all;
  Future<SearchResults>? _results;
  Future<List<YtItem>>? _filtered;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() => _typing = text.trim().isNotEmpty);
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final s = await context.read<InnerTube>().searchSuggestions(text);
        if (mounted && _controller.text == text) {
          setState(() => _suggestions = s);
        }
      } catch (_) {}
    });
  }

  void _submit(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _focus.unfocus();
    context.read<LibraryService>().addSearch(q);
    setState(() {
      _controller.text = q;
      _typing = false;
      _submitted = q;
      _filter = _SearchFilter.all;
      _results = context.read<InnerTube>().search(q);
      _filtered = null;
    });
  }

  void _setFilter(_SearchFilter f) {
    setState(() {
      _filter = f;
      if (f != _SearchFilter.all && _submitted.isNotEmpty) {
        final kind = switch (f) {
          _SearchFilter.songs => YtKind.song,
          _SearchFilter.videos => YtKind.video,
          _SearchFilter.albums => YtKind.album,
          _SearchFilter.artists => YtKind.artist,
          _SearchFilter.playlists => YtKind.playlist,
          _SearchFilter.all => YtKind.song,
        };
        _filtered = context.read<InnerTube>().searchFiltered(_submitted, kind);
      }
    });
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
              focusNode: _focus,
              onChanged: _onChanged,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Songs, artists, albums…',
                hintStyle: TextStyle(color: MTheme.textLow),
                prefixIcon: Icon(Icons.search_rounded, color: MTheme.textLow),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: MTheme.textLow, size: 20),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _typing = false;
                            _suggestions = [];
                            _submitted = '';
                            _results = null;
                            _filtered = null;
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
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_typing) return _suggestionList();
    if (_submitted.isNotEmpty) return _resultsView();
    return _idleView();
  }

  Widget _idleView() {
    final library = context.watch<LibraryService>();
    final history = library.searchHistory;
    return ListView(
      padding: const EdgeInsets.only(bottom: 160),
      children: [
        if (history.isNotEmpty) ...[
          const SectionHeader(title: 'Recent searches'),
          for (final q in history)
            ListTile(
              leading: Icon(Icons.history_rounded, color: MTheme.textLow),
              title: Text(q, style: const TextStyle(fontSize: 15)),
              trailing: IconButton(
                icon: Icon(Icons.close_rounded,
                    size: 18, color: MTheme.textLow),
                onPressed: () => library.removeSearch(q),
              ),
              onTap: () => _submit(q),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              children: [
                Icon(Icons.travel_explore_rounded,
                    size: 56, color: MTheme.textLow),
                const SizedBox(height: 16),
                Text(
                  'Find any song, artist or album\non YouTube Music',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MTheme.textMid, height: 1.5),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _suggestionList() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 160),
      children: [
        for (final s in _suggestions)
          ListTile(
            leading: Icon(Icons.search_rounded, color: MTheme.textLow),
            title: Text(s, style: const TextStyle(fontSize: 15)),
            trailing: Icon(Icons.north_west_rounded,
                size: 16, color: MTheme.textLow),
            onTap: () => _submit(s),
          ),
      ],
    );
  }

  Widget _resultsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in _SearchFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(switch (f) {
                      _SearchFilter.all => 'All',
                      _SearchFilter.songs => 'Songs',
                      _SearchFilter.videos => 'Videos',
                      _SearchFilter.albums => 'Albums',
                      _SearchFilter.artists => 'Artists',
                      _SearchFilter.playlists => 'Playlists',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => _setFilter(f),
                    showCheckmark: false,
                    selectedColor: MTheme.accent,
                    backgroundColor: MTheme.surfaceHigh,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          _filter == f ? Colors.white : MTheme.textMid,
                    ),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _filter == _SearchFilter.all
              ? _groupedResults()
              : _filteredResults(),
        ),
      ],
    );
  }

  Widget _groupedResults() {
    return FutureBuilder<SearchResults>(
      future: _results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SingleChildScrollView(child: ShimmerTrackList());
        }
        final r = snap.data;
        if (r == null || r.isEmpty) return _noResults();
        final handler = context.read<MaheraiAudioHandler>();
        return ListView(
          padding: const EdgeInsets.only(bottom: 160),
          children: [
            if (r.songs.isNotEmpty) ...[
              _groupHeader('Songs', _SearchFilter.songs),
              for (final item in r.songs.take(5))
                if (item.track != null)
                  TrackTile(
                    track: item.track!,
                    onTap: () => handler.playSong(item.track!),
                  ),
            ],
            if (r.artists.isNotEmpty) ...[
              _groupHeader('Artists', _SearchFilter.artists),
              _hCards(r.artists),
            ],
            if (r.albums.isNotEmpty) ...[
              _groupHeader('Albums', _SearchFilter.albums),
              _hCards(r.albums),
            ],
            if (r.videos.isNotEmpty) ...[
              _groupHeader('Videos', _SearchFilter.videos),
              for (final item in r.videos.take(4))
                if (item.track != null)
                  TrackTile(
                    track: item.track!,
                    onTap: () => handler.playSong(item.track!),
                  ),
            ],
            if (r.playlists.isNotEmpty) ...[
              _groupHeader('Playlists', _SearchFilter.playlists),
              _hCards(r.playlists),
            ],
          ],
        );
      },
    );
  }

  Widget _groupHeader(String title, _SearchFilter more) {
    return SectionHeader(
      title: title,
      trailing: TextButton(
        onPressed: () => _setFilter(more),
        child: Text('More',
            style: TextStyle(color: MTheme.textMid, fontSize: 13)),
      ),
    );
  }

  Widget _hCards(List<YtItem> items) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => YtCard(item: items[i], size: 132),
      ),
    );
  }

  Widget _filteredResults() {
    return FutureBuilder<List<YtItem>>(
      future: _filtered,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SingleChildScrollView(child: ShimmerTrackList());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) return _noResults();
        final handler = context.read<MaheraiAudioHandler>();
        final playableQueue =
            items.map((it) => it.track).whereType<Track>().toList();
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 160, top: 8),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            if (item.track != null) {
              final t = item.track!;
              return TrackTile(
                track: t,
                showDuration: true,
                onTap: () {
                  final idx = playableQueue.indexOf(t);
                  handler.playQueue(playableQueue,
                      startIndex: idx < 0 ? 0 : idx, radio: true);
                },
              );
            }
            return ListTile(
              leading: SizedBox(
                width: 52,
                height: 52,
                child: _CardThumb(item: item),
              ),
              title: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: MTheme.textLow, fontSize: 12)),
              onTap: () => openYtItem(context, item),
            );
          },
        );
      },
    );
  }

  Widget _noResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: MTheme.textLow),
          const SizedBox(height: 12),
          Text('No results for “$_submitted”',
              style: TextStyle(color: MTheme.textMid)),
        ],
      ),
    );
  }
}

class _CardThumb extends StatelessWidget {
  final YtItem item;
  const _CardThumb({required this.item});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius:
          BorderRadius.circular(item.kind == YtKind.artist ? 26 : 8),
      child: item.thumbUrl.isEmpty
          ? Container(
              color: MTheme.surfaceHigh,
              child: Icon(
                item.kind == YtKind.artist
                    ? Icons.person_rounded
                    : Icons.album_rounded,
                color: MTheme.textLow,
              ),
            )
          : Image.network(item.thumbUrl, fit: BoxFit.cover),
    );
  }
}
