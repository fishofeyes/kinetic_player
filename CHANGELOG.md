## 2.1.2

- **Stable dependency audit (2026-10-16)**: GSYVideoPlayer **14.0.0**, AGP **9.4.1**, Kotlin **2.4.21**, example Gradle **9.8.1** with distribution SHA-256 verification; Mockito **5.24.0**, Kotlin JUnit adapter and JUnit **6.1.3** engine. Enable built-in Kotlin, retain `android.newDsl=false` for Flutter 3.47, and align example subprojects with SDK Build Tools **37.0.0** / NDK **30.0.16248370**. The example falls back to debug signing when release signing is absent.
- **GSY 14 migration**: IJK now bundles FFmpeg n5.1.10 / OpenSSL 3.5.9 and upstream session, buffering, RTSP and decoder fixes. Enable SoundTouch by default and align Dart, initial configuration and native rate controls for pitch-preserving IJK playback (0.25×–4×); apply runtime changes through `setSpeedPlaying`. New multi-pass/LUT rendering and optional cast/RTMP/Compose modules are not automatically exposed through the Flutter API. See [upstream release notes](https://github.com/CarGuo/GSYVideoPlayer/blob/v14.0.0/doc/UPDATE_VERSION.md).
- **Flutter**: `material_ui` **1.7.0**; align minimum SDKs to **Dart 3.13 / Flutter 3.47**. Reviewed 1.5–1.7 changes; existing widget calls remain compatible. `web`, `path_provider`, `flutter_lints` and Web direct dependencies already match the latest stable releases.
- **Web**: migrate DASH request headers to dash.js 5 asynchronous `addRequestInterceptor`, preserving existing headers for Fetch/XHR; rebuild the shipped JS bundle and refresh npm transitive dependencies.
- **Desktop / Darwin**: update the Windows LGPL libmpv build to **2026-10-15 / a2cd83c56d** in CMake, download script and manifest. Official stable mpv remains **0.41.0**; keep the Linux system-library minimum. SGPlayer iOS/macOS **1.0.0** are still the latest published binaries in this repository.
- **SDK-pinned transitives**: `material_color_utilities` **0.13.0** and `test_api` **0.7.12** remain fixed by Flutter 3.47.7; newer published versions cannot resolve without changing Flutter SDK pins.
- **Validation**: Dart analysis and 17 Flutter tests pass; Web type checking, 3 bridge regression tests and example Web build pass; Android Debug/Release (R8 enabled) APK builds and the native JVM test pass. Device playback and Windows/iOS/macOS runtime behavior were not exercised.

## 2.1.1

### Features

- **Web streaming deps**: `hls.js` **1.7.3**, `dashjs` **5.2.1** (Artplayer remains **5.4.0**). Source switch tears down HLS/DASH engines and calls Artplayer `reset()` before `switchUrl`.

### Fixes

- **Web artPlugins**: skip `vttThumbnail` when `vtt` is missing (avoids null cue parse crash); soft-bind `hlsControl` / `dashControl` so non-HLS/DASH sources no longer throw `Cannot find instance of HLS/DASH`.

### Docs

- WEB_ARTPLAYER: note `hls.js` / `dashjs` versions in the package tree.

## 2.1.0

### Features

- **Windows / Linux libmpv**: Built-in desktop backend with the same `CommonVideoController` API. Flutter `Texture` + Dart chrome (macOS-style, no pan gestures). Windows bundles the latest zhongfly LGPL `libmpv-2.dll` (mpv **0.41.0** API); Linux uses system libmpv. See [doc/DESKTOP_MPV_EN.md](doc/DESKTOP_MPV_EN.md).
- **Desktop vs Android**: rotation, mirror, cover, title, subtitles, playlist / play-next, video tracks, net speed, show type, pure play, and watermark overlay. Skipped: GL filters, GIF, danmaku, ads, system PiP, list auto-play.
- **HTTP headers / User-Agent (all platforms)**: `CommonVideoController.setHttpRequestOptions` and `creationParams['userAgent']` / `headers`. Web: HLS/DASH xhr only (not progressive MP4; UA usually forbidden by browsers).

### Docs

- README / USAGE / Example: desktop libmpv replaces GstPlayer as the default Windows/Linux path. GstPlayer remains an optional GStreamer alternative.
- USAGE: document cross-platform HTTP request options.

## 2.0.4

### Features

- **Screenshot data**: `captureFrame()` and `onScreenshotCaptured` return PNG bytes (`Uint8List?`). The plugin does not write a temp file; the host saves the bytes.

### Fixes

- **macOS toolbar popups**: opening volume / settings / rate no longer trips Swift exclusivity (`swift_beginAccess` in `repositionToolbarPanels` during `layout()`).

### Docs

- USAGE / README / Darwin / Web / Example: version `2.0.4`.

## 2.0.3

### Features

- **Danmaku input** (Android): the input field stays visible; tapping the danmaku icon enables/disables it and toggles the overlay together.
- **Settings panel scroll**: first- and second-level settings clamp to available height and scroll (Android GSY and Darwin SGPlayer).
- **Settings screenshot / GIF**: level-2 “Other” has **Screenshot** on all platforms (current frame, no chrome overlay; PNG bytes via `captureFrame()` / `onScreenshotCaptured` so the host chooses where to save — the plugin does not write files or Photos). Android also has **Record GIF** (tap to start, tap again to stop). Reuses `captureFrame()` / `gsyStartGifRecording()`.
- **Popup fade**: volume / settings / rate / quality (Android) popups fade in and out over 200ms. Closing with the control bar is instant so the animations do not stack.
- **Settings panel width**: wrap-content (min ~140, capped to the player). Labels longer than **10 characters** are truncated with an ellipsis (including audio-track names).
- **Chrome locale**: `KineticUiConfig.locale` plus common `setLocale` / `KineticChromeStrings` (`zh` / `en` / `vi` / `ms` / `id` / `fil`) applied on Android, shared Darwin, and Web Artplayer `lang`.
- **KineticUiConfig**: renamed from `GsyUiConfig` (plugin-wide, not Android-only). Language is serialized under `creationParams['ui']`. Hot-swap still uses `setLocale`.
- **Toolbar icons**: first-row play / volume / settings / fullscreen glyphs enlarged (20pt in a 36dp hit target).
- **material_ui**: depends on `material_ui ^1.1.0`; minimum SDK **Dart 3.12 / Flutter 3.44**. Example no longer uses `cupertino_icons`.

### Fixes

- **List auto-play**: `GsyAutoPlayVideoList` rebuilds when `GsyAutoPlayCoordinator` changes so the active cell actually mounts a player. The play window is computed against the **ListView** bounds, not full-screen `MediaQuery` (avoids AppBar offset).

### Docs

- USAGE / README / Darwin / Web / Example: locale API, SDK floor, version `2.0.3`.
- USAGE / GSY_FEATURES: settings screenshot / GIF, `onScreenshotCaptured`, popup fade, wrap-content labels, list auto-play rebuild.

## 2.0.2

### Features

- **Android danmaku / watermark**: Live in the player layout and follow **window fullscreen** (clone sync).
- **Android ads**: Full pre-roll / mid-roll with skip countdown UI (`gsyPlayWithPreRollAd`, `gsySetMidRollAds` with `positionMs`/`adUrl`/`contentUrl`, `gsySkipAd`); works in fullscreen.
- **List auto-play**: `GsyAutoPlayVideoList` uses list-level visibility and mounts a player only for the active cell.
- **Pure play mode**: Also hides volume / settings / title.
- **SG creation**: `GsyUiConfig.speed` / `looping` applied on iOS / macOS create.

### Fixes

- Screenshot / GIF / filters / rotation / mirror / subtitles target the active fullscreen window when present.

### Removals

- **Detail-page seamless handoff** removed (`gsySeamlessHandoffParams`).
- **Multi-instance simultaneous play** no longer documented as supported.
- Dead **`customRatio`** parameter removed from `gsySetGsyShowType`.

### Docs

- GSY_FEATURES / USAGE / README aligned to fully delivered features only; HDR links marked as test sources, not HDR product support; macOS gestures clarified (iOS only pans).

---

## 2.0.1

### Fixes

- **macOS center play/pause icon**: Bake play and pause SF Symbols into a fixed square canvas and set `imageScaling` / cell to `.scaleNone`, so AppKit no longer fattens `pause.fill` inside the 60×60 hit target.

### Docs

- Document **GstPlayer** selection for **Linux / Windows**: [GitHub](https://github.com/wanwenfeng4798/GstPlayer), [pub.dev](https://pub.dev/packages/gstplayer). README / USAGE (EN + ZH) updated.

---

## 2.0.0

### Features

- **Flutter Web**: Artplayer.js **5.4.0** via `HtmlElementView`; public API aligned with Android / iOS / macOS. Web-only APIs on `ArtplayerVideoControllerImpl` / `ArtplayerUiConfig` (does not pollute `CommonVideoController`). See [doc/WEB_ARTPLAYER.md](doc/WEB_ARTPLAYER.md).
- **Web streaming**: HLS / DASH via `hls.js` / `dashjs` with automatic `customType` for `.m3u8` / `.mpd`.
- **Artplayer plugins**: Bundled official plugins through `artPlugins` / `ArtplayerPluginKeys` (danmuku, HLS/DASH control, VTT thumbnail, subtitles, Chromecast, VAST, chapter, auto-thumbnail, ambilight, Document PiP, audio-track, JASSUB, ASR, ads). `danmukuMask` remains CDN lazy-load (MediaPipe size).
- **In-process Web bridge**: `ArtplayerViewRegistry` instead of dual-end MethodChannel (avoids conflict on Web).
- **pub.dev zero-config Darwin**: `sharedDarwinSource` single tree `darwin/kinetic_player` (Package.swift + Sources); remote `binaryTarget` downloads SGPlayer. No host Scheme Pre-action. CocoaPods uses `darwin/kinetic_player.podspec` → `ensure_sgplayer`.

### Fixes

- **Web audio tracks**: No fake “Default” track when the browser exposes no `audioTracks`; `selectAudioTrack(0)` is a no-op success when the list is empty.
- **macOS center play icon**: Stop AppKit from stretching SF Symbols into the 60×60 hit target (`imageScaling` + fixed symbol size / optical centering for `play.fill`).
- **macOS pan gestures**: Removed unreliable pans inside Flutter `AppKitView` (and there is no public brightness API). Seek / volume / tracks use the same button + popup pattern as the gear / 音轨 UI (progress slider, speaker panel, settings panel). **iOS keeps** horizontal seek / left brightness / right volume pans.

### Docs

- Web guides [WEB_ARTPLAYER.md](doc/WEB_ARTPLAYER.md) / [WEB_ARTPLAYER_EN.md](doc/WEB_ARTPLAYER_EN.md); README / USAGE / EXAMPLE / Darwin docs updated for Web, macOS interaction differences, and pub.dev out-of-the-box SPM.

---

## 1.0.0

### Features

- **macOS support**: SGPlayer on macOS via `AppKitView`, sharing Darwin UI/bridge with iOS (`darwin/SgNativePlayerBridge`, `darwin/kinetic_player/Sources/SgPlayerKit`). Minimum **macOS 11**.
- **Unified Darwin tooling**: Shared scripts under `darwin/scripts/sgplayer/` (`ios` | `macos`); artifacts in `darwin/Frameworks/{ios,macos}/`; manifests in `darwin/sgplayer/manifest.*.json`.
- **SPM binaryTarget**: Remote `binaryTarget(url:checksum:)` for iOS/macOS `Package.swift`, with Example Scheme Pre-actions and `spm_prebuild_hook` / `ensure_sgplayer` (download → local build fallback).
- **Docs**: Single guide [doc/DARWIN_SGPLAYER.md](doc/DARWIN_SGPLAYER.md); README / USAGE / EXAMPLE aligned for iOS + macOS.

### Fixes

- **Android PiP**: Clamp picture-in-picture aspect ratio (and guard failures) to avoid crashes on ultra-wide / extreme aspect videos.
- **Large remote media (Android)**: Safer timeouts / cache behavior for big remote MKV-style streams (e.g. disable aggressive play-while-cache where it caused hangs).
- **iOS / macOS SPM**: Package targets stay inside the Flutter-ephemeral package root (synced sources + local xcframework); `SgPlayerKit` compiled in the main `kinetic_player` target so `Flutter` / `FlutterMacOS` resolve correctly.
- **Platform view APIs**: Correct iOS vs macOS factory signatures (`FlutterPlatformView` vs returning `NSView`; `createArgsCodec` optionality).
- **macOS Example**: Enable `com.apple.security.network.client` for sandboxed outbound streaming; align deployment target to 11.0.

### Enhancements

- **Example**: HDR / high-bitrate demo sources; Android kernel switcher in the demo UI; macOS Example app + Pre-action hooks.
- **Android** (carried from 0.0.4 line): default kernel **IJKPlayer**; `GsyUiConfig.ijkEnableAccurateSeek` → `enable-accurate-seek` for IJK.

---

## 0.0.4

### Fixes

- Android **default kernel**: Set to **IJKPlayer** when plugin loads.
- Android IJK accurate seek: `GsyUiConfig.ijkEnableAccurateSeek` (default `true`) sets `enable-accurate-seek=1` via `GSYVideoManager.setOptionModelList` to reduce keyframe bounce when dragging the progress bar; only effective for IJK kernels.
- iOS: inaccurate seek / progress-bar scrubbing and background playback issues.

---

## 0.0.3

### Fixes

- **Volume persistence**: Fixed volume level and slider position resetting after pause/resume, replay after completion, or switching video source. Android re-applies saved volume on `onPrepared` / playback start; iOS uses `applySavedVolume` on play/replay and returns `_savedVolume` from `currentVolume()`.
- **Picture-in-Picture (Android)**: Fixed auto PiP not triggering when playback started via GSY auto-play or native play button (`isPlaying` was only set from Flutter `play()`). Playback state now syncs with native GSY events; PiP eligibility uses actual player state (`isPlaybackActive()`).
- **Volume gesture conflict (Android)**: When `showVolumeToolbar` is enabled, GSY’s built-in left-edge volume slider gesture is disabled so only the Bilibili-style volume popup is shown.
- **Volume drag label**: Fixed percentage label (`50%`) flickering or disappearing while dragging the volume slider.
- **Toolbar icons**: Unified fullscreen button size with settings/volume icons (28dp); replaced GSY default enlarge icon with matching vector assets.

### Enhancements

- **Volume UI**: Dragging the vertical volume slider shows a percentage label to the left of the track; the label hides on release. Panel background width reduced to 44dp (label floats outside the panel).
- **iOS gesture controls**: Added GSY-style pan gestures — horizontal seek, left-half brightness, right-half volume — with a center HUD overlay. Controlled by the shared `enableNativeControls` flag (same as Android). System brightness is restored when the player is disposed. Swipe-volume is blocked while the volume popup is open or its slider is being dragged (same as Android), and volume sensitivity matches GSY (~3×).
- **Render rotate / mirror**: Android already exposed `gsySetRenderRotation` / `gsySetMirrorHorizontal`; iOS adds matching `sgSetRenderRotation` / `sgSetMirrorHorizontal` via `CGAffineTransform` on the video view. Example app includes rotate/mirror controls for both platforms.
- **Cover / keep last frame**: Android uses GSY `setThumbImageView` + KeepLastFrameVideo-style `onAutoCompletion`; iOS uses a cover overlay and hides it when keeping the last frame. Config: `GsyUiConfig.coverUrl` / `keepLastFrameWhenComplete`; runtime: `gsySetCoverUrl` / `gsySetKeepLastFrameWhenComplete` (iOS: `sgSet*`).
- **Rotate fill + vertical mirror**: 90°/270° rotation now scales to center-fill the player; added `gsySetMirrorVertical` / `sgSetMirrorVertical`.
- **Rotate / mirror positioning fix**: Android now uses GSY `View.setRotation` + `scaleX`/`scaleY` (MeasureHelper remeasure) instead of a mis-pivoted TextureView matrix; iOS uses `SgTransformHostView` (clipping host + inner content transform) so Auto Layout stays stable and the Metal render target stays identity.
- **SGPlayer deep APIs**: buffered progress + error details, pitch, VR/VRBox + viewport, demuxer options (timeout/UA/headers), video track selection, multi-segment `SGMutableAsset`, background playback policy.
- **Example**: Explicitly enables `pictureInPictureEnabled: true`; added PiP usage hint in the control panel.

---

## 0.0.2

### Fixes & Optimizations

- **Audio Track & Gesture Fixes**: Fixed an issue where audio track settings were reset upon replay, and resolved conflicts between audio track settings and gesture operations.
- **Audio Control Fixes**: Fixed conflicts between the audio track bar and gesture-based volume adjustments.
- **Example Optimization**: Optimized the example project to prevent the application from failing to open after enabling code obfuscation (ProGuard) on Android.

---

## 0.0.1

### Public API

- Unified `CommonVideoController`: `play` / `pause` / `stop` / `seekTo` / `setScaleMode` / `setRate` / `setVolume` / `setMute` / `switchVideoSource` / `getAudioTracks` / `selectAudioTrack` / `getDuration` / `getCurrentPosition` / `getVideoSize` / `setLooping` / `captureFrame` / `dispose`
- Dual-platform MethodChannel status and progress callbacks (`onPlayerStateChanged` / `onPositionChanged`, throttled at approx. 250ms)

### Native Control Bar (Android GSY + iOS SGPlayer)

- Bilibili-style UI: Click the speaker icon to pop up a **vertical** volume bar; click the gear icon to open the **settings panel** for audio track selection.
- Unified track colors for the progress bar and volume bar (`kinetic_seek_progress` / `KineticPlayerColors`).
- Added `GsyUiConfig.showSettingsButton` (defaults to `true`).
- `showVolumeToolbar` now controls the speaker button (instead of a persistent bottom volume bar).
- The bottom area no longer intercepts clicks after the control bar is hidden, allowing the bottom-right corner to normal toggle the control bar visibility.

### Picture-in-Picture (Android)

- `GsyUiConfig.pictureInPictureEnabled` defaults to `true`.
- Automatically enters PiP when switching to the background during playback (`onUserLeaveHint`, API 26+).
- Supports `setAutoEnterEnabled` on Android 12+.
- Manual API: `gsyEnterPictureInPicture()`.
- Host app configuration required: `supportsPictureInPicture`, `resizeableActivity`, and forwarding `KineticPlayerPlugin.handleUserLeaveHint`.
- iOS: SGPlayer custom rendering, **system PiP is not supported**.

### Playback Experience

- Fixed an issue where playback could not be replayed after completion (Android completion state now executes seek(0) first; iOS uses `replayFromBeginning`).

### Android GSY Advanced Capabilities

- Filters, danmaku (bullet comments), subtitles, screenshots/GIFs, lists, Exo tracks, watermarks, etc. (see [GSY_FEATURES.md](doc/GSY_FEATURES.md)).

### iOS SGPlayer

- Native control bar, full screen, `sgSetVRMode`.
- Audio track APIs aligned with the Android public layer.
