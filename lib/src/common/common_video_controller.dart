import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../video_player/kinetic_video_player.dart';
import '../gsy/gsy_chrome_strings.dart';
import 'common_video_controller_bridge.dart';
import 'common_audio_track.dart';
import 'common_player_state.dart';
import 'common_scale_mode.dart';
import 'common_video_size.dart';
import 'kinetic_http_request_options.dart';

part 'common_video_controller_playback.dart';

/// Unified controller, retaining the original class name and native APIs.
///
/// Source constructors own their playback session and can initialize before a
/// view is mounted. Controllers created from a legacy view ID keep their
/// original lifecycle; their existing notifiers and platform-specific APIs remain
/// available.
abstract class CommonVideoController
    implements ValueListenable<VideoPlayerValue> {
  CommonVideoController();

  factory CommonVideoController.networkUrl(
    Uri url, {
    Map<String, String> httpHeaders = const {},
  }) => _ControllerOwnedCommonVideoController(
    VideoPlayerController.networkUrl(url, httpHeaders: httpHeaders),
  );

  factory CommonVideoController.file(
    File file, {
    Map<String, String> httpHeaders = const {},
  }) => _ControllerOwnedCommonVideoController(
    VideoPlayerController.file(file, httpHeaders: httpHeaders),
  );

  factory CommonVideoController.asset(String asset, {String? package}) =>
      _ControllerOwnedCommonVideoController(
        VideoPlayerController.asset(asset, package: package),
      );

  factory CommonVideoController.contentUri(Uri uri) =>
      _ControllerOwnedCommonVideoController(
        VideoPlayerController.contentUri(uri),
      );

  ValueListenable<VideoPlayerValue> get _playbackValues =>
      throw UnsupportedError(
        'value/listeners require a CommonVideoController source constructor. '
        'For a view-ID controller, use playerState/position/duration instead.',
      );

  @override
  VideoPlayerValue get value => _playbackValues.value;

  @override
  void addListener(VoidCallback listener) =>
      _playbackValues.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _playbackValues.removeListener(listener);

  /// Only source constructors need explicit initialization. Legacy view-ID
  /// controllers are initialized by their native view as before.
  Future<void> initialize() => throw UnsupportedError(
    'Use a CommonVideoController source constructor to initialize before mount.',
  );

  Future<void> setPlaybackSpeed(double speed) => setRate(speed);

  /// Used by CommonVideoPlayerView(controller: ...).
  @internal
  Widget buildVideoView() => throw UnsupportedError(
    'View-ID controllers must use their original native view.',
  );

  ValueNotifier<CommonPlayerState> get playerState;
  ValueNotifier<Duration> get position;
  ValueNotifier<Duration> get duration;

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seekTo(Duration position);
  Future<void> setScaleMode(CommonScaleMode mode);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> setMute(bool muted);
  Future<void> switchVideoSource(String url, {bool autoPlay = true});
  Future<List<CommonAudioTrack>> getAudioTracks();
  Future<void> selectAudioTrack(int index);
  Future<Duration> getDuration();
  Future<Duration> getCurrentPosition();
  Future<CommonVideoSize?> getVideoSize();
  Future<void> setLooping(bool looping);

  /// Chrome copy language: `zh` / `en` / `vi` / `ms` / `id` / `fil`.
  ///
  /// Unknown codes fall back to `zh`. Pass `KineticUiConfig.locale` at create;
  /// call this to hot-swap native / Artplayer chrome without `gsySetUiConfig`.
  Future<void> setLocale(String locale);

  /// Persist custom HTTP [User-Agent] / headers for subsequent media loads.
  ///
  /// Pass `null` or an empty [KineticHttpRequestOptions] to clear. Also
  /// accept `creationParams['userAgent']` / `creationParams['headers']` at
  /// view create. Does not change [switchVideoSource] signature — call this
  /// before switching sources when needed.
  Future<void> setHttpRequestOptions(KineticHttpRequestOptions? options);

  /// [includeOverlay] includes native chrome on Android (GSY); ignored on iOS.
  /// Returns PNG bytes, or null on failure. The plugin does not write files.
  Future<Uint8List?> captureFrame({
    bool highQuality = true,
    bool includeOverlay = false,
  });

  /// Native settings screenshot finished. [bytes] is PNG data (null on failure).
  ///
  /// The plugin does not write to disk or Photos; save [bytes] in the host.
  void Function(Uint8List? bytes)? onScreenshotCaptured;

  Future<void> dispose();
}
