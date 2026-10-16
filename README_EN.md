# kinetic_player

The strongest cross-platform Flutter video player plugin for **Android / iOS / macOS / Web / Windows / Linux**.

- **Android**: [GSYVideoPlayer 14.0.0](https://github.com/CarGuo/GSYVideoPlayer)
- **iOS / macOS**: [wanwenfeng4798/SGPlayer](https://github.com/wanwenfeng4798/SGPlayer) (**master**)
- **Web**: [Artplayer.js 5.4.0](https://artplayer.org)
- **Windows / Linux**: [libmpv](https://mpv.io)

Repo: [github.com/wanwenfeng4798/kinetic_player](https://github.com/wanwenfeng4798/kinetic_player)

Requires **Dart 3.13 / Flutter 3.47+** and `material_ui: ^1.7.0`.

## Platform previews

| Android | iOS |
|:-------:|:---:|
| <img src="doc/android.jpg" alt="Android" width="240" /> | <img src="doc/ios.jpg" alt="iOS" width="240" /> |

| macOS | Web |
|:-----:|:---:|
| <img src="doc/macos.png" alt="macOS" width="420" /> | <img src="doc/web.png" alt="Web" width="240" /> |

## Features

- Unified `CommonVideoController` API (play / pause / seek / scale / rate / volume / tracks / loop / screenshot / etc.)
- Platform auto-selection: Android → GSY, iOS / macOS → SGPlayer, Web → Artplayer, **Windows / Linux → libmpv**
- Bilibili-style native control bar (vertical volume popup with percentage while dragging, settings panel for tracks / screenshot / Android GIF, popup fade, consistent progress bar + bottom bar icon sizing)
- **Android / iOS** pan gestures for seek / volume / brightness (`enableNativeControls`); **macOS / Windows / Linux** have no pans — progress bar + speaker / gear popups
- Android Picture-in-Picture (PiP) **enabled by default** (API 26+)
- Web: Video / Document PiP, HLS/DASH, official Artplayer plugins (danmaku / subtitles / Chromecast / …)
- Android GSY advanced features (danmaku / watermark / ads / filters, including fullscreen): [doc/GSY_FEATURES_EN.md](doc/GSY_FEATURES_EN.md)
- Private platform-only APIs via explicit downcasting (does not pollute the public interface)
- iOS / macOS integrate via **sharedDarwinSource** (`darwin/`) with both **CocoaPods** and **Swift Package Manager (SPM)**
- Prebuilt `SGPlayer.xcframework` download via **GitHub Release** (avoid local building)

## Docs

| Document | Description |
|---|---|
| [doc/USAGE_EN.md](doc/USAGE_EN.md) | Integration steps, public API, native UI, platform differences |
| [doc/GSY_FEATURES_EN.md](doc/GSY_FEATURES_EN.md) | Android GSY advanced capability matrix |
| [doc/DARWIN_SGPLAYER_EN.md](doc/DARWIN_SGPLAYER_EN.md) | iOS / macOS SGPlayer binaries, scripts, SPM, Release |
| [doc/WEB_ARTPLAYER_EN.md](doc/WEB_ARTPLAYER_EN.md) | Web Artplayer plugins, HLS/DASH, Web-only APIs, rebuild |
| [doc/DESKTOP_MPV_EN.md](doc/DESKTOP_MPV_EN.md) | Windows / Linux libmpv: deps, DLL, Wayland, hwdec |
| [doc/EXAMPLE_EN.md](doc/EXAMPLE_EN.md) | Example app notes |

## Quick Start

### 1. Add dependency

```yaml
dependencies:
  kinetic_player:
    path: ../kinetic_player   # or pub.dev / git reference
```

### 2. Enable Apple SPM (recommended for iOS / macOS)

In your app and the plugin `pubspec.yaml`:

```yaml
flutter:
  config:
    enable-swift-package-manager: true
```

### 3. iOS / macOS (usually no extra steps)

See [doc/DARWIN_SGPLAYER_EN.md](doc/DARWIN_SGPLAYER_EN.md).

**SPM (recommended):** The published package already includes `Package.swift` + sources; Xcode downloads `SGPlayer.xcframework` via the remote `binaryTarget`. Set macOS `MACOSX_DEPLOYMENT_TARGET` to **11.0+**. If Xcode reports an SPM wrapper version mismatch, see [DARWIN_SGPLAYER_EN.md](doc/DARWIN_SGPLAYER_EN.md#spm-wrapper-minimum-os) to edit `FlutterGeneratedPluginSwiftPackage` manually.

**CocoaPods:** `pod install` runs `prepare_command` → `ensure_sgplayer.sh` (download prebuilt; fall back to local build).

Maintainers regenerating `Package.swift` after Release / manifest updates, or forcing a local build: see the Darwin guide.

### 4. Minimal example

```dart
import 'package:kinetic_player/kinetic_player.dart';

CommonVideoPlayerViewBuilder(
  url: 'https://example.com/video.mp4',
  creationParams: {
    ...const KineticUiConfig(
      showVolumeToolbar: true,
      showSettingsButton: true,
      pictureInPictureEnabled: true, // Android only
      locale: 'zh',
    ).toCreationParams(),
  },
  builder: (controller) {
    // controller is CommonVideoController; you can downcast per platform if needed.
  },
);
```

Complete example: [doc/EXAMPLE_EN.md](doc/EXAMPLE_EN.md) and the `example/` directory.

## HDR test links

To avoid duplicated maintenance, HDR test streams are maintained in dedicated docs:

- Chinese: [doc/HDR_TEST_LINKS.md](doc/HDR_TEST_LINKS.md)
- English: [doc/HDR_TEST_LINKS_EN.md](doc/HDR_TEST_LINKS_EN.md)

## Backend selection

The factory picks a backend by platform. **Windows / Linux use built-in libmpv**; you do not need GstPlayer.

| Target platforms | Backend | Notes |
|---|---|---|
| Android | GSYVideoPlayer | Default auto-selection |
| iOS / macOS | SGPlayer | Default auto-selection |
| Web | Artplayer.js | Default auto-selection |
| **Windows / Linux** | **libmpv** | Default auto-selection; see [doc/DESKTOP_MPV_EN.md](doc/DESKTOP_MPV_EN.md) |

If you specifically need a GStreamer pipeline, the separate [GstPlayer](https://pub.dev/packages/gstplayer) package is still available.

## Platform support

| Platform | Core | Device / desktop | Simulator / browser | PiP |
|---|---|---|---|---|
| Android | GSYVideoPlayer 14.0.0 | ✅ | ✅ | ✅ (enabled by default) |
| iOS | SGPlayer master | ✅ | ❌ (prebuilt FFmpeg is arm64 only) | ❌ |
| macOS | SGPlayer master | ✅ | ✅ (macosx xcframework) | ❌ |
| Web | Artplayer.js 5.4.0 | — | ✅ Chrome / Safari / mobile Web | ✅ Video PiP; Document PiP optional |
| Windows | libmpv (bundled DLL) | ✅ x64 | — | ❌ |
| Linux | libmpv (system library) | ✅ | — | ❌ |

## License

This plugin code is under the [MIT License](LICENSE).

SGPlayer is a standalone third-party project; its license follows the [wanwenfeng4798/SGPlayer](https://github.com/wanwenfeng4798/SGPlayer) repository (fork from libobjc/SGPlayer).

The Windows prebuilt **libmpv** is LGPLv2.1+ (dynamic link); see [doc/DESKTOP_MPV_EN.md](doc/DESKTOP_MPV_EN.md).

## Support

If you find this project helpful, please support me.

![Support](doc/pay.jpg)

