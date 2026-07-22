import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/models.dart';
import 'audio_handler.dart';
import 'stream_service.dart';

/// Owns video playback independently of any screen, so a video keeps
/// playing in the floating mini window (in-app) and its audio continues
/// when the app is minimized or the phone is locked
/// (VideoPlayerOptions.allowBackgroundPlayback + the audio background mode).
class VideoPlayerService extends ChangeNotifier {
  final StreamService streams;
  final MaheraiAudioHandler handler;

  VideoPlayerController? controller;
  Track? video;
  bool minimized = false;
  bool loading = false;
  String? error;

  StreamSubscription<bool>? _musicSub;

  VideoPlayerService({required this.streams, required this.handler}) {
    // One player at a time: starting music pauses the video.
    _musicSub = handler.player.playingStream.listen((playing) {
      final c = controller;
      if (playing && c != null && c.value.isPlaying) c.pause();
    });
  }

  bool get isActive => controller != null || loading;

  Future<void> open(Track v) async {
    handler.pause();
    minimized = false;
    error = null;
    if (video?.id == v.id && controller != null) {
      controller!.play();
      notifyListeners();
      return;
    }
    await _disposeController();
    video = v;
    loading = true;
    notifyListeners();
    try {
      final url = await streams.videoUrl(v.id);
      if (video?.id != v.id) return; // replaced meanwhile
      final c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
      );
      await c.initialize();
      if (video?.id != v.id) {
        c.dispose();
        return;
      }
      controller = c;
      c.addListener(notifyListeners);
      await c.play();
      WakelockPlus.enable();
    } catch (_) {
      if (video?.id == v.id) error = 'Couldn’t load this video.';
    } finally {
      if (video?.id == v.id) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> retry() async {
    final v = video;
    if (v == null) return;
    video = null; // force a fresh open
    await open(v);
  }

  void minimize() {
    if (!isActive) return;
    minimized = true;
    notifyListeners();
  }

  void restore() {
    minimized = false;
    notifyListeners();
  }

  Future<void> close() async {
    video = null;
    minimized = false;
    error = null;
    loading = false;
    await _disposeController();
    notifyListeners();
  }

  Future<void> _disposeController() async {
    final c = controller;
    controller = null;
    if (c != null) {
      c.removeListener(notifyListeners);
      await c.dispose();
    }
    WakelockPlus.disable();
  }

  @override
  void dispose() {
    _musicSub?.cancel();
    _disposeController();
    super.dispose();
  }
}
