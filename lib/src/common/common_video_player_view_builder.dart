import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'common_video_controller.dart';
import 'common_video_player_factory.dart';
import 'common_video_player_view.dart';

typedef CommonVideoPlayerViewCreatedCallback =
    void Function(CommonVideoController controller);

/// Wires [CommonVideoPlayerFactory.createAuto] to platform view lifecycle.
class CommonVideoPlayerViewBuilder extends StatefulWidget {
  const CommonVideoPlayerViewBuilder({
    super.key,
    required this.builder,
    this.url,
    this.creationParams,
    this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
  });

  final CommonVideoPlayerViewCreatedCallback builder;
  final String? url;
  final Map<String, dynamic>? creationParams;
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  @override
  State<CommonVideoPlayerViewBuilder> createState() =>
      _CommonVideoPlayerViewBuilderState();
}

class _CommonVideoPlayerViewBuilderState
    extends State<CommonVideoPlayerViewBuilder> {
  CommonVideoController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonVideoPlayerView(
      url: widget.url,
      creationParams: widget.creationParams,
      gestureRecognizers: widget.gestureRecognizers,
      onPlatformViewCreated: _handleCreated,
    );
  }

  void _handleCreated(int viewId) {
    if (_controller != null) return;
    final controller = CommonVideoPlayerFactory.createAuto(viewId);
    _controller = controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.builder(controller);
    });
  }
}
