# 使用指南

English version: [USAGE_EN.md](USAGE_EN.md)

最低 SDK：**Dart 3.13 / Flutter 3.47**。宿主应用请依赖 `material_ui: ^1.7.0`，并 `import 'package:material_ui/material_ui.dart'`（不要再 `import package:flutter/material.dart`）。

## 架构概览

```
Dart 层
  CommonVideoController          ← 纯公共 API
  CommonVideoPlayerView          ← 平台原生视图
  CommonVideoPlayerFactory       ← Android→GSY / iOS·macOS→SG / Web→Artplayer / Windows·Linux→libmpv
       │
       ├── GSYVideoControllerImpl        (Android 独有 API)
       ├── SGVideoControllerImpl         (iOS / macOS 独有 API)
       ├── ArtplayerVideoControllerImpl  (Web 独有 API)
       └── MpvVideoControllerImpl        (Windows / Linux 独有 API)
```

## 内核选型

默认按平台自动选型即可。**Windows / Linux 走内建 libmpv**，详见 [DESKTOP_MPV.md](DESKTOP_MPV.md)。

| 目标平台 | 选用内核 | 何时选用 |
|----------|----------|----------|
| Android | GSYVideoPlayer | 默认 |
| iOS / macOS | SGPlayer | 默认 |
| Web | Artplayer.js | 默认 |
| **Windows / Linux** | **libmpv** | 默认 |

