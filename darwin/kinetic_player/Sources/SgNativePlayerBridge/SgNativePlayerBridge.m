#import "SgNativePlayerBridge.h"

#import <AVFoundation/AVFoundation.h>
#import <SGPlayer/SGPlayer.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#define SgPlatformView NSView
#define SgPlatformColorBlack NSColor.blackColor
#else
#import <UIKit/UIKit.h>
#define SgPlatformView UIView
#define SgPlatformColorBlack UIColor.blackColor
#endif

@interface SgNativePlayerBridge ()

@property (nonatomic, copy) SgStateChangedBlock stateHandler;
@property (nonatomic, copy) SgProgressChangedBlock progressHandler;
@property (nonatomic, copy) SgErrorChangedBlock errorHandler;
@property (nonatomic, strong) SGPlayer *player;
@property (nonatomic, strong) SgPlatformView *containerView;
@property (nonatomic, assign) BOOL looping;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) Float64 savedVolume;
@property (nonatomic, assign) Float64 savedPitch;
@property (nonatomic, assign) int64_t lastBufferedMs;
@property (nonatomic, copy, nullable) NSString *lastErrorMessage;
@property (nonatomic, assign) NSInteger lastErrorCode;
@property (nonatomic, copy, nullable) NSDictionary *pendingDemuxerOptions;
@property (nonatomic, assign) BOOL seekInFlight;
@property (nonatomic, assign) int64_t pendingSeekMs;
@property (nonatomic, assign) BOOL needsVideoDisplayRefresh;
@property (nonatomic, assign) BOOL wantsBackgroundPlayback;
@property (nonatomic, strong, nullable) dispatch_block_t seekWatchdog;

@end

@implementation SgNativePlayerBridge

- (instancetype)initWithStateHandler:(SgStateChangedBlock)stateHandler
                     progressHandler:(SgProgressChangedBlock)progressHandler
                        errorHandler:(SgErrorChangedBlock)errorHandler {
  self = [super init];
  if (self) {
    _stateHandler = [stateHandler copy];
    _progressHandler = [progressHandler copy];
    _errorHandler = [errorHandler copy];
    _containerView = [[SgPlatformView alloc] init];
#if TARGET_OS_OSX
    if ([_containerView respondsToSelector:@selector(setWantsLayer:)]) {
      _containerView.wantsLayer = YES;
      _containerView.layer.backgroundColor = NSColor.blackColor.CGColor;
    }
#else
    _containerView.backgroundColor = UIColor.blackColor;
#endif
    _savedVolume = 1.0;
    _savedPitch = 1.0;

    _player = [[SGPlayer alloc] init];
    _player.minimumTimeInfoInterval = 0.25;
    _player.videoRenderer.view = _containerView;
    _player.videoRenderer.scalingMode = SGScalingModeResizeAspect;
    _player.videoRenderer.displayMode = SGDisplayModePlane;
    _player.audioRenderer.pitch = _savedPitch;

    __weak typeof(self) weakSelf = self;
    _player.readyHandler = ^(SGPlayer *player) {
      (void)player;
      [weakSelf applySavedVolume];
      weakSelf.player.audioRenderer.pitch = weakSelf.savedPitch;
    };

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleInfoChanged:)
                                                 name:SGPlayerDidChangeInfosNotification
                                               object:_player];
#if TARGET_OS_IPHONE || TARGET_OS_TV
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
#elif TARGET_OS_OSX
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDidEnterBackground:)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDidBecomeActive:)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];
#endif
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self releasePlayer];
}

- (SgPlatformView *)view {
  return _containerView;
}

