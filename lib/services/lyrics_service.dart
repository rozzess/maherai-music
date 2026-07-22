import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'innertube.dart';

/// Fetches lyrics: time-synced from LRCLIB when available, otherwise plain
/// lyrics from YouTube Music.
class LyricsService {
  final InnerTube _innertube;
  final Map<String, Lyrics?> _cache = {};

  LyricsService(this._innertube);

  Future<Lyrics?> forTrack(Track track, {String? ytLyricsBrowseId}) async {
    if (_cache.containsKey(track.id)) return _cache[track.id];
    Lyrics? result = await _fromLrclib(track);
    if (result == null && ytLyricsBrowseId != null) {
      try {
        final plain = await _innertube.lyricsPlain(ytLyricsBrowseId);
        if (plain != null && plain.trim().isNotEmpty) {
          result = Lyrics(
            lines: plain
                .split('\n')
                .map((l) => LyricLine(Duration.zero, l))
                .toList(),
            synced: false,
            source: 'YouTube Music',
          );
        }
      } catch (_) {}
    }
    _cache[track.id] = result;
    return result;
  }

  Future<Lyrics?> _fromLrclib(Track track) async {
    try {
      final params = {
        'track_name': track.title,
        'artist_name': track.artist.split(',').first.trim(),
        if (track.duration != null)
          'duration': track.duration!.inSeconds.toString(),
      };
      final uri = Uri.https('lrclib.net', '/api/get', params);
      final res = await http.get(uri, headers: {
        'User-Agent': 'MaheraiMusic/1.0 (https://github.com)',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final synced = json['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        final lines = parseLrc(synced);
        if (lines.isNotEmpty) {
          return Lyrics(lines: lines, synced: true, source: 'LRCLIB');
        }
      }
      final plain = json['plainLyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        return Lyrics(
          lines:
              plain.split('\n').map((l) => LyricLine(Duration.zero, l)).toList(),
          synced: false,
          source: 'LRCLIB',
        );
      }
    } catch (_) {}
    return null;
  }

  /// Parses LRC format: `[mm:ss.xx] line`.
  static List<LyricLine> parseLrc(String lrc) {
    final re = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\](.*)');
    final lines = <LyricLine>[];
    for (final raw in lrc.split('\n')) {
      final m = re.firstMatch(raw.trim());
      if (m == null) continue;
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final fracRaw = m.group(3) ?? '0';
      final ms = (double.parse('0.$fracRaw') * 1000).round();
      lines.add(LyricLine(
        Duration(minutes: min, seconds: sec, milliseconds: ms),
        m.group(4)!.trim(),
      ));
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }
}
