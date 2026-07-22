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
  // In-flight resolutions, so a prefetch and a play of the same id share one
  // network round trip instead of racing.
  final Map<String, Future<String>> _pending = {};

  Future<String> audioUrl(String videoId) {
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
    final future = _resolve(videoId).then((url) {
      _pending.remove(videoId);
      return url;
    }, onError: (Object e) {
      _pending.remove(videoId);
      throw e;
    });
    _pending[videoId] = future;
    return future;
  }

  Future<String> _resolve(String videoId) async {
    final info = await _bestAudio(videoId);
    final url = info.url.toString();
    _cache[videoId] = (url, DateTime.now().add(const Duration(hours: 4)));
    return url;
  }

  /// Drops a cached URL (used when playback discovers it's bad/truncated).
  void invalidate(String videoId) => _cache.remove(videoId);

  Future<AudioOnlyStreamInfo> _bestAudio(String videoId) async {
    // Try ONE client at a time, fastest-first: passing several makes
    // youtube_explode query and merge all of them, multiplying latency.
    // androidVr needs no signature deciphering (no player-JS fetch) and no
    // po_token, so it answers in ~1s — but YouTube bot-checks it
    // intermittently, so it gets a second chance before falling back.
    Object? lastError;
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
        if (await _servesFullStream(best)) return best;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('No full audio stream for $videoId ($lastError)');
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

  Future<bool> _servesFullStream(AudioOnlyStreamInfo info) async {
    final size = info.size.totalBytes;
    if (size <= 2048) return true;
    try {
      final res = await http.get(info.url, headers: {
        'Range': 'bytes=${size - 1024}-${size - 1}',
      }).timeout(const Duration(seconds: 6));
      return res.statusCode == 200 || res.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  /// Stream info for downloading (needs size/container, not just URL).
  Future<AudioOnlyStreamInfo> downloadInfo(String videoId) => _bestAudio(videoId);

  Stream<List<int>> openStream(AudioOnlyStreamInfo info) =>
      _yt.videos.streamsClient.get(info);

  void dispose() => _yt.close();
}
