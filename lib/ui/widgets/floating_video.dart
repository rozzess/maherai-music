import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../services/video_player_service.dart';
import '../../theme.dart';
import '../nav.dart';
import '../screens/video_player_screen.dart';

/// Draggable in-app mini video window shown while a video is minimized.
/// Tap to expand back to the full player; playback never stops.
class FloatingVideo extends StatefulWidget {
  const FloatingVideo({super.key});

  @override
  State<FloatingVideo> createState() => _FloatingVideoState();
}

class _FloatingVideoState extends State<FloatingVideo> {
  static const _width = 200.0;
  static const _height = 112.0 + 32; // 16:9 video + control strip
  Offset? _offset;

  void _expand(VideoPlayerService svc) {
    final video = svc.video;
    if (video == null) return;
    svc.restore();
    // This widget lives above the Navigator (app-level overlay), so it
    // pushes through the root navigator key.
    rootNavigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(video: video),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<VideoPlayerService>();
    final c = svc.controller;
    if (!svc.minimized || c == null || !c.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final screen = MediaQuery.of(context).size;
    final maxX = screen.width - _width - 8;
    final maxY = screen.height - _height - 200; // stay above mini player/nav
    final offset = _offset ?? Offset(maxX, maxY);
    final playing = c.value.isPlaying;

    return Positioned(
      left: offset.dx.clamp(8, maxX),
      top: offset.dy.clamp(8, maxY),
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _offset = Offset(
            (offset.dx + d.delta.dx).clamp(8, maxX),
            (offset.dy + d.delta.dy).clamp(8, maxY),
          );
        }),
        onTap: () => _expand(svc),
        child: Material(
          color: Colors.black,
          elevation: 12,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: _width,
            height: _height,
            child: Column(
              children: [
                SizedBox(
                  width: _width,
                  height: 112,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
                    ),
                  ),
                ),
                Container(
                  height: 32,
                  color: MTheme.surfaceHigh,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _MiniButton(
                        icon: playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onTap: () => playing ? c.pause() : c.play(),
                      ),
                      _MiniButton(
                        icon: Icons.open_in_full_rounded,
                        size: 15,
                        onTap: () => _expand(svc),
                      ),
                      _MiniButton(
                        icon: Icons.close_rounded,
                        onTap: svc.close,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const _MiniButton({required this.icon, required this.onTap, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: size, color: MTheme.textHigh),
      ),
    );
  }
}
