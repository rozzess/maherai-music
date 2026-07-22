import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'stream_service.dart';

/// Downloads tracks for offline playback and tracks their progress.
///
/// Files live under the app documents dir in MaheraiMusic/; metadata lives in the
/// 'downloads' Hive box (track json + 'path' + 'ts').
class DownloadService extends ChangeNotifier {
  static const boxName = 'downloads';

  final StreamService _streams;
  final Box _box = Hive.box(boxName);

  /// videoId → 0..1 progress for in-flight downloads.
  final Map<String, double> active = {};

  Directory? _dir;

  DownloadService(this._streams);

  Future<Directory> _downloadsDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}MaheraiMusic');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  bool isDownloaded(String id) => _box.containsKey(id);
  bool isDownloading(String id) => active.containsKey(id);

  String? pathFor(String id) {
    final v = _box.get(id);
    if (v == null) return null;
    final path = v['path'] as String?;
    if (path == null || !File(path).existsSync()) return null;
    return path;
  }

  List<Track> get all {
    final entries = _box.toMap().entries.toList()
      ..sort((a, b) =>
          ((b.value['ts'] ?? 0) as int).compareTo((a.value['ts'] ?? 0) as int));
    return entries.map((e) => Track.fromJson(e.value as Map)).toList();
  }

  Future<void> download(Track track) async {
    if (isDownloaded(track.id) || isDownloading(track.id)) return;
    active[track.id] = 0;
    notifyListeners();
    try {
      final info =
          await _streams.downloadInfo(track.id, expected: track.duration);
      final dir = await _downloadsDir();
      final ext = info.container.name; // mp4 → .mp4 (AAC audio), webm → .webm
      final file = File('${dir.path}${Platform.pathSeparator}${track.id}.$ext');
      final sink = file.openWrite();
      final total = info.size.totalBytes;
      var received = 0;
      try {
        await for (final chunk in _streams.openStream(info)) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final p = received / total;
            if ((p - (active[track.id] ?? 0)) > 0.01) {
              active[track.id] = p;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
      await _box.put(track.id, {
        ...track.toJson(),
        'path': file.path,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } finally {
      active.remove(track.id);
      notifyListeners();
    }
  }

  Future<void> delete(String id) async {
    final path = _box.get(id)?['path'] as String?;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    await _box.delete(id);
    notifyListeners();
  }
}
