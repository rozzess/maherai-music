// ignore_for_file: avoid_print
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  // Houdini (3:06) and Love Again (4:19)
  for (final videoId in ['cCfPDrRQp9k', 'IkL-RjXJLv0']) {
    print('=== $videoId');
    for (final (name, client) in [
      ('androidVr', YoutubeApiClient.androidVr),
      ('android', YoutubeApiClient.android),
      ('androidMusic', YoutubeApiClient.androidMusic),
      ('ios', YoutubeApiClient.ios),
      ('tv', YoutubeApiClient.tv),
      ('mweb', YoutubeApiClient.mweb),
      ('safari', YoutubeApiClient.safari),
    ]) {
      final sw = Stopwatch()..start();
      try {
        final m = await yt.videos.streamsClient
            .getManifest(videoId, ytClients: [client])
            .timeout(const Duration(seconds: 20));
        final audio = m.audioOnly.toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
        if (audio.isEmpty) {
          print('  $name: NO AUDIO (${sw.elapsedMilliseconds}ms)');
          continue;
        }
        final mp4 = audio.where((s) => s.container == StreamContainer.mp4);
        final best = mp4.isNotEmpty ? mp4.first : audio.first;
        final resolveMs = sw.elapsedMilliseconds;
        // Probe: first KB and last KB, like a real player's range requests.
        final size = best.size.totalBytes;
        var headStatus = 0, tailStatus = 0;
        try {
          final r1 = await http.get(best.url,
              headers: {'Range': 'bytes=0-1023'}).timeout(const Duration(seconds: 10));
          headStatus = r1.statusCode;
          final r2 = await http.get(best.url, headers: {
            'Range': 'bytes=${size - 1024}-${size - 1}'
          }).timeout(const Duration(seconds: 10));
          tailStatus = r2.statusCode;
        } catch (e) {
          print('  $name: probe error ${e.runtimeType}');
        }
        print('  $name: ${resolveMs}ms ${best.container.name}@${best.bitrate.kiloBitsPerSecond.round()}kbps '
            'size=${(size / 1024 / 1024).toStringAsFixed(1)}MB head=$headStatus tail=$tailStatus');
      } catch (e) {
        print('  $name FAILED ${sw.elapsedMilliseconds}ms: ${e.toString().split('\n').first}');
      }
    }
  }
  yt.close();
}
