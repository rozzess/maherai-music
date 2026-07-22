import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/models.dart';
import '../../services/audio_handler.dart';
import '../../theme.dart';
import '../../util/fmt.dart';

/// Plays a YouTube video (progressive MP4). Pauses music playback while
/// open, keeps the screen awake, supports landscape fullscreen.
class VideoPlayerScreen extends StatefulWidget {
  final Track video;
  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  String? _error;
  bool _showControls = true;
  bool _fullscreen = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    // One player at a time: pause the music.
    context.read<MaheraiAudioHandler>().pause();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final url = await context
          .read<MaheraiAudioHandler>()
          .streams
          .videoUrl(widget.video.id);
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      controller.addListener(_onTick);
      controller.play();
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn’t load this video.');
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    if (_fullscreen) {
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

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
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
                      else if (_error != null)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!,
                                  style: TextStyle(color: MTheme.textMid)),
                              const SizedBox(height: 12),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: MTheme.accent),
                                onPressed: _load,
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
            if (!_fullscreen) _infoPanel(),
          ],
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
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                onPressed: () => Navigator.of(context).pop(),
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
                onPressed: _toggleFullscreen,
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

  Widget _infoPanel() {
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
          ],
        ),
      ),
    );
  }
}
