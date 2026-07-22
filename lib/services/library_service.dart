import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/models.dart';

/// A user-created local playlist.
class LocalPlaylist {
  final String id;
  final String name;
  final List<Track> tracks;
  const LocalPlaylist({required this.id, required this.name, required this.tracks});

  String get coverUrl => tracks.isEmpty ? '' : tracks.first.thumbUrl;
}

/// Local library: favorites, playlists, recently played, search history.
/// Backed by Hive boxes of plain JSON maps.
class LibraryService extends ChangeNotifier {
  static const favoritesBox = 'favorites';
  static const playlistsBox = 'playlists';
  static const recentsBox = 'recents';
  static const historyBox = 'searchHistory';

  final Box _favorites = Hive.box(favoritesBox);
  final Box _playlists = Hive.box(playlistsBox);
  final Box _recents = Hive.box(recentsBox);
  final Box _history = Hive.box(historyBox);

  // -------------------------------------------------------------- favorites

  bool isFavorite(String id) => _favorites.containsKey(id);

  List<Track> get favorites {
    final entries = _favorites.toMap().entries.toList()
      ..sort((a, b) =>
          ((b.value['ts'] ?? 0) as int).compareTo((a.value['ts'] ?? 0) as int));
    return entries.map((e) => Track.fromJson(e.value as Map)).toList();
  }

  Future<void> toggleFavorite(Track track) async {
    if (_favorites.containsKey(track.id)) {
      await _favorites.delete(track.id);
    } else {
      await _favorites.put(track.id, {
        ...track.toJson(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- playlists

  List<LocalPlaylist> get playlists {
    final entries = _playlists.toMap().entries.toList()
      ..sort((a, b) => ((a.value['createdAt'] ?? 0) as int)
          .compareTo((b.value['createdAt'] ?? 0) as int));
    return entries.map((e) {
      final v = e.value as Map;
      final tracks = ((v['tracks'] ?? []) as List)
          .map((t) => Track.fromJson(t as Map))
          .toList();
      return LocalPlaylist(
        id: e.key as String,
        name: (v['name'] ?? '') as String,
        tracks: tracks,
      );
    }).toList();
  }

  LocalPlaylist? playlistById(String id) {
    final v = _playlists.get(id);
    if (v == null) return null;
    return LocalPlaylist(
      id: id,
      name: (v['name'] ?? '') as String,
      tracks: ((v['tracks'] ?? []) as List)
          .map((t) => Track.fromJson(t as Map))
          .toList(),
    );
  }

  Future<String> createPlaylist(String name) async {
    final id = 'pl_${DateTime.now().millisecondsSinceEpoch}';
    await _playlists.put(id, {
      'name': name,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'tracks': <Map<String, dynamic>>[],
    });
    notifyListeners();
    return id;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final v = _playlists.get(id);
    if (v == null) return;
    await _playlists.put(id, {...v, 'name': name});
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    await _playlists.delete(id);
    notifyListeners();
  }

  /// Adds [track] to playlist [id]; returns false if it was already there.
  Future<bool> addToPlaylist(String id, Track track) async {
    final v = _playlists.get(id);
    if (v == null) return false;
    final tracks = List<Map>.from((v['tracks'] ?? []) as List);
    if (tracks.any((t) => t['id'] == track.id)) return false;
    tracks.add(track.toJson());
    await _playlists.put(id, {...v, 'tracks': tracks});
    notifyListeners();
    return true;
  }

  Future<void> removeFromPlaylist(String id, int index) async {
    final v = _playlists.get(id);
    if (v == null) return;
    final tracks = List<Map>.from((v['tracks'] ?? []) as List);
    if (index < 0 || index >= tracks.length) return;
    tracks.removeAt(index);
    await _playlists.put(id, {...v, 'tracks': tracks});
    notifyListeners();
  }

  Future<void> reorderPlaylist(String id, int oldIndex, int newIndex) async {
    final v = _playlists.get(id);
    if (v == null) return;
    final tracks = List<Map>.from((v['tracks'] ?? []) as List);
    if (oldIndex < 0 || oldIndex >= tracks.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = tracks.removeAt(oldIndex);
    tracks.insert(newIndex.clamp(0, tracks.length), item);
    await _playlists.put(id, {...v, 'tracks': tracks});
    notifyListeners();
  }

  // ---------------------------------------------------------------- recents

  List<Track> get recents {
    final entries = _recents.toMap().entries.toList()
      ..sort((a, b) =>
          ((b.value['ts'] ?? 0) as int).compareTo((a.value['ts'] ?? 0) as int));
    return entries.map((e) => Track.fromJson(e.value as Map)).toList();
  }

  Future<void> addRecent(Track track) async {
    await _recents.put(track.id, {
      ...track.toJson(),
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    if (_recents.length > 50) {
      final entries = _recents.toMap().entries.toList()
        ..sort((a, b) =>
            ((a.value['ts'] ?? 0) as int).compareTo((b.value['ts'] ?? 0) as int));
      for (final e in entries.take(_recents.length - 50)) {
        await _recents.delete(e.key);
      }
    }
    notifyListeners();
  }

  // --------------------------------------------------------- search history

  List<String> get searchHistory {
    final entries = _history.toMap().entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    return entries.map((e) => e.key as String).toList();
  }

  Future<void> addSearch(String query) async {
    await _history.put(query, DateTime.now().millisecondsSinceEpoch);
    if (_history.length > 20) {
      final entries = _history.toMap().entries.toList()
        ..sort((a, b) => (a.value as int).compareTo(b.value as int));
      for (final e in entries.take(_history.length - 20)) {
        await _history.delete(e.key);
      }
    }
    notifyListeners();
  }

  Future<void> removeSearch(String query) async {
    await _history.delete(query);
    notifyListeners();
  }
}
