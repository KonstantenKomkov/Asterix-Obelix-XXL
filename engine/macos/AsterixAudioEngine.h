#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface AsterixAudioEngine : NSObject

@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly) NSUInteger activeEffectCount;

- (BOOL)loadWaveData:(NSData*)data error:(NSError**)error;
- (void)setMusicVolume:(float)music effectsVolume:(float)effects;
- (void)setListenerPosition:(vector_float3)position forward:(vector_float3)forward;
- (void)startBeds;
- (void)playCue:(NSUInteger)cue channel:(NSUInteger)channel position:(vector_float3)position spatial:(BOOL)spatial gain:(float)gain;
- (void)suspend;
- (void)resume;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
