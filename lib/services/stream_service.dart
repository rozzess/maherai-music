import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolves playable audio stream URLs for a videoId via youtube_explode.
///
/// Prefers MP4/AAC audio-only streams (natively decodable by AVPlayer on
/// iOS); falls back to whatever has the highest bitrate. URLs are cached for
/// a few hours (Google stream URLs expire after ~6h).
class StreamService {
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, (String url, DateTime expiry)> _cache = {};

  Future<String> audioUrl(String videoId) async {
    final cached = _cache[videoId];
    if (cached != null && DateTime.now().isBefore(cached.$2)) {
      return cached.$1;
    }
    final info = await _bestAudio(videoId);
    final url = info.url.toString();
    _cache[videoId] =
        (url, DateTime.now().add(const Duration(hours: 4)));
    return url;
  }

  Future<AudioOnlyStreamInfo> _bestAudio(String videoId) async {
    StreamManifest manifest;
    try {
      manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.ios, YoutubeApiClient.androidVr],
      );
    } catch (_) {
      // Retry with default clients if the preferred ones are rejected.
      manifest = await _yt.videos.streamsClient.getManifest(videoId);
    }
    final audio = manifest.audioOnly.toList();
    if (audio.isEmpty) {
      throw Exception('No audio streams available for $videoId');
    }
    final mp4 = audio
        .where((s) => s.container == StreamContainer.mp4)
        .toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    if (mp4.isNotEmpty) return mp4.first;
    audio.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return audio.first;
  }

  /// Stream info for downloading (needs size/container, not just URL).
  Future<AudioOnlyStreamInfo> downloadInfo(String videoId) => _bestAudio(videoId);

  Stream<List<int>> openStream(AudioOnlyStreamInfo info) =>
      _yt.videos.streamsClient.get(info);

  void dispose() => _yt.close();
}
