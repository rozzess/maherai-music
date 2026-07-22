import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Lightweight InnerTube (YouTube Music private API) client.
///
/// Talks to music.youtube.com/youtubei/v1 with the WEB_REMIX client context —
/// same API the YT Music web app uses. All parsing is defensive: a malformed
/// item is skipped, never thrown.
class InnerTube {
  static const _base = 'https://music.youtube.com/youtubei/v1';
  static const _clientVersion = '1.20250310.01.00';

  // Search filter params (from ytmusicapi): 'EgWKAQ' + kind + suffix.
  static const searchParams = {
    YtKind.song: 'EgWKAQIIAWoMEA4QChADEAQQCRAF',
    YtKind.video: 'EgWKAQIQAWoMEA4QChADEAQQCRAF',
    YtKind.album: 'EgWKAQIYAWoMEA4QChADEAQQCRAF',
    YtKind.artist: 'EgWKAQIgAWoMEA4QChADEAQQCRAF',
    YtKind.playlist: 'EgWKAQIoAWoMEA4QChADEAQQCRAF',
  };

  final http.Client _http = http.Client();

  Future<Map<String, dynamic>> _post(
      String endpoint, Map<String, dynamic> body) async {
    final res = await _http
        .post(
          Uri.parse('$_base/$endpoint?prettyPrint=false'),
          headers: {
            'Content-Type': 'application/json',
            'Origin': 'https://music.youtube.com',
            'Referer': 'https://music.youtube.com/',
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/124.0.0.0 Safari/537.36',
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB_REMIX',
                'clientVersion': _clientVersion,
                'hl': 'en',
                'gl': 'US',
              },
            },
            ...body,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('InnerTube $endpoint failed: HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------- helpers

  static dynamic _nav(dynamic node, List<Object> path) {
    dynamic cur = node;
    for (final key in path) {
      if (cur == null) return null;
      if (key is String && cur is Map) {
        cur = cur[key];
      } else if (key is int && cur is List && key >= 0 && key < cur.length) {
        cur = cur[key];
      } else {
        return null;
      }
    }
    return cur;
  }

  static String _runsText(dynamic runs) {
    if (runs is! List) return '';
    return runs.map((r) => (r is Map ? r['text'] : null) ?? '').join();
  }

  /// Picks the largest thumbnail and upgrades googleusercontent sizes so the
  /// lock screen / full player gets crisp art.
  static String _thumb(dynamic thumbnails) {
    if (thumbnails is! List || thumbnails.isEmpty) return '';
    final url = (_nav(thumbnails.last, ['url']) ?? '') as String;
    return upscaleThumb(url);
  }

  static String upscaleThumb(String url) {
    final m = RegExp(r'=w\d+-h\d+').firstMatch(url);
    if (m != null) {
      return url.replaceRange(m.start, m.end, '=w544-h544');
    }
    return url;
  }

  static Duration? _parseDuration(String? text) {
    if (text == null || text.isEmpty) return null;
    final parts = text.split(':').map((p) => int.tryParse(p.trim())).toList();
    if (parts.any((p) => p == null)) return null;
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + p!;
    }
    return Duration(seconds: seconds);
  }

  // ------------------------------------------------------------ item parsing

  /// Type labels YT Music puts as the first run of the metadata column
  /// ("Song • Artist • 3:45").
  static const _typeLabels = {
    'Song': YtKind.song,
    'Video': YtKind.video,
    'Album': YtKind.album,
    'Single': YtKind.album,
    'EP': YtKind.album,
    'Artist': YtKind.artist,
    'Playlist': YtKind.playlist,
  };

  /// Parses a musicResponsiveListItemRenderer (rows in search results,
  /// playlists, albums, artist top-songs).
  static YtItem? _parseListItem(
    Map item, {
    YtKind? hint,
    String? fallbackThumb,
    String fallbackArtist = '',
  }) {
    final thumb = _thumb(_nav(item, [
          'thumbnail',
          'musicThumbnailRenderer',
          'thumbnail',
          'thumbnails',
        ])) ;
    final thumbUrl = thumb.isNotEmpty ? thumb : (fallbackThumb ?? '');

    final flex = _nav(item, ['flexColumns']) as List?;
    if (flex == null || flex.isEmpty) return null;
    final titleRuns = _nav(flex[0], [
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
    ]) as List?;
    if (titleRuns == null || titleRuns.isEmpty) return null;
    final title = (titleRuns[0]['text'] ?? '') as String;

    // videoId can live on the title run or in playlistItemData.
    String? videoId = _nav(titleRuns[0],
            ['navigationEndpoint', 'watchEndpoint', 'videoId']) as String? ??
        _nav(item, ['playlistItemData', 'videoId']) as String?;

    // Whole-row navigation → albums / artists / playlists.
    final rowBrowseId =
        _nav(item, ['navigationEndpoint', 'browseEndpoint', 'browseId'])
            as String?;
    final rowPageType = _nav(item, [
      'navigationEndpoint',
      'browseEndpoint',
      'browseEndpointContextSupportedConfigs',
      'browseEndpointContextMusicConfig',
      'pageType',
    ]) as String?;

    // Second flex column: type label / artist / album / duration metadata.
    String artist = '';
    String? artistId;
    String? album;
    String? albumId;
    Duration? duration;
    YtKind? labelKind;
    if (flex.length > 1) {
      // Merge every metadata column (some layouts split artist/album/plays
      // across flexColumns[1..n]).
      var metaRuns = <dynamic>[];
      for (var ci = 1; ci < flex.length; ci++) {
        final r = _nav(flex[ci], [
          'musicResponsiveListItemFlexColumnRenderer',
          'text',
          'runs',
        ]) as List?;
        if (r != null) metaRuns.addAll(r);
      }
      if (metaRuns.isNotEmpty) {
        final firstText =
            ((metaRuns.first is Map ? metaRuns.first['text'] : null) ?? '')
                as String;
        labelKind = _typeLabels[firstText.trim()];
        if (labelKind != null) {
          // Drop the label (and its trailing separator) from metadata parsing.
          metaRuns = metaRuns.skip(1).toList();
        }
        for (final run in metaRuns) {
          if (run is! Map) continue;
          final text = (run['text'] ?? '') as String;
          final browseId =
              _nav(run, ['navigationEndpoint', 'browseEndpoint', 'browseId'])
                  as String?;
          if (browseId != null && browseId.startsWith('UC')) {
            artist = artist.isEmpty ? text : '$artist, $text';
            artistId ??= browseId;
          } else if (browseId != null && browseId.startsWith('MPRE')) {
            album = text;
            albumId = browseId;
          } else if (RegExp(r'^\d+:\d').hasMatch(text)) {
            duration = _parseDuration(text);
          } else if (artist.isEmpty &&
              text.trim() != '•' &&
              !text.contains('views') &&
              !text.contains('plays')) {
            // Unlinked artist name (common in video results).
            if (text.trim().isNotEmpty && text.trim() != '&') {
              artist = text;
            }
          }
        }
      }
    }
    // Duration sometimes sits in fixedColumns.
    duration ??= _parseDuration(_runsText(_nav(item, [
      'fixedColumns',
      0,
      'musicResponsiveListItemFixedColumnRenderer',
      'text',
      'runs',
    ])));

    var kind = hint ?? labelKind;
    if (kind == null) {
      if (videoId != null) {
        kind = YtKind.song;
      } else if (rowPageType == 'MUSIC_PAGE_TYPE_ALBUM') {
        kind = YtKind.album;
      } else if (rowPageType == 'MUSIC_PAGE_TYPE_ARTIST' ||
          rowPageType == 'MUSIC_PAGE_TYPE_USER_CHANNEL') {
        kind = YtKind.artist;
      } else if (rowPageType == 'MUSIC_PAGE_TYPE_PLAYLIST') {
        kind = YtKind.playlist;
      } else {
        return null;
      }
    }

    if (artist.isEmpty) artist = fallbackArtist;

    if (kind == YtKind.song || kind == YtKind.video) {
      if (videoId == null) return null;
      final track = Track(
        id: videoId,
        title: title,
        artist: artist,
        artistId: artistId,
        album: album,
        albumId: albumId,
        thumbUrl: thumbUrl,
        duration: duration,
      );
      return YtItem(
        kind: kind,
        id: videoId,
        title: title,
        subtitle: artist,
        thumbUrl: thumbUrl,
        track: track,
      );
    }

    var id = rowBrowseId;
    if (id == null) return null;
    if (kind == YtKind.playlist && id.startsWith('VL')) {
      id = id.substring(2);
    }
    return YtItem(
      kind: kind,
      id: id,
      title: title,
      subtitle: artist,
      thumbUrl: thumbUrl,
    );
  }

  /// Parses a musicCardShelfRenderer (the "Top result" card in search).
  static YtItem? _parseCardShelf(Map card) {
    final title = _runsText(_nav(card, ['title', 'runs']));
    if (title.isEmpty) return null;
    final thumb = _thumb(_nav(card,
        ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']));
    final subtitleRuns = _nav(card, ['subtitle', 'runs']) as List? ?? [];
    final subtitleTexts = subtitleRuns
        .map((r) => ((r is Map ? r['text'] : null) ?? '') as String)
        .toList();
    final labelKind = subtitleTexts.isEmpty
        ? null
        : _typeLabels[subtitleTexts.first.trim()];
    final subtitle = subtitleTexts
        .skip(labelKind == null ? 0 : 1)
        .join()
        .replaceAll(RegExp(r'^\s*•\s*'), '');

    // The card subtitle carries the duration ("Song • 4:19").
    Duration? duration;
    for (final text in subtitleTexts) {
      if (RegExp(r'^\d+:\d\d').hasMatch(text.trim())) {
        duration = _parseDuration(text.trim());
        break;
      }
    }

    final nav = _nav(card, ['title', 'runs', 0, 'navigationEndpoint']);
    final videoId = _nav(nav, ['watchEndpoint', 'videoId']) as String?;
    var browseId = _nav(nav, ['browseEndpoint', 'browseId']) as String?;
    final pageType = _nav(nav, [
      'browseEndpoint',
      'browseEndpointContextSupportedConfigs',
      'browseEndpointContextMusicConfig',
      'pageType',
    ]) as String?;

    if (videoId != null) {
      final kind = labelKind == YtKind.video ? YtKind.video : YtKind.song;
      return YtItem(
        kind: kind,
        id: videoId,
        title: title,
        subtitle: subtitle,
        thumbUrl: thumb,
        track: Track(
          id: videoId,
          title: title,
          artist: subtitle.split('•').first.trim(),
          thumbUrl: thumb,
          duration: duration,
        ),
      );
    }
    if (browseId == null) return null;
    YtKind kind;
    if (pageType == 'MUSIC_PAGE_TYPE_ARTIST' || browseId.startsWith('UC')) {
      kind = YtKind.artist;
    } else if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' ||
        browseId.startsWith('MPRE')) {
      kind = YtKind.album;
    } else {
      kind = YtKind.playlist;
      if (browseId.startsWith('VL')) browseId = browseId.substring(2);
    }
    return YtItem(
      kind: kind,
      id: browseId,
      title: title,
      subtitle: subtitle,
      thumbUrl: thumb,
    );
  }

  /// Parses a musicTwoRowItemRenderer (cards in home / artist carousels).
  static YtItem? _parseTwoRowItem(Map item) {
    final title = _runsText(_nav(item, ['title', 'runs']));
    final subtitle = _runsText(_nav(item, ['subtitle', 'runs']));
    final thumb = _thumb(_nav(item, [
      'thumbnailRenderer',
      'musicThumbnailRenderer',
      'thumbnail',
      'thumbnails',
    ]));
    if (title.isEmpty) return null;

    final videoId =
        _nav(item, ['navigationEndpoint', 'watchEndpoint', 'videoId'])
            as String?;
    if (videoId != null) {
      return YtItem(
        kind: YtKind.song,
        id: videoId,
        title: title,
        subtitle: subtitle,
        thumbUrl: thumb,
        track: Track(
          id: videoId,
          title: title,
          artist: subtitle.split('•').first.trim(),
          thumbUrl: thumb,
        ),
      );
    }

    var browseId =
        _nav(item, ['navigationEndpoint', 'browseEndpoint', 'browseId'])
            as String?;
    final pageType = _nav(item, [
      'navigationEndpoint',
      'browseEndpoint',
      'browseEndpointContextSupportedConfigs',
      'browseEndpointContextMusicConfig',
      'pageType',
    ]) as String?;
    if (browseId == null) return null;

    YtKind kind;
    if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' || browseId.startsWith('MPRE')) {
      kind = YtKind.album;
    } else if (pageType == 'MUSIC_PAGE_TYPE_ARTIST' ||
        browseId.startsWith('UC')) {
      kind = YtKind.artist;
    } else {
      kind = YtKind.playlist;
      if (browseId.startsWith('VL')) browseId = browseId.substring(2);
    }
    return YtItem(
      kind: kind,
      id: browseId,
      title: title,
      subtitle: subtitle,
      thumbUrl: thumb,
    );
  }

  static List<YtItem> _parseShelfContents(dynamic contents, {YtKind? hint}) {
    final items = <YtItem>[];
    if (contents is! List) return items;
    for (final c in contents) {
      if (c is! Map) continue;
      YtItem? parsed;
      if (c['musicResponsiveListItemRenderer'] != null) {
        parsed =
            _parseListItem(c['musicResponsiveListItemRenderer'] as Map, hint: hint);
      } else if (c['musicTwoRowItemRenderer'] != null) {
        parsed = _parseTwoRowItem(c['musicTwoRowItemRenderer'] as Map);
      }
      if (parsed != null) items.add(parsed);
    }
    return items;
  }

  // ------------------------------------------------------------------- home

  /// Home feed shelves ("Quick picks", charts, moods...).
  Future<List<HomeSection>> home() async {
    try {
      final res = await _post('browse', {'browseId': 'FEmusic_home'});
      final sections = _parseSectionList(_nav(res, [
        'contents',
        'singleColumnBrowseResultsRenderer',
        'tabs',
        0,
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
      ]));
      if (sections.isNotEmpty) return sections;
    } catch (_) {
      // fall through to search-based fallback
    }
    return _fallbackHome();
  }

  List<HomeSection> _parseSectionList(dynamic contents) {
    final sections = <HomeSection>[];
    if (contents is! List) return sections;
    for (final section in contents) {
      final carousel = _nav(section, ['musicCarouselShelfRenderer']);
      if (carousel == null) continue;
      final title = _runsText(_nav(carousel, [
        'header',
        'musicCarouselShelfBasicHeaderRenderer',
        'title',
        'runs',
      ]));
      final items = _parseShelfContents(_nav(carousel, ['contents']));
      if (items.isNotEmpty) {
        sections.add(HomeSection(title: title, items: items));
      }
    }
    return sections;
  }

  /// If the home feed can't be parsed (layout change), build shelves from
  /// searches so the screen is never empty.
  Future<List<HomeSection>> _fallbackHome() async {
    const seeds = [
      ('Trending now', 'top hits 2026'),
      ('Feel-good pop', 'feel good pop hits'),
      ('Hip-hop heat', 'hip hop hits'),
      ('Chill & lo-fi', 'lofi chill beats'),
      ('Throwback classics', 'throwback classic hits'),
    ];
    final sections = <HomeSection>[];
    for (final (title, query) in seeds) {
      try {
        final items = await searchFiltered(query, YtKind.song);
        if (items.isNotEmpty) {
          sections.add(HomeSection(title: title, items: items.take(10).toList()));
        }
      } catch (_) {}
    }
    return sections;
  }

  // ----------------------------------------------------------------- search

  Future<List<String>> searchSuggestions(String input) async {
    if (input.trim().isEmpty) return [];
    final res = await _post('music/get_search_suggestions', {'input': input});
    final out = <String>[];
    final contents = _nav(res, ['contents']) as List?;
    if (contents == null) return out;
    for (final section in contents) {
      final items =
          _nav(section, ['searchSuggestionsSectionRenderer', 'contents'])
              as List?;
      if (items == null) continue;
      for (final item in items) {
        final text = _runsText(
            _nav(item, ['searchSuggestionRenderer', 'suggestion', 'runs']));
        if (text.isNotEmpty) out.add(text);
      }
    }
    return out;
  }

  /// Unfiltered search — returns top results grouped by category.
  Future<SearchResults> search(String query) async {
    final res = await _post('search', {'query': query});
    final contents = _nav(res, [
          'contents',
          'tabbedSearchResultsRenderer',
          'tabs',
          0,
          'tabRenderer',
          'content',
          'sectionListRenderer',
          'contents',
        ]) as List? ??
        [];

    final songs = <YtItem>[];
    final videos = <YtItem>[];
    final albums = <YtItem>[];
    final artists = <YtItem>[];
    final playlists = <YtItem>[];
    final seen = <String>{};

    void add(YtItem? item) {
      if (item == null || !seen.add('${item.kind.name}:${item.id}')) return;
      switch (item.kind) {
        case YtKind.song:
          songs.add(item);
        case YtKind.video:
          videos.add(item);
        case YtKind.album:
          albums.add(item);
        case YtKind.artist:
          artists.add(item);
        case YtKind.playlist:
          playlists.add(item);
      }
    }

    for (final section in contents) {
      // Current layout: one itemSectionRenderer per result, kind encoded in
      // the row's type label ("Song • ...").
      final itemSection = _nav(section, ['itemSectionRenderer', 'contents']);
      if (itemSection is List) {
        for (final c in itemSection) {
          final r = _nav(c, ['musicResponsiveListItemRenderer']);
          if (r is Map) add(_parseListItem(r));
        }
        continue;
      }
      // Top result card.
      final card = _nav(section, ['musicCardShelfRenderer']);
      if (card is Map) {
        final cardItem = _parseCardShelf(card);
        add(cardItem);
        final extra = _nav(card, ['contents']);
        if (extra is List) {
          for (final c in extra) {
            final r = _nav(c, ['musicResponsiveListItemRenderer']);
            // Songs nested in the card omit the artist — it's the card entity.
            if (r is Map) {
              add(_parseListItem(r, fallbackArtist: cardItem?.title ?? ''));
            }
          }
        }
        continue;
      }
      // Legacy layout: titled musicShelfRenderer per category.
      final shelf = _nav(section, ['musicShelfRenderer']);
      if (shelf == null) continue;
      final title = _runsText(_nav(shelf, ['title', 'runs'])).toLowerCase();
      YtKind? hint;
      if (title.contains('song')) {
        hint = YtKind.song;
      } else if (title.contains('video')) {
        hint = YtKind.video;
      } else if (title.contains('album') || title.contains('single')) {
        hint = YtKind.album;
      } else if (title.contains('artist')) {
        hint = YtKind.artist;
      } else if (title.contains('playlist')) {
        hint = YtKind.playlist;
      }
      for (final item
          in _parseShelfContents(_nav(shelf, ['contents']), hint: hint)) {
        add(item);
      }
    }
    return SearchResults(
      songs: songs,
      videos: videos,
      albums: albums,
      artists: artists,
      playlists: playlists,
    );
  }

  /// Filtered search (more results of one kind).
  Future<List<YtItem>> searchFiltered(String query, YtKind kind) async {
    final res = await _post('search', {
      'query': query,
      'params': searchParams[kind],
    });
    final contents = _nav(res, [
          'contents',
          'tabbedSearchResultsRenderer',
          'tabs',
          0,
          'tabRenderer',
          'content',
          'sectionListRenderer',
          'contents',
        ]) as List? ??
        [];
    final items = <YtItem>[];
    for (final section in contents) {
      final shelfContents = _nav(section, ['musicShelfRenderer', 'contents']) ??
          _nav(section, ['itemSectionRenderer', 'contents']);
      if (shelfContents == null) continue;
      items.addAll(_parseShelfContents(shelfContents, hint: kind));
    }
    return items;
  }

  // ------------------------------------------------------------ radio/queue

  /// Builds a radio queue seeded from [videoId] (the "next" endpoint).
  /// Returns the upcoming tracks and, if available, the lyrics browseId.
  Future<(List<Track>, String?)> radio(String videoId,
      {String? playlistId}) async {
    final res = await _post('next', {
      'videoId': videoId,
      'playlistId': playlistId ?? 'RDAMVM$videoId',
      'params': 'wAEB',
      'enablePersistentPlaylistPanel': true,
      'isAudioOnly': true,
    });
    final tabs = _nav(res, [
      'contents',
      'singleColumnMusicWatchNextResultsRenderer',
      'tabbedRenderer',
      'watchNextTabbedResultsRenderer',
      'tabs',
    ]) as List?;

    String? lyricsBrowseId;
    List? panelContents;
    if (tabs != null) {
      for (final tab in tabs) {
        final tabRenderer = _nav(tab, ['tabRenderer']);
        if (tabRenderer == null) continue;
        final endpointBrowseId =
            _nav(tabRenderer, ['endpoint', 'browseEndpoint', 'browseId'])
                as String?;
        if (endpointBrowseId != null && endpointBrowseId.startsWith('MPLYt')) {
          lyricsBrowseId = endpointBrowseId;
        }
        panelContents ??= _nav(tabRenderer, [
          'content',
          'musicQueueRenderer',
          'content',
          'playlistPanelRenderer',
          'contents',
        ]) as List?;
      }
    }

    final tracks = <Track>[];
    if (panelContents != null) {
      for (final c in panelContents) {
        final r = _nav(c, ['playlistPanelVideoRenderer']) ??
            _nav(c, [
              'playlistPanelVideoWrapperRenderer',
              'primaryRenderer',
              'playlistPanelVideoRenderer',
            ]);
        if (r == null) continue;
        final id = r['videoId'] as String?;
        if (id == null) continue;
        final byline = _nav(r, ['longBylineText', 'runs']) as List?;
        String artist = '';
        String? artistId;
        String? album;
        String? albumId;
        if (byline != null) {
          for (final run in byline) {
            if (run is! Map) continue;
            final browseId =
                _nav(run, ['navigationEndpoint', 'browseEndpoint', 'browseId'])
                    as String?;
            final text = (run['text'] ?? '') as String;
            if (browseId != null && browseId.startsWith('UC')) {
              artist = artist.isEmpty ? text : '$artist, $text';
              artistId ??= browseId;
            } else if (browseId != null && browseId.startsWith('MPRE')) {
              album = text;
              albumId = browseId;
            }
          }
          if (artist.isEmpty && byline.isNotEmpty) {
            artist = (byline[0]['text'] ?? '') as String;
          }
        }
        tracks.add(Track(
          id: id,
          title: _runsText(_nav(r, ['title', 'runs'])),
          artist: artist,
          artistId: artistId,
          album: album,
          albumId: albumId,
          thumbUrl: _thumb(_nav(r, ['thumbnail', 'thumbnails'])),
          duration: _parseDuration(_runsText(_nav(r, ['lengthText', 'runs']))),
        ));
      }
    }
    return (tracks, lyricsBrowseId);
  }

  // -------------------------------------------------------- playlist/album

  /// Loads a remote playlist (playlistId) or album (MPRE browseId).
  Future<RemotePlaylist> playlist(String id) async {
    final browseId = id.startsWith('MPRE') || id.startsWith('VL') ? id : 'VL$id';
    final res = await _post('browse', {'browseId': browseId});

    // Header (old singleColumn layout and new twoColumn layout).
    String title = '';
    String subtitle = '';
    String thumb = '';
    for (final headerPath in [
      ['header', 'musicDetailHeaderRenderer'],
      ['header', 'musicResponsiveHeaderRenderer'],
      [
        'contents',
        'twoColumnBrowseResultsRenderer',
        'tabs',
        0,
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
        0,
        'musicResponsiveHeaderRenderer',
      ],
    ]) {
      final header = _nav(res, headerPath);
      if (header == null) continue;
      title = _runsText(_nav(header, ['title', 'runs']));
      subtitle = [
        _runsText(_nav(header, ['straplineTextOne', 'runs'])),
        _runsText(_nav(header, ['subtitle', 'runs'])),
      ].where((s) => s.isNotEmpty).join(' • ');
      thumb = _thumb(_nav(header, [
            'thumbnail',
            'croppedSquareThumbnailRenderer',
            'thumbnail',
            'thumbnails',
          ])) ;
      if (thumb.isEmpty) {
        thumb = _thumb(_nav(header,
            ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']));
      }
      if (title.isNotEmpty) break;
    }

    // Track shelf (both layouts, playlists and albums).
    List? shelfContents;
    for (final path in [
      [
        'contents',
        'twoColumnBrowseResultsRenderer',
        'secondaryContents',
        'sectionListRenderer',
        'contents',
      ],
      [
        'contents',
        'singleColumnBrowseResultsRenderer',
        'tabs',
        0,
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
      ],
    ]) {
      final sections = _nav(res, path) as List?;
      if (sections == null) continue;
      for (final section in sections) {
        shelfContents = _nav(section, ['musicPlaylistShelfRenderer', 'contents'])
                as List? ??
            _nav(section, ['musicShelfRenderer', 'contents']) as List?;
        if (shelfContents != null) break;
      }
      if (shelfContents != null) break;
    }

    final tracks = <Track>[];
    if (shelfContents != null) {
      for (final c in shelfContents) {
        final r = _nav(c, ['musicResponsiveListItemRenderer']);
        if (r is! Map) continue;
        final item =
            _parseListItem(r, hint: YtKind.song, fallbackThumb: thumb);
        if (item?.track != null) {
          var t = item!.track!;
          // Album rows have no per-track artist — inherit the header artist.
          if (t.artist.isEmpty && subtitle.isNotEmpty) {
            t = Track(
              id: t.id,
              title: t.title,
              artist: subtitle.split('•').first.trim(),
              thumbUrl: t.thumbUrl,
              duration: t.duration,
            );
          }
          tracks.add(t);
        }
      }
    }
    return RemotePlaylist(
        title: title, subtitle: subtitle, thumbUrl: thumb, tracks: tracks);
  }

  // ----------------------------------------------------------------- artist

  Future<ArtistPage> artist(String browseId) async {
    final res = await _post('browse', {'browseId': browseId});
    String name = '';
    String thumb = '';
    String description = '';
    for (final headerKey in [
      'musicImmersiveHeaderRenderer',
      'musicVisualHeaderRenderer',
    ]) {
      final header = _nav(res, ['header', headerKey]);
      if (header == null) continue;
      name = _runsText(_nav(header, ['title', 'runs']));
      description = _runsText(_nav(header, ['description', 'runs']));
      thumb = _thumb(_nav(header,
          ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']));
      if (name.isNotEmpty) break;
    }

    final sections = _nav(res, [
          'contents',
          'singleColumnBrowseResultsRenderer',
          'tabs',
          0,
          'tabRenderer',
          'content',
          'sectionListRenderer',
          'contents',
        ]) as List? ??
        [];

    final topSongs = <Track>[];
    final shelves = <HomeSection>[];
    for (final section in sections) {
      final songShelf = _nav(section, ['musicShelfRenderer']);
      if (songShelf != null && topSongs.isEmpty) {
        for (final item
            in _parseShelfContents(_nav(songShelf, ['contents']), hint: YtKind.song)) {
          if (item.track != null) topSongs.add(item.track!);
        }
        continue;
      }
      final carousel = _nav(section, ['musicCarouselShelfRenderer']);
      if (carousel != null) {
        final title = _runsText(_nav(carousel, [
          'header',
          'musicCarouselShelfBasicHeaderRenderer',
          'title',
          'runs',
        ]));
        final items = _parseShelfContents(_nav(carousel, ['contents']));
        if (items.isNotEmpty) {
          shelves.add(HomeSection(title: title, items: items));
        }
      }
    }
    return ArtistPage(
      name: name,
      thumbUrl: thumb,
      description: description,
      topSongs: topSongs,
      shelves: shelves,
    );
  }

  // ----------------------------------------------------------------- lyrics

  /// Plain (unsynced) lyrics from YouTube Music, given the browseId that
  /// [radio] discovered.
  Future<String?> lyricsPlain(String lyricsBrowseId) async {
    final res = await _post('browse', {'browseId': lyricsBrowseId});
    final text = _runsText(_nav(res, [
      'contents',
      'sectionListRenderer',
      'contents',
      0,
      'musicDescriptionShelfRenderer',
      'description',
      'runs',
    ]));
    return text.isEmpty ? null : text;
  }
}
