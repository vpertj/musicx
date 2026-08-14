# MusicX

A plugin-based, cross-platform free music player (Flutter).

## Current Progress

- **Phase 1 (Done)**: Plugin runtime layer — CommonJS plugin loading, JS↔Dart bridge, isolate isolation with timeout circuit breaker, MusicFree-compatible data models.
- **Phase 2 (Done)**: Plugin management, search, playback (just_audio), and play queue.
- **Phase 2.5 (Done)**: Brand-new modern UI — immersive dark theme (purple→pink gradient accents), mini player bar, full-screen player (gradient progress bar / loop / shuffle / queue), search page (history / recommendations / result cards), card-based plugin management.

## Running

```bash
flutter pub get
flutter run -d macos   # or android / windows
```

1. On the "Plugins" page, tap + and install the sample plugin by entering its path `example/plugins/demo_plugin.js`;
2. Switch to the "Search" page, type any keyword (e.g. `SoundHelix`), and press Enter;
3. Tap a result song to start playback (the sample plugin returns SoundHelix's public test audio).

## Testing

```bash
flutter test
```

## Architecture

Five layers: UI (Flutter) → State management (Riverpod) → Plugin runtime layer (QuickJS) → Playback engine (just_audio) → Data layer (Drift, Phase 3).

## License Compliance

Self-built implementation; the plugin protocol is compatible with MusicFree (CommonJS modules exporting platform/version/search/getMediaSource, etc.) without copying its source code (to avoid AGPL contamination).
