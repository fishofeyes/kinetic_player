# Web Artplayer 集成与能力

English version: [WEB_ARTPLAYER_EN.md](WEB_ARTPLAYER_EN.md)

kinetic_player 在 **Flutter Web** 上使用 [Artplayer.js **5.4.0**](https://artplayer.org) 作为内核，经 `HtmlElementView` 挂载；公共 API 与 Android / iOS / macOS 一致，Web 独有能力通过 `ArtplayerVideoControllerImpl` / `ArtplayerUiConfig` 暴露，**不污染** `CommonVideoController`。

## 平台对照

| 项 | Web |
|----|-----|
| 内核 | Artplayer.js 5.4.0（`assets/web/kinetic_artplayer.js`） |
| Dart 视图 | `HtmlElementView`（`com.example.player/art_view_ui`） |
| 控制器 | `ArtplayerVideoControllerImpl` |
| 通信 | 进程内 `ArtplayerViewRegistry`（非跨端 MethodChannel） |
| 控制栏 | Artplayer UI（`enableNativeControls` 映射） |
| Video PiP | ✅（`document.pictureInPictureEnabled` + `togglePip()`） |
| Document PiP | ✅（需 `artPlugins.documentPip`） |
| HLS / DASH | ✅（`hls.js` / `dashjs`，`.m3u8` / `.mpd` 自动 `customType`） |
| 多音轨 | ⚠️（依赖浏览器 `audioTracks`；多数普通 MP4 为空） |

公共 API、原生 UI 字段与平台差异总表见 [USAGE.md](USAGE.md)。

## 目录结构

```
web/                              ← npm / TypeScript 源码
  package.json                    ← artplayer 5.4.0 + 官方插件 + hls.js 1.7.3 / dashjs 5.2.1
  src/
    artplayer_adapter.ts          ← KineticArtplayerAdapter
    artplayer_web_bridge.ts       ← Dart JS interop 桥
    plugins.ts                    ← artPlugins 注册表
    stream_types.ts               ← HLS / DASH customType
    index.ts
assets/web/kinetic_artplayer.js   ← esbuild 产物（plugin asset）
lib/kinetic_player_web.dart       ← 注册 HtmlElementView
lib/src/web/                      ← Dart 控制器 / 配置 / Host
```

## 集成

无需额外原生工程。Example：

```bash
cd example
flutter pub get
flutter run -d chrome
```

宿主依赖与其它平台相同：

```yaml
dependencies:
  kinetic_player:
    path: ../kinetic_player
```

### 修改 TS 后重新打包

```bash
cd web
npm install
npm run build   # → assets/web/kinetic_artplayer.js
```

当前工具链：`typescript` 7.0.2、`esbuild` 0.28.1。

## 配置：ArtplayerUiConfig

```dart
CommonVideoPlayerViewBuilder(
  url: videoUrl, // .m3u8 / .mpd 自动挂 HLS/DASH
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
        // 透传给 new Artplayer({...})：theme / layers 等
      },
      webCustomExtensions: {
        // 宿主扩展钩子（可选）
      },
    ).toCreationParams(),
  },
  builder: (controller) { /* … */ },
);
```

| 字段 | 说明 |
|------|------|
| `ui` | 复用 `KineticUiConfig`（控制栏 / PiP / 封面 / 循环 / 倍速 / `locale`）。语言随 `ui.locale` + `ui.strings` 下发，映射 Artplayer `lang`；`vi` / `ms` / `fil` 用同一份 `KineticChromeStrings` 补 i18n |
| `artPlugins` | 声明式启用官方插件（见下表） |
| `artplayerOptions` | 透传 Artplayer Option |
| `webCustomExtensions` | 宿主自定义扩展；也可内嵌 `artPlugins` |

## 官方插件（artPlugins）

值：`true` 用默认选项；`Map` 传入插件构造参数。键见 `ArtplayerPluginKeys`。

| 键 | npm 包 | 说明 |
|----|--------|------|
| `danmuku` | `artplayer-plugin-danmuku` | 弹幕 |
| `danmukuMask` | `artplayer-plugin-danmuku-mask` | 弹幕遮罩（**CDN 懒加载** MediaPipe） |
| `hlsControl` | `artplayer-plugin-hls-control` | HLS 清晰度 / 音轨面板（需 HLS 流） |
| `dashControl` | `artplayer-plugin-dash-control` | DASH 清晰度面板（需 MPD） |
| `vttThumbnail` | `artplayer-plugin-vtt-thumbnail` | 进度条 VTT 缩略图（`vtt` URL） |
| `multipleSubtitles` | `artplayer-plugin-multiple-subtitles` | 多字幕（`subtitles: [...]`） |
| `chromecast` | `artplayer-plugin-chromecast` | Chromecast |
| `vast` | `artplayer-plugin-vast` | VAST（Dart 侧传 `tagUrl` / `url`） |
| `chapter` | `artplayer-plugin-chapter` | 章节标记 |
| `autoThumbnail` | `artplayer-plugin-auto-thumbnail` | 自动生成缩略图 |
| `ambilight` | `artplayer-plugin-ambilight` | 氛围光 |
| `documentPip` | `artplayer-plugin-document-pip` | Document Picture-in-Picture |
| `audioTrack` | `artplayer-plugin-audio-track` | 外挂音轨（需 `url`） |
| `jassub` | `artplayer-plugin-jassub` | ASS/SSA 字幕（JASSUB） |
| `asr` | `artplayer-plugin-asr` | 语音识别字幕辅助 |
| `ads` | `artplayer-plugin-ads` | 贴片广告（需 `source` + `type`） |

> `danmukuMask` 不打进主 bundle，启用时从 jsDelivr 加载，需可访问外网 CDN。

## Web 独有 API（向下转型）

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

| API | 说明 |
|-----|------|
| `togglePip()` | 浏览器 Video PiP |
| `artIsPipSupported()` | `document.pictureInPictureEnabled` |
| `pipActive` | Video PiP 状态 |
| `artToggleDocumentPip()` | Document PiP（需已启用 `documentPip` 插件） |
| `artEmitDanmuku` | 发送弹幕（需已启用 `danmuku`） |
| `artCallPlugin(name, method, {args})` | 调用已加载插件实例方法 |
| `artAvailablePlugins()` | 本构建支持的插件键 |
| `artSetUiConfig` | 运行时更新 UI 字段（插件须在创建时通过 `artPlugins` 启用） |

## 行为说明

- 默认关闭 HTML5 `video.controls`；`enableNativeControls: true` 时使用 Artplayer 控制栏。
- 移动 Web：`playsInline` + `playsinline` / `webkit-playsinline` / `x5-video-player-type=h5`。
- 自动播放失败会先静音再试；仍失败则进入 `error`。
- 进度约 **250ms** 节流推送，与原生一致。
- 多数浏览器对普通 progressive MP4 **不暴露** `audioTracks`，`getAudioTracks()` 可能为空；可用 `artPlugins.audioTrack` 外挂音轨。

## 与原生平台关系

| | Android GSY | iOS / macOS SG | Web Artplayer |
|--|-------------|----------------|---------------|
| 独有文档 | [GSY_FEATURES.md](GSY_FEATURES.md) | [DARWIN_SGPLAYER.md](DARWIN_SGPLAYER.md) | 本文 |
| 独有控制器 | `GSYVideoControllerImpl` | `SGVideoControllerImpl` | `ArtplayerVideoControllerImpl` |
| 弹幕 | `gsyToggleDanmaku` 等（含全屏） | ❌ | `artPlugins.danmuku` |
| 字幕 | `gsySetSubtitleUrl` 等 | ❌ | 字幕类插件 |
| 全屏 | `gsyStartFullscreen` | `sgStartFullscreen` | Artplayer fullscreen 控件 |
| PiP | 系统 Activity PiP | 不支持 | Video / Document PiP |

公共集成与差异总表仍以 [USAGE.md](USAGE.md) 为准。
