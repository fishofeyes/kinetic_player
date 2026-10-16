# GSY advanced feature matrix

Chinese: [GSY_FEATURES.md](GSY_FEATURES.md)

Android uses **GSYVideoPlayer 14.0.0**. This doc lists **fully delivered** Android GSY features only.

## Legend

| Status | Meaning |
|--------|---------|
| ✅ | Fully exposed; embedded and window-fullscreen behavior match unless noted |
| ⚠️ | Host wiring required |
| ❌ | Unsupported |

## Highlights

| Feature | Status | Notes |
|---------|--------|-------|
| GL filters | ✅ | Names from `gsyListEffectFilters()` only (no mosaic) |
| Watermark / danmaku | ✅ | Both work in embedded **and** window fullscreen |
| Pre-roll / mid-roll ads + skip | ✅ | `gsyPlayWithPreRollAd` / `gsySetMidRollAds` / `gsySkipAd` |
| List scroll auto-play | ✅ | `GsyAutoPlayVideoList` (ListView-relative play window; not ListGSYVideoPlayer; not detail seamless) |
| Multi-instance simultaneous play | ❌ | GSY singleton manager |
| Detail seamless handoff | ❌ | Removed (`gsySeamlessHandoffParams` deleted) |
| AliPlayer | ❌ | Optional `gsyvideoplayer-aliplay` module is not included |
| Pure play mode | ✅ | Hides gestures, chrome buttons, volume, settings, title |
| Chrome locale | ✅ | `KineticUiConfig.locale` + `setLocale` / `KineticChromeStrings`: `zh` / `en` / `vi` / `ms` / `id` / `fil` |
| Subtitles / GIF / screenshot / rotation / mirror / filters | ✅ | Follow fullscreen window when applicable. Settings screenshot: PNG bytes + `onScreenshotCaptured` (host saves). Record GIF on Android |
| Android PiP | ✅ | Host Manifest + lifecycle required (⚠️) |
| iOS/macOS PiP | ❌ | |

Mid-roll maps: `{positionMs, adUrl, contentUrl?}`.

See Chinese doc for full tables and examples.
