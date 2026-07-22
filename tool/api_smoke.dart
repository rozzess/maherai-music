// ignore_for_file: avoid_print
// Smoke test for the pure-Dart services against live endpoints.
// Run: dart run tool/api_smoke.dart
import 'package:maherai_music/models/models.dart';
import 'package:maherai_music/services/innertube.dart';
import 'package:maherai_music/services/lyrics_service.dart';
import 'package:maherai_music/services/stream_service.dart';

Future<void> main() async {
  final yt = InnerTube();

  print('--- home()');
  final home = await yt.home();
  print('${home.length} sections');
  for (final s in home.take(3)) {
    print('  [${s.title}] ${s.items.length} items — '
        '${s.items.take(2).map((i) => '${i.kind.name}:${i.title}').join(' | ')}');
  }

  print('--- searchSuggestions("dua li")');
  print((await yt.searchSuggestions('dua li')).take(4).toList());

  print('--- search("dua lipa")');
  final r = await yt.search('dua lipa');
  print('songs=${r.songs.length} videos=${r.videos.length} '
      'albums=${r.albums.length} artists=${r.artists.length} '
      'playlists=${r.playlists.length}');
  final song = r.songs.first.track!;
  print('first song: ${song.title} / ${song.artist} / ${song.id} '
      'dur=${song.duration} thumb=${song.thumbUrl.isNotEmpty}');

  print('--- searchFiltered songs');
  final filtered = await yt.searchFiltered('the weeknd', YtKind.song);
  print('${filtered.length} songs — first: ${filtered.first.title}');

  print('--- radio(${song.id})');
  final (radio, lyricsId) = await yt.radio(song.id);
  print('${radio.length} tracks, lyricsBrowseId=$lyricsId');
  print('  next up: ${radio.take(3).map((t) => t.title).join(' | ')}');

  if (r.albums.isNotEmpty) {
    print('--- playlist(album ${r.albums.first.id})');
    final album = await yt.playlist(r.albums.first.id);
    print('"${album.title}" (${album.subtitle}) ${album.tracks.length} tracks, '
        'thumb=${album.thumbUrl.isNotEmpty}');
  }

  if (r.artists.isNotEmpty) {
    print('--- artist(${r.artists.first.id})');
    final artist = await yt.artist(r.artists.first.id);
    print('"${artist.name}" topSongs=${artist.topSongs.length} '
        'shelves=${artist.shelves.map((s) => s.title).toList()}');
  }

  if (lyricsId != null) {
    print('--- lyricsPlain');
    final text = await yt.lyricsPlain(lyricsId);
    print('yt lyrics: ${text?.split('\n').take(2).join(' / ')}');
  }

  print('--- LyricsService (LRCLIB synced)');
  final lyrics = await LyricsService(yt).forTrack(const Track(
    id: 'test',
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    duration: Duration(seconds: 200),
  ));
  print('synced=${lyrics?.synced} source=${lyrics?.source} '
      'lines=${lyrics?.lines.length} '
      'first="${lyrics?.lines.firstWhere((l) => l.text.isNotEmpty).text}" '
      '@${lyrics?.lines.firstWhere((l) => l.text.isNotEmpty).time}');

  print('--- StreamService.audioUrl(${song.id})');
  final streams = StreamService();
  final url = await streams.audioUrl(song.id);
  print('stream url ok: ${Uri.parse(url).host}');
  streams.dispose();

  print('ALL OK');
}
