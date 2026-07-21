#import <MetalKit/MetalKit.h>

typedef NS_ENUM(NSUInteger, AsterixMetalRendererState) {
  AsterixMetalRendererStateRunning,
  AsterixMetalRendererStateSuspended,
  AsterixMetalRendererStateStopped,
};

NS_ASSUME_NONNULL_BEGIN

@interface AsterixMetalRenderer : NSObject <MTKViewDelegate>

@property(nonatomic, readonly) AsterixMetalRendererState state;
@property(nonatomic, readonly) CGSize drawableSize;
@property(nonatomic, readonly) BOOL hasCommandQueue;
@property(nonatomic, readonly) BOOL isSceneReady;
@property(nonatomic, readonly) double framesPerSecond;
@property(nonatomic, readonly) double cpuFrameTimeMilliseconds;
@property(nonatomic, readonly) double gpuFrameTimeMilliseconds;
@property(nonatomic, readonly) uint64_t allocatedMemoryBytes;
@property(nonatomic, readonly) uint64_t frameCount;

- (instancetype)initWithView:(MTKView*)view NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)resizeToDrawableSize:(CGSize)drawableSize;
- (void)suspend;
- (void)resume;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
