# Kinetic：保留原类名的 video_player 使用方式

业务入口继续使用 `CommonVideoController`、`CommonVideoPlayerView`。
原来的 `CommonVideoPlayerViewBuilder`、`CommonVideoPlayerFactory`、`CommonPlayerState`、`CommonVideoSize`、各平台 `GSYVideoControllerImpl` / `SGVideoControllerImpl` / `MpvVideoControllerImpl` / `ArtplayerVideoControllerImpl` 等类名均未改变。

## 接入与使用

```yaml
dependencies:
  kinetic_player:
    path: /Users/fishofeyes/Downloads/kinetic_player
```

原包仍要求 Flutter >= 3.47、Dart >= 3.13。新增依赖保留为 `video_player: ^2.14.1` 与 `video_player_platform_interface: ^6.9.0`。

```dart
import 'package:kinetic_player/kinetic_player.dart';

final controller = CommonVideoController.networkUrl(
  Uri.parse(videoUrl),
  httpHeaders: {'Authorization': token},
);
await controller.initialize();
await controller.play();
```

来源构造器自动启用内部 Kinetic 播放后端，无需业务层换用其他控制器类名或手动注册。

本地文件、资源和 Android content URI：

```dart
final local = CommonVideoController.file(File(videoPath));
final asset = CommonVideoController.asset('assets/videos/demo.mp4');
final packageAsset = CommonVideoController.asset('demo.mp4', package: 'my_package');
final content = CommonVideoController.contentUri(contentUri); // 仅 Android
```

`File` 需导入 `dart:io`，仅用于原生平台。Web 使用网络、blob 或 asset；资源需要在业务 pubspec 声明。

在 StatefulWidget 中持有、初始化、释放控制器。异步完成后先检查 `mounted`：

```dart
ValueListenableBuilder(
  valueListenable: controller,
  builder: (context, value, child) {
    if (value.hasError) return errorWidget;
    if (!value.isInitialized) return loadingWidget;
    return Center(
      child: AspectRatio(
        aspectRatio: value.aspectRatio,
        child: CommonVideoPlayerView(controller: controller),
      ),
    );
  },
)
```

```dart
await controller.pause();
await controller.seekTo(Duration(seconds: 10));
await controller.setVolume(0.5);
await controller.setPlaybackSpeed(1.5);
await controller.setLooping(true);
controller.addListener(onPlayerChanged);
final duration = controller.value.duration;
final position = controller.value.position;
final playing = controller.value.isPlaying;

// 原有公共接口仍可使用。
await controller.setRate(1.5);
await controller.setMute(true);
await controller.setScaleMode(CommonScaleMode.fit);
final size = await controller.getVideoSize();

controller.removeListener(onPlayerChanged);
await controller.dispose();
```

旧的 `playerState`、`position`、`duration` 三个 notifier 也保留；新来源模式同步更新它们。`value` 的数据类型复用官方 `VideoPlayerValue`，没有复制官方状态类。

完整示例：`example/lib/video_player_demo.dart`。`flutter run -t lib/video_player_demo.dart` 在 example 目录运行。

## 与旧接口的关系

| 方式 | 创建与生命周期 |
| --- | --- |
| 新来源构造器 | `CommonVideoController.networkUrl/file/asset/contentUri` → `initialize()` → `CommonVideoPlayerView(controller: ...)`；调用方释放控制器 |
| 原来的视图方式 | `CommonVideoPlayerView(url: ..., onPlatformViewCreated: ...)` → `CommonVideoPlayerFactory.createAuto(viewId)`；原生视图负责原有初始化过程 |
| 原来的 builder | `CommonVideoPlayerViewBuilder` 保留类名和导出路径，负责其创建的控制器的释放 |

同一个视图不能同时传 `controller` 与旧的 URL / creationParams / onPlatformViewCreated。

`initialize()`、`value` 和统一监听用于**新来源构造器**。原有 view-ID 控制器继续通过原有 notifier 监听；没有把旧实例替换成另一种控制器。旧模式调用新增 `initialize/value` 会明确提示使用来源构造器。

各平台控制器的高级专属功能仍通过旧的工厂和具体控制器使用。来源构造器返回公共接口实现，不能向下转型为 `GSYVideoControllerImpl` 等原生 view-ID 控制器。

