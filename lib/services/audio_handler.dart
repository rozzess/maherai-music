import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import 'download_service.dart';
import 'innertube.dart';
import 'library_service.dart';
import 'stream_service.dart';

/// Central playback engine. Extends audio_service's BaseAudioHandler so the
/// OS (iOS lock screen / control center, Android notification) gets media
/// info and remote controls; wraps a single just_audio player.
class MaheraiAudioHandler extends BaseAudioHandler with SeekHandler {
  final StreamService streams;
  final InnerTube innertube;
  final DownloadService downloads;
  final LibraryService library;

  final AudioPlayer player = AudioPlayer();

  // UI-observable state.
  final ValueNotifier<List<Track>> queueTracks = ValueNotifier([]);
  final ValueNotifier<int> queueIndex = ValueNotifier(-1);
  final ValueNotifier<Track?> current = ValueNotifier(null);
  final ValueNotifier<bool> shuffleOn = ValueNotifier(false);
  final ValueNotifier<AudioServiceRepeatMode> repeat =
      ValueNotifier(AudioServiceRepeatMode.none);
  final ValueNotifier<bool> autoplayRadio = ValueNotifier(true);
  final ValueNotifier<bool> loading = ValueNotifier(false);

  /// Lyrics browseId for the current track, discovered via the next endpoint.
  String? lyricsBrowseIdForCurrent;

  bool _isRadioQueue = false;
  bool _advancing = false;
  int _consecutiveErrors = 0;
  int _playRequestSeq = 0;
  List<Track>? _unshuffled;

