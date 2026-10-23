import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_player/video_player.dart';
import 'package:kinetic_player/kinetic_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <(int, MethodCall)>[];
  final destroyed = <int>[];
  final channels = <MethodChannel>[];
  var nextId = 1000000000;
  var failInitialization = false;
  var sendMetadata = true;
  late KineticVideoPlayer platform;

  Future<void> send(int id, String method, Map<String, dynamic> args) async {
    await messenger.handlePlatformMessage(
      'com.example.player/sg_$id',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    destroyed.clear();
    failInitialization = false;
    sendMetadata = true;
    platform = KineticVideoPlayer(
      initializationTimeout: const Duration(milliseconds: 100),
    );
    VideoPlayerPlatform.instance = platform;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.example.player/sg'),
      (call) async {
        if (call.method == 'create') {
          final id = nextId++;
          final channel = MethodChannel('com.example.player/sg_$id');
          channels.add(channel);
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add((id, call));
            if (call.method == 'getVideoMetadata') {
              return {'width': 1920, 'height': 1080, 'duration': 60000};
            }
            if (call.method == 'switchVideoSource') {
              if (failInitialization) {
                throw PlatformException(code: 'native_failure');
              }
              if (sendMetadata) {
                await send(id, 'onPlayerStateChanged', {'state': 2});
                await send(id, 'onPositionChanged', {
                  'position': 0,
                  'duration': 60000,
                  'buffered': 10000,
                });
              }
            }
            return null;
          });
          return {'viewId': id};
        }
        if (call.method == 'destroy') {
          destroyed.add((call.arguments as Map)['viewId'] as int);
        }
        if (call.method == 'resolveAsset') {
          return 'file:///bundle/flutter_assets/demo.mp4';
        }
        return null;
      },
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await platform.init();
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    channels.clear();
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.example.player/sg'),
      null,
    );
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  test(
    'official controller initializes before a VideoPlayer widget exists',
    () async {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/test.mp4'),
        httpHeaders: {'Authorization': 'test'},
      );
      await controller.initialize();
      expect(controller.value.isInitialized, isTrue);
      expect(controller.value.duration, const Duration(minutes: 1));
      expect(controller.value.size, const Size(1920, 1080));
      expect(controller.value.isPlaying, isFalse);
      expect(calls.first.$2.method, 'setHttpRequestOptions');
      expect(calls.first.$2.arguments, {
        'headers': {'Authorization': 'test'},
      });
      expect(platform.buildView(controller.playerId), isA<UiKitView>());
      await controller.dispose();
      expect(destroyed, [controller.playerId]);
    },
  );

  test(
    'original controller name supports source constructors and value',
    () async {
      final CommonVideoController controller = CommonVideoController.networkUrl(
        Uri.parse('https://example.com/common.mp4'),
        httpHeaders: {'Authorization': 'common-test'},
      );
      var changes = 0;
      void listener() => changes++;
      controller.addListener(listener);
      final initialization = controller.initialize();
      expect(identical(initialization, controller.initialize()), isTrue);
      await initialization;
      expect(controller.value.isInitialized, isTrue);
      expect(controller.value.aspectRatio, closeTo(16 / 9, 0.001));
      expect(controller.duration.value, const Duration(minutes: 1));
      expect(controller.buildVideoView(), isA<VideoPlayer>());
      await controller.play();
      await controller.seekTo(const Duration(seconds: 12));
      await controller.setPlaybackSpeed(1.5);
      await controller.setVolume(0.4);
      await controller.setMute(true);
      await controller.setMute(false);
      expect(controller.value.isPlaying, isTrue);
      expect(controller.playerState.value, CommonPlayerState.playing);
      expect(controller.position.value, const Duration(seconds: 12));
      expect(controller.value.playbackSpeed, 1.5);
      expect(controller.value.volume, 0.4);
      expect(changes, greaterThan(0));
      controller.removeListener(listener);
      await controller.dispose();
      await controller.dispose();
      expect(destroyed.length, 1);
    },
  );

  test(
    'original controller name retains native screenshot and scale APIs',
    () async {
      final controller = CommonVideoController.asset('demo.mp4');
      await controller.initialize();
      Uint8List? screenshot;
      controller.onScreenshotCaptured = (bytes) => screenshot = bytes;
      final id = calls.first.$1;
      await send(id, 'onScreenshotCaptured', {
        'bytes': [137, 80, 78, 71],
      });
      expect(screenshot, [137, 80, 78, 71]);
      await controller.setScaleMode(CommonScaleMode.fit);
      await controller.setLocale('en');
      expect(calls.any((entry) => entry.$2.method == 'setScaleMode'), isTrue);
      expect(calls.last.$2.arguments, containsPair('locale', 'en'));
      await controller.dispose();
    },
  );

  test(
    'switching sources retains listeners and releases the previous session',
    () async {
      final controller = CommonVideoController.networkUrl(
        Uri.parse('https://example.com/first.mp4'),
      );
      await controller.initialize();
      final firstId = calls.first.$1;
      var notifications = 0;
      controller.addListener(() => notifications++);
      await controller.setPlaybackSpeed(1.5);
      await controller.setLooping(true);
      await controller.setHttpRequestOptions(
        KineticHttpRequestOptions(headers: {'Authorization': 'next-test'}),
      );
      await controller.switchVideoSource('https://example.com/second.mp4');
      expect(destroyed, [firstId]);
      expect(controller.value.isInitialized, isTrue);
      expect(controller.value.isPlaying, isTrue);
      expect(controller.value.isLooping, isTrue);
      expect(controller.value.playbackSpeed, 1.5);
      expect(notifications, greaterThan(0));
      final loads = calls.where(
        (entry) => entry.$2.method == 'switchVideoSource',
      );
      expect((loads.last.$2.arguments as Map)['url'], contains('second.mp4'));
      final headers = calls.where(
        (entry) => entry.$2.method == 'setHttpRequestOptions',
      );
      expect((headers.last.$2.arguments as Map)['headers'], {
        'Authorization': 'next-test',
      });
      await controller.dispose();
      expect(destroyed.length, 2);
    },
  );

  test('disposed Common controller ignores late native events', () async {
    sendMetadata = false;
    final controller = CommonVideoController.networkUrl(
      Uri.parse('https://example.com/pending.mp4'),
    );
    final initialization = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    final id = calls.first.$1;
    await send(id, 'onPlayerStateChanged', {'state': 2});
    await initialization;
    await controller.dispose();
    await send(id, 'onPlayerStateChanged', {'state': 3});
    expect(destroyed, [id]);
    expect(controller.buildVideoView(), isA<SizedBox>());
  });

  test(
    'dispose cancels a pending Common initialization and releases the session',
    () async {
      sendMetadata = false;
      final controller = CommonVideoController.networkUrl(
        Uri.parse('https://example.com/pending.mp4'),
      );
      final initialization = controller.initialize();
      final cancelled = expectLater(initialization, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final id = calls.first.$1;
      await controller.dispose();
      await cancelled;
      expect(destroyed, [id]);
    },
  );

  testWidgets(
    'CommonVideoPlayerView preserves its controller across unmount and remount',
    (tester) async {
      final controller = CommonVideoController.networkUrl(
        Uri.parse('https://example.com/view.mp4'),
      );
      await tester.runAsync(controller.initialize);
      Widget view() => Directionality(
        textDirection: TextDirection.ltr,
        child: CommonVideoPlayerView(controller: controller),
      );
      await tester.pumpWidget(view());
      await tester.pump();
      expect(find.byType(CommonVideoPlayerView), findsOneWidget);
      expect(find.byType(UiKitView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(destroyed, isEmpty);
      await tester.pumpWidget(view());
      await tester.pump();
      expect(find.byType(UiKitView), findsOneWidget);
      expect(
        calls.where((entry) => entry.$2.method == 'switchVideoSource').length,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controller.dispose);
      expect(destroyed.length, 1);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('rapid source replacement releases every superseded session', () async {
    final controller = CommonVideoController.networkUrl(
      Uri.parse('https://example.com/original.mp4'),
    );
    await controller.initialize();
    sendMetadata = false;
    final switching = controller.switchVideoSource(
      'https://example.com/pending.mp4',
    );
    await Future<void>.delayed(Duration.zero);
    sendMetadata = true;
    await controller.switchVideoSource('https://example.com/final.mp4');
    await switching;
    expect(controller.value.isInitialized, isTrue);
    expect(controller.value.isPlaying, isTrue);
    expect(destroyed.length, 2);
    await controller.dispose();
    expect(destroyed.length, 3);
  });

  test(
    'official play, seek, volume, speed and loop use Kinetic commands',
    () async {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/a.mp4'),
      );
      await controller.initialize();
      await controller.play();
      await controller.seekTo(const Duration(seconds: 12));
      await controller.setVolume(0.4);
      await controller.setPlaybackSpeed(1.5);
      await controller.setLooping(true);
      await controller.pause();
      expect(
        await platform.getPosition(controller.playerId),
        const Duration(seconds: 12),
      );
      expect(
        calls.map((entry) => entry.$2.method),
        containsAll([
          'play',
          'seekTo',
          'setVolume',
          'setRate',
          'setLooping',
          'pause',
        ]),
      );
      expect(
        calls.any(
          (entry) =>
              entry.$2.method == 'setRate' &&
              (entry.$2.arguments as Map)['rate'] == 1.5,
        ),
        isTrue,
      );
      await controller.dispose();
    },
  );

  test(
    'native pause, progress, buffering and completion update official value',
    () async {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/a.mp4'),
      );
      await controller.initialize();
      final id = controller.playerId;
      await send(id, 'onPlayerStateChanged', {'state': 3});
      await send(id, 'onPlayerStateChanged', {'state': 1});
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isBuffering, isTrue);
      await send(id, 'onPlayerStateChanged', {'state': 4});
      await send(id, 'onPositionChanged', {
        'position': 15000,
        'duration': 60000,
        'buffered': 30000,
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isPlaying, isFalse);
      expect(controller.value.isBuffering, isFalse);
      expect(await controller.position, const Duration(seconds: 15));
      expect(controller.value.buffered.single.end, const Duration(seconds: 30));
      await send(id, 'onPlayerStateChanged', {'state': 5});
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isCompleted, isTrue);
      await controller.dispose();
    },
  );

  test(
    'native initialization failure reaches initialize rather than hanging',
    () async {
      failInitialization = true;
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/bad.mp4'),
      );
      await expectLater(
        controller.initialize(),
        throwsA(isA<PlatformException>()),
      );
      expect(controller.value.hasError, isTrue);
      await controller.dispose();
      expect(destroyed, hasLength(1));
    },
  );

  test(
    'missing readiness times out and the session can still be released',
    () async {
      sendMetadata = false;
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/a.mp4'),
      );
      await expectLater(
        controller.initialize(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'KineticInitializationTimeout',
          ),
        ),
      );
      await controller.dispose();
      expect(destroyed, hasLength(1));
    },
  );

  test(
    'asset resolution precedes loading and disposing one leaves another alive',
    () async {
      final first = VideoPlayerController.asset('demo.mp4');
      final second = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/b.mp4'),
      );
      await Future.wait([first.initialize(), second.initialize()]);
      final source =
          calls
                  .firstWhere(
                    (entry) =>
                        entry.$1 == first.playerId &&
                        entry.$2.method == 'switchVideoSource',
                  )
                  .$2
                  .arguments
              as Map;
      expect(source['url'], 'file:///bundle/flutter_assets/demo.mp4');
      await first.dispose();
      await second.play();
      expect(destroyed, [first.playerId]);
      expect(second.value.isPlaying, isTrue);
      await second.dispose();
    },
  );

  test('duplicate ready events emit initialized only once', () async {
    final id = await platform.create(
      DataSource(
        sourceType: DataSourceType.network,
        uri: 'https://example.com/a.mp4',
      ),
    );
    final events = <VideoEvent>[];
    final subscription = platform.videoEventsFor(id).listen(events.add);
    await Future<void>.delayed(Duration.zero);
    await send(id, 'onPlayerStateChanged', {'state': 4});
    await send(id, 'onPositionChanged', {'position': 0, 'duration': 60000});
    await Future<void>.delayed(Duration.zero);
    expect(
      events.where((event) => event.eventType == VideoEventType.initialized),
      hasLength(1),
    );
    await subscription.cancel();
    await platform.dispose(id);
    await platform.dispose(id);
    expect(destroyed, [id]);
  });

  test(
    'a native player created after reset is released instead of leaking',
    () async {
      final enteredCreate = Completer<void>();
      final nativeResult = Completer<Map<String, dynamic>>();
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.example.player/sg'),
        (call) async {
          if (call.method == 'create') {
            enteredCreate.complete();
            return nativeResult.future;
          }
          if (call.method == 'destroy') {
            destroyed.add((call.arguments as Map)['viewId'] as int);
          }
          return null;
        },
      );
      final pending = platform.create(
        DataSource(
          sourceType: DataSourceType.network,
          uri: 'https://example.com/a.mp4',
        ),
      );
      final expectation = expectLater(pending, throwsStateError);
      await enteredCreate.future;
      await platform.init();
      nativeResult.complete({'viewId': 42});
      await expectation;
      expect(destroyed, [42]);
    },
  );

  test(
    'disposing before metadata returns ignores late initialization',
    () async {
      final pendingMetadata = Completer<Map<String, dynamic>>();
      sendMetadata = false;
      final id = await platform.create(
        DataSource(
          sourceType: DataSourceType.network,
          uri: 'https://example.com/a.mp4',
        ),
      );
      messenger.setMockMethodCallHandler(
        MethodChannel('com.example.player/sg_$id'),
        (call) async =>
            call.method == 'getVideoMetadata' ? pendingMetadata.future : null,
      );
      final events = <VideoEvent>[];
      final subscription = platform.videoEventsFor(id).listen(events.add);
      await send(id, 'onPlayerStateChanged', {'state': 2});
      await platform.dispose(id);
      pendingMetadata.complete({
        'width': 1920,
        'height': 1080,
        'duration': 60000,
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        events.where((event) => event.eventType == VideoEventType.initialized),
        isEmpty,
      );
      expect(destroyed, [id]);
      await subscription.cancel();
    },
  );
}