- (void)applyPendingDemuxerOptions {
  if (!self.pendingDemuxerOptions.count) {
    return;
  }
  NSMutableDictionary *ffmpeg = [NSMutableDictionary dictionary];
  NSDictionary *extra = self.pendingDemuxerOptions[@"options"];
  if ([extra isKindOfClass:[NSDictionary class]]) {
    [ffmpeg addEntriesFromDictionary:extra];
  }
  NSNumber *timeout = self.pendingDemuxerOptions[@"timeoutMicros"];
  if ([timeout isKindOfClass:[NSNumber class]]) {
    ffmpeg[@"timeout"] = timeout;
  }
  NSNumber *reconnect = self.pendingDemuxerOptions[@"reconnect"];
  if ([reconnect isKindOfClass:[NSNumber class]]) {
    ffmpeg[@"reconnect"] = reconnect;
  }
  NSString *userAgent = self.pendingDemuxerOptions[@"userAgent"];
  if ([userAgent isKindOfClass:[NSString class]] && userAgent.length > 0) {
    ffmpeg[@"user-agent"] = userAgent;
  }
  NSDictionary *headers = self.pendingDemuxerOptions[@"headers"];
  if ([headers isKindOfClass:[NSDictionary class]] && headers.count > 0) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
      [parts addObject:[NSString stringWithFormat:@"%@: %@", key, obj]];
    }];
    // FFmpeg expects headers separated by CRLF.
    ffmpeg[@"headers"] = [[parts componentsJoinedByString:@"\r\n"] stringByAppendingString:@"\r\n"];
  }
  if (ffmpeg.count > 0) {
    self.player.options.demuxer.options = ffmpeg;
  }
}

- (void)clearError {
  self.lastErrorMessage = nil;
  self.lastErrorCode = 0;
  if (self.errorHandler) {
    self.errorHandler(nil, 0);
  }
}

- (void)publishError:(NSError *)error {
  if (!error) {
    return;
  }
  self.lastErrorMessage = error.localizedDescription ?: error.domain;
  self.lastErrorCode = error.code;
  if (self.errorHandler) {
    self.errorHandler(self.lastErrorMessage, self.lastErrorCode);
  }
}

- (void)switchVideoSource:(NSString *)urlString autoPlay:(BOOL)autoPlay {
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) {
    NSError *error = [NSError errorWithDomain:@"SgNativePlayer"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey : @"Invalid URL"}];
    [self publishError:error];
    [self emitState:6];
    return;
  }
  [self clearError];
  [self emitState:0];
  [self applyPendingDemuxerOptions];
  [_player replaceWithURL:url];
  [self applySavedVolume];
  _player.audioRenderer.pitch = _savedPitch;
  if (autoPlay) {
    [_player play];
  }
}

- (BOOL)replaceWithSegments:(NSArray<NSDictionary *> *)segments autoPlay:(BOOL)autoPlay {
  if (segments.count == 0) {
    return NO;
  }
  [self clearError];
  [self applyPendingDemuxerOptions];

  SGMutableAsset *asset = [[SGMutableAsset alloc] init];
  SGMutableTrack *videoTrack = [asset addTrack:SGMediaTypeVideo];
  SGMutableTrack *audioTrack = [asset addTrack:SGMediaTypeAudio];

  for (NSDictionary *seg in segments) {
    NSString *urlString = seg[@"url"];
    if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
      continue;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
      continue;
    }
    NSInteger streamIndex = [seg[@"streamIndex"] respondsToSelector:@selector(integerValue)]
                                ? [seg[@"streamIndex"] integerValue]
                                : 0;
    CMTimeRange range = kCMTimeRangeZero;
    NSNumber *startMs = seg[@"startMs"];
    NSNumber *endMs = seg[@"endMs"];
    if ([startMs isKindOfClass:[NSNumber class]] || [endMs isKindOfClass:[NSNumber class]]) {
      int64_t start = [startMs isKindOfClass:[NSNumber class]] ? startMs.longLongValue : 0;
      CMTime startTime = CMTimeMake(start, 1000);
      if ([endMs isKindOfClass:[NSNumber class]]) {
        int64_t end = endMs.longLongValue;
        CMTime duration = CMTimeMake(MAX(0, end - start), 1000);
        range = CMTimeRangeMake(startTime, duration);
      } else {
        range = CMTimeRangeMake(startTime, kCMTimePositiveInfinity);
      }
    }
    SGURLSegment *segment =
        [[SGURLSegment alloc] initWithURL:url
                                    index:streamIndex
                                timeRange:range
                                    scale:CMTimeMake(1, 1)];
    [videoTrack appendSegment:segment];
    [audioTrack appendSegment:segment];
  }

  [self emitState:0];
  BOOL ok = [_player replaceWithAsset:asset];
  [self applySavedVolume];
  _player.audioRenderer.pitch = _savedPitch;
  if (ok && autoPlay) {
    [_player play];
  }
  return ok;
}

