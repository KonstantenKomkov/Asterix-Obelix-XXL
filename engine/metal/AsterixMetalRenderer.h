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
@property(nonatomic, readonly) NSUInteger sceneMeshCount;
@property(nonatomic, readonly) NSUInteger visibleMeshCount;
@property(nonatomic, readonly) NSUInteger drawBatchCount;
@property(nonatomic, readonly) NSUInteger residentSectionCount;
@property(nonatomic, readonly) NSUInteger collisionTriangleCount;
@property(nonatomic, readonly) uint32_t debugOptions;
@property(nonatomic, readonly) NSString* playerState;
@property(nonatomic, readonly) NSInteger playerHealth;
@property(nonatomic, readonly) vector_float3 playerPosition;
@property(nonatomic, readonly) float cameraFieldOfView;
@property(nonatomic, readonly) BOOL cameraCollisionLimited;
@property(nonatomic, readonly, nullable) NSString* sceneError;

- (instancetype)initWithView:(MTKView*)view NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)resizeToDrawableSize:(CGSize)drawableSize;
- (BOOL)loadAssetPackageAtURL:(NSURL*)url;
- (void)reportSceneError:(NSString*)message;
- (void)setDebugOptions:(uint32_t)options;
- (void)setInputMoveX:(float)moveX
                moveZ:(float)moveZ
                 jump:(BOOL)jump
                attack:(BOOL)attack;
- (void)suspend;
- (void)resume;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
