import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../common/common_audio_track.dart';
import '../common/common_player_state.dart';
import '../common/common_scale_mode.dart';
import '../common/common_video_controller.dart';
import '../common/common_video_controller_bridge.dart';
import '../common/platform_guard.dart';
import 'sg_video_features.dart';

class SGVideoControllerImpl
    extends CommonVideoController
    with CommonVideoControllerBridge {
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

  /// Buffered end position from SGPlayer `SGTimeInfo.cached`.
  final ValueNotifier<Duration> buffered = ValueNotifier(Duration.zero);

  /// Last native error message (null when cleared / no error).
  final ValueNotifier<String?> playerError = ValueNotifier<String?>(null);

  /// Last native error code (0 when none).
  final ValueNotifier<int> playerErrorCode = ValueNotifier(0);

  SGVideoControllerImpl(this.viewId) {
    assertAppleSgPlatform('SGVideoControllerImpl');
    _channel = MethodChannel('com.example.player/sg_$viewId');
    _channel.setMethodCallHandler(_handleNativeEvents);
  }

  Future<void> _handleNativeEvents(MethodCall call) async {
    if (_isDisposed) return;
    switch (call.method) {
      case 'onPlayerStateChanged':
        final args = call.arguments as Map;
        playerState.value =
            CommonPlayerState.values[args['state'] as int];
        if (playerState.value != CommonPlayerState.error) {
          playerError.value = null;
          playerErrorCode.value = 0;
        }
        break;
      case 'onPositionChanged':
        final args = call.arguments as Map;
        position.value =
            Duration(milliseconds: args['position'] as int);
        duration.value =
            Duration(milliseconds: args['duration'] as int);
        final bufferedMs = args['buffered'] as int? ?? 0;
        buffered.value = Duration(milliseconds: bufferedMs);
        break;
      case 'onPlayerError':
        final args = call.arguments as Map;
        playerError.value = args['message'] as String?;
        playerErrorCode.value = args['code'] as int? ?? 0;
        break;
      case 'onScreenshotCaptured':
        final args = call.arguments as Map?;
        onScreenshotCaptured?.call(screenshotBytesFromNative(args?['bytes']));
        break;
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

  /// Enable classic VR (mono) rendering. Prefer [sgSetDisplayMode] for VRBox.
  Future<void> sgSetVRMode({required bool enabled}) =>
      _invoke('sgSetVRMode', {'enabled': enabled});

  Future<void> sgSetDisplayMode(SgDisplayMode mode) =>
      _invoke('sgSetDisplayMode', {'mode': mode.index});

  Future<SgDisplayMode> sgGetDisplayMode() async {
    final result = await _channel.invokeMethod<int>('sgGetDisplayMode');
    final index = result ?? 0;
    if (index < 0 || index >= SgDisplayMode.values.length) {
      return SgDisplayMode.plane;
    }
    return SgDisplayMode.values[index];
  }

  Future<void> sgSetVrViewport(SgVrViewport viewport) =>
      _invoke('sgSetVrViewport', viewport.toMap());

  Future<SgVrViewport> sgGetVrViewport() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('sgGetVrViewport');
    return SgVrViewport.fromMap(result ?? const {});
  }

  Future<void> sgSetPitch(double pitch) =>
      _invoke('sgSetPitch', {'pitch': pitch});

  Future<double> sgGetPitch() async {
    final result = await _channel.invokeMethod<double>('sgGetPitch');
    return result ?? 1;
  }

  Future<List<CommonAudioTrack>> sgGetVideoTracks() async {
    final result =
        await _channel.invokeMethod<List<Object?>>('sgGetVideoTracks');
    return result
            ?.map(
              (item) =>
                  CommonAudioTrack.fromMap(item! as Map<Object?, Object?>),
            )
            .toList() ??
        const [];
  }

  Future<void> sgSelectVideoTrack(int index) =>
      _invoke('sgSelectVideoTrack', {'index': index});

  Future<void> sgSetDemuxerOptions(SgDemuxerOptions options) =>
      _invoke('sgSetDemuxerOptions', options.toMap());

  Future<bool> sgReplaceWithSegments(
    List<SgMediaSegment> segments, {
    bool autoPlay = true,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'sgReplaceWithSegments',
      {
        'segments': segments.map((s) => s.toMap()).toList(),
        'autoPlay': autoPlay,
      },
    );
    return result ?? false;
  }

  Future<void> sgSetBackgroundPlaybackPolicy(
    SgBackgroundPlaybackPolicy policy,
  ) =>
      _invoke('sgSetBackgroundPlaybackPolicy', policy.toMap());

  Future<SgBackgroundPlaybackPolicy> sgGetBackgroundPlaybackPolicy() async {
    final result = await _channel
        .invokeMethod<Map<Object?, Object?>>('sgGetBackgroundPlaybackPolicy');
    return SgBackgroundPlaybackPolicy.fromMap(result ?? const {});
  }

  Future<Duration> sgGetBufferedPosition() async {
    final result = await _channel.invokeMethod<int>('sgGetBufferedPosition');
    return Duration(milliseconds: result ?? 0);
  }

  Future<({String? message, int code})> sgGetLastError() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('sgGetLastError');
    return (
      message: result?['message'] as String?,
      code: result?['code'] as int? ?? 0,
    );
  }

  Future<bool> sgIsSeekable() async {
    final result = await _channel.invokeMethod<bool>('sgIsSeekable');
    return result ?? false;
  }

  Future<void> sgStartFullscreen() => _invoke('sgStartFullscreen');

  Future<void> sgExitFullscreen() => _invoke('sgExitFullscreen');

  Future<bool> sgIsFullscreen() async {
    final result = await _channel.invokeMethod<bool>('sgIsFullscreen');
    return result ?? false;
  }

  Future<void> sgSetRenderRotation(int degrees) =>
      _invoke('sgSetRenderRotation', {'degrees': degrees});

  Future<void> sgSetMirrorHorizontal({required bool enabled}) =>
      _invoke('sgSetMirrorHorizontal', {'enabled': enabled});

  Future<void> sgSetMirrorVertical({required bool enabled}) =>
      _invoke('sgSetMirrorVertical', {'enabled': enabled});

  Future<void> sgSetKeepLastFrameWhenComplete({required bool enabled}) =>
      _invoke('sgSetKeepLastFrameWhenComplete', {'enabled': enabled});

  Future<void> sgSetCoverUrl(String? url) =>
      _invoke('sgSetCoverUrl', {'url': url});

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod('dispose');
    playerState.dispose();
    position.dispose();
    duration.dispose();
    buffered.dispose();
    playerError.dispose();
    playerErrorCode.dispose();
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    if (_isDisposed) return;
    await _channel.invokeMethod(method, arguments);
  }
}
