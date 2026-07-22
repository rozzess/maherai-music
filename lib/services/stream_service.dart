import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolves playable audio stream URLs for a videoId via youtube_explode.
///
/// Prefers MP4/AAC audio-only streams (natively decodable by AVPlayer on
/// iOS); falls back to whatever has the highest bitrate. URLs are cached for
/// a few hours (Google stream URLs expire after ~6h).
class StreamService {
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, (String url, DateTime expiry)> _cache = {};
  final Map<String, (String url, DateTime expiry)> _videoCache = {};
  final Map<String, Duration> _approxDurations = {};

  /// True audio length of the accepted stream, computed from file size at
  /// the stream bitrate. Immune to lying container headers (files that claim
  /// 9:44 while holding 3:22 of audio) — used when a track has no metadata
  /// duration.
  Duration? approxDuration(String videoId) => _approxDurations[videoId];
  // In-flight resolutions, so a prefetch and a play of the same id share one
  // network round trip instead of racing.
  final Map<String, Future<String>> _pending = {};

  /// Audio stream URL. Pass [expected] (the song's real length from YT Music
  /// metadata) so wrong-length streams — truncated files that end early, or
  /// bloated ones that "play" silence past the song — are rejected up front.
  Future<String> audioUrl(String videoId, {Duration? expected}) {
    final cached = _cache[videoId];
    if (cached != null && DateTime.now().isBefore(cached.$2)) {
      return Future.value(cached.$1);
    }
    final pending = _pending[videoId];
    if (pending != null) return pending;
    // NOTE: not whenComplete(() => _pending.remove(id)) — Map.remove returns
    // the removed value (this very future), and a whenComplete callback that
    // returns a future is awaited by the chain: the future would deadlock
    // waiting on itself.
    final future = _resolve(videoId, expected).then((url) {
      _pending.remove(videoId);
      return url;
    }, onError: (Object e) {
      _pending.remove(videoId);
      throw e;
    });
    _pending[videoId] = future;
    return future;
  }

  Future<String> _resolve(String videoId, Duration? expected) async {
    final info = await _bestAudio(videoId, expected: expected);
    final url = info.url.toString();
    _cache[videoId] = (url, DateTime.now().add(const Duration(hours: 4)));
    return url;
  }

  /// Muxed (audio+video) stream URL for the video player. YouTube serves one
  /// progressive MP4 (360p) that AVPlayer/ExoPlayer play natively.
  Future<String> videoUrl(String videoId) async {
    final cached = _videoCache[videoId];
    if (cached != null && DateTime.now().isBefore(cached.$2)) {
      return cached.$1;
    }
    Object? lastError;
    for (final clients in [
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.androidVr],
      null,
    ]) {
      try {
        final m = clients == null
            ? await _yt.videos.streamsClient
                .getManifest(videoId)
                .timeout(const Duration(seconds: 10))
            : await _yt.videos.streamsClient
                .getManifest(videoId, ytClients: clients)
                .timeout(const Duration(seconds: 10));
        final muxed = m.muxed.toList()
          ..sort((a, b) => (b.videoResolution.height * b.videoResolution.width)
              .compareTo(a.videoResolution.height * a.videoResolution.width));
        if (muxed.isEmpty) continue;
        final best = muxed.first;
        if (!await _servesFullUrl(best.url, best.size.totalBytes)) continue;
        final url = best.url.toString();
        _videoCache[videoId] =
            (url, DateTime.now().add(const Duration(hours: 4)));
        return url;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('No playable video stream for $videoId ($lastError)');
  }

  /// Drops a cached URL (used when playback discovers it's bad/truncated).
  void invalidate(String videoId) => _cache.remove(videoId);

  Future<AudioOnlyStreamInfo> _bestAudio(String videoId,
      {Duration? expected}) async {
    // Try ONE client at a time, fastest-first: passing several makes
    // youtube_explode query and merge all of them, multiplying latency.
    // androidVr needs no signature deciphering (no player-JS fetch) and no
    // po_token, so it answers in ~1s — but YouTube bot-checks it
    // intermittently, so it gets a second chance before falling back.
    Object? lastError;
    AudioOnlyStreamInfo? fullButWrongLength;
    for (final clients in [
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.ios],
      null, // library defaults, last resort
    ]) {
      try {
        // getManifest can hang indefinitely when YouTube bot-checks a
        // client; a bounded attempt lets the next client take over.
        final m = clients == null
            ? await _yt.videos.streamsClient
                .getManifest(videoId)
                .timeout(const Duration(seconds: 10))
            : await _yt.videos.streamsClient
                .getManifest(videoId, ytClients: clients)
                .timeout(const Duration(seconds: 10));
        final best = _pickBest(m.audioOnly.toList());
        if (best == null) continue;
        // Some clients resolve fine but their URLs only serve the head of
        // the file (observed: 'android' returns 403 for the tail), which
        // plays as a cut-off short version. Only accept URLs that can serve
        // the END of the stream.
        if (!await _servesFullStream(best)) continue;
        _recordApproxDuration(videoId, best);
        // Wrong-length guard: file size at this bitrate must roughly match
        // the song's real duration, otherwise the stream is a cut or padded
        // version of the track.
        if (_matchesDuration(best, expected)) return best;
        fullButWrongLength ??= best;
      } catch (e) {
        lastError = e;
      }
    }
    // Better to play an imperfect stream than nothing; the audio handler's
    // watchdogs handle the mismatch at playback time.
    if (fullButWrongLength != null) return fullButWrongLength;
    throw Exception('No full audio stream for $videoId ($lastError)');
  }

  void _recordApproxDuration(String videoId, AudioOnlyStreamInfo info) {
    final bps = info.bitrate.bitsPerSecond;
    if (bps <= 0 || info.size.totalBytes <= 0) return;
    _approxDurations[videoId] = Duration(
        milliseconds: (info.size.totalBytes * 8 / bps * 1000).round());
  }

  bool _matchesDuration(AudioOnlyStreamInfo info, Duration? expected) {
    if (expected == null || expected <= Duration.zero) return true;
    final bps = info.bitrate.bitsPerSecond;
    if (bps <= 0 || info.size.totalBytes <= 0) return true;
    final approxSeconds = info.size.totalBytes * 8 / bps;
    final tolerance = math.max(20.0, expected.inSeconds * 0.25);
    return (approxSeconds - expected.inSeconds).abs() <= tolerance;
  }

  AudioOnlyStreamInfo? _pickBest(List<AudioOnlyStreamInfo> audio) {
    if (audio.isEmpty) return null;
    final mp4 = audio
        .where((s) => s.container == StreamContainer.mp4)
        .toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    if (mp4.isNotEmpty) return mp4.first;
    audio.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return audio.first;
  }

  Future<bool> _servesFullStream(AudioOnlyStreamInfo info) =>
      _servesFullUrl(info.url, info.size.totalBytes);

  Future<bool> _servesFullUrl(Uri url, int size) async {
    if (size <= 2048) return true;
    try {
      final res = await http.get(url, headers: {
        'Range': 'bytes=${size - 1024}-${size - 1}',
      }).timeout(const Duration(seconds: 6));
      return res.statusCode == 200 || res.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  /// Stream info for downloading (needs size/container, not just URL).
  Future<AudioOnlyStreamInfo> downloadInfo(String videoId,
          {Duration? expected}) =>
      _bestAudio(videoId, expected: expected);

  Stream<List<int>> openStream(AudioOnlyStreamInfo info) =>
      _yt.videos.streamsClient.get(info);

  void dispose() => _yt.close();
}
