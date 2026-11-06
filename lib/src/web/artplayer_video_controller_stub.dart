import 'package:flutter/foundation.dart';

import '../common/common_audio_track.dart';
import '../common/common_player_state.dart';
import '../common/common_scale_mode.dart';
import '../common/common_video_controller.dart';
import '../common/common_video_size.dart';
import '../common/kinetic_http_request_options.dart';
import 'artplayer_ui_config.dart';

/// Stub for non-web platforms. Real implementation is conditionally imported.
class ArtplayerVideoControllerImpl extends CommonVideoController {
  ArtplayerVideoControllerImpl(this.viewId) {
    throw UnsupportedError(
      'ArtplayerVideoControllerImpl is only available on Flutter Web.',
    );
  }

  final int viewId;

  final ValueNotifier<bool> pipActive = ValueNotifier(false);

  @override
  final ValueNotifier<CommonPlayerState> playerState =
      ValueNotifier(CommonPlayerState.idle);
  @override
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  @override
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);

  @override
  Future<void> play() => throw UnimplementedError();
  @override
  Future<void> pause() => throw UnimplementedError();
  @override
  Future<void> stop() => throw UnimplementedError();
  @override
  Future<void> seekTo(Duration position) => throw UnimplementedError();
  @override
  Future<void> setScaleMode(CommonScaleMode mode) => throw UnimplementedError();
  @override
  Future<void> setRate(double rate) => throw UnimplementedError();
  @override
  Future<void> setVolume(double volume) => throw UnimplementedError();
  @override
  Future<void> setMute(bool muted) => throw UnimplementedError();
  @override
  Future<void> switchVideoSource(String url, {bool autoPlay = true}) =>
      throw UnimplementedError();
  @override
  Future<List<CommonAudioTrack>> getAudioTracks() => throw UnimplementedError();
  @override
  Future<void> selectAudioTrack(int index) => throw UnimplementedError();
  @override
  Future<Duration> getDuration() => throw UnimplementedError();
  @override
  Future<Duration> getCurrentPosition() => throw UnimplementedError();
  @override
  Future<CommonVideoSize?> getVideoSize() => throw UnimplementedError();
  @override
  Future<void> setLooping(bool looping) => throw UnimplementedError();
  @override
  Future<void> setLocale(String locale) => throw UnimplementedError();
  @override
  Future<void> setHttpRequestOptions(KineticHttpRequestOptions? options) =>
      throw UnimplementedError();
  @override
  Future<Uint8List?> captureFrame({
    bool highQuality = true,
    bool includeOverlay = false,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> dispose() async {}

  Future<bool> togglePip() => throw UnimplementedError();
  Future<bool> artIsPipSupported() => throw UnimplementedError();
  Future<void> artSetUiConfig(ArtplayerUiConfig config) =>
      throw UnimplementedError();
  Future<List<String>> artAvailablePlugins() => throw UnimplementedError();
  Future<Object?> artCallPlugin(
    String name,
    String method, {
    List<Object?> args = const [],
  }) =>
      throw UnimplementedError();
  Future<void> artEmitDanmuku(Map<String, dynamic> danmu) =>
      throw UnimplementedError();
  Future<bool> artToggleDocumentPip() => throw UnimplementedError();
}
