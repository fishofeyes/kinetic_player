import 'dart:async';

import 'package:flutter/services.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'kinetic_video_backend.dart'
    if (dart.library.js_interop) 'kinetic_video_backend_web.dart';

/// Converts Kinetic channel events into the official controller's value stream.
class KineticVideoSession {
  KineticVideoSession({
    required this.backend,
    required Duration initializationTimeout,
  }) {
    backend.onEvent = _onEvent;
    _timeout = Timer(initializationTimeout, () {
      _fail(
        PlatformException(
          code: 'KineticInitializationTimeout',
          message:
              'The media did not become ready within $initializationTimeout.',
        ),
      );
    });
  }

  final KineticVideoBackend backend;
  // A single-subscription stream buffers native events before video_player listens.
  final _events = StreamController<VideoEvent>();
  Stream<VideoEvent> get events => _events.stream;
  Duration position = Duration.zero;
  void Function(String, Map<dynamic, dynamic>)? onNativeEvent;
  Timer? _timeout;
  var _ready = false;
  var _initialized = false;
  var _readingMetadata = false;
  var _disposed = false;
  var _failed = false;
  var _buffering = false;
  int? _lastState;

  Future<void> initialize(DataSource source) async {
    try {
      await backend.initialize(source);
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  Future<void> command(String method, [Map<String, dynamic>? args]) async {
    if (_disposed) return;
    await backend.invoke<void>(method, args);
  }

  Future<void> seekTo(Duration target) async {
    await command('seekTo', {'position': target.inMilliseconds});
    if (!_disposed) position = target;
  }

  void _emit(VideoEvent event) {
    if (!_disposed && !_failed) _events.add(event);
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_disposed || _failed) return;
    _failed = true;
    _timeout?.cancel();
    _events.addError(
      error is PlatformException
          ? PlatformException(
              code: error.code,
              message: error.message ?? error.code,
              details: error.details,
            )
          : PlatformException(code: 'KineticPlayerError', message: '$error'),
      stack,
    );
  }

  void _onEvent(String method, Map<dynamic, dynamic> args) {
    if (_disposed || _failed) return;
    onNativeEvent?.call(method, args);
    if (method == 'onPlayerError' || method == 'onError') {
      final message = args['message'];
      // SG also sends an empty error event when clearing a previous error.
      if (message != null && '$message'.isNotEmpty) {
        _fail(
          PlatformException(
            code: '${args['code'] ?? 'KineticPlayerError'}',
            message: '$message',
          ),
        );
      }
    } else if (method == 'onPositionChanged') {
      position = Duration(
        milliseconds: (args['position'] as num?)?.toInt() ?? 0,
      );
      final buffered = (args['buffered'] as num?)?.toInt();
      if (buffered != null) {
        _emit(
          VideoEvent(
            eventType: VideoEventType.bufferingUpdate,
            buffered: [
              DurationRange(
                Duration.zero,
                Duration(milliseconds: buffered.clamp(0, 1 << 62)),
              ),
            ],
          ),
        );
      }
      _initializeValue();
    } else if (method == 'onPlayerStateChanged') {
      final state = (args['state'] as num?)?.toInt();
      if (state == _lastState) return;
      _lastState = state;
      if (state == 6) {
        _fail(
          PlatformException(
            code: 'KineticPlayerError',
            message: 'The native player could not load this media.',
          ),
        );
        return;
      }
      final buffering = state == 1;
      if (buffering != _buffering) {
        _buffering = buffering;
        _emit(
          VideoEvent(
            eventType: buffering
                ? VideoEventType.bufferingStart
                : VideoEventType.bufferingEnd,
          ),
        );
      }
      if (state == 2 || state == 3 || state == 4) {
        _ready = true;
        _initializeValue();
      }
      if (state == 3 || state == 4 || state == 5) {
        _emit(
          VideoEvent(
            eventType: VideoEventType.isPlayingStateUpdate,
            isPlaying: state == 3,
          ),
        );
      }
      if (state == 5) {
        _emit(VideoEvent(eventType: VideoEventType.completed));
      }
    }
  }

  Future<void> _initializeValue() async {
    if (!_ready || _initialized || _readingMetadata) {
      return;
    }
    _readingMetadata = true;
    try {
      final metadata = await backend.invoke<Map<dynamic, dynamic>>(
        'getVideoMetadata',
      );
      if (_disposed || _failed) return;
      _initialized = true;
      _timeout?.cancel();
      _emit(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: Duration(
            milliseconds: (metadata?['duration'] as num?)?.toInt() ?? 0,
          ),
          size: Size(
            (metadata?['width'] as num?)?.toDouble() ?? 0,
            (metadata?['height'] as num?)?.toDouble() ?? 0,
          ),
          rotationCorrection: 0,
        ),
      );
    } catch (error, stack) {
      _fail(error, stack);
    } finally {
      _readingMetadata = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timeout?.cancel();
    backend.onEvent = null;
    onNativeEvent = null;
    try {
      await backend.dispose();
    } finally {
      // Do not await close: a controller can be disposed before its stream is heard.
      _events.close();
    }
  }
}
