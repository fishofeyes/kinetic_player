# iOS / macOS SGPlayer 集成（Darwin）

English version: [DARWIN_SGPLAYER_EN.md](DARWIN_SGPLAYER_EN.md)

kinetic_player 在 **iOS** 与 **macOS** 上共用同一套 SGPlayer 集成方案（`sharedDarwinSource`）：

- 源码：`darwin/kinetic_player/Sources/`（`SgPlayerKit`、`SgNativePlayerBridge`、`kinetic_player`）
- 脚本：`darwin/scripts/sgplayer/`（统一入口，参数 `ios` | `macos`）
- 产物：`darwin/Frameworks/{ios,macos}/SGPlayer.xcframework`
- Manifest：`darwin/sgplayer/manifest.{ios,macos}.json`
- 配置：`darwin/kinetic_player/Package.swift`、`darwin/kinetic_player.podspec`

内核：[wanwenfeng4798/SGPlayer](https://github.com/wanwenfeng4798/SGPlayer)（master）。

## 平台对照

| 项 | iOS | macOS |
|----|-----|-------|
| 最低系统 | iOS 13 | **macOS 11**（控制栏 SF Symbols） |
| Dart 视图 | `UiKitView` | `AppKitView` |
| 产物 | `darwin/Frameworks/ios/SGPlayer.xcframework` | `darwin/Frameworks/macos/SGPlayer.xcframework` |
| Manifest | `darwin/sgplayer/manifest.ios.json` | `darwin/sgplayer/manifest.macos.json` |
| Release 附件 | `SGPlayer.xcframework.zip` | `SGPlayer-macOS.xcframework.zip` |
| Release tag | `sgplayer-v1.0.0` | `sgplayer-macos-v1.0.0` |
| 本地编译 | `./build.sh iOS` + scheme `SGPlayer iOS` | `./build.sh macOS` + scheme `SGPlayer macOS` |
| 模拟器 | ❌（FFmpeg 仅真机 arm64） | ✅（`macosx` arm64 + x86_64） |
| 画中画 | ❌ | ❌ |
| 出站网络（Example） | ATS / 系统网络 | App Sandbox 需 `com.apple.security.network.client` |

其余能力（底栏、音轨、封面、SG API）两端同源；设置面板二级含**截图**（不含 GIF；PNG 字节 + `onScreenshotCaptured`）；音量 / 设置 / 倍速弹窗 200ms 淡入淡出；设置宽度自适应、超 10 字省略。**滑动手势仅 iOS**（macOS 用进度条 + 喇叭/齿轮按钮，见 [USAGE.md](USAGE.md)）。控制栏文案由 `KineticUiConfig.locale` / `setLocale` 经 `SgUiConfig.strings` 下发（共享 Darwin，无独立 `.lproj`）。Android 独有能力见 [GSY_FEATURES.md](GSY_FEATURES.md)；Web 见 [WEB_ARTPLAYER.md](WEB_ARTPLAYER.md)。

## 目录结构

```
darwin/
  kinetic_player.podspec     ← 唯一 CocoaPods（ios + osx）
  kinetic_player/
    Package.swift            ← 唯一 SPM（双平台 + 条件 binaryTarget）
    Sources/
      kinetic_player/        ← KineticPlayerPlugin + PrivacyInfo
      SgPlayerKit/           ← Swift UI / 播放逻辑
      SgNativePlayerBridge/  ← ObjC 桥
  scripts/sgplayer/          ← 统一 bash（build / download / ensure / generate / package / prebuild）
  sgplayer/
    manifest.ios.json
    manifest.macos.json
  Frameworks/
    ios/SGPlayer.xcframework
    macos/SGPlayer.xcframework
  third_party/SGPlayer/      ← 本地编译时的源码克隆（gitignore）
```

`pubspec.yaml` 中 iOS / macOS 均设置 `sharedDarwinSource: true`，无单独的 `ios/`、`macos/` 插件目录。

统一调用（维护者）：

```bash
bash darwin/scripts/sgplayer/<script>.sh ios|macos
# Package.swift 由 generate_package_swift.sh 一次生成（读两份 manifest）
```

## 能否把 xcframework 提交进 Git？

| 方式 | 是否可行 | 说明 |
|------|----------|------|
| 提交到 `main` | ❌ 不推荐 | GitHub 单文件硬限制约 100 MiB；产物远超 |
| **GitHub Release 附件** | ✅ **推荐** | 单文件最大 2 GiB |
| Git LFS | ⚠️ 可选 | 有带宽配额 |

**结论：** zip 放 Release，在对应 manifest 填写 `download_url` / `sha256`。

## 使用者：获取二进制

两端流程相同，只改平台参数 `ios` 或 `macos`。

### 方式 A — SPM（推荐，pub.dev 开箱即用）

1. 应用 `pubspec.yaml`：

```yaml
dependencies:
  kinetic_player: ^2.1.1   # 或 path / git

flutter:
  config:
    enable-swift-package-manager: true
```

2. `flutter pub get` 后直接 `flutter run`（或 `flutter build macos` / `flutter build ios`）。  
   - **SPM**：`Package.swift` 远程 `binaryTarget` 由 Xcode 自动下载 SGPlayer；宿主 **无需** Scheme Pre-action / 额外脚本  
   - **CocoaPods**：`prepare_command` 自动 `ensure_sgplayer`（下载预编译 → 本地编译回退）  
   - macOS 最低版本 **11.0**（SF Symbols 底栏）；宿主请设置 `MACOSX_DEPLOYMENT_TARGET = 11.0`（见下方 [SPM 包装包最低版本](#spm-包装包最低版本)）

### 方式 B — 维护者手动 / CI（更新 manifest / Frameworks）

更新 Release 附件或 manifest 后：

```bash
bash darwin/scripts/sgplayer/spm_prebuild_hook.sh ios
bash darwin/scripts/sgplayer/spm_prebuild_hook.sh macos
```

仅 ensure（不重写 Package.swift）：

```bash
bash darwin/scripts/sgplayer/ensure_sgplayer.sh ios
bash darwin/scripts/sgplayer/ensure_sgplayer.sh macos
```

`ensure` 顺序：

1. 已存在 `darwin/Frameworks/<platform>/SGPlayer.xcframework` → 跳过构建  
2. 读 manifest `download_url` → 下载解压  
3. 未配置或失败 → 源码编译（首次约 30–60 分钟）

Swift / ObjC 源码直接改 `darwin/kinetic_player/Sources/`（唯一一份），无需再同步副本。

### 方式 C — 环境变量指定 URL

```bash
export KINETIC_PLAYER_SGPLAYER_DOWNLOAD_URL="https://github.com/wanwenfeng4798/kinetic_player/releases/download/sgplayer-v1.0.0/SGPlayer.xcframework.zip"
bash darwin/scripts/sgplayer/ensure_sgplayer.sh ios
```

### 方式 D — CocoaPods

关闭 SPM 时，`darwin/kinetic_player.podspec` 的 `prepare_command` 会分别 `ensure` ios / macos；`vendored_frameworks` 指向 `Frameworks/{ios,macos}/...`。终端用户只需 `pod install`（或由 Flutter 构建触发）。

### 方式 E — 本地编译

```bash
bash darwin/scripts/sgplayer/build_sgplayer.sh ios
bash darwin/scripts/sgplayer/build_sgplayer.sh macos

# 清理（ios 会清 third_party + 产物；macos 只清该平台 Frameworks）
bash darwin/scripts/sgplayer/build_sgplayer.sh ios clean
bash darwin/scripts/sgplayer/build_sgplayer.sh macos clean
```

## 维护者：发布预编译包

### 1. 构建

```bash
bash darwin/scripts/sgplayer/build_sgplayer.sh ios    # → darwin/Frameworks/ios/
bash darwin/scripts/sgplayer/build_sgplayer.sh macos  # → darwin/Frameworks/macos/
```

### 2. 打包并写回 manifest + Package.swift

```bash
bash darwin/scripts/sgplayer/package_sgplayer_release.sh ios
bash darwin/scripts/sgplayer/package_sgplayer_release.sh macos
```

输出示例：

- iOS：`darwin/Frameworks/ios/SGPlayer.xcframework.zip` + `.sha256`，更新 `manifest.ios.json`，并重写统一的 `darwin/kinetic_player/Package.swift`
- macOS：`darwin/Frameworks/macos/SGPlayer-macOS.xcframework.zip` + `.sha256`，更新 `manifest.macos.json`，并重写统一的 `darwin/kinetic_player/Package.swift`

### 3. 创建 GitHub Release

```bash
gh release create sgplayer-v1.0.0 \
  darwin/Frameworks/ios/SGPlayer.xcframework.zip \
  --repo wanwenfeng4798/kinetic_player \
  --title "SGPlayer iOS prebuilt v1.0.0"

gh release create sgplayer-macos-v1.0.0 \
  darwin/Frameworks/macos/SGPlayer-macOS.xcframework.zip \
  --repo wanwenfeng4798/kinetic_player \
  --title "SGPlayer macOS prebuilt v1.0.0"
```

### 4. 提交（不要提交 zip）

- `darwin/sgplayer/manifest.ios.json` / `manifest.macos.json`
- `darwin/kinetic_player/Package.swift`

### 5. 验证下载

```bash
rm -rf darwin/Frameworks/ios/SGPlayer.xcframework
bash darwin/scripts/sgplayer/download_sgplayer.sh ios
ls darwin/Frameworks/ios/SGPlayer.xcframework
```

手动改 manifest 后：

```bash
bash darwin/scripts/sgplayer/generate_package_swift.sh
```

## manifest 字段

| 字段 | 说明 |
|------|------|
| `version` | 预编译版本，与 Release tag 对应 |
| `sgplayer_branch` | SGPlayer 分支（本地编译） |
| `sgplayer_repository` | SGPlayer git 地址 |
| `asset_name` | Release 附件名 |
| `download_url` | HTTPS 下载地址；空则跳过下载、走本地编译 |
| `sha256` | zip SHA256（与 `swift package compute-checksum` 一致） |

## SPM 说明（sharedDarwinSource）

Flutter 将 `darwin/kinetic_player` 软链到 `ephemeral/Packages`。因此：

- 所有源码与 `Package.swift` 都在该包根下（唯一一份）
- `Package.swift` 含 `SGPlayer_iOS` / `SGPlayer_macOS` 两个 remote `binaryTarget`，按平台条件链接
- 包内 `SGPlayer.xcframework` 仅作本地 / CocoaPods 回退，仍 `.gitignore`；SPM 消费者走远程 `binaryTarget`

Swift 目标结构：`SgNativePlayerBridge`（ObjC）+ `kinetic_player`（含 SgPlayerKit Swift，依赖 `FlutterFramework`）。中间独立 Swift target 拿不到 Flutter 框架搜索路径。

## 平台视图 API（iOS vs macOS）

两端都支持 Flutter 平台视图，但原生 API 形态不同：

| | iOS | macOS |
|--|-----|-------|
| 协议 | `FlutterPlatformView` | 无同名协议 |
| Factory 返回 | `FlutterPlatformView` | **`NSView`** |
| 创建方法 | `create(withFrame:viewIdentifier:arguments:)` | `create(withViewIdentifier:arguments:)` |

实现见 `darwin/.../SgVideoPlatformView.swift`（`#if os` 分支）。

## SPM 包装包最低版本

`flutter pub get` 会生成 `FlutterGeneratedPluginSwiftPackage`，其中 macOS 默认为 **10.15**、iOS 默认为 **12.0**，而本插件 `Package.swift` 要求 **macOS 11.0** / **iOS 13.0**。若直接在 Xcode 构建出现类似：

```text
The package product 'kinetic-player' requires minimum platform version 11.0 for the macOS platform,
but this target supports 10.15
```

请任选其一：

### 方式 1 — 手动改包装包（Xcode 直编前）

编辑宿主 App 下的 ephemeral 文件（**每次 `flutter pub get` 后可能被重置，需重新改**）：

| 平台 | 路径 |
|------|------|
| macOS | `macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift` |
| iOS | `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift` |

将 `platforms` 中的默认值改为与宿主一致，例如 macOS：

```swift
    platforms: [
        .macOS("11.0")   // 原为 "10.15"
    ],
```

iOS 若遇同类错误，将 `.iOS("12.0")` 改为 `.iOS("13.0")`。

### 方式 2 — 用 Flutter 命令自动同步（推荐）

宿主已设 `MACOSX_DEPLOYMENT_TARGET = 11.0` 时，先执行一次：

```bash
flutter build macos --config-only   # 或 flutter run -d macos
flutter build ios --config-only     # 或 flutter run（iOS）
```

Flutter 会把包装包最低版本抬升到与宿主 deployment target 一致。

### 方式 3 — 插件脚本（维护者 / CI）

```bash
bash darwin/scripts/sgplayer/sync_flutter_spm_wrapper.sh [flutter_app_root]
```

## Example 注意

- **macOS**：`DebugProfile.entitlements` / `Release.entitlements` 需 `com.apple.security.network.client`，否则沙盒下无法拉远程片源。
- **Example 集成**：Example 与终端用户一致，默认 **SPM**（`enable-swift-package-manager: true`），无 Podfile；SGPlayer 由 `Package.swift` 远程 `binaryTarget` 自动下载。
- **macOS 部署版本**：插件 `Package.swift` / podspec 均为 **11.0**；宿主 App 设置 `MACOSX_DEPLOYMENT_TARGET = 11.0`。SPM 包装包版本见 [SPM 包装包最低版本](#spm-包装包最低版本)。
- `Failed to foreground app; open returned 1`：多为 Flutter 拉前台失败，可从 Dock 点开 App，一般与播放无关。

## 已暴露的 SG 高级能力

见 [USAGE.md](USAGE.md) 与 `lib/src/sg/sg_video_features.dart`（iOS / macOS 共用 Dart 侧 SG API）。

## 第三方许可

SGPlayer 遵循 [wanwenfeng4798/SGPlayer](https://github.com/wanwenfeng4798/SGPlayer) 仓库许可证；本插件封装为 [MIT](../LICENSE)。
