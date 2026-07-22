// ignore_for_file: avoid_print
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  // A music video (Despacito) — check muxed (audio+video in one file) streams.
  for (final (name, client) in [
    ('androidVr', YoutubeApiClient.androidVr),
    ('ios', YoutubeApiClient.ios),
  ]) {
    try {
      final m = await yt.videos.streamsClient
          .getManifest('kJQP7kiw5Fk', ytClients: [client])
          .timeout(const Duration(seconds: 15));
      print('$name: muxed=${m.muxed.length} audioOnly=${m.audioOnly.length} videoOnly=${m.videoOnly.length}');
      for (final s in m.muxed) {
        final size = s.size.totalBytes;
        int tail = 0;
        try {
          final r = await http.get(s.url, headers: {
            'Range': 'bytes=${size - 1024}-${size - 1}'
          }).timeout(const Duration(seconds: 8));
          tail = r.statusCode;
        } catch (_) {}
        print('  muxed ${s.container.name} ${s.qualityLabel} ${s.videoResolution} '
            '${(size / 1024 / 1024).toStringAsFixed(1)}MB tail=$tail');
      }
    } catch (e) {
      print('$name FAILED: ${e.toString().split('\n').first}');
    }
  }
  yt.close();
}
