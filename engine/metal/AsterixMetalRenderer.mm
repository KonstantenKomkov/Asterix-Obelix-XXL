#import "AsterixMetalRenderer.h"

#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>

typedef struct {
  vector_float3 position;
  vector_float3 color;
} AsterixVertex;

typedef struct {
  matrix_float4x4 transform;
} AsterixUniforms;

static matrix_float4x4 AsterixPerspective(float fovY, float aspect,
                                           float nearZ, float farZ) {
  const float y = 1.0f / tanf(fovY * 0.5f);
  const float x = y / aspect;
  const float z = farZ / (nearZ - farZ);
  return (matrix_float4x4){{{x, 0, 0, 0}, {0, y, 0, 0},
                            {0, 0, z, -1}, {0, 0, z * nearZ, 0}}};
}

@implementation AsterixMetalRenderer {
  __weak MTKView* _view;
  id<MTLCommandQueue> _commandQueue;
  id<MTLRenderPipelineState> _pipeline;
  id<MTLDepthStencilState> _depthState;
  id<MTLBuffer> _vertices;
  id<MTLTexture> _depthTexture;
  dispatch_group_t _inFlightCommands;
  AsterixMetalRendererState _state;
  CGSize _drawableSize;
  CFTimeInterval _startTime;
  CFTimeInterval _lastFrameTime;
  double _cpuFrameTimeMilliseconds;
  double _gpuFrameTimeMilliseconds;
  double _framesPerSecond;
  uint64_t _frameCount;
}

- (instancetype)initWithView:(MTKView*)view {
  self = [super init];
  if (self) {
    _view = view;
    _commandQueue = [view.device newCommandQueue];
    _inFlightCommands = dispatch_group_create();
    _state = AsterixMetalRendererStateRunning;
    _drawableSize = view.drawableSize;
    _startTime = CACurrentMediaTime();
    _lastFrameTime = _startTime;
    [self buildSceneResources:view.device colorFormat:view.colorPixelFormat];
    view.delegate = self;
    view.paused = NO;
  }
  return self;
}

- (void)buildSceneResources:(id<MTLDevice>)device
                colorFormat:(MTLPixelFormat)colorFormat {
  if (device == nil) return;
  static NSString* source = @"#include <metal_stdlib>\n"
      "using namespace metal;\n"
      "struct V { float3 p; float3 c; }; struct U { float4x4 m; };\n"
      "struct O { float4 p [[position]]; float3 c; };\n"
      "vertex O vs(uint i [[vertex_id]], constant V* v [[buffer(0)]], constant U& u [[buffer(1)]]) { O o; o.p=u.m*float4(v[i].p,1); o.c=v[i].c; return o; }\n"
      "fragment float4 fs(O i [[stage_in]]) { return float4(i.c,1); }";
  NSError* error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  if (library == nil) return;
  MTLRenderPipelineDescriptor* descriptor = [MTLRenderPipelineDescriptor new];
  descriptor.vertexFunction = [library newFunctionWithName:@"vs"];
  descriptor.fragmentFunction = [library newFunctionWithName:@"fs"];
  descriptor.colorAttachments[0].pixelFormat = colorFormat;
  descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
  _pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
  MTLDepthStencilDescriptor* depth = [MTLDepthStencilDescriptor new];
  depth.depthCompareFunction = MTLCompareFunctionLess;
  depth.depthWriteEnabled = YES;
  _depthState = [device newDepthStencilStateWithDescriptor:depth];
  const AsterixVertex vertices[] = {
      {{0.0f, 0.9f, 0.0f}, {1.0f, 0.75f, 0.12f}},
      {{-0.8f, -0.65f, 0.0f}, {0.12f, 0.65f, 1.0f}},
      {{0.8f, -0.65f, 0.0f}, {0.95f, 0.2f, 0.15f}},
  };
  _vertices = [device newBufferWithBytes:vertices length:sizeof(vertices)
                                  options:MTLResourceStorageModeShared];
}

- (void)dealloc {
  [self stop];
}

- (AsterixMetalRendererState)state {
  @synchronized(self) {
    return _state;
  }
}

- (CGSize)drawableSize {
  @synchronized(self) {
    return _drawableSize;
  }
}

- (BOOL)hasCommandQueue {
  @synchronized(self) {
    return _commandQueue != nil;
  }
}

- (BOOL)isSceneReady {
  @synchronized(self) {
    return _pipeline != nil && _depthState != nil && _vertices != nil;
  }
}

- (double)framesPerSecond {
  @synchronized(self) { return _framesPerSecond; }
}
- (double)cpuFrameTimeMilliseconds { @synchronized(self) { return _cpuFrameTimeMilliseconds; } }
- (double)gpuFrameTimeMilliseconds { @synchronized(self) { return _gpuFrameTimeMilliseconds; } }
- (uint64_t)allocatedMemoryBytes { return _view.device.currentAllocatedSize; }
- (uint64_t)frameCount { @synchronized(self) { return _frameCount; } }

