# HDR 视频测试链接汇总

> **说明**：本文件仅为**测试片源清单**，不代表 kinetic_player 提供产品级 HDR API 或保证。Android 默认内核为 **IJK**，HDR/HEVC/HLS 表现因设备与内核而异；自适应流建议切 **Exo**。能否正确显示 HDR 取决于系统解码器与显示链路。

本文件整理了用于测试 HDR 视频显示及播放器硬件解码能力的稳定直链。

## 直接复制以下 `.m3u8` / `.mpd` 到播放器即可

下面表格汇总了常用测试场景（点击链接可跳转，亦可直接复制 URL）。  

| 测试场景 | 协议 / 格式 | 直链 URL |
|---|---|---|
| 虚拟频道 (45s 无缝切换) | HLS | [`https://virtual-channel.unified-streaming.com/demo_channel-stable.isml/.m3u8`](https://virtual-channel.unified-streaming.com/demo_channel-stable.isml/.m3u8) |
| 虚拟频道 (45s 无缝切换) | DASH | [`https://virtual-channel.unified-streaming.com/demo_channel-stable.isml/.mpd`](https://virtual-channel.unified-streaming.com/demo_channel-stable.isml/.mpd) |
| 标准 4K VOD 点播 (Tears of Steel) | HLS | [`https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8`](https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8) |
| 标准 4K VOD 点播 (Tears of Steel) | DASH | [`https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.mpd`](https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.mpd) |
| SCTE-35 动态广告插播 | HLS | [`https://live-dai.unified-streaming.com/live/scte35/scte35.isml/.m3u8`](https://live-dai.unified-streaming.com/live/scte35/scte35.isml/.m3u8) |
| SCTE-35 动态广告插播 | DASH | [`https://live-dai.unified-streaming.com/live/scte35/scte35.isml/.mpd`](https://live-dai.unified-streaming.com/live/scte35/scte35.isml/.mpd) |
| 低延迟直播 (LL-DASH) | DASH | [`https://livesim.dashif.org/livesim/testpic_2s/Manifest.mpd`](https://livesim.dashif.org/livesim/testpic_2s/Manifest.mpd) |

英文版本：见 [doc/HDR_TEST_LINKS_EN.md](HDR_TEST_LINKS_EN.md)。

## 1. Jellyfish 4K HDR 测试流 (水母测试片)

HEVC 10-bit 编码，是发烧友测试显示设备 HDR 映射能力的金标准。

* **10bit 高码率测试
  `https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8`
* **140 Mbps 码率版本**
  `http://www.thismonkey.com/files/2160p/jellyfish-140-mbps-4k-uhd-hevc-10bit.mkv`
* **400 Mbps 极限码率版本**
  `http://www.thismonkey.com/files/2160p/jellyfish-400-mbps-4k-uhd-hevc-10bit.mkv`
*（提示：码率较高，建议下载至本地后播放）*

## 2. 《特警判官》(Dredd) 4K 测试片段

用于测试电影场景下的 HDR 色彩表现。

* **测试片段 1**
  `http://www.thismonkey.com/files/2160p/dredd-1.mkv`
* **测试片段 2**
  `http://www.thismonkey.com/files/2160p/dredd-2.mkv`

## 平台支持

| 平台 | 内核 | 真机 | 模拟器 | 画中画 |
|---|---|---|---|---|
| Android | GSYVideoPlayer 14.0.0 | ✅ | ✅ | ✅ 默认开启 |
| iOS | SGPlayer master | ✅ | ❌（FFmpeg 预编译仅 arm64 真机） | ❌ |
| macOS | SGPlayer master | ✅ | ✅（`macosx` xcframework） | ❌ |

## 许可证

本插件代码采用 [MIT License](LICENSE)。

SGPlayer 为独立第三方项目，其许可证以 [wanwenfeng4798/SGPlayer](https://github.com/wanwenfeng4798/SGPlayer) 仓库为准（fork 自 libobjc/SGPlayer）。