- (void)play {
  [self configurePlaybackAudioSessionIfNeeded];
  SGStateInfo stateInfo = [_player sstateInfo];
  if (stateInfo.playback & SGPlaybackStateFinished) {
    [self replayFromBeginning];
    return;
  }
  [_player play];
  [self applySavedVolume];
  _player.audioRenderer.pitch = _savedPitch;
}

- (void)pause {
  [_player pause];
}

- (void)stop {
  [_player pause];
  [_player seekToTime:kCMTimeZero];
  [self emitState:0];
  if (self.progressHandler) {
    self.progressHandler(0, [self getDurationMs], 0);
  }
}

- (void)setRate:(double)rate {
  _player.rate = rate;
}

- (void)setVolume:(double)volume {
  Float64 clamped = fmax(0.0, fmin(volume, 1.0));
  if (clamped > 0.0) {
    _muted = NO;
  }
  _savedVolume = clamped;
  [self applySavedVolume];
}

- (void)setMuted:(BOOL)muted {
  _muted = muted;
  [self applySavedVolume];
}

- (void)setPitch:(double)pitch {
  // SGPlayer pitch is typically around 0.5–2.0; clamp gently.
  Float64 clamped = fmax(0.5, fmin(pitch, 2.0));
  _savedPitch = clamped;
  _player.audioRenderer.pitch = clamped;
}

- (double)currentPitch {
  return _savedPitch;
}

- (void)applySavedVolume {
  _player.audioRenderer.volume = _muted ? 0.0 : _savedVolume;
}

- (NSArray<NSDictionary *> *)tracksOfType:(SGMediaType)type labelPrefix:(NSString *)prefix {
  SGPlayerItem *item = [_player currentItem];
  if (!item) {
    return @[];
  }
  NSArray<SGTrack *> *tracks = [SGTrack tracksWithTracks:item.tracks type:type];
  SGTrackSelection *selection =
      (type == SGMediaTypeAudio) ? item.audioSelection : item.videoSelection;
  NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
  NSInteger index = 0;
  for (SGTrack *track in tracks) {
    BOOL selected = [selection.tracks containsObject:track];
    [result addObject:@{
      @"index" : @(index),
      @"label" : [NSString stringWithFormat:@"%@_%ld", prefix, (long)track.index],
      @"language" : [NSNull null],
      @"selected" : @(selected),
    }];
    index++;
  }
  return result;
}

- (BOOL)selectTrackAtIndex:(NSInteger)index type:(SGMediaType)type {
  SGPlayerItem *item = [_player currentItem];
  if (!item) {
    return NO;
  }
  NSArray<SGTrack *> *tracks = [SGTrack tracksWithTracks:item.tracks type:type];
  if (index < 0 || index >= (NSInteger)tracks.count) {
    return NO;
  }
  SGTrack *track = tracks[(NSUInteger)index];
  SGTrackSelection *selection = [[SGTrackSelection alloc] init];
  selection.tracks = @[ track ];
  selection.weights = @[ @(1.0) ];
  if (type == SGMediaTypeAudio) {
    [item setAudioSelection:selection action:SGTrackSelectionActionTracks];
  } else {
    [item setVideoSelection:selection action:SGTrackSelectionActionTracks];
  }
  return YES;
}

- (NSArray<NSDictionary *> *)getAudioTracks {
  return [self tracksOfType:SGMediaTypeAudio labelPrefix:@"音轨"];
}

- (BOOL)selectAudioTrack:(NSInteger)index {
  return [self selectTrackAtIndex:index type:SGMediaTypeAudio];
}

- (NSArray<NSDictionary *> *)getVideoTracks {
  return [self tracksOfType:SGMediaTypeVideo labelPrefix:@"视频轨"];
}

- (BOOL)selectVideoTrack:(NSInteger)index {
  return [self selectTrackAtIndex:index type:SGMediaTypeVideo];
}

- (int64_t)getDurationMs {
  SGTimeInfo timeInfo = [_player timeInfo];
  if (CMTIME_IS_NUMERIC(timeInfo.duration)) {
    return (int64_t)(CMTimeGetSeconds(timeInfo.duration) * 1000.0);
  }
  SGPlayerItem *item = [_player currentItem];
  if (item && CMTIME_IS_NUMERIC(item.duration)) {
    return (int64_t)(CMTimeGetSeconds(item.duration) * 1000.0);
  }
  return 0;
}

- (int64_t)bufferedPositionMs {
  return _lastBufferedMs;
}

