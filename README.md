# Maherai Music

Ad-free YouTube Music client for iOS (Flutter). Inspired by [SpMp](https://github.com/sayaka-sh/spmp).

## Features

- **Full YouTube Music catalog** — home feed, search (songs / videos / albums / artists / playlists) with live suggestions, artist pages, albums and public playlists. No ads, ever.
- **Background playback** — keeps playing when the app is minimized or the screen locks.
- **Lock screen & Control Center** — artwork, title, play/pause, next/previous, and seek from the lock screen (audio_service → MPNowPlayingInfoCenter).
- **Downloads** — save any song (or a whole playlist) for offline playback; downloaded songs play from disk automatically.
- **Local playlists** — create, rename, reorder (drag), and delete playlists; add any song from anywhere via long-press.
- **Favorites + listening history**.
- **Radio / autoplay** — endless queue of related songs seeded from what you play (toggle in the queue sheet).
- **Lyrics** — time-synced from LRCLIB (tap a line to seek), YouTube Music plain lyrics as fallback.
- **Queue management** — play next, add to queue, drag to reorder, swipe to remove, shuffle and repeat modes.
- **Dynamic UI** — full player tints itself from the artwork palette, animated mini player, hero transitions, shimmer loading, glass bottom bar.

## Architecture

- `lib/services/innertube.dart` — InnerTube (music.youtube.com private API, WEB_REMIX client): home feed, search, suggestions, radio/next, playlists/albums, artists, lyrics metadata. All parsing is defensive; home falls back to search-built shelves if YouTube changes the layout.
- `lib/services/stream_service.dart` — youtube_explode_dart resolves audio stream URLs (prefers MP4/AAC for AVPlayer), with URL caching.
- `lib/services/audio_handler.dart` — audio_service `BaseAudioHandler` wrapping just_audio: queue, shuffle/repeat, radio auto-extend, lock-screen state.
- `lib/services/download_service.dart` / `library_service.dart` — Hive-backed downloads, playlists, favorites, history.
- `lib/ui/` — screens and widgets (Provider for state).

## Build

### iOS IPA (CI)

GitHub Actions (`.github/workflows/build-ios.yml`, macos-15, Flutter 3.32.5) builds an **unsigned** IPA on every push to `main`, or manually via *Run workflow*. Download the `maherai_music-ipa` artifact:

```
gh run watch
gh run download <run-id>
```

Install with **Sideloadly** (re-signs with your Apple ID; free accounts re-sideload every 7 days). After installing, enable the app in Settings → General → VPN & Device Management.

> Keep the repo **public** — macOS runner minutes are free on public repos (10× billing on private ones).

### Android (local, for testing)

```
flutter build apk --release
```

## Notes

- No Google/YouTube login required; everything uses public endpoints.
- Stream URLs expire after ~6 h; the app re-resolves them per play.
- If playback breaks after a YouTube change, bump `youtube_explode_dart` in `pubspec.yaml` and rebuild.
