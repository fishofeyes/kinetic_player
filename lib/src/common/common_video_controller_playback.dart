part of 'common_video_controller.dart';

/// The source-based implementation is private: callers keep the Common names.
class _ControllerOwnedCommonVideoController extends CommonVideoController {
  _ControllerOwnedCommonVideoController(this._controller) {
    KineticVideoPlayer.registerWith();
    _platform = VideoPlayerPlatform.instance as KineticVideoPlayer;
    _controller.addListener(_syncValue);
    _requestOptions = KineticHttpRequestOptions(
      headers: _controller.httpHeaders,
    );
  }

  VideoPlayerController _controller;
  late final KineticVideoPlayer _platform;
  late KineticHttpRequestOptions _requestOptions;
  final _values = ValueNotifier(const VideoPlayerValue.uninitialized());
  Future<void>? _initialization;
  Future<void>? _disposal;
  Completer<void>? _cancelInitialization;
  var _disposed = false;
  var _generation = 0;
  var _unmutedVolume = 1.0;

  @override
  ValueListenable<VideoPlayerValue> get _playbackValues => _values;

  @override
  final playerState = ValueNotifier(CommonPlayerState.idle);
  @override
  final position = ValueNotifier(Duration.zero);
  @override
  final duration = ValueNotifier(Duration.zero);

  void _syncValue() {
    if (_disposed) return;
    final next = _controller.value;
    final state = next.hasError
        ? CommonPlayerState.error
        : !next.isInitialized
        ? CommonPlayerState.idle
        : next.isCompleted
        ? CommonPlayerState.completed
        : next.isBuffering
        ? CommonPlayerState.buffering
        : next.isPlaying
        ? CommonPlayerState.playing
        : CommonPlayerState.paused;
    playerState.value = state;
    if (_disposed) return;
    position.value = next.position;
    if (_disposed) return;
    duration.value = next.duration;
    if (!_disposed) _values.value = next;
  }

  @override
  Future<void> initialize() {
    if (_disposed) return Future.error(StateError('Controller is disposed.'));
    if (!identical(VideoPlayerPlatform.instance, _platform)) {
      return Future.error(StateError('The video_player backend was replaced.'));
    }
    return _initialization ??= _initialize(_controller);
  }

  Future<void> _initialize(VideoPlayerController controller) async {
    final cancellation = Completer<void>();
    _cancelInitialization = cancellation;
    try {
      await Future.any([controller.initialize(), cancellation.future]);
    } finally {
      if (identical(_cancelInitialization, cancellation)) {
        _cancelInitialization = null;
      }
    }
    if (_disposed || !identical(controller, _controller)) return;
    _platform.setNativeEventListener(_sessionId(controller), (method, args) {
      if (method == 'onScreenshotCaptured') {
        onScreenshotCaptured?.call(screenshotBytesFromNative(args['bytes']));
      }
    });
  }

  void _cancelPendingInitialization() {
    _cancelInitialization?.completeError(
      StateError('Controller was disposed or its source was replaced.'),
    );
    _cancelInitialization = null;
  }

  // video_player exposes no public native-session handle. Keep this dependency
  // confined to the bridge; callers never need its controller or session ID.
  int _sessionId(VideoPlayerController controller) =>
      // ignore: invalid_use_of_visible_for_testing_member
      controller.playerId;

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    final controller = _controller;
    await initialize();
    if (_disposed || !identical(controller, _controller)) return null;
    return _platform.invokeNative<T>(_sessionId(controller), method, args);
  }

  @override
  Widget buildVideoView() =>
      _disposed ? const SizedBox.shrink() : VideoPlayer(_controller);

  @override
  Future<void> play() => _controller.play();
  @override
  Future<void> pause() => _controller.pause();
  @override
  Future<void> seekTo(Duration target) => _controller.seekTo(target);

  @override
  Future<void> stop() async {
    await pause();
    if (!_disposed) await seekTo(Duration.zero);
  }

  @override
  Future<void> setRate(double rate) => _controller.setPlaybackSpeed(rate);
  @override
  Future<void> setVolume(double volume) {
    _unmutedVolume = volume.clamp(0.0, 1.0);
    return _controller.setVolume(_unmutedVolume);
  }

  @override
  Future<void> setMute(bool muted) =>
      _controller.setVolume(muted ? 0 : _unmutedVolume);

  @override
  Future<void> setLooping(bool looping) => _controller.setLooping(looping);
  @override
  Future<Duration> getDuration() async => value.duration;
  @override
  Future<Duration> getCurrentPosition() async => value.position;
  @override
  Future<CommonVideoSize?> getVideoSize() async {
    if (!value.isInitialized || value.size.isEmpty) return null;
    return CommonVideoSize(
      width: value.size.width.round(),
      height: value.size.height.round(),
    );
  }

  @override
  Future<void> setScaleMode(CommonScaleMode mode) async {
    await _invoke<void>('setScaleMode', {'mode': mode.index});
  }

  @override
  Future<List<CommonAudioTrack>> getAudioTracks() async {
    final tracks = await _invoke<List<Object?>>('getAudioTracks');
    return tracks
            ?.map((track) => CommonAudioTrack.fromMap(track! as Map))
            .toList() ??
        [];
  }

  @override
  Future<void> selectAudioTrack(int index) async {
    await _invoke<void>('selectAudioTrack', {'index': index});
  }

  @override
  Future<void> setLocale(String locale) async {
    await _invoke<void>(
      'setLocale',
      KineticChromeStrings.toCreationParams(locale),
    );
  }

  @override
  Future<void> setHttpRequestOptions(KineticHttpRequestOptions? options) async {
    _requestOptions = options ?? const KineticHttpRequestOptions();
    if (value.isInitialized) {
      await _invoke<void>(
        'setHttpRequestOptions',
        _requestOptions.toMethodChannelArgs(),
      );
    }
  }

  @override
  Future<Uint8List?> captureFrame({
    bool highQuality = true,
    bool includeOverlay = false,
  }) async => screenshotBytesFromNative(
    await _invoke<Object>('captureFrame', {
      'highQuality': highQuality,
      'includeOverlay': includeOverlay,
    }),
  );

  @override
  Future<void> switchVideoSource(String url, {bool autoPlay = true}) async {
    if (_disposed) return;
    final generation = ++_generation;
    final previous = _controller;
    final settings = previous.value;
    previous.removeListener(_syncValue);
    _cancelPendingInitialization();
    final headers = <String, String>{
      ...?_requestOptions.headers,
      if (_requestOptions.userAgent != null)
        'User-Agent': _requestOptions.userAgent!,
    };
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers,
    )..addListener(_syncValue);
    _initialization = null;
    _syncValue();
    // Unmounted old VideoPlayer widgets retain the old controller until rebuild.
    // Its own dispose is idempotent; the new session has a different identity.
    await previous.dispose();
    if (_disposed || generation != _generation) return;
    final current = _controller;
    try {
      await initialize();
    } catch (_) {
      if (_disposed || generation != _generation) return;
      rethrow;
    }
    if (_disposed || generation != _generation) return;
    await current.setLooping(settings.isLooping);
    if (_disposed || generation != _generation) return;
    await current.setVolume(settings.volume);
    if (_disposed || generation != _generation) return;
    await current.setPlaybackSpeed(settings.playbackSpeed);
    if (!_disposed && generation == _generation && autoPlay) {
      await current.play();
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _generation++;
    _cancelPendingInitialization();
    _controller.removeListener(_syncValue);
    try {
      await _controller.dispose();
    } finally {
      playerState.dispose();
      position.dispose();
      duration.dispose();
      _values.dispose();
    }
  }
}