- (NSDictionary *)getVideoSize {
  SGPLFImage *image = [_player.videoRenderer currentImage];
  if (image && image.size.width > 0 && image.size.height > 0) {
    return @{
      @"width" : @((int)image.size.width),
      @"height" : @((int)image.size.height),
    };
  }
  return nil;
}

- (void)setLooping:(BOOL)looping {
  _looping = looping;
  if (looping) {
    SGStateInfo stateInfo = [_player sstateInfo];
    if (stateInfo.playback & SGPlaybackStateFinished) {
      [self replayFromBeginning];
    }
  }
}

- (void)replayFromBeginning {
  __weak typeof(self) weakSelf = self;
  [_player seekToTime:kCMTimeZero
                result:^(CMTime time, NSError *error) {
                  if (error) {
                    [weakSelf publishError:error];
                    return;
                  }
                  [weakSelf.player play];
                  [weakSelf applySavedVolume];
                  weakSelf.player.audioRenderer.pitch = weakSelf.savedPitch;
                }];
}

- (NSData *)captureFrame {
  SGPLFImage *image = [_player.videoRenderer currentImage];
  if (!image) {
    return nil;
  }
  NSData *pngData = nil;
#if TARGET_OS_OSX
  if ([image isKindOfClass:[NSImage class]]) {
    NSImage *nsImage = (NSImage *)image;
    CGImageRef cgImage = [nsImage CGImageForProposedRect:NULL context:nil hints:nil];
    if (cgImage) {
      NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
      pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    }
  }
#else
  pngData = UIImagePNGRepresentation(image);
#endif
  return pngData;
}

- (double)currentVolume {
  return _savedVolume;
}

- (BOOL)isMuted {
  return _muted;
}

- (void)seekToMs:(NSInteger)positionMs {
  int64_t targetMs = (int64_t)MAX(0, positionMs);
  CMTime time = CMTimeMake(targetMs, 1000);
  BOOL resumeAfterSeek = _player.wantsToPlay;

  [self cancelSeekWatchdog];
  self.seekInFlight = YES;
  self.pendingSeekMs = targetMs;

  if (![_player seekable]) {
    self.seekInFlight = NO;
    [self emitProgressAtMs:targetMs];
    return;
  }

  __weak typeof(self) weakSelf = self;
  BOOL started =
      [_player seekToTime:time
           toleranceBefor:kCMTimeZero
            toleranceAfter:kCMTimeZero
                   result:^(CMTime resultTime, NSError *error) {
                     __strong typeof(weakSelf) strongSelf = weakSelf;
                     if (!strongSelf) {
                       return;
                     }
                     [strongSelf cancelSeekWatchdog];
                     strongSelf.seekInFlight = NO;

                     int64_t landedMs = strongSelf.pendingSeekMs;
                     if (!error && CMTIME_IS_NUMERIC(resultTime)) {
                       landedMs = (int64_t)llround(CMTimeGetSeconds(resultTime) * 1000.0);
                     }
                     [strongSelf emitProgressAtMs:landedMs];
                     [strongSelf kickMetalDisplay];

                     if (resumeAfterSeek || strongSelf.player.wantsToPlay) {
                       [strongSelf.player play];
                       [strongSelf applySavedVolume];
                       strongSelf.player.audioRenderer.pitch = strongSelf.savedPitch;
                     }
                   }];

  if (!started) {
    self.seekInFlight = NO;
    [self emitProgressAtMs:targetMs];
    return;
  }

  // If SGPlayer never invokes the result block, unblock progress updates.
  dispatch_block_t watchdog = dispatch_block_create(0, ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || !strongSelf.seekInFlight) {
      return;
    }
    strongSelf.seekInFlight = NO;
    [strongSelf emitProgressAtMs:strongSelf.pendingSeekMs];
  });
  self.seekWatchdog = watchdog;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), watchdog);
}

- (void)cancelSeekWatchdog {
  if (self.seekWatchdog) {
    dispatch_block_cancel(self.seekWatchdog);
    self.seekWatchdog = nil;
  }
}

- (void)emitProgressAtMs:(int64_t)positionMs {
  int64_t durationMs = [self getDurationMs];
  if (self.progressHandler) {
    self.progressHandler(MAX(0, positionMs), durationMs, self.lastBufferedMs);
  }
}

- (BOOL)isSeekable {
  return [_player seekable];
}

