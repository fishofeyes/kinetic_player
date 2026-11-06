import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../common/common_player_state.dart';
import '../common/common_scale_mode.dart';
import '../common/common_video_controller.dart';
import '../common/common_video_controller_bridge.dart';
import '../common/kinetic_ui_config.dart';
import '../common/platform_guard.dart';
import '../gsy/gsy_chrome_strings.dart';
import '../gsy/gsy_video_features.dart';
import 'mpv_video_features.dart';

class MpvVideoControllerImpl
    extends CommonVideoController
    with CommonVideoControllerBridge {
  factory MpvVideoControllerImpl(int viewId) {
    final existing = _instances[viewId];
    if (existing != null && !existing._isDisposed) {
      existing._retainCount++;
      return existing;
    }
    final created = MpvVideoControllerImpl._(viewId);
    _instances[viewId] = created;
    return created;
  }

  MpvVideoControllerImpl._(this.viewId) : _retainCount = 1 {
    assertDesktopMpvPlatform('MpvVideoControllerImpl');
    _channel = MethodChannel(MpvChannelNames.instance(viewId));
    _channel.setMethodCallHandler(_handleNativeEvents);
  }

  static final Map<int, MpvVideoControllerImpl> _instances =
      <int, MpvVideoControllerImpl>{};

  final int viewId;
  late MethodChannel _channel;
  bool _isDisposed = false;
  int _retainCount;

  @override
  MethodChannel get bridgeChannel => _channel;

  @override
  bool get bridgeDisposed => _isDisposed;

  @override
  final ValueNotifier<CommonPlayerState> playerState =
      ValueNotifier(CommonPlayerState.idle);
  @override
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  @override
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);

  /// Approximate buffered end from libmpv demuxer cache.
  final ValueNotifier<Duration> buffered = ValueNotifier(Duration.zero);

  /// Last native error message (null when cleared / no error).
  final ValueNotifier<String?> playerError = ValueNotifier<String?>(null);

  /// Last native error code (0 when none).
  final ValueNotifier<int> playerErrorCode = ValueNotifier(0);

  /// Chrome language for the Dart overlay (`KineticChromeStrings`).
  final ValueNotifier<String> chromeLocale = ValueNotifier<String>('zh');

  /// Live cover / poster URL for the Dart overlay.
  final ValueNotifier<String?> coverUrl = ValueNotifier<String?>(null);

  /// Flutter watermark overlay URL (not baked into the video).
  final ValueNotifier<String?> watermarkUrl = ValueNotifier<String?>(null);

  /// Hide chrome (Android `gsySetPurePlayMode`).
  final ValueNotifier<bool> purePlayMode = ValueNotifier(false);

  /// Title shown on the Dart overlay.
  final ValueNotifier<String> videoTitle = ValueNotifier('');

  /// Whether the Dart overlay currently shows subtitles as enabled.
  final ValueNotifier<bool> subtitleEnabled = ValueNotifier(true);

  Future<void> _handleNativeEvents(MethodCall call) async {
    if (_isDisposed) return;
    switch (call.method) {
      case 'onPlayerStateChanged':
        final args = call.arguments as Map;
        playerState.value = CommonPlayerState.values[args['state'] as int];
        if (playerState.value != CommonPlayerState.error) {
          playerError.value = null;
          playerErrorCode.value = 0;
        }
      case 'onPositionChanged':
        final args = call.arguments as Map;
        position.value = Duration(milliseconds: args['position'] as int);
        duration.value = Duration(milliseconds: args['duration'] as int);
        buffered.value =
            Duration(milliseconds: args['buffered'] as int? ?? 0);
      case 'onPlayerError':
        final args = call.arguments as Map;
        playerError.value = args['message'] as String?;
        playerErrorCode.value = args['code'] as int? ?? 0;
      case 'onScreenshotCaptured':
        final args = call.arguments as Map?;
        onScreenshotCaptured?.call(screenshotBytesFromNative(args?['bytes']));
    }
  }

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> seekTo(Duration position) =>
      _invoke('seekTo', {'position': position.inMilliseconds});

  @override
  Future<void> setScaleMode(CommonScaleMode mode) =>
      _invoke('setScaleMode', {'mode': mode.index});

  @override
  Future<void> setLocale(String locale) {
    chromeLocale.value = KineticChromeStrings.normalize(locale);
    return super.setLocale(locale);
  }

  /// Toggle the host Flutter window fullscreen (desktop).
  Future<void> mpvStartFullscreen() => _invoke('mpvStartFullscreen');

  Future<void> mpvExitFullscreen() => _invoke('mpvExitFullscreen');

  Future<bool> mpvIsFullscreen() async {
    final result = await _channel.invokeMethod<bool>('mpvIsFullscreen');
    return result ?? false;
  }

  /// libmpv `hwdec` property (`auto-safe`, `no`, `d3d11va`, `vaapi`, …).
  Future<void> mpvSetHwdec(String hwdec) =>
      _invoke('mpvSetHwdec', {'hwdec': hwdec});

  /// Raw libmpv command, e.g. `['show-text', 'hello']`.
  Future<void> mpvCommand(List<String> args) =>
      _invoke('mpvCommand', {'args': args});

  Future<void> mpvSetKeepLastFrameWhenComplete({required bool enabled}) =>
      _invoke('mpvSetKeepLastFrameWhenComplete', {'enabled': enabled});

  Future<void> mpvSetCoverUrl(String? url) async {
    coverUrl.value = url;
    await _invoke('mpvSetCoverUrl', {'url': url});
  }

  Future<void> mpvSetWatermarkUrl(String? url) async {
    watermarkUrl.value = url;
    await _invoke('mpvSetWatermarkUrl', {'url': url});
  }

  Future<void> mpvSetPurePlayMode({required bool enabled}) async {
    purePlayMode.value = enabled;
    await _invoke('mpvSetPurePlayMode', {'enabled': enabled});
  }

  Future<void> mpvSetUiConfig(KineticUiConfig config) async {
    chromeLocale.value = KineticChromeStrings.normalize(config.locale);
    videoTitle.value = config.videoTitle;
    coverUrl.value = config.coverUrl;
    await setRate(config.speed);
    await setLooping(config.looping);
    await mpvSetKeepLastFrameWhenComplete(
      enabled: config.keepLastFrameWhenComplete,
    );
    await _invoke('mpvSetUiConfig', config.toCreationParams());
  }

  Future<void> mpvSetRenderRotation(int degrees) =>
      _invoke('mpvSetRenderRotation', {'degrees': degrees});

  Future<void> mpvSetMirrorHorizontal({required bool enabled}) =>
      _invoke('mpvSetMirrorHorizontal', {'enabled': enabled});

  Future<void> mpvSetMirrorVertical({required bool enabled}) =>
      _invoke('mpvSetMirrorVertical', {'enabled': enabled});

  /// Aspect / crop modes matching Android [GsyShowType].
  Future<void> mpvSetShowType(GsyShowType type) =>
      _invoke('mpvSetShowType', {'mode': type.gsyIndex});

  Future<void> mpvSetPlaylist(
    List<String> urls, {
    int startIndex = 0,
  }) =>
      _invoke('mpvSetPlaylist', {
        'urls': urls,
        'startIndex': startIndex,
      });

  Future<bool> mpvPlayNextInPlaylist() async {
    final result = await _channel.invokeMethod<bool>('mpvPlayNextInPlaylist');
    return result ?? false;
  }

  Future<void> mpvSetAutoPlayNext({required bool enabled}) =>
      _invoke('mpvSetAutoPlayNext', {'enabled': enabled});

  Future<void> mpvSetSubtitleUrl(
    String url, {
    String? mimeType,
  }) =>
      _invoke('mpvSetSubtitleUrl', {
        'url': url,
        'mimeType': mimeType,
      });

  Future<void> mpvSetSubtitleEnabled({required bool enabled}) async {
    subtitleEnabled.value = enabled;
    await _invoke('mpvSetSubtitleEnabled', {'enabled': enabled});
  }

  Future<List<MpvVideoTrack>> mpvListVideoTracks() async {
    final result =
        await _channel.invokeMethod<List<Object?>>('mpvListVideoTracks');
    return result
            ?.whereType<Map<Object?, Object?>>()
            .map(MpvVideoTrack.fromMap)
            .toList() ??
        const <MpvVideoTrack>[];
  }

  /// Select a video track by [index]. Pass `-1` to restore auto.
  Future<bool> mpvSelectVideoTrack(int index) async {
    final result = await _channel
        .invokeMethod<bool>('mpvSelectVideoTrack', {'index': index});
    return result ?? false;
  }

  Future<bool> mpvSetVideoTrackAuto() => mpvSelectVideoTrack(-1);

  Future<MpvNetSpeed> mpvGetNetSpeed() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('mpvGetNetSpeed');
    return MpvNetSpeed(
      bytesPerSecond: result?['bytesPerSecond'] as int? ?? 0,
      text: result?['text'] as String? ?? '',
    );
  }

  @override
  Future<void> dispose() async {
    _retainCount--;
    if (_retainCount > 0) return;
    if (_isDisposed) return;
    _isDisposed = true;
    _instances.remove(viewId);
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod('dispose');
    } catch (_) {}
    playerState.dispose();
    position.dispose();
    duration.dispose();
    buffered.dispose();
    playerError.dispose();
    playerErrorCode.dispose();
    chromeLocale.dispose();
    coverUrl.dispose();
    watermarkUrl.dispose();
    purePlayMode.dispose();
    videoTitle.dispose();
    subtitleEnabled.dispose();
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    if (_isDisposed) return;
    await _channel.invokeMethod(method, arguments);
  }
}
