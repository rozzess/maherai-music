import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/audio_handler.dart';
import '../services/download_service.dart';
import '../services/library_service.dart';
import '../services/lyrics_service.dart';
import '../theme.dart';
import '../util/fmt.dart';
import 'widgets/add_to_playlist_sheet.dart';
import 'widgets/artwork.dart';
import 'widgets/track_actions_sheet.dart';
import 'widgets/track_tile.dart';

/// Full-screen player: dynamic palette gradient, hero artwork that breathes
/// with play/pause, swipe artwork to skip, drag down to dismiss, plus
/// lyrics and queue panels.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static final Map<String, Color> _paletteCache = {};

  double _drag = 0;
  bool _dragging = false;
  bool _showLyrics = false;
  Color _tint = MTheme.surfaceHigh;
  String? _tintForUrl;

  Future<void> _updatePalette(String url) async {
    if (url.isEmpty || _tintForUrl == url) return;
    _tintForUrl = url;
    final cached = _paletteCache[url];
    if (cached != null) {
      setState(() => _tint = cached);
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        maximumColorCount: 12,
      );
      final color = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          MTheme.surfaceHigh;
      _paletteCache[url] = color;
      if (mounted && _tintForUrl == url) setState(() => _tint = color);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MaheraiAudioHandler>();
    return ValueListenableBuilder<Track?>(
      valueListenable: handler.current,
      builder: (context, track, _) {
        if (track == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }
        _updatePalette(track.thumbUrl);

        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _dragging = true),
          onVerticalDragUpdate: (d) =>
              setState(() => _drag = (_drag + d.delta.dy).clamp(0.0, 600.0)),
          onVerticalDragEnd: (d) {
            _dragging = false;
            if (_drag > 140 || (d.primaryVelocity ?? 0) > 700) {
              Navigator.of(context).pop();
            } else {
              setState(() => _drag = 0);
            }
          },
          child: AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, _drag, 0),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(_tint, MTheme.bg, 0.35)!,
                      Color.lerp(_tint, MTheme.bg, 0.75)!,
                      MTheme.bg,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      _topBar(context, track),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          child: _showLyrics
                              ? _LyricsView(
                                  key: ValueKey('lyrics-${track.id}'),
                                  track: track)
                              : _artworkView(handler, track),
                        ),
                      ),
                      _titleRow(context, track),
                      _SeekBar(handler: handler),
                      _controls(handler),
                      _secondaryRow(context, handler, track),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _topBar(BuildContext context, Track track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text('NOW PLAYING',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                      color: MTheme.textLow,
                    )),
                Text(
                  track.album ?? 'Maherai Music',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: MTheme.textMid),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () => showTrackActions(context, track),
          ),
        ],
      ),
    );
  }

  Widget _artworkView(MaheraiAudioHandler handler, Track track) {
    return Center(
      key: const ValueKey('artwork'),
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -300) handler.skipToNext();
          if (v > 300) handler.skipToPrevious();
        },
        onTap: () =>
            handler.player.playing ? handler.pause() : handler.play(),
        child: StreamBuilder<bool>(
          stream: handler.player.playingStream,
          builder: (context, snap) {
            final playing = snap.data ?? false;
            final size = MediaQuery.of(context).size.width - 64;
            return AnimatedScale(
              scale: playing ? 1.0 : 0.88,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _tint.withValues(alpha: 0.45),
                      blurRadius: 60,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Hero(
                  tag: 'now-playing-art',
                  child: Artwork(url: track.thumbUrl, size: size, radius: 24),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _titleRow(BuildContext context, Track track) {
    final library = context.watch<LibraryService>();
    final fav = library.isFavorite(track.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: MTheme.textMid),
                ),
              ],
            ),
          ),
          _AnimatedFavButton(
            fav: fav,
            onTap: () => library.toggleFavorite(track),
          ),
        ],
      ),
    );
  }

  Widget _controls(MaheraiAudioHandler handler) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: handler.shuffleOn,
            builder: (_, on, _) => IconButton(
              icon: Icon(Icons.shuffle_rounded,
                  color: on ? MTheme.accent : MTheme.textMid),
              onPressed: handler.toggleShuffle,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded, size: 42),
            onPressed: handler.skipToPrevious,
          ),
          _PlayPauseButton(handler: handler),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded, size: 42),
            onPressed: handler.skipToNext,
          ),
          ValueListenableBuilder<AudioServiceRepeatMode>(
            valueListenable: handler.repeat,
            builder: (_, mode, _) => IconButton(
              icon: Icon(
                mode == AudioServiceRepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color: mode == AudioServiceRepeatMode.none
                    ? MTheme.textMid
                    : MTheme.accent,
              ),
              onPressed: handler.cycleRepeat,
            ),
          ),
        ],
      ),
    );
  }

  Widget _secondaryRow(
      BuildContext context, MaheraiAudioHandler handler, Track track) {
    final downloads = context.watch<DownloadService>();
    final downloaded = downloads.isDownloaded(track.id);
    final progress = downloads.active[track.id];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              Icons.lyrics_outlined,
              color: _showLyrics ? MTheme.accent : MTheme.textMid,
            ),
            tooltip: 'Lyrics',
            onPressed: () => setState(() => _showLyrics = !_showLyrics),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded),
            color: MTheme.textMid,
            tooltip: 'Add to playlist',
            onPressed: () => showAddToPlaylist(context, track),
          ),
          if (progress != null)
            SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      value: progress, strokeWidth: 2, color: MTheme.accent),
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(
                downloaded
                    ? Icons.download_done_rounded
                    : Icons.download_rounded,
                color: downloaded ? MTheme.accent : MTheme.textMid,
              ),
              tooltip: 'Download',
              onPressed: () {
                if (downloaded) {
                  downloads.delete(track.id);
                } else {
                  downloads.download(track);
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            color: MTheme.textMid,
            tooltip: 'Queue',
            onPressed: () => showModalBottomSheet(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              builder: (_) => const QueueSheet(),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ pieces

class _PlayPauseButton extends StatelessWidget {
  final MaheraiAudioHandler handler;
  const _PlayPauseButton({required this.handler});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: handler.loading,
      builder: (_, loading, _) => StreamBuilder<bool>(
        stream: handler.player.playingStream,
        builder: (_, snap) {
          final playing = snap.data ?? false;
          return GestureDetector(
            onTap: () => playing ? handler.pause() : handler.play(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: MTheme.accent.withValues(alpha: 0.35),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: MTheme.bg),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey(playing),
                        size: 42,
                        color: MTheme.bg,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _AnimatedFavButton extends StatefulWidget {
  final bool fav;
  final VoidCallback onTap;
  const _AnimatedFavButton({required this.fav, required this.onTap});

  @override
  State<_AnimatedFavButton> createState() => _AnimatedFavButtonState();
}

class _AnimatedFavButtonState extends State<_AnimatedFavButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    lowerBound: 0.7,
  )..value = 1;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
      child: IconButton(
        icon: Icon(
          widget.fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: widget.fav ? MTheme.accent : MTheme.textMid,
          size: 28,
        ),
        onPressed: () {
          _c.forward(from: 0.7);
          widget.onTap();
        },
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  final MaheraiAudioHandler handler;
  const _SeekBar({required this.handler});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final player = widget.handler.player;
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final duration = player.duration ?? Duration.zero;
        final position = snap.data ?? Duration.zero;
        final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
        final value =
            (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, max);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              Slider(
                value: value,
                max: max,
                onChanged: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  widget.handler.seek(Duration(milliseconds: v.round()));
                  _dragValue = null;
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(fmtDuration(Duration(milliseconds: value.round())),
                        style:
                            TextStyle(fontSize: 12, color: MTheme.textLow)),
                    Text(fmtDuration(duration),
                        style:
                            TextStyle(fontSize: 12, color: MTheme.textLow)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------- lyrics

class _LyricsView extends StatefulWidget {
  final Track track;
  const _LyricsView({super.key, required this.track});

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  final ScrollController _scroll = ScrollController();
  Lyrics? _lyrics;
  bool _loaded = false;
  int _activeIndex = -1;
  static const double _lineExtent = 56;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final handler = context.read<MaheraiAudioHandler>();
    final lyricsService = context.read<LyricsService>();
    final browseId = await handler.lyricsBrowseId();
    final lyrics = await lyricsService.forTrack(widget.track,
        ytLyricsBrowseId: browseId);
    if (mounted) {
      setState(() {
        _lyrics = lyrics;
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onPosition(Duration pos) {
    final lyrics = _lyrics;
    if (lyrics == null || !lyrics.synced) return;
    var idx = -1;
    for (var i = 0; i < lyrics.lines.length; i++) {
      if (lyrics.lines[i].time <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx != _activeIndex) {
      setState(() => _activeIndex = idx);
      if (idx >= 0 && _scroll.hasClients) {
        final target = (idx * _lineExtent - 120)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MaheraiAudioHandler>();
    if (!_loaded) {
      return const Center(
          child: CircularProgressIndicator(color: MTheme.accent));
    }
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, size: 48, color: MTheme.textLow),
            const SizedBox(height: 12),
            Text('No lyrics found for this song',
                style: TextStyle(color: MTheme.textMid)),
          ],
        ),
      );
    }
    return StreamBuilder<Duration>(
      stream: handler.player.positionStream,
      builder: (context, snap) {
        if (snap.hasData) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _onPosition(snap.data!));
        }
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          itemExtent: lyrics.synced ? _lineExtent : null,
          itemCount: lyrics.lines.length,
          itemBuilder: (_, i) {
            final line = lyrics.lines[i];
            final active = lyrics.synced && i == _activeIndex;
            return GestureDetector(
              onTap: lyrics.synced ? () => handler.seek(line.time) : null,
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: active ? 20 : 17,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? MTheme.textHigh
                        : lyrics.synced
                            ? MTheme.textLow
                            : MTheme.textMid,
                    height: 1.3,
                  ),
                  child: Text(
                    line.text.isEmpty ? '♪' : line.text,
                    maxLines: lyrics.synced ? 2 : null,
                    overflow: lyrics.synced ? TextOverflow.ellipsis : null,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// -------------------------------------------------------------------- queue

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MaheraiAudioHandler>();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Up next',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: handler.autoplayRadio,
                    builder: (_, on, _) => Row(
                      children: [
                        Text('Autoplay',
                            style: TextStyle(
                                fontSize: 13, color: MTheme.textMid)),
                        const SizedBox(width: 4),
                        Switch(
                          value: on,
                          activeColor: MTheme.accent,
                          onChanged: (v) => handler.autoplayRadio.value = v,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<List<Track>>(
                valueListenable: handler.queueTracks,
                builder: (context, tracks, _) {
                  return ValueListenableBuilder<int>(
                    valueListenable: handler.queueIndex,
                    builder: (context, currentIndex, _) {
                      return ReorderableListView.builder(
                        scrollController: scrollController,
                        itemCount: tracks.length,
                        onReorder: handler.moveInQueue,
                        proxyDecorator: (child, _, _) => Material(
                          color: MTheme.surfaceHigh,
                          borderRadius: BorderRadius.circular(12),
                          child: child,
                        ),
                        itemBuilder: (context, i) {
                          final t = tracks[i];
                          return Dismissible(
                            key: ValueKey('q-${t.id}-$i'),
                            direction: i == currentIndex
                                ? DismissDirection.none
                                : DismissDirection.endToStart,
                            onDismissed: (_) => handler.removeFromQueue(i),
                            background: Container(
                              color: MTheme.accent.withValues(alpha: 0.25),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: const Icon(Icons.delete_outline_rounded),
                            ),
                            child: TrackTile(
                              track: t,
                              onTap: () => handler.skipToQueueItem(i),
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
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