- (void)setRenderMode:(NSInteger)mode {
  switch (mode) {
    case 0:
      _player.videoRenderer.scalingMode = SGScalingModeResizeAspect;
      break;
    case 1:
      _player.videoRenderer.scalingMode = SGScalingModeResizeAspectFill;
      break;
    default:
      _player.videoRenderer.scalingMode = SGScalingModeResize;
      break;
  }
}

- (void)setDisplayMode:(NSInteger)mode {
  switch (mode) {
    case 1:
      _player.videoRenderer.displayMode = SGDisplayModeVR;
      break;
    case 2:
      _player.videoRenderer.displayMode = SGDisplayModeVRBox;
      break;
    default:
      _player.videoRenderer.displayMode = SGDisplayModePlane;
      break;
  }
}

- (NSInteger)displayMode {
  switch (_player.videoRenderer.displayMode) {
    case SGDisplayModeVR:
      return 1;
    case SGDisplayModeVRBox:
      return 2;
    default:
      return 0;
  }
}

- (void)setVrModeEnabled:(BOOL)enabled {
  [self setDisplayMode:enabled ? 1 : 0];
}

- (void)setVrViewport:(NSDictionary *)viewport {
  SGVRViewport *vp = _player.videoRenderer.viewport;
  if (!vp) {
    return;
  }
  NSNumber *degrees = viewport[@"degrees"] ?: viewport[@"degress"];
  if ([degrees isKindOfClass:[NSNumber class]]) {
    vp.degress = degrees.doubleValue;
  }
  NSNumber *x = viewport[@"x"];
  if ([x isKindOfClass:[NSNumber class]]) {
    vp.x = x.doubleValue;
  }
  NSNumber *y = viewport[@"y"];
  if ([y isKindOfClass:[NSNumber class]]) {
    vp.y = y.doubleValue;
  }
  NSNumber *flipX = viewport[@"flipX"];
  if ([flipX isKindOfClass:[NSNumber class]]) {
    vp.flipX = flipX.boolValue;
  }
  NSNumber *flipY = viewport[@"flipY"];
  if ([flipY isKindOfClass:[NSNumber class]]) {
    vp.flipY = flipY.boolValue;
  }
  NSNumber *sensor = viewport[@"sensorEnable"];
  if ([sensor isKindOfClass:[NSNumber class]]) {
    vp.sensorEnable = sensor.boolValue;
  }
}

- (NSDictionary *)vrViewport {
  SGVRViewport *vp = _player.videoRenderer.viewport;
  if (!vp) {
    return @{};
  }
  return @{
    @"degrees" : @(vp.degress),
    @"x" : @(vp.x),
    @"y" : @(vp.y),
    @"flipX" : @(vp.flipX),
    @"flipY" : @(vp.flipY),
    @"sensorEnable" : @(vp.sensorEnable),
  };
}

- (void)setDemuxerOptions:(NSDictionary *)options {
  NSMutableDictionary *merged =
      [NSMutableDictionary dictionaryWithDictionary:self.pendingDemuxerOptions ?: @{}];
  if ([options isKindOfClass:[NSDictionary class]]) {
    [merged addEntriesFromDictionary:options];
  }
  self.pendingDemuxerOptions = [merged copy];
  [self applyPendingDemuxerOptions];
}

- (void)setHttpRequestOptions:(NSDictionary *)options {
  NSMutableDictionary *merged =
      [NSMutableDictionary dictionaryWithDictionary:self.pendingDemuxerOptions ?: @{}];
  NSString *userAgent = options[@"userAgent"];
  if ([userAgent isKindOfClass:[NSString class]] && userAgent.length > 0) {
    merged[@"userAgent"] = userAgent;
  } else {
    [merged removeObjectForKey:@"userAgent"];
  }
  NSDictionary *headers = options[@"headers"];
  if ([headers isKindOfClass:[NSDictionary class]] && headers.count > 0) {
    merged[@"headers"] = headers;
  } else {
    [merged removeObjectForKey:@"headers"];
  }
  self.pendingDemuxerOptions = [merged copy];
  [self applyPendingDemuxerOptions];
}

