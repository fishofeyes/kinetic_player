# GSY 高级能力对照表

English version: [GSY_FEATURES_EN.md](GSY_FEATURES_EN.md)

Android 侧基于 **GSYVideoPlayer 14.0.0**（`io.github.carguo:gsyvideoplayer-*`）。iOS / macOS 见 [DARWIN_SGPLAYER.md](DARWIN_SGPLAYER.md)；Web 见 [WEB_ARTPLAYER.md](WEB_ARTPLAYER.md)。本文仅覆盖 **已完整交付** 的 Android GSY 能力。

## 图例

| 状态 | 含义 |
|------|------|
| ✅ | 已通过插件 MethodChannel 完整暴露，内嵌与窗口全屏行为一致（另有说明除外） |
| ⚠️ | 需宿主配合（Manifest / Activity 生命周期等） |
| ❌ | 不支持 |

---

## 1. 滤镜 / 水印

| 能力 | 状态 | API |
|------|------|-----|
| GL 滤镜（`gsyListEffectFilters()` 返回的名称，含 `none`） | ✅ | `gsySetRenderType(GsyRenderType.glSurface)` + `gsySetEffectFilter(name)`；全屏同步 |
| 水印 | ✅ | `gsySetWatermarkUrl(url)` 右上角图片；内嵌与窗口全屏均显示 |

滤镜名称以 `gsyListEffectFilters()` 为准，勿假设未列出的效果（例如不存在「马赛克」）。

---

## 2. 截图 / GIF

| 能力 | 状态 | API |
|------|------|-----|
| 视频帧截图 | ✅ | `captureFrame()`（公共 API；全屏时截当前全屏窗；返回 PNG 字节）。设置面板二级「截图」同一能力，完成后 `onScreenshotCaptured`（宿主自行保存） |
| 播放器 UI 组合截图 | ✅ | `captureFrame(includeOverlay: true)` |
| 保存截图到文件 | ✅ | `gsySaveScreenshot()`（缓存 PNG 路径） |
| 生成 GIF | ✅ | `gsyStartGifRecording()` → `gsyStopGifRecording()`（全屏时录当前全屏窗；缓存路径）。设置面板「录制 GIF」同一能力（点开始、再点停止） |

---

## 3. 列表 / 旋转 / 倍速 / 网速

| 能力 | 状态 | API |
|------|------|-----|
| 列表播放 / 连续播放 | ✅ | `creationParams['playlist']` / `gsySetPlaylist()` / `gsyPlayNextInPlaylist()` |
| 列表滑动自动播放 | ✅ | `GsyAutoPlayVideoList` / `GsyAutoPlayCoordinator`（相对 ListView 可见区；仅活跃 cell 挂载 PlatformView）。**不是** `ListGSYVideoPlayer`，**不是**详情页无缝 |
| 重力 / 手动旋转 | ✅ | `KineticUiConfig.rotateViewAuto` + Activity `configChanges` 转发 |
| 手动旋转 0/90/180/270 | ✅ | `gsySetRenderRotation(degrees)`；全屏同步。Android 依赖 GSY MeasureHelper 重测布局 |
| 水平 / 垂直镜像 | ✅ | `gsySetMirrorHorizontal` / `gsySetMirrorVertical`；全屏同步 |
| 快播 / 慢播 | ✅ | `setRate()` 或 `KineticUiConfig.speed` |
| 网络加载速度 | ✅ | `gsyGetNetSpeed()` |
| 完成后保留最后一帧 | ✅ | `KineticUiConfig.keepLastFrameWhenComplete` |
| 视频封面 | ✅ | `KineticUiConfig.coverUrl` / `gsySetCoverUrl` |

---

## 4. 显示比例

| 能力 | 状态 | API |
|------|------|-----|
| 默认 / 16:9 / 4:3 / 填充 / 拉伸 / 18:9 | ✅ | `setScaleMode()` 或 `gsySetGsyShowType(GsyShowType.*)` |

---

## 5. 播放内核

| 内核 | 状态 | API |
|------|------|-----|
| IJKPlayer | ✅ | `gsySwitchRenderCore(GsyRenderCore.ijk)`（**插件默认**；Maven 包为 **arm64**） |
| Media3 (Exo2) | ✅ | `gsySwitchRenderCore(GsyRenderCore.exo)` |
| MediaPlayer | ✅ | `gsySwitchRenderCore(GsyRenderCore.system)` |
| AliPlayer | ❌ | 插件未引入可选 gsyvideoplayer-aliplay 模块 |

