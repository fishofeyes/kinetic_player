import 'dart:async';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:web/web.dart' as web;

import '../web/artplayer_view_host.dart';

/// A detached Artplayer can load metadata before VideoPlayer enters the tree.
class KineticVideoBackend {
  KineticVideoBackend._(this.id, this._host);

  static var _nextId = 1000000000;
  static var _registered = false;
  static final _players = <int, KineticVideoBackend>{};
  static const _viewType = 'kinetic.video_player';

  final int id;
  final ArtplayerViewHost _host;
  void Function(String, Map<dynamic, dynamic>)? onEvent;
  Timer? _metadataTimer;
  var _disposed = false;

  web.HTMLVideoElement? get _video =>
      _host.element.querySelector('video') as web.HTMLVideoElement?;

  static Future<void> reset() async {
    await Future.wait(
      _players.values.toList().map((player) => player.dispose()),
    );
  }

  static Future<KineticVideoBackend> create(DataSource source) async {
    if (source.sourceType == DataSourceType.file ||
        source.sourceType == DataSourceType.contentUri) {
      throw UnsupportedError('Use a network/blob URL or asset on Web.');
    }
    if (!_registered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (
        int viewId, {
        Object? params,
      }) {
        final id = (params as Map)['sessionId'] as int;
        return _players[id]?._host.element ?? web.HTMLDivElement();
      });
      _registered = true;
    }
    var url = source.uri;
    if (source.sourceType == DataSourceType.asset) {
      final key = source.package == null
          ? source.asset
          : 'packages/${source.package}/${source.asset}';
      url = 'assets/$key';
    }
    if (url == null || url.isEmpty) throw ArgumentError('Video URL is empty.');
    final id = _nextId++;
    final element = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'relative'
      ..style.pointerEvents = 'none';
    final host = ArtplayerViewHost(
      viewId: id,
      element: element,
      params: {
        'url': url,
        'headers': source.httpHeaders,
        'ui': {'enableNativeControls': false},
        'artplayerOptions': {'mutex': false, 'preload': 'auto'},
      },
    );
    final backend = KineticVideoBackend._(id, host);
    _players[id] = backend;
    return backend;
  }

  Future<void> initialize(DataSource source) async {
    _host.setEventSink((method, args) => onEvent?.call(method, args));
    await _host.ready;
    if (_disposed) return;
    // Metadata/timeupdate are not guaranteed to fire at the same time as Artplayer.ready.
    _metadataTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_disposed) return;
      final video = _video;
      if (video == null || video.readyState < 1) return;
      final duration = video.duration;
      onEvent?.call('onPositionChanged', {
        'position': (video.currentTime * 1000).round(),
        'duration': duration.isFinite ? (duration * 1000).round() : 0,
      });
      onEvent?.call('onPlayerStateChanged', {'state': 2});
      timer.cancel();
    });
  }

  Future<T?> invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (_disposed) return null;
    if (method == 'getVideoMetadata') {
      final video = _video;
      final duration = video?.duration ?? 0;
      return {
            'width': video?.videoWidth ?? 0,
            'height': video?.videoHeight ?? 0,
            'duration': duration.isFinite ? (duration * 1000).round() : 0,
          }
          as T;
    }
    return _host.invoke<T>(method, args);
  }

  Widget buildView() =>
      HtmlElementView(viewType: _viewType, creationParams: {'sessionId': id});

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _metadataTimer?.cancel();
    onEvent = null;
    _host.setEventSink(null);
    _players.remove(id);
    await _host.dispose();
    _host.element.remove();
  }
}
