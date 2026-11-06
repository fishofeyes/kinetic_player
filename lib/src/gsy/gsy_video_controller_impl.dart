import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gsy_video_features.dart';
import '../common/common_player_state.dart';
import '../common/common_scale_mode.dart';
import '../common/common_video_controller.dart';
import '../common/common_video_controller_bridge.dart';
import '../common/kinetic_ui_config.dart';
import '../common/platform_guard.dart';

class GSYVideoControllerImpl
    extends CommonVideoController
    with CommonVideoControllerBridge {
  GSYVideoControllerImpl(this.viewId) {
    assertAndroidPlatform('GSYVideoControllerImpl');
    _channel = MethodChannel('com.example.player/gsy_$viewId');
    _channel.setMethodCallHandler(_handleNativeEvents);
  }

  final int viewId;
  late MethodChannel _channel;
  bool _isDisposed = false;

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

  Future<void> _handleNativeEvents(MethodCall call) async {
    if (_isDisposed) return;
    switch (call.method) {
      case 'onPlayerStateChanged':
        final args = call.arguments as Map;
        playerState.value = CommonPlayerState.values[args['state'] as int];
      case 'onPositionChanged':
        final args = call.arguments as Map;
        position.value = Duration(milliseconds: args['position'] as int);
        duration.value = Duration(milliseconds: args['duration'] as int);
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

  Future<void> gsySwitchRenderCore(GsyRenderCore core) =>
      _invoke('gsySwitchRenderCore', {'core': core.gsyIndex});

  Future<void> gsyToggleDanmaku({required bool enabled}) =>
      _invoke('gsyToggleDanmaku', {'enabled': enabled});

  Future<void> gsyStartFullscreen() => _invoke('gsyStartFullscreen');

  Future<void> gsySetPreviewVttUrl(String? url) =>
      _invoke('gsySetPreviewVttUrl', {'url': url});

  Future<void> gsySetUiConfig(KineticUiConfig config) =>
      _invoke('gsySetUiConfig', config.toCreationParams());

  Future<void> gsySetGsyShowType(GsyShowType type) =>
      _invoke('gsySetGsyShowType', {
        'mode': type.gsyIndex,
      });

  Future<void> gsySetRenderType(GsyRenderType type) =>
      _invoke('gsySetRenderType', {'renderType': type.gsyIndex});

  Future<void> gsySetEffectFilter(GsyEffectFilterName name) =>
      _invoke('gsySetEffectFilter', {'name': name});

  Future<List<String>> gsyListEffectFilters() async {
    final result = await _channel.invokeMethod<List<Object?>>('gsyListEffectFilters');
    return result?.cast<String>() ?? const <String>[];
  }

  Future<void> gsySetRenderRotation(int degrees) =>
      _invoke('gsySetRenderRotation', {'degrees': degrees});

  Future<void> gsySetMirrorHorizontal({required bool enabled}) =>
      _invoke('gsySetMirrorHorizontal', {'enabled': enabled});

  Future<void> gsySetMirrorVertical({required bool enabled}) =>
      _invoke('gsySetMirrorVertical', {'enabled': enabled});

  /// Keep the last rendered frame when playback completes.
  Future<void> gsySetKeepLastFrameWhenComplete({required bool enabled}) =>
      _invoke('gsySetKeepLastFrameWhenComplete', {'enabled': enabled});

  /// Set cover / poster image URL (null to clear).
  Future<void> gsySetCoverUrl(String? url) =>
      _invoke('gsySetCoverUrl', {'url': url});

  Future<GsyNetSpeed> gsyGetNetSpeed() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('gsyGetNetSpeed');
    return GsyNetSpeed(
      bytesPerSecond: result?['bytesPerSecond'] as int? ?? 0,
      text: result?['text'] as String? ?? '',
    );
  }

  Future<void> gsySetSubtitleUrl(
    String url, {
    String? mimeType,
  }) =>
      _invoke('gsySetSubtitleUrl', {
        'url': url,
        'mimeType': mimeType,
      });

  Future<void> gsySetSubtitleEnabled({required bool enabled}) =>
      _invoke('gsySetSubtitleEnabled', {'enabled': enabled});

  Future<void> gsySetEmbeddedSubtitleText(String? text) =>
      _invoke('gsySetEmbeddedSubtitleText', {'text': text});

  Future<String?> gsySaveScreenshot({
    bool withView = false,
    bool high = false,
  }) async {
    return _channel.invokeMethod<String>('gsySaveScreenshot', {
      'withView': withView,
      'high': high,
    });
  }

  Future<void> gsyStartGifRecording() => _invoke('gsyStartGifRecording');

  Future<String?> gsyStopGifRecording() =>
      _channel.invokeMethod<String>('gsyStopGifRecording');

  Future<void> gsySetPlaylist(
    List<String> urls, {
    int startIndex = 0,
  }) =>
      _invoke('gsySetPlaylist', {
        'urls': urls,
        'startIndex': startIndex,
      });

  Future<bool> gsyPlayNextInPlaylist() async {
    final result = await _channel.invokeMethod<bool>('gsyPlayNextInPlaylist');
    return result ?? false;
  }

  Future<void> gsyPlayWithPreRollAd({
    required String adUrl,
    required String contentUrl,
    Duration skipAfter = const Duration(seconds: 5),
  }) =>
      _invoke('gsyPlayWithPreRollAd', {
        'adUrl': adUrl,
        'contentUrl': contentUrl,
        'skipAfterMs': skipAfter.inMilliseconds,
      });

  Future<void> gsySkipAd() => _invoke('gsySkipAd');

  Future<void> gsySetPurePlayMode({required bool enabled}) =>
      _invoke('gsySetPurePlayMode', {'enabled': enabled});

  Future<bool> gsyEnterPictureInPicture() async {
    final result = await _channel.invokeMethod<bool>('gsyEnterPictureInPicture');
    return result ?? false;
  }

  Future<void> gsyReleaseAllVideos() => _invoke('gsyReleaseAllVideos');

  Future<void> gsySetDanmakuUrl(String? url) =>
      _invoke('gsySetDanmakuUrl', {'url': url});

  /// Mid-roll ads. Each map: `positionMs`, `adUrl`, optional `contentUrl`.
  Future<void> gsySetMidRollAds(List<Map<String, dynamic>> ads) =>
      _invoke('gsySetMidRollAds', {'ads': ads});

  Future<List<Map<String, dynamic>>> gsyListExoVideoTracks() async {
    final result =
        await _channel.invokeMethod<List<Object?>>('gsyListExoVideoTracks');
    return result?.cast<Map<String, dynamic>>() ?? const [];
  }

  /// Select Exo video track by [index]. Pass `-1` to restore Auto (ABR).
  Future<bool> gsySelectExoVideoTrack(int index) async {
    final result =
        await _channel.invokeMethod<bool>('gsySelectExoVideoTrack', {'index': index});
    return result ?? false;
  }

  /// Restore Exo adaptive quality selection (same as [gsySelectExoVideoTrack](-1)).
  Future<bool> gsySetExoVideoTrackAuto() => gsySelectExoVideoTrack(-1);

  Future<void> gsySetWatermarkUrl(String? url) =>
      _invoke('gsySetWatermarkUrl', {'url': url});

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod('dispose');
    playerState.dispose();
    position.dispose();
    duration.dispose();
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    if (_isDisposed) return;
    await _channel.invokeMethod(method, arguments);
  }
}
