import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/models.dart';
import '../../services/video_player_service.dart';
import '../../theme.dart';
import '../../util/fmt.dart';

/// Full-screen view over VideoPlayerService. The down-arrow minimizes into
/// the floating mini window (playback continues); X closes for real.
class VideoPlayerScreen extends StatefulWidget {
  final Track video;
  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  bool _showControls = true;
  bool _fullscreen = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<VideoPlayerService>().open(widget.video);
    });
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      final playing = context.mounted &&
          (context.read<VideoPlayerService>().controller?.value.isPlaying ??
              false);
      if (mounted && playing) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  Future<void> _setFullscreen(bool on) async {
    _fullscreen = on;
    if (on) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) setState(() {});
  }

  Future<void> _minimize() async {
    if (_fullscreen) await _setFullscreen(false);
    if (!mounted) return;
    context.read<VideoPlayerService>().minimize();
    Navigator.of(context).pop();
  }

  Future<void> _close() async {
    if (_fullscreen) await _setFullscreen(false);
    if (!mounted) return;
    context.read<VideoPlayerService>().close();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    // Screen never owns the controller — the service does.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<VideoPlayerService>();
    final c = svc.controller;
    return PopScope(
      // Swiping back minimizes rather than killing playback.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimize();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: _fullscreen ? 1 : 0,
                child: AspectRatio(
                  aspectRatio: _fullscreen
                      ? MediaQuery.of(context).size.aspectRatio
                      : 16 / 9,
                  child: GestureDetector(
                    onTap: _toggleControls,
                    child: Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: [
                        if (c != null && c.value.isInitialized)
                          FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: c.value.size.width,
                              height: c.value.size.height,
                              child: VideoPlayer(c),
                            ),
                          )
                        else if (svc.error != null)
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(svc.error!,
                                    style: TextStyle(color: MTheme.textMid)),
                                const SizedBox(height: 12),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: MTheme.accent),
                                  onPressed: svc.retry,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        else
                          const Center(
                            child: CircularProgressIndicator(
                                color: MTheme.accent),
                          ),
                        if (_showControls) _controlsOverlay(c),
                      ],
                    ),
                  ),
                ),
              ),
              if (!_fullscreen) _infoPanel(svc),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlsOverlay(VideoPlayerController? c) {
    final value = c?.value;
    final playing = value?.isPlaying ?? false;
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Minimize',
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                onPressed: _minimize,
              ),
              Expanded(
                child: Text(
                  widget.video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: Icon(_fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded),
                onPressed: () => _setFullscreen(!_fullscreen),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: _close,
              ),
            ],
          ),
          const Spacer(),
          if (c != null && value != null && value.isInitialized)
            IconButton(
              iconSize: 64,
              icon: Icon(
                playing
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_filled_rounded,
              ),
              onPressed: () {
                playing ? c.pause() : c.play();
                _scheduleHide();
              },
            ),
          const Spacer(),
          if (c != null && value != null && value.isInitialized)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(fmtDuration(value.position),
                      style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: value.position.inMilliseconds
                          .clamp(0, value.duration.inMilliseconds)
                          .toDouble(),
                      max: value.duration.inMilliseconds
                          .toDouble()
                          .clamp(1, double.infinity),
                      onChanged: (v) {
                        c.seekTo(Duration(milliseconds: v.round()));
                        _scheduleHide();
                      },
                    ),
                  ),
                  Text(fmtDuration(value.duration),
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _infoPanel(VideoPlayerService svc) {
    return Expanded(
      child: Container(
        width: double.infinity,
        color: MTheme.bg,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.video.title,
              maxLines: 3,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.video.artist,
              style: TextStyle(fontSize: 14, color: MTheme.textMid),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.picture_in_picture_alt_rounded,
                    size: 16, color: MTheme.textLow),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Swipe down to keep watching in a mini window. '
                    'Audio keeps playing if you leave the app.',
                    style: TextStyle(fontSize: 12, color: MTheme.textLow),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
