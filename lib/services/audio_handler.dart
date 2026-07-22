import 'dart:async';
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

  // Tuned for fast time-to-first-audio. NOTE: automaticallyWaitsToMinimize-
  // Stalling must stay ON (default) — disabling it makes AVPlayer's clock
  // keep running when the buffer is empty, i.e. the position advances in
  // total silence ("pretend playback"). A small forward-buffer target gets
  // the fast start without that failure mode.
  final AudioPlayer player = AudioPlayer(
    audioLoadConfiguration: AudioLoadConfiguration(
      darwinLoadControl: DarwinLoadControl(
        preferredForwardBufferDuration: const Duration(seconds: 5),
      ),
      androidLoadControl: AndroidLoadControl(
        bufferForPlaybackDuration: const Duration(milliseconds: 750),
        bufferForPlaybackAfterRebufferDuration: const Duration(seconds: 3),
      ),
    ),
  );

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
  String? _cutoffRetryId;
  bool _overrunHandled = false;

  /// What the UI should show as the track length: the shorter of the song's
  /// metadata duration and the loaded media's duration. A truncated stream
  /// honestly shows where it will end; a bloated stream shows the song's
  /// real length instead of 9 minutes of silence.
  Duration? get displayDuration {
    final meta = current.value?.duration;
    final media = player.duration;
    if (meta == null || meta <= Duration.zero) return media;
    if (media == null || media <= Duration.zero) return meta;
    return media < meta ? media : meta;
  }

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
      // Lock screen gets the honest length (min of metadata and media).
      final effective = displayDuration ?? d;
      if (effective != null && item != null && item.duration != effective) {
        mediaItem.add(item.copyWith(duration: effective));
      }
    });
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_advancing) {
        _onTrackCompleted();
      }
    });
    // Overrun watchdog: some streams are LONGER than the actual song and
    // "play" silence past its real end. When the position passes the song's
    // metadata length, treat it as completed instead of sitting in silence.
    player.positionStream.listen((pos) {
      final expected = current.value?.duration;
      if (expected == null || expected <= Duration.zero) return;
      if (pos <= expected + const Duration(seconds: 2)) {
        _overrunHandled = false;
        return;
      }
      if (!_overrunHandled && !_advancing && player.playing) {
        _overrunHandled = true;
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
          : AudioSource.uri(Uri.parse(
              await streams.audioUrl(track.id, expected: track.duration)));
      if (seq != _playRequestSeq) return; // superseded by a newer request
      await player.setAudioSource(source);
      if (seq != _playRequestSeq) return;
      // Truncated-stream guard: if the loaded stream is much shorter than
      // the song's real length, the URL served a cut version — re-resolve
      // once with the cache bypassed.
      final expected = track.duration;
      final actual = player.duration;
      if (localPath == null &&
          expected != null &&
          actual != null &&
          expected - actual > const Duration(seconds: 10)) {
        streams.invalidate(track.id);
        try {
          final freshUrl =
              await streams.audioUrl(track.id, expected: track.duration);
          if (seq != _playRequestSeq) return;
          await player.setAudioSource(AudioSource.uri(Uri.parse(freshUrl)));
          if (seq != _playRequestSeq) return;
        } catch (_) {
          // keep the short stream rather than failing playback entirely
        }
      }
      _advancing = false;
      await player.play();
      _consecutiveErrors = 0;
      library.addRecent(track);
      _prefetchUpcoming();
    } catch (_) {
      if (seq != _playRequestSeq) return;
      _advancing = false;
      _onPlayerError();
    } finally {
      if (seq == _playRequestSeq) loading.value = false;
    }
  }

  void _onTrackCompleted() async {
    // Cut-off guard: "completed" long before the song's real end means the
    // stream URL died or was truncated mid-play. Re-resolve fresh and resume
    // from where it stopped (once per track) instead of jumping ahead.
    final t = current.value;
    final expected = t?.duration;
    final pos = player.position;
    if (t != null &&
        expected != null &&
        expected - pos > const Duration(seconds: 10) &&
        _cutoffRetryId != t.id &&
        downloads.pathFor(t.id) == null) {
      _cutoffRetryId = t.id;
      streams.invalidate(t.id);
      try {
        final url = await streams.audioUrl(t.id, expected: t.duration);
        if (current.value?.id == t.id) {
          _advancing = true;
          await player.setAudioSource(
            AudioSource.uri(Uri.parse(url)),
            initialPosition: pos,
          );
          _advancing = false;
          await player.play();
          return;
        }
      } catch (_) {
        _advancing = false;
        // fall through to normal advance
      }
    }
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

  /// Resolves stream URLs for the next couple of queue items in the
  /// background so skips and auto-advance start instantly (URLs are cached
  /// in StreamService for ~4h).
  void _prefetchUpcoming() {
    final q = queueTracks.value;
    for (var i = queueIndex.value + 1;
        i <= queueIndex.value + 2 && i < q.length;
        i++) {
      final t = q[i];
      if (downloads.pathFor(t.id) == null) {
        unawaited(streams
            .audioUrl(t.id, expected: t.duration)
            .catchError((_) => ''));
      }
    }
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
        _prefetchUpcoming();
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