若需要 GStreamer 管线，仍可使用独立包 [GstPlayer](https://pub.dev/packages/gstplayer)。

Channel 命名：

- Android GSY：`com.example.player/gsy_<viewId>`
- iOS / macOS SG：`com.example.player/sg_<viewId>`
- Web Artplayer：进程内 Dart 注册表（`ArtplayerViewRegistry`，无跨端 MethodChannel）
- Windows / Linux libmpv：`com.example.player/mpv`（create/destroy）+ `com.example.player/mpv_<viewId>`

PlatformView / Texture 类型：

- Android：`com.example.player/gsy_view_ui`（`AndroidView`）
- iOS：`com.example.player/sg_view_ui`（`UiKitView`）
- macOS：`com.example.player/sg_view_ui`（`AppKitView`）
- Web：`com.example.player/art_view_ui`（`HtmlElementView` + Artplayer.js）
- Windows / Linux：`com.example.player/mpv_view_ui`（Flutter `Texture` + Dart 控制栏）

## 集成

### pubspec.yaml

```yaml
dependencies:
  kinetic_player:
    path: ../kinetic_player

flutter:
  config:
    enable-swift-package-manager: true   # iOS 推荐开启 SPM
```

### Android

无需额外步骤。GSYVideoPlayer 通过 Gradle Maven 依赖自动拉取：

- `io.github.carguo:gsyvideoplayer-java:14.0.0`
- `io.github.carguo:gsyvideoplayer-exo2:14.0.0`
- `io.github.carguo:gsyvideoplayer-arm64:14.0.0`

**画中画（PiP）** 需在宿主 Activity 的 `AndroidManifest.xml` 中声明：

```xml
<activity
    android:name=".MainActivity"
    android:resizeableActivity="true"
    android:supportsPictureInPicture="true"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    ... />
```

> 注意：不要在 `configChanges` 中使用 `pictureInPictureMode`，当前 AAPT 不支持该 flag；已有 `screenSize|screenLayout` 等即可满足 PiP 场景。

并在 Activity 中转发生命周期（example 已配置）：

```kotlin
override fun onConfigurationChanged(newConfig: Configuration) {
  super.onConfigurationChanged(newConfig)
  KineticPlayerPlugin.handleConfigurationChanged(this, newConfig)
}

override fun onBackPressed() {
  if (KineticPlayerPlugin.handleBackPressed(this)) return
  super.onBackPressed()
}

override fun onUserLeaveHint() {
  super.onUserLeaveHint()
  KineticPlayerPlugin.handleUserLeaveHint(this)  // 播放中切后台自动 PiP
}
```

**PiP 触发条件**（0.0.3+）：

- 视频处于**实际播放中**（含 GSY 自动播放 `startAfterPrepared`、原生播放按钮，不限于 Flutter `play()`）
- `pictureInPictureEnabled: true`（默认）
- 设备 API 26+ 且支持 PiP
- Android 8–11：依赖 `onUserLeaveHint` 主动进入 PiP
- Android 12+：额外通过 `PictureInPictureParams.setAutoEnterEnabled` 在用户离开 Activity 时系统自动进入

按 **Home** 或切换到其他 App 即可验证；暂停状态下不会进入 PiP。

### iOS / macOS（SGPlayer，共用 Darwin）

两端流程一致，详见 [DARWIN_SGPLAYER.md](DARWIN_SGPLAYER.md)。

1. **启用 SPM**（推荐）：

```yaml
flutter:
  config:
    enable-swift-package-manager: true
```

2. **二进制**：SPM 下由 `Package.swift` 远程 `binaryTarget` 自动下载；CocoaPods 下 `prepare_command` 调用 `ensure_sgplayer.sh`。终端用户无需再跑脚本。

3. **运行**：

```bash
flutter pub get
flutter run          # iOS 真机
flutter run -d macos
```

> iOS 模拟器暂不支持（FFmpeg 预编译仅真机 arm64）。  
> macOS 部署版本需 **11.0+**（与插件 `Package.swift` 对齐）。  
> macOS Example 需 `com.apple.security.network.client` 出站网络权限。  
> iOS / macOS 均无系统 PiP；原生底栏与 SG API 共用。

### Web（Artplayer.js）

无需额外原生工程。通过 `HtmlElementView` 挂载 Artplayer，公共 API 与其它平台一致。

```bash
flutter pub get
flutter run -d chrome
```

Web 独有能力（`artPlugins`、HLS/DASH、Document PiP、弹幕 API、TS 打包等）见独立文档：

- 中文：[WEB_ARTPLAYER.md](WEB_ARTPLAYER.md)
- English：[WEB_ARTPLAYER_EN.md](WEB_ARTPLAYER_EN.md)

```dart
CommonVideoPlayerViewBuilder(
  url: videoUrl,
  creationParams: ArtplayerUiConfig(
    ui: const KineticUiConfig(
      enableNativeControls: true,
      pictureInPictureEnabled: true,
      locale: 'zh',
    ),
    artPlugins: {
      ArtplayerPluginKeys.hlsControl: true,
    },
  ).toCreationParams(),
  builder: (controller) { /* … */ },
);
```

### Windows / Linux（libmpv）

公共 API 不变。Windows 构建时下载最新 LGPL `libmpv-2.dll`（mpv 0.41 API）；Linux 需系统 `libmpv-dev` / `mpv-libs-devel`。详见 [DESKTOP_MPV.md](DESKTOP_MPV.md)。

```bash
flutter pub get
flutter run -d windows
flutter run -d linux
```

宿主继续使用 `CommonVideoPlayerViewBuilder` + `KineticUiConfig`，与其它平台相同。

## 公共 API

`CommonVideoController` 提供：

| 方法 / 属性 | 说明 |
|-------------|------|
| `play()` | 开始播放（播放结束后再次调用会先 seek 到开头再播） |
| `pause()` | 暂停 |
| `stop()` | 停止并重置 |
| `seekTo(Duration)` | 跳转 |
| `setScaleMode(CommonScaleMode)` | 缩放模式 |
| `setRate(double)` | 倍速 |
| `setVolume(double)` / `setMute(bool)` | 音量 / 静音 |
| `switchVideoSource(url, {autoPlay})` | 换源 |
| `getAudioTracks()` / `selectAudioTrack(index)` | 音轨列表 / 切换 |
| `getDuration()` / `getCurrentPosition()` | 读取当前进度（与 `duration`/`position` 一致） |
| `getVideoSize()` | 视频宽高 |
| `setLooping(bool)` | 循环（Android GSY 原生；iOS 播放结束时 seek(0)+play） |
| `setLocale(String)` | 控制栏语言（`zh` / `en` / `vi` / `ms` / `id` / `fil`；创建时用 `KineticUiConfig.locale`） |
| `setHttpRequestOptions(KineticHttpRequestOptions?)` | 自定义 User-Agent / HTTP 标头（下次换源生效；也可 `creationParams['userAgent']` / `headers`） |
| `captureFrame({highQuality, includeOverlay})` | 截当前帧，返回 PNG 字节 `Uint8List?`（Android 可含 UI overlay） |
| `onScreenshotCaptured` | 设置面板截图完成回调（PNG 字节；宿主自行保存，插件不写文件/相册） |
| `dispose()` | 释放 |
| `playerState` | `ValueNotifier<CommonPlayerState>` |
| `position` / `duration` | 进度（原生侧约 250ms 节流推送） |

`CommonScaleMode`：`fit` / `fill` / `stretch`

`CommonPlayerState`：`idle` / `buffering` / `ready` / `playing` / `paused` / `completed` / `error`

`CommonAudioTrack` 字段：`index`、`label`、`language`、`selected`

### HTTP 标头 / User-Agent（全平台）

```dart
await controller.setHttpRequestOptions(
  const KineticHttpRequestOptions(
    userAgent: 'MyApp/1.0',
    headers: {'Authorization': 'Bearer …', 'Referer': 'https://example.com/'},
  ),
);
await controller.switchVideoSource(url); // 换源时带上

// 或创建时：
creationParams: {
  'userAgent': 'MyApp/1.0',
  'headers': {'Referer': 'https://example.com/'},
  ...ui.toCreationParams(),
}
```

- Android / iOS / macOS / Windows / Linux：对媒体请求生效。
- Web：渐进式 MP4 **无法**自定义请求头；HLS/DASH 经 xhr 注入。浏览器通常禁止覆盖 `User-Agent`。
- Darwin 仍可用 `sgSetDemuxerOptions` 设 timeout / reconnect；UA/headers 与公共 API 写入同一 pending 袋。

## 视图组件

### CommonVideoPlayerViewBuilder（推荐）

自动创建 PlatformView 并在就绪后回调 controller：

```dart
CommonVideoPlayerViewBuilder(
  url: videoUrl,
  creationParams: {
    ...const KineticUiConfig(
      enableNativeControls: true,
      showFullscreenButton: true,
      showLockButton: true,
      showVolumeToolbar: true,      // 底部喇叭按钮（弹出竖向音量条）
      showSettingsButton: true,     // 底部齿轮按钮（弹出设置面板，含音轨）
      pictureInPictureEnabled: true, // Android 默认开启 PiP
      previewVttUrl: 'https://example.com/thumbs.vtt',
      locale: 'zh', // zh / en / vi / ms / id / fil
    ).toCreationParams(),
  },
  builder: (controller) {
    // 保存 controller 引用
  },
)
```

Android 默认使用 `EagerGestureRecognizer`，原生进度条/音量/亮度手势不会被 Flutter 抢走。若外层需要自定义手势竞争，可传入 `gestureRecognizers` 覆盖默认行为。

### CommonVideoPlayerView（低级）

```dart
CommonVideoPlayerView(
  url: videoUrl,
  onPlatformViewCreated: (viewId) {
    final controller = CommonVideoPlayerFactory.createAuto(viewId);
  },
)
```

## 原生控制栏 UI（双端对齐）

Android（GSY）与 iOS / macOS（SGPlayer）均采用 B 站风格底部控制栏；默认强调色为 B 站粉 `#FB7299`（可通过 `KineticUiConfig.accentColor` 覆盖）。底栏含倍速弹窗；Android Exo 多档源时另显示清晰度（含「自动」）。音量 / 设置 / 倍速 / 画质弹窗 200ms 淡入淡出（随控制栏收起时无动画）。设置面板（一级 / 二级）超出可用高度时可滚动；宽度随内容自适应（最小约 140，不超过播放器），超过 10 个字符的文案（含音轨名）截为省略号。二级「其它设置」含**截图**（全平台，当前帧不含控制栏；PNG 字节经 `onScreenshotCaptured` 回调，由宿主保存）；Android 另有**录制 GIF**（点开始、再点停止）。Android 第二行弹幕输入框始终显示，点击弹幕图标启用或禁用输入（同时开关弹幕画布）。

控制栏文案语言由公共配置 `KineticUiConfig.locale` 决定（`zh` / `en` / `vi` / `ms` / `id` / `fil`，默认 `zh`；未知码回退中文）。`toCreationParams()` 把 `locale` 与 `KineticChromeStrings` 文案表放进 `creationParams['ui']`。Darwin 走共享源 `SgUiConfig.strings`，不使用独立 `.lproj`。运行时调用 `controller.setLocale(...)` 热切换（不要用 `gsySetUiConfig` 改语言）。

| 能力 | Android | iOS | macOS | Win/Linux | 配置 |
|------|---------|-----|-------|-----------|------|
| 中央播放/暂停 | ✅ | ✅ | ✅ | ✅ | `enableNativeControls` |
| 进度条 + 时间 | ✅ | ✅ | ✅ | ✅ | 原生默认 / Dart 底栏 |
| 单击显隐控制栏 | ✅ | ✅ | ✅ | ✅ | 点击画面空白；播放中约 2.5s 自动隐藏 |
| **音量** | ✅ | ✅ | ✅ | ✅ | 点击**喇叭**弹出**竖向**音量条 |
| **手势** | ✅ | ✅ | ❌ | ❌ | Android / iOS：滑动调进度/亮度/音量。桌面用按钮弹窗 |
| **音轨** | ✅ | ✅ | ✅ | ✅ | 齿轮设置面板；亦可用 Dart `getAudioTracks` / `selectAudioTrack` |
| 全屏 | ✅ | ✅ | ✅ | ✅ 宿主窗口 | `gsyStartFullscreen` / `sgStartFullscreen` / `mpvStartFullscreen` |
| 画中画 PiP | ✅ 默认开启 | ❌ | ❌ | ❌ | `pictureInPictureEnabled`（Android）/ Web 见下 |

> **音量（Android）**：开启 `showVolumeToolbar` 后，画面右侧滑动调节的是**播放器音量**（与喇叭弹窗同源），不再用系统音量条。音量弹窗打开或正在拖动滑轨时，右侧滑动调音量会被暂时禁用，避免与竖向滑轨冲突。

> **音量（iOS）**：右侧滑动同样调节播放器音量（灵敏度与 Android GSY 一致，约 3×）；音量弹窗打开或拖动滑轨时，右侧滑动调音量同样被禁用。

> **音量（macOS）**：无滑动手势；点击喇叭弹出竖向音量条（与齿轮选音轨同一交互模式）。

> **音量持久化**：通过滑轨或 `setVolume()` 设置的音量在暂停/恢复、播放完成重播、换源后会自动恢复，不会回到默认值。

> **音轨**：不在音量弹窗内选择，请在设置面板（齿轮）或 Flutter 层调用 `selectAudioTrack`。

> **截图**：设置面板截图与 `captureFrame()` 返回 PNG 字节（`Uint8List?`）。插件**不**写临时文件、也**不**写入系统相册。设置面板完成后走 `CommonVideoController.onScreenshotCaptured`；`captureFrame()` 把字节返回给调用方。宿主自行写入相册或其它位置。

> **画中画**：SGPlayer 使用自定义渲染，无法接入系统 `AVPictureInPictureController`，iOS / macOS 当前均不支持 PiP。

### 触摸区域说明

控制栏隐藏后，底部透明区域不再拦截点击，右下角与画面其他区域均可单击唤出/隐藏控制栏与中央播放按钮。

## 平台独有 API（向下转型）

公共接口**不包含**以下方法，需显式转型：

### Android — GSYVideoControllerImpl

```dart
if (controller is GSYVideoControllerImpl) {
  await controller.gsySwitchRenderCore(1); // 0=IJK, 1=Exo, 2=System
  await controller.gsyToggleDanmaku(enabled: true);
  await controller.gsyStartFullscreen();
  await controller.gsySetPreviewVttUrl('https://example.com/thumbs.vtt');
  await controller.gsySetUiConfig(const KineticUiConfig(videoTitle: 'Demo'));
  await controller.gsyEnterPictureInPicture(); // 手动进入 PiP
  await controller.gsySetRenderRotation(90);
  await controller.gsySetMirrorHorizontal(enabled: true);
  await controller.gsySetMirrorVertical(enabled: true);
  await controller.gsySetCoverUrl('https://example.com/cover.jpg');
  await controller.gsySetKeepLastFrameWhenComplete(enabled: true);
}
```

#### 公共 UI 配置项（`KineticUiConfig`）

Android / iOS / macOS / Web 共用。创建时经 `creationParams['ui']` 下发；Android 运行时可用 `gsySetUiConfig` 更新外观（**不**改语言）。

| 字段 | 默认 | 说明 |
|------|------|------|
| `enableNativeControls` | `true` | Android / iOS：滑动手势（进度/音量/亮度）；Apple 端同时控制底栏显隐。macOS：底栏显隐，无滑动手势（用进度条 + 喇叭/齿轮按钮） |
| `enableNativeControlsFullscreen` | `true` | Android 全屏手势；Apple 端与 `enableNativeControls` 共用 |
| `showFullscreenButton` | `true` | 全屏按钮 |
| `showLockButton` | `true` | 全屏锁屏按钮（Android） |
| `showVolumeToolbar` | `true` | 喇叭按钮 + 竖向音量弹窗 |
| `showSettingsButton` | `true` | 齿轮按钮 + 两级设置面板（截图；Android 含 GIF） |
| `accentColor` | `#FB7299` | 进度条 / 选中态强调色 |
| `pictureInPictureEnabled` | `true` | Android 播放中切后台自动 PiP（API 26+） |
| `showDragProgressTextOnSeekBar` | `false` | 拖动进度时间文字 |
| `previewVttUrl` | — | 进度条缩略图 WebVTT |
| `dismissControlTime` | `2500` | 播放中控制栏自动隐藏（ms） |
| `videoTitle` | `''` | 标题栏文字 |
| `speed` / `looping` | `1` / `false` | 初始倍速 / 循环 |
| `keepLastFrameWhenComplete` | `false` | 播完保留最后一帧（不盖封面） |
| `coverUrl` | — | 封面 / 海报图 URL |
| `thumbPlay` | `true` | 点击封面开始播放（Android） |
| `ijkEnableAccurateSeek` | `true` | IJK 精确 seek，减轻拖动进度条关键帧回弹（仅 IJK 内核） |
| `cacheWithPlay` | `true` | 边播边缓（HttpProxyCache）； |
| `locale` | `'zh'` | 控制栏语言：`zh` / `en` / `vi` / `ms` / `id` / `fil` |

其他 GSY 能力（滤镜、截图、GIF、字幕、列表等）见 [GSY_FEATURES.md](GSY_FEATURES.md)。

### iOS / macOS — SGVideoControllerImpl

```dart
if (controller is SGVideoControllerImpl) {
  await controller.sgStartFullscreen();
  await controller.sgSetDisplayMode(SgDisplayMode.vrBox);
  await controller.sgSetVrViewport(const SgVrViewport(degrees: 75, sensorEnable: true));
  await controller.sgSetPitch(1.2);
  await controller.sgSetDemuxerOptions(const SgDemuxerOptions(
    timeout: Duration(seconds: 20),
    reconnect: true,
    userAgent: 'MyApp',
    headers: {'Authorization': 'Bearer …'},
  ));
  await controller.sgReplaceWithSegments([
    SgMediaSegment(url: 'https://example.com/a.mp4'),
    SgMediaSegment(url: 'https://example.com/b.mp4'),
  ]);
  await controller.sgSetBackgroundPlaybackPolicy(
    const SgBackgroundPlaybackPolicy(pausesWhenEnteredBackground: false),
  );
  final tracks = await controller.sgGetVideoTracks();
  await controller.sgSelectVideoTrack(0);
  // 缓冲 / 错误
  controller.buffered;      // ValueNotifier<Duration>
  controller.playerError;   // ValueNotifier<String?>
}
```

| API | 说明 |
|-----|------|
| `buffered` / `sgGetBufferedPosition` | 缓冲进度 |
| `playerError` / `sgGetLastError` | 详细错误 |
| `sgSetPitch` / `sgGetPitch` | 音高（约 0.5–2.0） |
| `sgSetDisplayMode` / `sgSetVrViewport` | Plane / VR / VRBox + 视角 |
| `sgSetDemuxerOptions` | FFmpeg 超时 / 重连 / UA / headers |
| `sgReplaceWithSegments` | 多段 `SGMutableAsset` |
| `sgGetVideoTracks` / `sgSelectVideoTrack` | 视频轨 |
| `sgSetBackgroundPlaybackPolicy` | 后台 / 中断策略 |

`creationParams` / `ui` 字段：`enableNativeControls`、`showVolumeToolbar`、`showSettingsButton`、`showFullscreenButton`、`dismissControlTime`、`pictureInPictureEnabled`（Apple 端读取但不生效）、`coverUrl`、`keepLastFrameWhenComplete`、`locale`。

### Windows / Linux — MpvVideoControllerImpl

```dart
if (controller is MpvVideoControllerImpl) {
  await controller.mpvStartFullscreen();
  await controller.mpvSetHwdec('auto-safe');
  await controller.mpvSetPlaylist(urls, startIndex: 0);
  await controller.mpvSetShowType(GsyShowType.ratio16x9);
  await controller.mpvCommand(['show-text', 'hello']);
}
```

| API | 说明 |
|-----|------|
| `mpvStartFullscreen` / `mpvExitFullscreen` | 宿主窗口全屏 |
| `mpvSetHwdec` / `mpvCommand` | 硬解 / 原始 mpv 命令 |
| `mpvSetRenderRotation` / `mpvSetMirrorHorizontal` | 旋转 / 水平镜像 |
| `mpvSetShowType` | 对齐 Android `GsyShowType` |
| `mpvSetPlaylist` / `mpvPlayNextInPlaylist` | 播放列表 / 下一集 |
| `mpvSetSubtitleUrl` / `mpvSetSubtitleEnabled` | 外挂字幕 |
| `mpvListVideoTracks` / `mpvGetNetSpeed` | 视频轨 / 网速 |
| `mpvSetCoverUrl` / `mpvSetWatermarkUrl` / `mpvSetPurePlayMode` | 封面 / 水印 / 纯播 |

详见 [DESKTOP_MPV.md](DESKTOP_MPV.md)。

### Web — ArtplayerVideoControllerImpl

完整插件表、HLS/DASH、Document PiP 与打包说明见 [WEB_ARTPLAYER.md](WEB_ARTPLAYER.md)。

```dart
if (controller is ArtplayerVideoControllerImpl) {
  await controller.togglePip();
  await controller.artEmitDanmuku({'text': 'hi', 'time': 1});
  controller.pipActive;
}
```

| API | 说明 |
|-----|------|
| `togglePip()` / `artToggleDocumentPip()` | Video / Document PiP |
| `artEmitDanmuku` / `artCallPlugin` | 弹幕 / 插件方法 |
| `artAvailablePlugins()` / `artSetUiConfig` | 插件键列表 / UI 更新 |

## 平台差异速查

| 能力 | Android (GSY) | iOS / macOS (SGPlayer) | Web (Artplayer) |
|------|---------------|------------------------|-----------------|
| 循环 | 原生 `isLooping`；`KineticUiConfig.looping` 创建生效 | 结束时 `seek(0)+play`；`KineticUiConfig.looping` / `speed` 创建生效 | Artplayer `loop` / 结束重播 |
| 截图 overlay | `captureFrame(includeOverlay: true)` 含 UI | `includeOverlay` 无效 | 当前帧 canvas（跨域可能失败） |
| 设置内截图 / GIF | 二级截图（`onScreenshotCaptured`）+ GIF | 仅截图（`onScreenshotCaptured`） | — |
| 换源 | 重建播放器 | `replaceWithURL` / `sgReplaceWithSegments` | `art.switchUrl` |
| 全屏 | `gsyStartFullscreen()` | `sgStartFullscreen()`（应用内 overlay） | Artplayer `fullscreen` 控件 |
| 画中画 | 默认开启，需 Manifest + `onUserLeaveHint` | 不支持 | `togglePip()` / Document PiP（见 [WEB_ARTPLAYER.md](WEB_ARTPLAYER.md)） |
| 弹幕 | `gsySetDanmakuUrl` / `gsyToggleDanmaku`（含全屏） | ❌ | `artPlugins.danmuku` |
| 字幕 | `gsySetSubtitleUrl` 等（含全屏） | ❌ | `multipleSubtitles` / `jassub` 等插件 |
| 水印 / 滤镜 / GIF / 广告 | 见 [GSY_FEATURES.md](GSY_FEATURES.md) | ❌ | 广告等见 Web 插件 |
| 列表滑动自动播放 | `GsyAutoPlayVideoList` | ❌ | 自行实现 |
| 音轨 UI | 齿轮设置面板 | 齿轮设置面板 | `AudioTrack` API（浏览器支持时） |
| 音量 UI | 喇叭竖向弹窗 | 喇叭竖向弹窗 | Artplayer 音量控件 |
| 手势调节 | `enableNativeControls` | iOS 同左；macOS 用进度条 + 喇叭/齿轮按钮 | Artplayer gesture（可关） |
| 画面旋转 / 镜像 | `gsySetRenderRotation` / MirrorH/V（含全屏） | `sgSetRenderRotation` / MirrorH/V | 经 `artplayerOptions` 扩展 |
| 封面 | `gsySetCoverUrl` | `sgSetCoverUrl` | `poster` / `coverUrl` |
| 保留最后一帧 | `gsySetKeepLastFrameWhenComplete` | `sgSetKeepLastFrameWhenComplete` | 浏览器默认行为 |
| 缓冲 / 错误详情 | — | `buffered` / `playerError` | `error` 状态 |
| 部署注意 | IJK 默认 arm64；混淆需宿主 ProGuard 规则；需转发 `handleBackPressed` | iOS：真机；macOS 11+；沙盒需 `network.client` | Chrome / Safari / 移动 Web；注意自动播放策略 |

`KineticUiConfig` 字段中，Darwin（SG）实际生效的主要有：`enableNativeControls`、`showVolumeToolbar`、`showSettingsButton`、`showFullscreenButton`、`showLockButton`、`dismissControlTime`、`coverUrl`、`keepLastFrameWhenComplete`、`speed`、`looping`、`accentColor`、`locale`。创建时语言走 `ui.locale` / `ui.strings`；运行时热切换用 `setLocale`，不是 `gsySetUiConfig`。`pictureInPictureEnabled` 在 Apple 端**无效**（无系统 PiP）。`previewVttUrl` / `cacheWithPlay` / `rotateViewAuto` / `thumbPlay` 等为 **Android 专用**。


## 监听状态

```dart
controller.playerState.addListener(() {
  final state = controller.playerState.value;
});

controller.position.addListener(() {
  final pos = controller.position.value;
});
```

## 注意事项

1. 每个 `CommonVideoPlayerViewBuilder` 会在 dispose 时自动释放 controller；若手动持有 controller，需在页面 dispose 时调用 `controller.dispose()`。
2. Android Activity 需转发 `onConfigurationChanged`、`onBackPressed`、`onUserLeaveHint`（见上文 Android 集成节）。
3. iOS 需在真机测试 SGPlayer；macOS 需 11.0+，并开启出站网络 entitlement。
4. 关闭画中画：`KineticUiConfig(pictureInPictureEnabled: false)`。
5. Web 使用 Artplayer.js；独有能力见 [WEB_ARTPLAYER.md](WEB_ARTPLAYER.md)。修改 `web/src` 后执行 `npm run build`。自动播放受浏览器策略限制。
