import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'kinetic_video_backend.dart'
    if (dart.library.js_interop) 'kinetic_video_backend_web.dart';
import 'kinetic_video_session.dart';

/// Opt-in video_player backend. Register before creating any controllers.
///
/// Existing CommonVideoController/CommonVideoPlayerView users are unaffected.
class KineticVideoPlayer extends VideoPlayerPlatform {
  KineticVideoPlayer({
    this.initializationTimeout = const Duration(seconds: 30),
  });

  final Duration initializationTimeout;
  final _sessions = <int, KineticVideoSession>{};
  var _generation = 0;
  Future<void> _resetFuture = Future.value();

  static void registerWith({
    Duration initializationTimeout = const Duration(seconds: 30),
  }) {
    if (VideoPlayerPlatform.instance is KineticVideoPlayer) return;
    VideoPlayerPlatform.instance = KineticVideoPlayer(
      initializationTimeout: initializationTimeout,
    );
  }

  @override
  Future<void> init() {
    _generation++;
    final sessions = _sessions.values.toList();
    _sessions.clear();
    final previousReset = _resetFuture;
    _resetFuture = () async {
      await previousReset;
      await Future.wait(sessions.map((session) => session.dispose()));
      await KineticVideoBackend.reset();
    }();
    return _resetFuture;
  }

  @override
  Future<int> create(DataSource dataSource) async {
    final generation = _generation;
    await _resetFuture;
    if (generation != _generation) {
      throw StateError('Kinetic was reset while creating a player.');
    }
    final backend = await KineticVideoBackend.create(dataSource);
    if (generation != _generation) {
      await backend.dispose();
      throw StateError('Kinetic was reset while creating a player.');
    }
    final session = KineticVideoSession(
      backend: backend,
      initializationTimeout: initializationTimeout,
    );
    _sessions[backend.id] = session;
    session.initialize(dataSource);
    return backend.id;
  }

  @override
  Future<int> createWithOptions(VideoCreationOptions options) =>
      create(options.dataSource);

  KineticVideoSession _session(int id) {
    final session = _sessions[id];
    if (session == null) throw StateError('Player $id has been disposed.');
    return session;
  }

  /// Internal bridge for the original CommonVideoController API.
  @internal
  Future<T?> invokeNative<T>(
    int id,
    String method, [
    Map<String, dynamic>? args,
  ]) => _session(id).backend.invoke<T>(method, args);

  @internal
  void setNativeEventListener(
    int id,
    void Function(String, Map<dynamic, dynamic>) listener,
  ) => _session(id).onNativeEvent = listener;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _session(playerId).events;

  @override
  Future<void> dispose(int playerId) async {
    await _sessions.remove(playerId)?.dispose();
  }

  @override
  Widget buildView(int playerId) => _session(playerId).backend.buildView();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      buildView(options.playerId);

  @override
  Future<void> play(int playerId) => _session(playerId).command('play');

  @override
  Future<void> pause(int playerId) => _session(playerId).command('pause');

  @override
  Future<void> seekTo(int playerId, Duration position) =>
      _session(playerId).seekTo(position);

  @override
  Future<Duration> getPosition(int playerId) async =>
      _session(playerId).position;

  @override
  Future<void> setLooping(int playerId, bool looping) =>
      _session(playerId).command('setLooping', {'looping': looping});

  @override
  Future<void> setVolume(int playerId, double volume) =>
      _session(playerId).command('setVolume', {'volume': volume});

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) =>
      _session(playerId).command('setRate', {'rate': speed});

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    if (mixWithOthers) {
      throw UnsupportedError('Kinetic does not implement mixWithOthers.');
    }
  }

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {
    if (allowBackgroundPlayback) {
      throw UnsupportedError(
        'Configure background playback through Kinetic native options.',
      );
    }
  }
}