- (void)resizeToDrawableSize:(CGSize)drawableSize {
  @synchronized(self) {
    if (_state != AsterixMetalRendererStateStopped) {
      _drawableSize = drawableSize;
      _depthTexture = nil;
    }
  }
}

- (void)suspend {
  @synchronized(self) {
    if (_state != AsterixMetalRendererStateRunning) {
      return;
    }
    _state = AsterixMetalRendererStateSuspended;
    _view.paused = YES;
  }
}

- (void)resume {
  @synchronized(self) {
    if (_state == AsterixMetalRendererStateStopped) {
      return;
    }
    _state = AsterixMetalRendererStateRunning;
    _view.paused = NO;
  }
}

- (void)stop {
  MTKView* view = nil;
  @synchronized(self) {
    if (_state == AsterixMetalRendererStateStopped) {
      return;
    }
    _state = AsterixMetalRendererStateStopped;
    view = _view;
    view.paused = YES;
    if (view.delegate == self) {
      view.delegate = nil;
    }
  }

  dispatch_group_wait(_inFlightCommands, DISPATCH_TIME_FOREVER);

  @synchronized(self) {
    _commandQueue = nil;
    _pipeline = nil;
    _depthState = nil;
    _vertices = nil;
    _depthTexture = nil;
    _view = nil;
  }
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
  [self resizeToDrawableSize:size];
}

- (void)drawInMTKView:(MTKView*)view {
  const CFTimeInterval cpuStart = CACurrentMediaTime();
  id<MTLCommandBuffer> commandBuffer = nil;
  @synchronized(self) {
    if (_state != AsterixMetalRendererStateRunning || _commandQueue == nil) {
      return;
    }
    commandBuffer = [_commandQueue commandBuffer];
    if (commandBuffer == nil) {
      return;
    }
    dispatch_group_enter(_inFlightCommands);
  }

  [commandBuffer addCompletedHandler:^(__unused id<MTLCommandBuffer> buffer) {
    dispatch_group_leave(self->_inFlightCommands);
  }];

  MTLRenderPassDescriptor* descriptor = view.currentRenderPassDescriptor;
  id<CAMetalDrawable> drawable = view.currentDrawable;
  BOOL rendered = NO;
  if (descriptor != nil && drawable != nil) {
    if (_depthTexture == nil || _depthTexture.width != (NSUInteger)view.drawableSize.width ||
        _depthTexture.height != (NSUInteger)view.drawableSize.height) {
      MTLTextureDescriptor* depth = [MTLTextureDescriptor
          texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                      width:MAX(1, (NSUInteger)view.drawableSize.width)
                                     height:MAX(1, (NSUInteger)view.drawableSize.height)
                                  mipmapped:NO];
      depth.usage = MTLTextureUsageRenderTarget;
      depth.storageMode = MTLStorageModePrivate;
      _depthTexture = [view.device newTextureWithDescriptor:depth];
    }
    descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    descriptor.colorAttachments[0].clearColor = view.clearColor;
    descriptor.depthAttachment.texture = _depthTexture;
    descriptor.depthAttachment.loadAction = MTLLoadActionClear;
    descriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
    descriptor.depthAttachment.clearDepth = 1.0;
    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    if (_pipeline != nil && _vertices != nil) {
      const float seconds = (float)(cpuStart - _startTime);
      const float c = cosf(seconds * 0.7f), s = sinf(seconds * 0.7f);
      matrix_float4x4 rotation = (matrix_float4x4){{{c, 0, -s, 0}, {0, 1, 0, 0},
          {s, 0, c, 0}, {0, 0, -2.4f, 1}}};
      const float aspect = MAX(0.01f, view.drawableSize.width / view.drawableSize.height);
      AsterixUniforms uniforms = {simd_mul(AsterixPerspective(70.0f * 3.14159265358979323846f / 180.0f,
                                                              aspect, 0.1f, 100.0f), rotation)};
      [encoder setRenderPipelineState:_pipeline];
      [encoder setDepthStencilState:_depthState];
      [encoder setVertexBuffer:_vertices offset:0 atIndex:0];
      [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
      [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    }
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    rendered = YES;
  }
  const CFTimeInterval submitted = CACurrentMediaTime();
  if (rendered) @synchronized(self) {
    _cpuFrameTimeMilliseconds = (submitted - cpuStart) * 1000.0;
    const double interval = submitted - _lastFrameTime;
    if (interval > 0 && interval < 0.5) {
      const double instantaneous = 1.0 / interval;
      _framesPerSecond = _framesPerSecond == 0
          ? instantaneous
          : _framesPerSecond * 0.9 + instantaneous * 0.1;
    }
    _lastFrameTime = submitted;
    _frameCount += 1;
  }
  if (rendered) [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    if (buffer.GPUEndTime > buffer.GPUStartTime) {
      @synchronized(self) {
        self->_gpuFrameTimeMilliseconds =
            (buffer.GPUEndTime - buffer.GPUStartTime) * 1000.0;
      }
    }
  }];
  [commandBuffer commit];
}

@end
