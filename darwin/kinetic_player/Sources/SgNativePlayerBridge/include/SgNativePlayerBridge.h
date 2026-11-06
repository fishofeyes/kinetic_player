#import <Foundation/Foundation.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

typedef void (^SgStateChangedBlock)(NSInteger commonState);
typedef void (^SgProgressChangedBlock)(int64_t positionMs, int64_t durationMs, int64_t bufferedMs);
typedef void (^SgErrorChangedBlock)(NSString *_Nullable message, NSInteger code);

@interface SgNativePlayerBridge : NSObject

#if TARGET_OS_OSX
@property (nonatomic, readonly) NSView *view;
#else
@property (nonatomic, readonly) UIView *view;
#endif

- (instancetype)initWithStateHandler:(SgStateChangedBlock)stateHandler
                     progressHandler:(SgProgressChangedBlock)progressHandler
                        errorHandler:(SgErrorChangedBlock)errorHandler;

- (void)switchVideoSource:(NSString *)urlString autoPlay:(BOOL)autoPlay;
/// Replace with multi-segment asset. Each segment: {url, streamIndex?, startMs?, endMs?}.
- (BOOL)replaceWithSegments:(NSArray<NSDictionary *> *)segments autoPlay:(BOOL)autoPlay;
- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToMs:(NSInteger)positionMs;
- (void)setRenderMode:(NSInteger)mode;
- (void)setRate:(double)rate;
- (void)setVolume:(double)volume;
- (void)setMuted:(BOOL)muted;
- (void)setPitch:(double)pitch;
- (double)currentPitch;
- (NSArray<NSDictionary *> *)getAudioTracks;
- (BOOL)selectAudioTrack:(NSInteger)index;
- (NSArray<NSDictionary *> *)getVideoTracks;
- (BOOL)selectVideoTrack:(NSInteger)index;
- (NSDictionary *_Nullable)getVideoSize;
- (int64_t)getDurationMs;
- (void)setLooping:(BOOL)looping;
- (NSData *_Nullable)captureFrame;
- (double)currentVolume;
- (BOOL)isMuted;
/// 0=Plane, 1=VR, 2=VRBox
- (void)setDisplayMode:(NSInteger)mode;
- (NSInteger)displayMode;
- (void)setVrModeEnabled:(BOOL)enabled;
/// Keys: degrees, x, y, flipX, flipY, sensorEnable (all optional).
- (void)setVrViewport:(NSDictionary *)viewport;
- (NSDictionary *)vrViewport;
/// FFmpeg avformat options applied on next replace. Keys: timeoutMicros, reconnect, userAgent, headers(map), options(map).
- (void)setDemuxerOptions:(NSDictionary *)options;
/// Merge/clear User-Agent and HTTP headers (same pending demuxer bag). Empty clears UA/headers keys.
- (void)setHttpRequestOptions:(NSDictionary *)options;
/// Background / interrupt policy (iOS/tvOS; no-op on macOS).
- (void)setBackgroundPlaybackPolicy:(NSDictionary *)policy;
- (NSDictionary *)backgroundPlaybackPolicy;
- (NSString *_Nullable)lastErrorMessage;
- (NSInteger)lastErrorCode;
- (int64_t)bufferedPositionMs;
- (BOOL)isSeekable;
- (void)releasePlayer;

@end

NS_ASSUME_NONNULL_END
