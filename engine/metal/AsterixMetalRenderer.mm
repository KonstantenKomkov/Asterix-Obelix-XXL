#import "AsterixMetalRenderer.h"

@implementation AsterixMetalRenderer {
  __weak MTKView* _view;
  id<MTLCommandQueue> _commandQueue;
  dispatch_group_t _inFlightCommands;
  AsterixMetalRendererState _state;
  CGSize _drawableSize;
}

- (instancetype)initWithView:(MTKView*)view {
  self = [super init];
  if (self) {
    _view = view;
    _commandQueue = [view.device newCommandQueue];
    _inFlightCommands = dispatch_group_create();
    _state = AsterixMetalRendererStateRunning;
    _drawableSize = view.drawableSize;
    view.delegate = self;
    view.paused = NO;
  }
  return self;
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

- (void)resizeToDrawableSize:(CGSize)drawableSize {
  @synchronized(self) {
    if (_state != AsterixMetalRendererStateStopped) {
      _drawableSize = drawableSize;
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
    if (_state != AsterixMetalRendererStateSuspended) {
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
    _view = nil;
  }
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
  [self resizeToDrawableSize:size];
}

- (void)drawInMTKView:(MTKView*)view {
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
  if (descriptor != nil && drawable != nil) {
    descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    descriptor.colorAttachments[0].clearColor = view.clearColor;
    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
  }
  [commandBuffer commit];
}

@end