**大文件 / 远程 MKV**：`cacheWithPlay: true`（默认）走 HttpProxyCache，大文件易超时；请设 `cacheWithPlay: false`。

**音轨**：`getAudioTracks()` / `selectAudioTrack`（Exo / IJK；System 内核通常为空）。

---

## 6. 布局 / 纯播放 / 弹幕

| 能力 | 状态 | API |
|------|------|-----|
| 全屏 / 非全屏两套布局 | ✅ | `startWindowFullscreen` + `KineticUiConfig` |
| 无控件纯播放 | ✅ | `gsySetPurePlayMode(true)` 关闭手势、全屏/锁、喇叭、齿轮与标题 |
| 弹幕 | ✅ | `gsySetDanmakuUrl` + `gsyToggleDanmaku`（B 站 XML）；**内嵌与窗口全屏均显示并同步进度** |
| B 站风格控制栏 | ✅ | 竖向音量 + 设置面板（音轨 / 截图 / GIF）；弹窗 200ms 淡入淡出；设置宽度自适应、超 10 字省略；控制栏语言走 `KineticUiConfig.locale` / `setLocale` |

---

## 7. 单例 / 列表自动播放

| 能力 | 状态 | 说明 |
|------|------|------|
| 单例播放释放 | ✅ | `gsyReleaseAllVideos()` |
| 多实例同时播放 | ❌ | GSY `GSYVideoManager` 为单例，本插件**不支持**产品级多路同播 |
| 列表滑动自动播放 | ✅ | 见 §3 `GsyAutoPlayVideoList` |

---

## 8. 小窗口 / PiP

| 能力 | 状态 | API / 说明 |
|------|------|------------|
| Android 画中画 | ✅ | `pictureInPictureEnabled: true`（默认）；播放中切后台进入 |
| 手动 PiP | ✅ | `gsyEnterPictureInPicture()` |
| 宿主 Manifest / Activity | ⚠️ | 见 [USAGE.md](USAGE.md) |
| iOS / macOS 画中画 | ❌ | SGPlayer 自定义渲染 |

---

## 9. 广告

| 能力 | 状态 | API |
|------|------|-----|
| 片头广告 + 跳过 | ✅ | `gsyPlayWithPreRollAd(adUrl:, contentUrl:, skipAfter:)`；倒计时后可点「跳过广告」；全屏可用 |
| 中间插入广告 | ✅ | `gsySetMidRollAds([{positionMs, adUrl, contentUrl?}])`；到点播广告后恢复正片进度；亦可用 `gsySkipAd()` |
| 手动跳过 | ✅ | `gsySkipAd()` |

---

## 10. 字幕

| 能力 | 状态 | API |
|------|------|-----|
| 外挂 SRT/WebVTT | ✅ | `gsySetSubtitleUrl`；全屏同步 |
| 启用 / 禁用 | ✅ | `gsySetSubtitleEnabled` |
| Exo 内嵌字幕桥接 | ✅ | `gsySetEmbeddedSubtitleText` |

---

## 11. DASH / 自适应清晰度

| 能力 | 状态 | 说明 |
|------|------|------|
| Exo DASH / HLS | ✅ | Exo 内核 + URL |
| 轨道切换 API | ✅ | `gsyListExoVideoTracks` / `gsySelectExoVideoTrack`（`-1` 或 `gsySetExoVideoTrackAuto` = 自动）；原生底栏清晰度按钮 |

---

## 明确不做

- 详情页无缝切换（已移除 `gsySeamlessHandoffParams`）
- 多实例同播、AliPlayer、自定义比例 `customRatio`

## 快速示例

```dart
if (controller is GSYVideoControllerImpl) {
  await controller.gsySetRenderType(GsyRenderType.glSurface);
  await controller.gsySetEffectFilter('gaussianBlur');
  await controller.gsySetWatermarkUrl('https://example.com/wm.png');
  await controller.gsySetDanmakuUrl('https://example.com/danmaku.xml');
  await controller.gsyToggleDanmaku(enabled: true);
  await controller.gsyPlayWithPreRollAd(
    adUrl: 'https://example.com/ad.mp4',
    contentUrl: 'https://example.com/main.mp4',
    skipAfter: const Duration(seconds: 5),
  );
  await controller.gsySetMidRollAds([
    {'positionMs': 30000, 'adUrl': 'https://example.com/mid.mp4'},
  ]);
}
```
