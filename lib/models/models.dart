/// Core data models for Maherai Music.
///
/// Everything is JSON-map serializable so it can be stored directly in Hive
/// boxes without codegen.
library;

class Track {
  final String id; // YouTube videoId
  final String title;
  final String artist;
  final String? artistId; // channel browseId (UC...)
  final String? album;
  final String? albumId; // album browseId (MPRE...)
  final String thumbUrl;
  final Duration? duration;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId,
    this.album,
    this.albumId,
    this.thumbUrl = '',
    this.duration,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artistId': artistId,
        'album': album,
        'albumId': albumId,
        'thumbUrl': thumbUrl,
        'durationMs': duration?.inMilliseconds,
      };

  factory Track.fromJson(Map<dynamic, dynamic> j) => Track(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        artistId: j['artistId'] as String?,
        album: j['album'] as String?,
        albumId: j['albumId'] as String?,
        thumbUrl: (j['thumbUrl'] ?? '') as String,
        duration: j['durationMs'] == null
            ? null
            : Duration(milliseconds: j['durationMs'] as int),
      );

  Track copyWith({String? thumbUrl, Duration? duration}) => Track(
        id: id,
        title: title,
        artist: artist,
        artistId: artistId,
        album: album,
        albumId: albumId,
        thumbUrl: thumbUrl ?? this.thumbUrl,
        duration: duration ?? this.duration,
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum YtKind { song, video, album, playlist, artist }

/// A browsable YouTube Music entity (search result / home shelf card).
class YtItem {
  final YtKind kind;

  /// videoId for song/video, playlistId for playlist,
  /// browseId for album (MPRE...) / artist (UC...).
  final String id;
  final String title;
  final String subtitle;
  final String thumbUrl;

  /// Present when [kind] is song or video so it can be played directly.
  final Track? track;

  const YtItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.thumbUrl = '',
    this.track,
  });
}

/// A horizontal shelf on the home screen.
class HomeSection {
  final String title;
  final List<YtItem> items;
  const HomeSection({required this.title, required this.items});
}

/// Search results grouped by category (unfiltered "top results" search).
class SearchResults {
  final List<YtItem> songs;
  final List<YtItem> videos;
  final List<YtItem> albums;
  final List<YtItem> artists;
  final List<YtItem> playlists;

  const SearchResults({
    this.songs = const [],
    this.videos = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      songs.isEmpty &&
      videos.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty;
}

/// A remote playlist/album page (header + tracks).
class RemotePlaylist {
  final String title;
  final String subtitle;
  final String thumbUrl;
  final List<Track> tracks;
  const RemotePlaylist({
    required this.title,
    this.subtitle = '',
    this.thumbUrl = '',
    required this.tracks,
  });
}

/// An artist page: top songs plus shelves of albums/singles.
class ArtistPage {
  final String name;
  final String thumbUrl;
  final String description;
  final List<Track> topSongs;
  final List<HomeSection> shelves;
  const ArtistPage({
    required this.name,
    this.thumbUrl = '',
    this.description = '',
    this.topSongs = const [],
    this.shelves = const [],
  });
}

/// One line of (possibly time-synced) lyrics.
class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

class Lyrics {
  final List<LyricLine> lines;
  final bool synced;
  final String source;
  const Lyrics({required this.lines, required this.synced, this.source = ''});
}
