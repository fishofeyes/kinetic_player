# Web Artplayer Integration & Features

Chinese version: [WEB_ARTPLAYER.md](WEB_ARTPLAYER.md)

On **Flutter Web**, kinetic_player uses [Artplayer.js **5.4.0**](https://artplayer.org) via `HtmlElementView`. The public API matches Android / iOS / macOS. Web-only capabilities are exposed through `ArtplayerVideoControllerImpl` / `ArtplayerUiConfig` and **must not** pollute `CommonVideoController`.

## Platform matrix

| Item | Web |
|------|-----|
| Engine | Artplayer.js 5.4.0 (`assets/web/kinetic_artplayer.js`) |
| Dart view | `HtmlElementView` (`com.example.player/art_view_ui`) |
| Controller | `ArtplayerVideoControllerImpl` |
| IPC | In-process `ArtplayerViewRegistry` (not a cross-isolate MethodChannel) |
| Chrome | Artplayer UI (mapped from `enableNativeControls`) |
| Video PiP | ✅ (`document.pictureInPictureEnabled` + `togglePip()`) |
| Document PiP | ✅ (requires `artPlugins.documentPip`) |
| HLS / DASH | ✅ (`hls.js` / `dashjs`; auto `customType` for `.m3u8` / `.mpd`) |
| Multi audio | ⚠️ (browser `audioTracks`; often empty for plain MP4) |

See [USAGE_EN.md](USAGE_EN.md) for the shared public API and cross-platform difference table.

## Layout

```
web/                              ← npm / TypeScript sources
  package.json                    ← artplayer 5.4.0 + official plugins + hls.js 1.7.3 / dashjs 5.2.1
  src/
    artplayer_adapter.ts
    artplayer_web_bridge.ts
    plugins.ts
    stream_types.ts
    index.ts
assets/web/kinetic_artplayer.js   ← esbuild output (plugin asset)
lib/kinetic_player_web.dart       ← HtmlElementView registration
lib/src/web/                      ← Dart controller / config / host
```

## Integration

No native project steps. Example:

```bash
cd example
flutter pub get
flutter run -d chrome
```

```yaml
dependencies:
  kinetic_player:
    path: ../kinetic_player
```

### Rebuild after TS changes

```bash
cd web
npm install
npm run build   # → assets/web/kinetic_artplayer.js
```

Toolchain: `typescript` 7.0.2, `esbuild` 0.28.1.

## Configuration: ArtplayerUiConfig

```dart
CommonVideoPlayerViewBuilder(
  url: videoUrl, // .m3u8 / .mpd auto-wires HLS/DASH
  creationParams: {
    ...ArtplayerUiConfig(
      ui: const KineticUiConfig(
        enableNativeControls: true,
        showFullscreenButton: true,
        pictureInPictureEnabled: true,
        coverUrl: 'https://example.com/cover.jpg',
        locale: 'zh',
      ),
      artPlugins: {
        ArtplayerPluginKeys.danmuku: {
          'danmuku': [
            {'text': 'hello', 'time': 1},
          ],
        },
        ArtplayerPluginKeys.hlsControl: true,
        ArtplayerPluginKeys.vttThumbnail: {
          'vtt': 'https://example.com/thumbs.vtt',
        },
        ArtplayerPluginKeys.documentPip: true,
      },
      artplayerOptions: {
        // Passed through to new Artplayer({...})
      },
    ).toCreationParams(),
  },
  builder: (controller) { /* … */ },
);
```

| Field | Meaning |
|-------|---------|
| `ui` | Shared `KineticUiConfig` (chrome / PiP / cover / loop / rate / `locale`). Language is `ui.locale` + `ui.strings` (`KineticChromeStrings`) → Artplayer `lang`; `vi` / `ms` / `fil` filled from the same table |
| `artPlugins` | Declarative official plugins (table below) |
| `artplayerOptions` | Raw Artplayer Option passthrough |
| `webCustomExtensions` | Host extension hook (may embed `artPlugins`) |

## Official plugins (`artPlugins`)

Values: `true` for defaults, or a `Map` of constructor options. Keys: `ArtplayerPluginKeys`.

| Key | npm package | Notes |
|-----|-------------|-------|
| `danmuku` | `artplayer-plugin-danmuku` | Danmaku |
| `danmukuMask` | `artplayer-plugin-danmuku-mask` | Mask (**CDN lazy-load** MediaPipe) |
| `hlsControl` | `artplayer-plugin-hls-control` | HLS quality / audio UI |
| `dashControl` | `artplayer-plugin-dash-control` | DASH quality UI |
| `vttThumbnail` | `artplayer-plugin-vtt-thumbnail` | Seek preview (`vtt` URL) |
| `multipleSubtitles` | `artplayer-plugin-multiple-subtitles` | Multi subtitle tracks |
| `chromecast` | `artplayer-plugin-chromecast` | Chromecast |
| `vast` | `artplayer-plugin-vast` | VAST (`tagUrl` / `url` from Dart) |
| `chapter` | `artplayer-plugin-chapter` | Chapters |
| `autoThumbnail` | `artplayer-plugin-auto-thumbnail` | Auto thumbnails |
| `ambilight` | `artplayer-plugin-ambilight` | Ambilight |
| `documentPip` | `artplayer-plugin-document-pip` | Document PiP |
| `audioTrack` | `artplayer-plugin-audio-track` | External audio (`url` required) |
| `jassub` | `artplayer-plugin-jassub` | ASS/SSA via JASSUB |
| `asr` | `artplayer-plugin-asr` | ASR helper |
| `ads` | `artplayer-plugin-ads` | Ads (`source` + `type` required) |

> `danmukuMask` is not in the main bundle; enabling it loads from jsDelivr (needs CDN access).

## Web-only APIs (downcast)

```dart
if (controller is ArtplayerVideoControllerImpl) {
  await controller.togglePip();
  await controller.artToggleDocumentPip();
  await controller.artEmitDanmuku({'text': 'hi', 'time': 1});
  await controller.artCallPlugin('artplayerPluginDanmuku', 'hide');
  final keys = await controller.artAvailablePlugins();
  controller.pipActive; // ValueNotifier<bool>
}
```

| API | Description |
|-----|-------------|
| `togglePip()` | Browser Video PiP |
| `artIsPipSupported()` | `document.pictureInPictureEnabled` |
| `pipActive` | Video PiP state |
| `artToggleDocumentPip()` | Document PiP (plugin must be enabled) |
| `artEmitDanmuku` | Emit danmaku (`danmuku` plugin required) |
| `artCallPlugin(name, method, {args})` | Invoke a loaded plugin method |
| `artAvailablePlugins()` | Bundled plugin keys |
| `artSetUiConfig` | Runtime UI update (plugins must be enabled at create time) |

## Behavior notes

- HTML5 `video.controls` is off; Artplayer chrome follows `enableNativeControls`.
- Mobile Web: `playsInline` plus `playsinline` / `webkit-playsinline` / `x5-video-player-type=h5`.
- Autoplay failure retries muted; still failing → `error`.
- Position updates throttled ~**250ms**, same as native.
- Many browsers omit `audioTracks` for progressive MP4; use `artPlugins.audioTrack` for external audio.

## Relation to other platforms

| | Android GSY | iOS / macOS SG | Web Artplayer |
|--|-------------|----------------|---------------|
| Dedicated doc | [GSY_FEATURES_EN.md](GSY_FEATURES_EN.md) | [DARWIN_SGPLAYER_EN.md](DARWIN_SGPLAYER_EN.md) | This file |
| Controller | `GSYVideoControllerImpl` | `SGVideoControllerImpl` | `ArtplayerVideoControllerImpl` |
| Danmaku | `gsyToggleDanmaku` etc. (incl. fullscreen) | ❌ | `artPlugins.danmuku` |
| Subtitles | `gsySetSubtitleUrl` etc. | ❌ | subtitle plugins |
| Fullscreen | `gsyStartFullscreen` | `sgStartFullscreen` | Artplayer fullscreen control |
| PiP | System Activity PiP | Unsupported | Video / Document PiP |

Shared integration and the difference table live in [USAGE_EN.md](USAGE_EN.md).
