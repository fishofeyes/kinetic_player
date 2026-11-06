import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../mpv/mpv_player_surface.dart';
import 'common_video_controller.dart';
import 'platform_guard.dart';
import 'player_view_types.dart';

export 'common_video_player_view_builder.dart';

/// Unified player surface: Android → GSY, iOS/macOS → SGPlayer, Web → Artplayer,
/// Windows/Linux → libmpv.
class CommonVideoPlayerView extends StatefulWidget {
  const CommonVideoPlayerView({
    super.key,
    this.controller,
    this.url,
    this.creationParams,
    this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
    this.onPlatformViewCreated,
  }) : assert(
         controller == null ||
             (url == null &&
                 creationParams == null &&
                 onPlatformViewCreated == null),
         'Use either controller or legacy view creation parameters.',
       );

  /// A source-based CommonVideoController; the caller owns and disposes it.
  final CommonVideoController? controller;

  final String? url;
  final Map<String, dynamic>? creationParams;
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;
  final ValueChanged<int>? onPlatformViewCreated;

  @override
  State<CommonVideoPlayerView> createState() => _CommonVideoPlayerViewState();
}

class _CommonVideoPlayerViewState extends State<CommonVideoPlayerView> {
  Map<String, dynamic> get _creationParams => <String, dynamic>{
    if (widget.url != null) 'url': widget.url,
    ...?widget.creationParams,
  };

  @override
  Widget build(BuildContext context) {
    assertSupportedPlayerPlatform();

    final controller = widget.controller;
    if (controller != null) {
      return ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, child) => controller.buildVideoView(),
      );
    }

    final creationParams = _creationParams;

    final defaultGestures = widget.gestureRecognizers.isEmpty
        ? const <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          }
        : widget.gestureRecognizers;

    if (kIsWeb) {
      return HtmlElementView(
        viewType: PlayerViewTypes.art,
        creationParams: creationParams,
        onPlatformViewCreated: widget.onPlatformViewCreated,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: PlayerViewTypes.sg,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: defaultGestures,
        onPlatformViewCreated: widget.onPlatformViewCreated,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return AppKitView(
        viewType: PlayerViewTypes.sg,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: defaultGestures,
        onPlatformViewCreated: widget.onPlatformViewCreated,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return MpvPlayerSurface(
        url: widget.url,
        creationParams: widget.creationParams,
        onPlatformViewCreated: widget.onPlatformViewCreated,
      );
    }

    return AndroidView(
      viewType: PlayerViewTypes.gsy,
      layoutDirection: TextDirection.ltr,
      creationParams: creationParams.isEmpty ? null : creationParams,
      creationParamsCodec: const StandardMessageCodec(),
      // Let GSY handle progress/volume/brightness gestures inside PlatformView.
      gestureRecognizers: defaultGestures,
      onPlatformViewCreated: widget.onPlatformViewCreated,
    );
  }
}
