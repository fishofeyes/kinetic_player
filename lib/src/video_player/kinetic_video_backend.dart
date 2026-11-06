import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Owns the native session independently of the widget that displays it.
class KineticVideoBackend {
  KineticVideoBackend._(this.id, this._kind, this._plugin, this.textureId) {
    _channel = MethodChannel('com.example.player/${_kind}_$id');
    _channel.setMethodCallHandler((call) async {
      onEvent?.call(call.method, call.arguments as Map? ?? {});
    });
  }

  final int id;
  final int? textureId;
  final String _kind;
  final MethodChannel _plugin;
  late final MethodChannel _channel;
  void Function(String, Map<dynamic, dynamic>)? onEvent;
  var _disposed = false;

  static String get _platformKind => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'gsy',
    TargetPlatform.iOS || TargetPlatform.macOS => 'sg',
    TargetPlatform.windows || TargetPlatform.linux => 'mpv',
    _ => throw UnsupportedError('Kinetic does not support this platform.'),
  };

  static Future<void> reset() => MethodChannel(
    'com.example.player/$_platformKind',
  ).invokeMethod<void>('reset');

  static Future<KineticVideoBackend> create(DataSource source) async {
    final kind = _platformKind;
    if (source.sourceType == DataSourceType.contentUri && kind != 'gsy') {
      throw UnsupportedError('contentUri is only supported on Android.');
    }
    final plugin = MethodChannel('com.example.player/$kind');
    final result = await plugin.invokeMapMethod<String, dynamic>('create', {
      'controllerOwned': true,
      'ui': {
        'enableNativeControls': false,
        'enableNativeControlsFullscreen': false,
        'keepLastFrameWhenComplete': true,
        'startAfterPrepared': false,
        'rotateViewAuto': false,
        'rotateWithSystem': false,
        'needOrientationUtils': false,
        'needShowWifiTip': false,
        'cacheWithPlay': false,
        'releaseWhenLossAudio': false,
      },
    });
    if (result == null) throw StateError('Kinetic did not create a player.');
    return KineticVideoBackend._(
      result['viewId'] as int,
      kind,
      plugin,
      result['textureId'] as int?,
    );
  }

  Future<void> initialize(DataSource source) async {
    var url = source.uri;
    if (source.sourceType == DataSourceType.asset) {
      final asset = source.asset;
      if (asset == null || asset.isEmpty) {
        throw ArgumentError('Asset is empty.');
      }
      if (_kind == 'mpv') {
        final key = source.package == null
            ? asset
            : 'packages/${source.package}/$asset';
        url = File.fromUri(
          File(
            Platform.resolvedExecutable,
          ).parent.uri.resolve('data/flutter_assets/$key'),
        ).path;
      } else {
        url = await _plugin.invokeMethod<String>('resolveAsset', {
          'asset': asset,
          'package': source.package,
        });
      }
    }
    if (_disposed) return;
    if (url == null || url.isEmpty) throw ArgumentError('Video URL is empty.');
    await invoke<void>('setHttpRequestOptions', {
      'headers': source.httpHeaders,
    });
    if (_disposed) return;
    await invoke<void>(_kind == 'gsy' ? 'initialize' : 'switchVideoSource', {
      'url': url,
      'autoPlay': false,
    });
  }

  Future<T?> invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (_disposed) return null;
    return _channel.invokeMethod<T>(method, args);
  }

  Widget buildView() {
    if (_disposed) return const SizedBox.shrink();
    if (textureId != null) return Texture(textureId: textureId!);
    final params = {'sessionId': id};
    final viewType = 'com.example.player/${_kind}_view_ui';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
        viewType: viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      ),
      TargetPlatform.iOS => UiKitView(
        viewType: viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      ),
      TargetPlatform.macOS => AppKitView(
        viewType: viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      ),
      _ => throw UnsupportedError('Missing Kinetic rendering surface.'),
    };
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    onEvent = null;
    _channel.setMethodCallHandler(null);
    await _plugin.invokeMethod<void>('destroy', {'viewId': id});
  }
}