- (void)setBackgroundPlaybackPolicy:(NSDictionary *)policy {
#if TARGET_OS_IOS || TARGET_OS_TV
  NSNumber *interrupted = policy[@"pausesWhenInterrupted"];
  if ([interrupted isKindOfClass:[NSNumber class]]) {
    _player.pausesWhenInterrupted = interrupted.boolValue;
  }
  NSNumber *bg = policy[@"pausesWhenEnteredBackground"];
  if ([bg isKindOfClass:[NSNumber class]]) {
    _player.pausesWhenEnteredBackground = bg.boolValue;
    self.wantsBackgroundPlayback = !bg.boolValue;
  }
  NSNumber *bgNoAudio = policy[@"pausesWhenEnteredBackgroundIfNoAudioTrack"];
  if ([bgNoAudio isKindOfClass:[NSNumber class]]) {
    _player.pausesWhenEnteredBackgroundIfNoAudioTrack = bgNoAudio.boolValue;
  }
  if (self.wantsBackgroundPlayback) {
    [self configurePlaybackAudioSessionIfNeeded];
  }
#else
  (void)policy;
#endif
}

- (NSDictionary *)backgroundPlaybackPolicy {
#if TARGET_OS_IOS || TARGET_OS_TV
  return @{
    @"pausesWhenInterrupted" : @(_player.pausesWhenInterrupted),
    @"pausesWhenEnteredBackground" : @(_player.pausesWhenEnteredBackground),
    @"pausesWhenEnteredBackgroundIfNoAudioTrack" :
        @(_player.pausesWhenEnteredBackgroundIfNoAudioTrack),
  };
#else
  return @{};
#endif
}

- (void)releasePlayer {
  [self cancelSeekWatchdog];
  self.seekInFlight = NO;
  self.needsVideoDisplayRefresh = NO;
  [_player pause];
  _player = nil;
}

#pragma mark - Audio session / display

/// Required for real background playback together with UIBackgroundModes=audio.
- (void)configurePlaybackAudioSessionIfNeeded {
#if TARGET_OS_IOS || TARGET_OS_TV
  NSError *error = nil;
  AVAudioSession *session = [AVAudioSession sharedInstance];
  if (![session setCategory:AVAudioSessionCategoryPlayback
                       mode:AVAudioSessionModeMoviePlayback
                    options:0
                      error:&error]) {
    NSLog(@"[SgNativePlayerBridge] AVAudioSession setCategory failed: %@", error);
  }
  if (![session setActive:YES error:&error]) {
    NSLog(@"[SgNativePlayerBridge] AVAudioSession setActive failed: %@", error);
  }
#endif
}

- (void)kickMetalDisplay {
  if (!_player) {
    return;
  }
  SGVideoRenderer *renderer = _player.videoRenderer;
  id metalView = [renderer valueForKey:@"metalView"];
  if ([metalView respondsToSelector:@selector(setPaused:)]) {
    [metalView setValue:@NO forKey:@"paused"];
  }
  if ([metalView respondsToSelector:@selector(setNeedsDisplay)]) {
    [metalView setNeedsDisplay];
  }
  id fetchTimer = [renderer valueForKey:@"fetchTimer"];
  if ([fetchTimer respondsToSelector:@selector(setPaused:)]) {
    [fetchTimer setValue:@NO forKey:@"paused"];
  }
}

#pragma mark - Notifications

- (void)handleDidEnterBackground:(NSNotification *)notification {
  (void)notification;
  self.needsVideoDisplayRefresh = YES;
}

- (void)handleDidBecomeActive:(NSNotification *)notification {
  (void)notification;
  if (!self.needsVideoDisplayRefresh) {
    return;
  }
  self.needsVideoDisplayRefresh = NO;
  [self refreshVideoDisplayAfterForeground];
}

/// SGPlayer uses MTKView; background audio can keep the clock moving while Metal freezes.
/// Rebind the renderer and soft-seek to the current clock so the picture catches up.
- (void)refreshVideoDisplayAfterForeground {
  if (!_player) {
    return;
  }
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || !strongSelf->_player) {
      return;
    }

    if (strongSelf.wantsBackgroundPlayback) {
      [strongSelf configurePlaybackAudioSessionIfNeeded];
    }

    SGVideoRenderer *renderer = strongSelf->_player.videoRenderer;
    SgPlatformView *host = strongSelf->_containerView;
    renderer.view = nil;
    renderer.view = host;
    [strongSelf kickMetalDisplay];
#if TARGET_OS_OSX
    [host setNeedsLayout:YES];
    [host layoutSubtreeIfNeeded];
#else
    [host setNeedsLayout];
    [host layoutIfNeeded];