  MaheraiAudioHandler({
    required this.streams,
    required this.innertube,
    required this.downloads,
    required this.library,
  }) {
    player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object e, StackTrace st) => _onPlayerError(),
    );
    player.playingStream.listen((_) => _broadcastState());
    player.durationStream.listen((d) {
      final item = mediaItem.value;
      if (d != null && item != null && item.duration != d) {
        mediaItem.add(item.copyWith(duration: d));
      }
    });
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_advancing) {
        _onTrackCompleted();
      }
    });
  }

  // ------------------------------------------------------------ public API

  /// Replaces the queue and starts playing [startIndex].
  /// With [radio] true the queue keeps growing with related songs.
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool radio = false,
  }) async {
    if (tracks.isEmpty) return;
    _isRadioQueue = radio;
    _unshuffled = null;
    shuffleOn.value = false;
    queueTracks.value = List.of(tracks);
    queueIndex.value = startIndex.clamp(0, tracks.length - 1);
    _syncQueueMediaItems();
    await _playCurrent();
  }

  /// Plays one song and builds a radio around it in the background.
  Future<void> playSong(Track track) async {
    await playQueue([track], radio: true);
    _maybeExtendRadio();
  }

  Future<void> playNextInQueue(Track track) async {
    final q = List.of(queueTracks.value);
    if (q.isEmpty) {
      await playSong(track);
      return;
    }
    q.removeWhere((t) => t.id == track.id && q.indexOf(t) != queueIndex.value);
    final insertAt = (queueIndex.value + 1).clamp(0, q.length);
    q.insert(insertAt, track);
    queueTracks.value = q;
    _syncQueueMediaItems();
  }

  Future<void> addToQueue(Track track) async {
    final q = List.of(queueTracks.value);
    if (q.isEmpty) {
      await playSong(track);
      return;
    }
    if (q.any((t) => t.id == track.id)) return;
    q.add(track);
    queueTracks.value = q;
    _syncQueueMediaItems();
  }

  Future<void> removeFromQueue(int index) async {
    final q = List.of(queueTracks.value);
    if (index < 0 || index >= q.length || index == queueIndex.value) return;
    q.removeAt(index);
    if (index < queueIndex.value) queueIndex.value -= 1;
    queueTracks.value = q;
    _syncQueueMediaItems();
  }

  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    final q = List.of(queueTracks.value);
    if (oldIndex < 0 || oldIndex >= q.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = q.removeAt(oldIndex);
    newIndex = newIndex.clamp(0, q.length);
    q.insert(newIndex, item);
    final cur = queueIndex.value;
    if (oldIndex == cur) {
      queueIndex.value = newIndex;
    } else {
      if (oldIndex < cur) queueIndex.value -= 1;
      if (newIndex <= queueIndex.value) queueIndex.value += 1;
    }
    queueTracks.value = q;
    _syncQueueMediaItems();
  }

  void toggleShuffle() {
    final q = List.of(queueTracks.value);
    if (q.isEmpty) return;
    if (!shuffleOn.value) {
      _unshuffled = List.of(q);
      final cur = q.removeAt(queueIndex.value);
      q.shuffle(Random());
      q.insert(0, cur);
      queueTracks.value = q;
      queueIndex.value = 0;
      shuffleOn.value = true;
    } else {
      final restored = _unshuffled;
      if (restored != null) {
        final curId = current.value?.id;
        final idx = restored.indexWhere((t) => t.id == curId);
        queueTracks.value = restored;
        queueIndex.value = idx >= 0 ? idx : 0;
      }
      _unshuffled = null;
      shuffleOn.value = false;
    }
    _syncQueueMediaItems();
  }

  void cycleRepeat() {
    repeat.value = switch (repeat.value) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    };
  }

  // -------------------------------------------------- audio_service overrides

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    final q = queueTracks.value;
    if (q.isEmpty) return;
    if (queueIndex.value < q.length - 1) {
      queueIndex.value += 1;
      await _playCurrent();
    } else if (repeat.value == AudioServiceRepeatMode.all) {
      queueIndex.value = 0;
      await _playCurrent();
    } else if (_isRadioQueue && autoplayRadio.value) {
      await _extendRadio();
      if (queueIndex.value < queueTracks.value.length - 1) {
        queueIndex.value += 1;
        await _playCurrent();
      }
    }
    _maybeExtendRadio();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3) ||
        queueIndex.value <= 0) {
      await player.seek(Duration.zero);
      return;
    }
    queueIndex.value -= 1;
    await _playCurrent();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queueTracks.value.length) return;
    queueIndex.value = index;
    await _playCurrent();
    _maybeExtendRadio();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    repeat.value = repeatMode;
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final wantOn = shuffleMode != AudioServiceShuffleMode.none;
    if (wantOn != shuffleOn.value) toggleShuffle();
  }

  // ----------------------------------------------------------------- internals

  Future<void> _playCurrent() async {
    final q = queueTracks.value;
    final idx = queueIndex.value;
    if (idx < 0 || idx >= q.length) return;
    final track = q[idx];
    final seq = ++_playRequestSeq;

    _advancing = true;
    loading.value = true;
    current.value = track;
    lyricsBrowseIdForCurrent = null;
    mediaItem.add(_toMediaItem(track));
    _broadcastState();

    try {
      final localPath = downloads.pathFor(track.id);
      final source = localPath != null
          ? AudioSource.file(localPath)
          : AudioSource.uri(Uri.parse(await streams.audioUrl(track.id)));
      if (seq != _playRequestSeq) return; // superseded by a newer request
      await player.setAudioSource(source);
      if (seq != _playRequestSeq) return;
      _advancing = false;
      await player.play();
      _consecutiveErrors = 0;
      library.addRecent(track);
    } catch (_) {
      if (seq != _playRequestSeq) return;
      _advancing = false;
      _onPlayerError();
    } finally {
      if (seq == _playRequestSeq) loading.value = false;
    }
  }

  void _onTrackCompleted() async {
    if (repeat.value == AudioServiceRepeatMode.one) {
      await player.seek(Duration.zero);
      await player.play();
      return;
    }
    await skipToNext();
  }

  void _onPlayerError() {
    _consecutiveErrors += 1;
    if (_consecutiveErrors >= 3) {
      _consecutiveErrors = 0;
      player.stop();
      return;
    }
    // Skip unplayable tracks instead of dying silently.
    skipToNext();
  }

  /// Tops up a radio queue when the listener is near its end.
  void _maybeExtendRadio() {
    final q = queueTracks.value;
    if (!_isRadioQueue ||
        !autoplayRadio.value ||
        q.isEmpty ||
        q.length > 80 ||
        queueIndex.value < q.length - 3) {
      return;
    }
    _extendRadio();
  }

  bool _extending = false;
  Future<void> _extendRadio() async {
    if (_extending) return;
    _extending = true;
    try {
      final q = queueTracks.value;
      if (q.isEmpty) return;
      final seed = q[queueIndex.value.clamp(0, q.length - 1)];
      final (related, lyricsId) = await innertube.radio(seed.id);
      if (current.value?.id == seed.id) lyricsBrowseIdForCurrent = lyricsId;
      final known = q.map((t) => t.id).toSet();
      final fresh = related.where((t) => !known.contains(t.id)).toList();
      if (fresh.isNotEmpty) {
        queueTracks.value = [...queueTracks.value, ...fresh];
        _syncQueueMediaItems();
      }
    } catch (_) {
      // network hiccup — the queue just doesn't grow this time
    } finally {
      _extending = false;
    }
  }

  /// Fetches the YT lyrics browseId for the current track (used as a lyrics
  /// fallback when LRCLIB has nothing).
  Future<String?> lyricsBrowseId() async {
    if (lyricsBrowseIdForCurrent != null) return lyricsBrowseIdForCurrent;
    final track = current.value;
    if (track == null) return null;
    try {
      final (_, lyricsId) = await innertube.radio(track.id);
      if (current.value?.id == track.id) lyricsBrowseIdForCurrent = lyricsId;
      return lyricsId;
    } catch (_) {
      return null;
    }
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        artUri: t.thumbUrl.isEmpty ? null : Uri.tryParse(t.thumbUrl),
      );

  void _syncQueueMediaItems() {
    queue.add(queueTracks.value.map(_toMediaItem).toList());
  }

  void _broadcastState() {
    final playing = player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: queueIndex.value < 0 ? null : queueIndex.value,
      shuffleMode: shuffleOn.value
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      repeatMode: repeat.value,
    ));
  }
}
