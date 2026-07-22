import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/audio_handler.dart';
import '../theme.dart';
import 'player_screen.dart';
import 'widgets/artwork.dart';

/// Docked bar above the nav bar: artwork, title, play/pause, next.
/// Tapping (or swiping up) expands into the full player.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  void _openPlayer(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      opaque: false,
      pageBuilder: (_, _, _) => const PlayerScreen(),
      transitionsBuilder: (_, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(curved),
          child: child,
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MaheraiAudioHandler>();
    return ValueListenableBuilder<Track?>(
      valueListenable: handler.current,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _openPlayer(context),
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -300) _openPlayer(context);
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            decoration: BoxDecoration(
              color: MTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thin live progress line.
                  StreamBuilder<Duration>(
                    stream: handler.player.positionStream,
                    builder: (_, snap) {
                      final pos = snap.data ?? Duration.zero;
                      final dur = handler.displayDuration ?? Duration.zero;
                      final v = dur.inMilliseconds == 0
                          ? 0.0
                          : (pos.inMilliseconds / dur.inMilliseconds)
                              .clamp(0.0, 1.0);
                      return LinearProgressIndicator(
                        value: v,
                        minHeight: 2,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        color: MTheme.accent,
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'now-playing-art',
                          child:
                              Artwork(url: track.thumbUrl, size: 42, radius: 8),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: MTheme.textMid),
                              ),
                            ],
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: handler.loading,
                          builder: (_, loading, _) => loading
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: MTheme.accent),
                                  ),
                                )
                              : StreamBuilder<bool>(
                                  stream: handler.player.playingStream,
                                  builder: (_, snap) {
                                    final playing = snap.data ?? false;
                                    return IconButton(
                                      icon: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        transitionBuilder: (child, anim) =>
                                            ScaleTransition(
                                                scale: anim, child: child),
                                        child: Icon(
                                          playing
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          key: ValueKey(playing),
                                          size: 30,
                                        ),
                                      ),
                                      onPressed: () => playing
                                          ? handler.pause()
                                          : handler.play(),
                                    );
                                  },
                                ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, size: 28),
                          onPressed: handler.skipToNext,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