## 切换与释放

新来源模式的 `switchVideoSource` 会释放旧会话、初始化新会话，并保留公共监听器、音量、倍速与循环设置。`autoPlay` 默认 true。新来源的请求头可提前通过 `setHttpRequestOptions` 设置；首次加载的请求头通过构造器的 `httpHeaders` 传入。

重复调用同一个来源的 `initialize()` 复用同一个 Future。播放会话初始化不依赖渲染视图先挂载。同一个控制器同时只挂载一个播放视图；卸载、重新挂载视图不会重新加载媒体，也不会释放控制器。

页面退出始终调用 `dispose()`，包括初始化失败的情况。新来源模式重复 dispose 不重复释放。初始化过程中退出或换源时，尚未完成的公共初始化 Future 以 `StateError` 结束；调用方应正常捕获异步初始化异常。快速换源会忽略旧来源后续结果、释放被替换的会话。

`CommonVideoPlayerView` 在新来源模式只显示画面，Flutter 操作栏由业务提供。准备阶段不自动播放、Android 不抢音频焦点；开始播放时才申请。默认初始化超时 30 秒，初始化失败同步到 Future 和 `value.hasError`。

## 内部实现与边界

内部保留上一轮的 `KineticVideoPlayer` 平台适配层和官方控制器。这些实现细节不要求业务代码更换原有类名。

来源构造器注册的后端会影响同一 Dart isolate 中后续创建的官方 `VideoPlayerController`。不要在其他后端已有活动控制器时混用，不要在播放中重新注册另一个后端。旧模式本身不会主动注册该后端。

需要直接使用官方控制器的调用方仍可选用 `package:kinetic_player/video_player.dart` + `KineticVideoPlayer.registerWith()`；这是另一个可选入口。

原生播放内核保持不变：Android GSY、iOS/macOS SGPlayer、Web Artplayer、Windows/Linux MPV。新来源模式使用独立播放会话，视图只附加已有会话。Android/iOS/macOS 仍通过原生 PlatformView 显示；桌面 MPV 使用 Texture。

`mixWithOthers=true`、官方后台播放开关、formatHint 和官方高级音轨 / Web 专属配置尚未完整适配。新模式的原有公共音轨、截图、缩放等命令走 Kinetic 原生通道。具体协议、编码、DRM 支持取决于原有内核。没有引入预缓存、下载、业务预初始化或事件上报逻辑。

公共高级命令桥内部需要取得官方控制器的 playerId。官方目前将该属性标记为 visibleForTesting；该依赖限制在内部一处，并通过会话测试覆盖。升级 video_player 时需要重新核对此桥。

## 验证范围

本机 Flutter 3.41.6 / Dart 3.11.4，低于原包 Flutter 3.47 / Dart 3.13 的约束，无法在当前 SDK 完成原包完整依赖解析和原生构建。没有降低原包版本要求，也没有改动全局 Flutter SDK。

在临时验证工程复制修改后的源文件，以 `video_player 2.11.1`、`video_player_platform_interface 6.9.0` 检查兼容接口。临时工程仅为解析旧 SDK 不具备的 `material_ui` 包入口，使用 Flutter Material 的导出替身；替身未写入插件，也不代表真实 material_ui UI 验证。

测试覆盖原接口路由、来源初始化、控制/状态同步、异常/超时、多会话隔离、截图/缩放、换源、重复释放、初始化中退出、快速换源，以及原类名视图卸载/重挂载。测试使用模拟原生 MethodChannel，不等同于真实设备播放。Dart 分析与 Web 示例编译也只针对上述临时兼容环境。

本轮结果：33 项测试全部通过；修改文件、示例及测试的 Dart 分析无问题；使用原类名的示例 Web 编译通过。

上一轮的 Swift 语法解析和 MPV C++ 语法检查已通过；本轮没有修改原生文件。本机还缺少原包 Android SDK/Build Tools 37。真实原生构建、音频焦点及设备播放仍需在满足原包工具链的环境验证。包含原生改动的本地包接入后需要停止应用并完整重新构建，Hot Reload 不会更新原生插件。