#endif

    BOOL shouldResume = strongSelf->_player.wantsToPlay;
    SGTimeInfo timeInfo = [strongSelf->_player timeInfo];
    CMTime playback = timeInfo.playback;
    if (shouldResume && CMTIME_IS_NUMERIC(playback)) {
      // Soft seek forces a fresh decoded frame at the audio clock after metal resumes.
      [strongSelf->_player seekToTime:playback
                       toleranceBefor:kCMTimeZero
                        toleranceAfter:kCMTimePositiveInfinity
                               result:^(CMTime time, NSError *error) {
                                 (void)time;
                                 (void)error;
                                 __strong typeof(weakSelf) inner = weakSelf;
                                 if (!inner || !inner->_player) {
                                   return;
                                 }
                                 [inner kickMetalDisplay];
                                 if (inner->_player.wantsToPlay) {
                                   [inner->_player play];
                                   [inner applySavedVolume];
                                 }
                               }];
    } else if (shouldResume) {
      [strongSelf->_player play];
      [strongSelf applySavedVolume];
    }
  });
}

- (void)handleInfoChanged:(NSNotification *)notification {
  SGTimeInfo timeInfo = [SGPlayer timeInfoFromUserInfo:notification.userInfo];
  SGStateInfo stateInfo = [SGPlayer stateInfoFromUserInfo:notification.userInfo];
  SGInfoAction action = [SGPlayer infoActionFromUserInfo:notification.userInfo];

  if (action & SGInfoActionState) {
    NSInteger mapped = [self mapCommonState:stateInfo];
    [self emitState:mapped];
    if (stateInfo.player == SGPlayerStateFailed) {
      NSError *error = [_player error] ?: [_player currentItem].error;
      [self publishError:error];
    }
    if (stateInfo.playback & SGPlaybackStatePlaying) {
      [self applySavedVolume];
      _player.audioRenderer.pitch = _savedPitch;
    }
    if ((stateInfo.playback & SGPlaybackStateFinished) && self.looping) {
      [self replayFromBeginning];
    }
  }

    if (action & SGInfoActionTime) {
        // Suppress stale playhead while an async seek is in flight (prevents UI bounce).
        if (self.seekInFlight || (stateInfo.playback & SGPlaybackStateSeeking)) {
            return;
        }
        int64_t positionMs = 0;
        int64_t durationMs = 0;
        int64_t cachedDurationMs = 0;
        if (CMTIME_IS_NUMERIC(timeInfo.playback)) {
            positionMs = (int64_t)(CMTimeGetSeconds(timeInfo.playback) * 1000.0);
        }
        if (CMTIME_IS_NUMERIC(timeInfo.duration)) {
            durationMs = (int64_t)(CMTimeGetSeconds(timeInfo.duration) * 1000.0);
        }
        if (CMTIME_IS_NUMERIC(timeInfo.cached)) {
            cachedDurationMs = (int64_t)(CMTimeGetSeconds(timeInfo.cached) * 1000.0);
        }
        int64_t bufferedMs = MAX(0, positionMs) + MAX(0, cachedDurationMs);
        if (durationMs > 0) {
            bufferedMs = MIN(bufferedMs, durationMs);
        }
        NSCAssert(bufferedMs >= 0 && (durationMs <= 0 || bufferedMs <= durationMs),
                  @"Buffered position must stay within the media duration");
        self.lastBufferedMs = MAX(0, bufferedMs);
        if (self.progressHandler) {
            self.progressHandler(positionMs, durationMs, self.lastBufferedMs);
        }
    }
}

#pragma mark - Mapping

- (NSInteger)mapCommonState:(SGStateInfo)state {
  if (state.player == SGPlayerStateFailed) {
    return 6;
  }
  if (state.player == SGPlayerStatePreparing) {
    return 1;
  }
  if (state.playback & SGPlaybackStateFinished) {
    return 5;
  }
  if (state.playback & SGPlaybackStatePlaying) {
    return 3;
  }
  if (state.loading == SGLoadingStateStalled) {
    return 1;
  }
  if (state.player == SGPlayerStateReady) {
    if (self.player.wantsToPlay) {
      return 4;
    }
    return 2;
  }
  return 0;
}

- (void)emitState:(NSInteger)state {
  if (self.stateHandler) {
    self.stateHandler(state);
  }
}

@end
