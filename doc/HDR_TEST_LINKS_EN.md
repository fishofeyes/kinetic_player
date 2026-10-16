# HDR Test Media Links (Direct URLs)

Chinese version: [HDR_TEST_LINKS.md](HDR_TEST_LINKS.md)

> **Note**: This is a **test media list only**. It does **not** mean kinetic_player provides a product HDR API or guarantees HDR output. Android defaults to **IJK**; for adaptive streams prefer **Exo**. HDR depends on device decoders and display.

This document collects stable direct URLs for testing **HDR display output** and **hardware video decoding** performance.

## Copy `.m3u8` / `.mpd` directly into your player

The table below summarizes common test scenarios (click to open the link, or copy the URL as-is):

| Test scenario | Protocol / Format | Direct URL |
|---|---|---|
| Virtual channel (45s seamless switching) | HLS | [`https://virtual-channel.unified-streaming.com/demo_channel-stable.isml/.m3u8`](https://virtual-channel.unified-streaming.com/demo_channel-stable.isml/.m3u8) |
| Virtual channel (45s seamless switching) | DASH | [`https://virtual-channel.unified-streaming.com/demo_channel-stable.isml/.mpd`](https://virtual-channel.unified-streaming.com/demo_channel-stable.isml/.mpd) |
| Standard 4K VOD (Tears of Steel) | HLS | [`https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8`](https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8) |
| Standard 4K VOD (Tears of Steel) | DASH | [`https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.mpd`](https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.mpd) |
| SCTE-35 dynamic ad insertion | HLS | [`https://live-dai.unified-streaming.com/live/scte35/scte35.isml/.m3u8`](https://live-dai.unified-streaming.com/live/scte35/scte35.isml/.m3u8) |
| SCTE-35 dynamic ad insertion | DASH | [`https://live-dai.unified-streaming.com/live/scte35/scte35.isml/.mpd`](https://live-dai.unified-streaming.com/live/scte35/scte35.isml/.mpd) |
| Low-latency live (LL-DASH) | DASH | [`https://livesim.dashif.org/livesim/testpic_2s/Manifest.mpd`](https://livesim.dashif.org/livesim/testpic_2s/Manifest.mpd) |

## 1. Jellyfish 4K HDR test streams

HEVC **10-bit** encoding is a great baseline for validating HDR mapping behavior.

- **10bit high-bitrate stream**
  `https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8`
- **140 Mbps stream**
  `http://www.thismonkey.com/files/2160p/jellyfish-140-mbps-4k-uhd-hevc-10bit.mkv`
- **400 Mbps maximum stream**
  `http://www.thismonkey.com/files/2160p/jellyfish-400-mbps-4k-uhd-hevc-10bit.mkv`

(Note: for very high bitrate, downloading locally is recommended.)

## 2. Dredd (4K HDR) test clips

These clips help validate HDR color handling in movie-like scenarios.

- **Clip 1**
  `http://www.thismonkey.com/files/2160p/dredd-1.mkv`
- **Clip 2**
  `http://www.thismonkey.com/files/2160p/dredd-2.mkv`

## Platform support

| Platform | Core | Real device | Simulator | PiP |
|---|---|---|---|---|
| Android | GSYVideoPlayer 14.0.0 | ✅ | ✅ | ✅ Enabled by default |
| iOS | SGPlayer master | ✅ | ❌ (prebuilt FFmpeg is arm64 only) | ❌ |
| macOS | SGPlayer master | ✅ | ✅ (macosx xcframework) | ❌ |

