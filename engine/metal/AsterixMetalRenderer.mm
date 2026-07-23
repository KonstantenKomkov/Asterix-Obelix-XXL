#import "AsterixMetalRenderer.h"
#import "../macos/AsterixAudioEngine.h"

#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#include <string.h>
#include <memory>
#include <unordered_map>
#include <vector>
#include "asterix/scene_runtime.hpp"
#include "asterix/simulation_runtime.hpp"
#include "asterix/player_runtime.hpp"
#include "asterix/player_animation_runtime.hpp"
#include "asterix/camera_runtime.hpp"
#include "asterix/combat_runtime.hpp"
#include "asterix/enemy_runtime.hpp"
#include "asterix/interactive_runtime.hpp"
#include "asterix/audio_runtime.hpp"
#include "asterix/animation_runtime.hpp"
#include "asterix/animation_pose_runtime.hpp"
#include "asterix/fog_volume_runtime.hpp"

typedef struct {
  vector_float3 position;
  vector_float3 color;
  vector_float3 normal;
  vector_float2 uv;
  float alpha;
  float ambient;
  float diffuse;
  vector_float4 prelight;
  vector_uint4 joints;
  vector_float4 weights;
  uint32_t objectId;
} AsterixVertex;

typedef struct {
  matrix_float4x4 transform;
  uint32_t textured;
  float fogStart;
  float fogEnd;
  uint32_t debugOptions;
  float alphaCutoff;
  float effectTime;
  uint32_t effect;
  vector_float2 uvOffset;
  vector_float4 volumeFogColor;
  float volumeFogAmount;
} AsterixUniforms;

typedef struct {
  vector_float3 position;
  float rate;
  uint32_t mode;
  uint32_t objectId;
  __unsafe_unretained id<MTLTexture> texture;
} AsterixFireEmitter;

typedef struct {
  NSUInteger vertexStart;
  NSUInteger vertexCount;
  __unsafe_unretained id<MTLTexture> texture;
  __unsafe_unretained id<MTLSamplerState> sampler;
  float alphaCutoff;
  BOOL blended;
  vector_float2 waterSpeed;
  float waterPhase;
} AsterixMeshRange;

static NSString* AsterixTextureKey(NSString* name) {
  if (![name isKindOfClass:NSString.class]) return nil;
  NSString* key = name.lastPathComponent.stringByDeletingPathExtension.lowercaseString;
  return key.length == 0 ? nil : key;
}

static void AsterixWriteMarker(AsterixVertex* vertices,
                               asterix::collision::Vec3 position,
                               vector_float3 color,uint32_t objectId) {
  const vector_float3 p={position.x,position.y,position.z};
  const vector_float3 points[6]={
      p+(vector_float3){-.35f,0,0},p+(vector_float3){.35f,0,0},p+(vector_float3){0,1.4f,0},
      p+(vector_float3){0,0,-.35f},p+(vector_float3){0,0,.35f},p+(vector_float3){0,1.4f,0}};
  for(NSUInteger i=0;i<6;++i)
    vertices[i]={points[i],color,{0,1,0},{0,0},1,1,0,{1,1,1,1},{0,0,0,0},{1,0,0,0},objectId};
}

static asterix::scene::Frustum AsterixFrustum(matrix_float4x4 matrix) {
  asterix::scene::Frustum result;
  const vector_float4 rows[] = {
      {matrix.columns[0].x, matrix.columns[1].x, matrix.columns[2].x, matrix.columns[3].x},
      {matrix.columns[0].y, matrix.columns[1].y, matrix.columns[2].y, matrix.columns[3].y},
      {matrix.columns[0].z, matrix.columns[1].z, matrix.columns[2].z, matrix.columns[3].z},
      {matrix.columns[0].w, matrix.columns[1].w, matrix.columns[2].w, matrix.columns[3].w},
  };
  const vector_float4 planes[] = {rows[3] + rows[0], rows[3] - rows[0],
                                   rows[3] + rows[1], rows[3] - rows[1],
                                   rows[2], rows[3] - rows[2]};
  for (NSUInteger i = 0; i < 6; ++i) {
    const float length = simd_length(planes[i].xyz);
    result.planes[i] = {planes[i].x / length, planes[i].y / length,
                        planes[i].z / length, planes[i].w / length};
  }
  return result;
}

static uint32_t AsterixReadU32(const uint8_t* p) {
  return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
         (uint32_t)p[3] << 24;
}

static uint64_t AsterixReadU64(const uint8_t* p) {
  return (uint64_t)AsterixReadU32(p) | (uint64_t)AsterixReadU32(p + 4) << 32;
}

static NSArray* AsterixVec3Array(asterix::collision::Vec3 value) {
  return @[@(value.x),@(value.y),@(value.z)];
}

static BOOL AsterixReadVec3(id value,asterix::collision::Vec3& result) {
  if(![value isKindOfClass:NSArray.class]||[(NSArray*)value count]!=3)return NO;
  NSArray* values=(NSArray*)value;
  for(id item in values)if(![item isKindOfClass:NSNumber.class])return NO;
  result={(float)[values[0] doubleValue],(float)[values[1] doubleValue],
          (float)[values[2] doubleValue]};
  return std::isfinite(result.x)&&std::isfinite(result.y)&&std::isfinite(result.z);
}

static BOOL AsterixReadMatrix(NSArray* values, asterix::scene::Matrix4& result) {
  if (![values isKindOfClass:NSArray.class] || values.count != 16) return NO;
  for (NSUInteger i = 0; i < 16; ++i) {
    if (![values[i] isKindOfClass:NSNumber.class]) return NO;
    result.value[i] = [values[i] floatValue];
    if (!std::isfinite(result.value[i])) return NO;
  }
  // RenderWare RwMatrix uses the fourth lane of each vector for flags/padding,
  // not homogeneous matrix components.
  result.value[3]=result.value[7]=result.value[11]=0;
  result.value[15]=1;
  return YES;
}

static BOOL AsterixReadClip(NSDictionary* json, BOOL looping,
                            asterix::animation::Clip& result) {
  const NSUInteger jointCount = [json[@"nodeCount"] unsignedIntegerValue];
  const NSUInteger keySize = [json[@"keyFrameSize"] unsignedIntegerValue];
  NSArray* values = json[@"frames"];
  if (jointCount == 0 || keySize == 0 || ![values isKindOfClass:NSArray.class]) return NO;
  std::vector<asterix::animation::RawKeyframe> frames;
  frames.reserve(values.count);
  for (NSDictionary* value in values) {
    NSArray* q = value[@"quaternion"];
    NSArray* t = value[@"translation"];
    if (![q isKindOfClass:NSArray.class] || q.count != 4 ||
        ![t isKindOfClass:NSArray.class] || t.count != 3) return NO;
    asterix::animation::RawKeyframe frame;
    frame.time = [value[@"time"] floatValue];
    frame.previous = [value[@"previousFrame"] intValue] / (int)keySize;
    for (NSUInteger i = 0; i < 4; ++i) frame.transform.rotation[i] = [q[i] floatValue];
    for (NSUInteger i = 0; i < 3; ++i) frame.transform.translation[i] = [t[i] floatValue];
    frames.push_back(frame);
  }
  try { result.tracks = asterix::animation::linkedTracks(frames, jointCount); }
  catch (const std::exception&) { return NO; }
  result.duration = [json[@"duration"] floatValue];
  result.looping = looping;
  return result.duration > 0;
}

static std::optional<asterix::animation_controller::Graph>
AsterixReadAuthoredGraph(NSDictionary* json,
                         NSDictionary<NSString*, NSDictionary*>* animations,
                         NSDictionary<NSString*, NSDictionary*>* bindings) {
  using namespace asterix::animation_controller;
  if (![json[@"resourceType"] isEqual:@"asterix.authored-animation-graph"] ||
      [json[@"schemaVersion"] integerValue] != 1 ||
      ![json[@"entryState"] isKindOfClass:NSString.class] ||
      [json[@"states"] count] != 90 || [json[@"transitions"] count] != 90)
    return std::nullopt;
  NSDictionary* profile = json[@"profile"];
  if (![profile[@"id"] isEqual:@"actor:CKHkAsterix"]) return std::nullopt;
  Graph graph;
  graph.profile = [profile[@"id"] UTF8String];
  graph.entry_state = [json[@"entryState"] UTF8String];
  for (NSDictionary* value in json[@"states"]) {
    NSString* identifier = value[@"id"];
    NSString* binding = value[@"binding"];
    NSDictionary* clip = value[@"clip"];
    NSString* asset = clip[@"asset"];
    NSDictionary* animation = animations[binding];
    NSString* expectedSource =
        [asset hasPrefix:@"clip-"]
            ? [[asset substringFromIndex:@"clip-".length]
                  stringByAppendingPathExtension:@"animation.json"]
            : nil;
    if (![identifier isKindOfClass:NSString.class] ||
        ![binding isKindOfClass:NSString.class] ||
        ![asset isKindOfClass:NSString.class] ||
        ![clip[@"dictionary"] isKindOfClass:NSNumber.class] ||
        ![clip[@"slot"] isKindOfClass:NSNumber.class] ||
        ![value[@"playback"][@"rate"] isKindOfClass:NSNumber.class] ||
        ![value[@"phaseEvents"][@"initialPhase"] isKindOfClass:NSNumber.class] ||
        ![identifier isEqual:[@"binding:" stringByAppendingString:binding]] ||
        ![bindings[binding][@"clip"] isEqual:expectedSource] ||
        animation == nil)
      return std::nullopt;
    const double duration = [animation[@"duration"] doubleValue];
    const double rate = [value[@"playback"][@"rate"] doubleValue];
    const double phase = [value[@"phaseEvents"][@"initialPhase"] doubleValue];
    NSString* rootPolicy = value[@"rootMotion"][@"policy"];
    RootMotionPolicy rootMotion;
    if ([rootPolicy isEqual:@"inPlace"]) rootMotion = RootMotionPolicy::in_place;
    else if ([rootPolicy isEqual:@"physicsDriven"])
      rootMotion = RootMotionPolicy::physics_driven;
    else if ([rootPolicy isEqual:@"authored"])
      rootMotion = RootMotionPolicy::authored;
    else return std::nullopt;
    graph.states.push_back({
        [identifier UTF8String],
        {[clip[@"dictionary"] intValue], [clip[@"slot"] intValue],
         [asset UTF8String]},
        duration, rate, phase, rootMotion});
  }
  for (NSDictionary* value in json[@"transitions"]) {
    NSString* identifier = value[@"id"];
    NSString* from = value[@"fromState"];
    NSString* to = value[@"toState"];
    NSString* completion = value[@"completion"][@"kind"];
    NSString* operation = value[@"operation"];
    if (![identifier isKindOfClass:NSString.class] ||
        ![from isKindOfClass:NSString.class] ||
        ![to isKindOfClass:NSString.class] ||
        ![completion isKindOfClass:NSString.class] ||
        ![operation isKindOfClass:NSString.class])
      return std::nullopt;
    Completion completionValue;
    if ([completion isEqual:@"loop"]) completionValue = Completion::loop;
    else if ([completion isEqual:@"authoredClipEnd"])
      completionValue = Completion::authored_clip_end;
    else if ([completion isEqual:@"landing"])
      completionValue = Completion::landing;
    else if ([completion isEqual:@"terminal"])
      completionValue = Completion::terminal;
    else return std::nullopt;
    Operation operationValue;
    if ([operation isEqual:@"start"]) operationValue = Operation::start;
    else if ([operation isEqual:@"change"]) operationValue = Operation::change;
    else return std::nullopt;
    graph.transitions.push_back({
        [identifier UTF8String], [from UTF8String], [to UTF8String],
        completionValue, operationValue, [value[@"blend"][@"seconds"] doubleValue]});
  }
  return graph;
}

static matrix_float4x4 AsterixMetalMatrix(const asterix::scene::Matrix4& value) {
  matrix_float4x4 result;
  for (NSUInteger i = 0; i < 16; ++i) result.columns[i / 4][i % 4] = value.value[i];
  return result;
}

static matrix_float4x4 AsterixPerspective(float fovY, float aspect,
                                           float nearZ, float farZ) {
  const float y = 1.0f / tanf(fovY * 0.5f);
  const float x = y / aspect;
  const float z = farZ / (nearZ - farZ);
  return (matrix_float4x4){{{x, 0, 0, 0}, {0, y, 0, 0},
                            {0, 0, z, -1}, {0, 0, z * nearZ, 0}}};
}

static matrix_float4x4 AsterixLookAt(vector_float3 eye, vector_float3 target) {
  vector_float3 backward = simd_normalize(eye - target);
  vector_float3 right = simd_normalize(simd_cross((vector_float3){0,1,0}, backward));
  if (!isfinite(right.x)) right = (vector_float3){1,0,0};
  vector_float3 up = simd_cross(backward, right);
  return (matrix_float4x4){{
      {right.x, up.x, backward.x, 0},
      {right.y, up.y, backward.y, 0},
      {right.z, up.z, backward.z, 0},
      {-simd_dot(right,eye),-simd_dot(up,eye),-simd_dot(backward,eye),1}}};
}

struct AsterixPushMesh {
  std::uint32_t id=0;
  NSUInteger vertexStart=0;
  NSUInteger vertexCount=0;
  float appliedOffset=0;
};

@implementation AsterixMetalRenderer {
  __weak MTKView* _view;
  id<MTLCommandQueue> _commandQueue;
  id<MTLRenderPipelineState> _pipeline;
  id<MTLDepthStencilState> _depthState;
  id<MTLDepthStencilState> _readOnlyDepthState;
  id<MTLSamplerState> _defaultSampler;
  id<MTLBuffer> _vertices;
  id<MTLBuffer> _sceneVertices;
  id<MTLBuffer> _collisionVertices;
  id<MTLBuffer> _fireVertices;
  id<MTLTexture> _sceneTexture;
  NSArray<id<MTLTexture>>* _sceneTextures;
  NSArray<id<MTLSamplerState>>* _sceneSamplers;
  NSUInteger _sceneVertexCount;
  NSUInteger _sceneMeshCount;
  NSUInteger _collisionTriangleCount;
  NSUInteger _visibleMeshCount;
  NSUInteger _drawBatchCount;
  NSUInteger _playerMarkerVertexStart;
  NSUInteger _playerMeshVertexStart;
  NSUInteger _playerMeshVertexCount;
  std::vector<AsterixMeshRange> _playerMeshRanges;
  std::vector<asterix::animation::Joint> _playerJoints;
  std::unordered_map<std::string, asterix::animation::Clip> _playerClips;
  std::vector<asterix::animation::Clip> _animationReviewClips;
  NSArray<NSDictionary*>* _animationReviewCandidates;
  NSString* _animationReviewClip;
  CFTimeInterval _animationReviewStartedAt;
  NSUInteger _enemyMarkerVertexStart;
  std::vector<std::vector<AsterixMeshRange>> _sceneMeshRanges;
  std::vector<AsterixFireEmitter> _fireEmitters;
  std::vector<AsterixPushMesh> _pushMeshes;
  std::unique_ptr<asterix::scene::Runtime> _sceneRuntime;
  NSString* _sceneError;
  vector_float3 _sceneCenter;
  float _sceneRadius;
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
  asterix::simulation::FixedTimestep _simulationClock;
  float _previousAnimationPhase;
  float _currentAnimationPhase;
  CFTimeInterval _lastSimulationTime;
  uint32_t _debugOptions;
  std::unique_ptr<asterix::collision::World> _collisionWorld;
  std::unique_ptr<asterix::collision::CapsuleController> _capsuleController;
  std::unique_ptr<asterix::player::Runtime> _playerRuntime;
  std::unique_ptr<asterix::player_animation::Runtime> _playerAnimationRuntime;
  asterix::animation_controller::Snapshot _previousPlayerPose;
  asterix::animation_controller::Snapshot _currentPlayerPose;
  std::unique_ptr<asterix::collision::CapsuleController> _enemyCapsuleController;
  std::unique_ptr<asterix::enemy::Runtime> _enemyRuntime;
  std::unique_ptr<asterix::interactive::Runtime> _interactiveRuntime;
  std::unique_ptr<asterix::camera::Runtime> _cameraRuntime;
  std::unique_ptr<asterix::combat::Runtime> _combatRuntime;
  std::unique_ptr<asterix::audio::Runtime> _audioRuntime;
  std::unique_ptr<asterix::fog_volume::Runtime> _fogRuntime;
  AsterixAudioEngine* _audioEngine;
  float _footstepSeconds;
  asterix::player::Input _playerInput;
  bool _combatAttackWasPressed;
  bool _interactPressed;
  bool _interactWasPressed;
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
    _lastSimulationTime = _startTime;
    _audioRuntime = std::make_unique<asterix::audio::Runtime>();
    _audioEngine = [[AsterixAudioEngine alloc] init];
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
      "struct V { float3 p; float3 c; float3 n; float2 uv; float a; float ambient; float diffuse; float4 prelight; uint4 joints; float4 weights; uint objectId; }; struct U { float4x4 m; uint textured; float fogStart; float fogEnd; uint debugOptions; float alphaCutoff; float effectTime; uint effect; float2 uvOffset; float4 volumeFogColor; float volumeFogAmount; };\n"
      "struct O { float4 p [[position]]; float3 c; float3 n; float2 uv; float a; float distance; float ambient; float diffuse; float4 prelight; };\n"
      "vertex O vs(uint i [[vertex_id]], constant V* v [[buffer(0)]], constant U& u [[buffer(1)]], constant float4x4* bones [[buffer(2)]]) { O o; float4 local=float4(v[i].p,1); float4 skinned=float4(0); float3 normal=float3(0); for(uint j=0;j<4;j++){ float4x4 bone=bones[v[i].joints[j]]; skinned+=bone*local*v[i].weights[j]; normal+=float3x3(bone[0].xyz,bone[1].xyz,bone[2].xyz)*v[i].n*v[i].weights[j]; } float4 p=u.m*skinned; o.p=p; uint h=v[i].objectId*1664525u+1013904223u; o.c=(u.debugOptions&16u)!=0?float3(float(h&255u),float((h>>8)&255u),float((h>>16)&255u))/255.0:v[i].c; o.n=normal; o.uv=v[i].uv+u.uvOffset; o.a=v[i].a; o.distance=abs(p.w); o.ambient=v[i].ambient; o.diffuse=v[i].diffuse; o.prelight=v[i].prelight; return o; }\n"
      "fragment float4 fs(O i [[stage_in]], constant U& u [[buffer(1)]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) { float4 base=u.textured != 0 ? t.sample(s,i.uv)*float4(i.c,i.a) : float4(i.c,i.a); base*=i.prelight; if(base.a<u.alphaCutoff) discard_fragment(); if(u.effect==1u){ float pulse=.82+.18*sin(u.effectTime*12.566+i.uv.y*3.14159); base.rgb*=pulse; return base; } float light=saturate(i.ambient+i.diffuse*max(dot(normalize(i.n),normalize(float3(.35,.8,.45))),0.0)); base.rgb*=light; float fog=saturate((u.fogEnd-i.distance)/max(.001,u.fogEnd-u.fogStart)); float3 distanceFog=mix(float3(.58,.68,.72),base.rgb,fog); return float4(mix(distanceFog,u.volumeFogColor.rgb,saturate(u.volumeFogAmount)),base.a); }";
  NSError* error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  if (library == nil) {
    _sceneError = [NSString stringWithFormat:@"Metal shader compilation failed: %@",
                                             error.localizedDescription ?: @"unknown error"];
    NSLog(@"%@", _sceneError);
    return;
  }
  MTLRenderPipelineDescriptor* descriptor = [MTLRenderPipelineDescriptor new];
  descriptor.vertexFunction = [library newFunctionWithName:@"vs"];
  descriptor.fragmentFunction = [library newFunctionWithName:@"fs"];
  descriptor.colorAttachments[0].pixelFormat = colorFormat;
  descriptor.colorAttachments[0].blendingEnabled = YES;
  descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
  descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
  descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
  descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
  descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  descriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
  _pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
  if (_pipeline == nil) {
    _sceneError = [NSString stringWithFormat:@"Metal pipeline creation failed: %@",
                                             error.localizedDescription ?: @"unknown error"];
  }
  MTLDepthStencilDescriptor* depth = [MTLDepthStencilDescriptor new];
  depth.depthCompareFunction = MTLCompareFunctionLess;
  depth.depthWriteEnabled = YES;
  _depthState = [device newDepthStencilStateWithDescriptor:depth];
  depth.depthWriteEnabled = NO;
  _readOnlyDepthState = [device newDepthStencilStateWithDescriptor:depth];
  MTLSamplerDescriptor* defaultSampler=[MTLSamplerDescriptor new];
  defaultSampler.minFilter=defaultSampler.magFilter=MTLSamplerMinMagFilterLinear;
  defaultSampler.mipFilter=MTLSamplerMipFilterLinear;
  defaultSampler.sAddressMode=defaultSampler.tAddressMode=MTLSamplerAddressModeRepeat;
  _defaultSampler=[device newSamplerStateWithDescriptor:defaultSampler];
  const AsterixVertex vertices[] = {
      {{0.0f, 0.9f, 0.0f}, {1.0f, 0.75f, 0.12f}, {0, 0, 1}, {0.5f, 0}, 1, .35f, .65f, {1,1,1,1}, {1,0,0,0}, {1,0,0,0}, 1},
      {{-0.8f, -0.65f, 0.0f}, {0.12f, 0.65f, 1.0f}, {0, 0, 1}, {0, 1}, 1, .35f, .65f, {1,1,1,1}, {0,0,0,0}, {1,0,0,0}, 1},
      {{0.8f, -0.65f, 0.0f}, {0.95f, 0.2f, 0.15f}, {0, 0, 1}, {1, 1}, 1, .35f, .65f, {1,1,1,1}, {0,0,0,0}, {1,0,0,0}, 1},
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
- (NSUInteger)sceneMeshCount { @synchronized(self) { return _sceneMeshCount; } }
- (NSUInteger)visibleMeshCount { @synchronized(self) { return _visibleMeshCount; } }
- (NSUInteger)drawBatchCount { @synchronized(self) { return _drawBatchCount; } }
- (NSUInteger)collisionTriangleCount { @synchronized(self) { return _collisionTriangleCount; } }
- (NSString*)playerState { @synchronized(self) {
  if (!_playerRuntime) return @"unavailable";
  NSString* name=[NSString stringWithUTF8String:
      asterix::player::stateName(_playerRuntime->snapshot().state)];
  return name ?: @"unavailable";
} }

- (NSArray<NSDictionary*>*)animationReviewCandidates {
  @synchronized(self) { return _animationReviewCandidates ?: @[]; }
}

- (NSString*)animationReviewClip {
  @synchronized(self) { return _animationReviewClip; }
}

- (BOOL)previewAnimationClip:(NSString*)clip {
  @synchronized(self) {
    NSUInteger index=[_animationReviewCandidates indexOfObjectPassingTest:
        ^BOOL(NSDictionary* candidate, NSUInteger _, BOOL* stop) {
          return [candidate[@"clip"] isEqual:clip];
        }];
    if(index==NSNotFound||index>=_animationReviewClips.size())return NO;
    _animationReviewClip=[clip copy];
    _animationReviewStartedAt=CACurrentMediaTime();
    return YES;
  }
}

- (void)clearAnimationPreview {
  @synchronized(self) {
    _animationReviewClip=nil;
    _animationReviewStartedAt=0;
  }
}
- (NSInteger)playerHealth { @synchronized(self) { return _playerRuntime ? _playerRuntime->snapshot().health : 0; } }
- (NSInteger)playerMaximumHealth { @synchronized(self) {
  return _playerRuntime ? _playerRuntime->config().maximum_health : 0;
} }
- (vector_float3)playerPosition { @synchronized(self) {
  if (!_playerRuntime) return (vector_float3){0,0,0};
  const auto p=_playerRuntime->snapshot().body.position;
  return (vector_float3){p.x,p.y,p.z};
} }
- (NSString*)enemyState { @synchronized(self) {
  if (!_enemyRuntime) return @"unavailable";
  NSString* name=[NSString stringWithUTF8String:
      asterix::enemy::stateName(_enemyRuntime->snapshot().state)];
  return name ?: @"unavailable";
} }
- (NSInteger)enemyHealth { @synchronized(self) {
  return _enemyRuntime ? _enemyRuntime->snapshot().health : 0;
} }
- (vector_float3)enemyPosition { @synchronized(self) {
  if (!_enemyRuntime) return (vector_float3){0,0,0};
  const auto p=_enemyRuntime->snapshot().body.position;
  return (vector_float3){p.x,p.y,p.z};
} }
- (NSInteger)rewardCount { @synchronized(self) {
  return _interactiveRuntime ? _interactiveRuntime->snapshot().rewards : 0;
} }
- (NSUInteger)activeCheckpoint { @synchronized(self) {
  return _interactiveRuntime ? _interactiveRuntime->snapshot().active_checkpoint : 0;
} }
- (BOOL)leverActivated { @synchronized(self) {
  return _interactiveRuntime&&!_interactiveRuntime->levers().empty()&&
      _interactiveRuntime->levers().front().activated;
} }
- (BOOL)destructibleDestroyed { @synchronized(self) {
  return _interactiveRuntime&&!_interactiveRuntime->destructibles().empty()&&
      _interactiveRuntime->destructibles().front().destroyed;
} }
- (NSString*)interactionHint { @synchronized(self) {
  if(!_interactiveRuntime||!_playerRuntime)return @"";
  const auto hint=_interactiveRuntime->hint(_playerRuntime->snapshot().body.position,
      _playerRuntime->snapshot().state==asterix::player::State::death);
  NSString* name=[NSString stringWithUTF8String:asterix::interactive::hintName(hint)];
  return name ?: @"";
} }
- (float)cameraFieldOfView { @synchronized(self) {
  return _cameraRuntime ? _cameraRuntime->snapshot().field_of_view_degrees : 70;
} }
- (BOOL)cameraCollisionLimited { @synchronized(self) {
  return _cameraRuntime && _cameraRuntime->snapshot().collision_limited;
} }
- (BOOL)combatActive { @synchronized(self) {
  return _combatRuntime && _combatRuntime->attack().active;
} }
- (NSUInteger)comboStage { @synchronized(self) {
  return _combatRuntime && _combatRuntime->attack().active
      ? _combatRuntime->attack().stage + 1 : 0;
} }
- (BOOL)combatHitWindow { @synchronized(self) {
  return _combatRuntime && _combatRuntime->attack().hit_window;
} }
- (BOOL)audioReady { return _audioEngine.ready; }
- (NSUInteger)activeAudioEffects { return _audioEngine.activeEffectCount; }
- (void)setMusicVolume:(float)music effectsVolume:(float)effects {
  @synchronized(self) {
    _audioRuntime->setVolumes(music,effects);
    [_audioEngine setMusicVolume:music effectsVolume:effects];
  }
}
- (uint32_t)debugOptions { @synchronized(self) { return _debugOptions; } }
- (void)setDebugOptions:(uint32_t)options { @synchronized(self) { _debugOptions = options & 31u; } }
- (NSUInteger)residentSectionCount {
  @synchronized(self) {
    if (!_sceneRuntime) return 0;
    NSUInteger count = 0;
    for (const auto& section : _sceneRuntime->sections()) if (section.resident) ++count;
    return count;
  }
}
- (NSString*)sceneError { @synchronized(self) { return _sceneError; } }
- (void)reportSceneError:(NSString*)message {
  @synchronized(self) { if (_sceneError == nil) _sceneError = [message copy]; }
}

- (NSDictionary*)gameplaySaveState { @synchronized(self) {
  if(!_playerRuntime||!_enemyRuntime||!_interactiveRuntime)return @{};
  const auto player=_playerRuntime->snapshot();
  const auto enemy=_enemyRuntime->snapshot();
  const auto world=_interactiveRuntime->persistentState();
  NSMutableArray* triggers=[NSMutableArray array];
  for(bool value:world.triggers_fired)[triggers addObject:@(value)];
  NSMutableArray* levers=[NSMutableArray array];
  for(bool value:world.levers_activated)[levers addObject:@(value)];
  NSMutableArray* objects=[NSMutableArray array];
  for(auto value:world.destructible_health)[objects addObject:@(value)];
  NSMutableArray* available=[NSMutableArray array];
  for(bool value:world.rewards_available)[available addObject:@(value)];
  NSMutableArray* collected=[NSMutableArray array];
  for(bool value:world.rewards_collected)[collected addObject:@(value)];
  NSMutableArray* pushBlocks=[NSMutableArray array];
  for(float value:world.push_block_offsets)[pushBlocks addObject:@(value)];
  return @{ @"player":@{ @"position":AsterixVec3Array(player.body.position),
                           @"checkpoint":AsterixVec3Array(player.body.checkpoint),
                           @"health":@(player.health)},
            @"enemy":@{ @"position":AsterixVec3Array(enemy.body.position),
                          @"health":@(enemy.health)},
            @"presentation":@{ @"simulationSeconds":@(_currentAnimationPhase)},
            @"world":@{ @"rewards":@(world.snapshot.rewards),
                          @"checkpoint":@(world.snapshot.active_checkpoint),
                          @"triggers":triggers,@"levers":levers,@"objects":objects,
                          @"rewardAvailable":available,@"rewardCollected":collected,
                          @"pushBlocks":pushBlocks} };
} }

- (BOOL)restoreGameplaySaveState:(NSDictionary*)state { @synchronized(self) {
  if(!_playerRuntime||!_enemyRuntime||!_interactiveRuntime||!_combatRuntime||
     ![state isKindOfClass:NSDictionary.class])return NO;
  NSDictionary* player=state[@"player"];
  NSDictionary* enemy=state[@"enemy"];
  NSDictionary* world=state[@"world"];
  NSDictionary* presentation=state[@"presentation"];
  if(![player isKindOfClass:NSDictionary.class]||![enemy isKindOfClass:NSDictionary.class]||
     ![world isKindOfClass:NSDictionary.class])return NO;
  if(presentation!=nil&&(![presentation isKindOfClass:NSDictionary.class]||
     ![presentation[@"simulationSeconds"] isKindOfClass:NSNumber.class]||
     !std::isfinite([presentation[@"simulationSeconds"] doubleValue])||
     [presentation[@"simulationSeconds"] doubleValue]<0))return NO;
  asterix::collision::Vec3 playerPosition,checkpoint,enemyPosition;
  if(!AsterixReadVec3(player[@"position"],playerPosition)||
     !AsterixReadVec3(player[@"checkpoint"],checkpoint)||
     !AsterixReadVec3(enemy[@"position"],enemyPosition)||
     ![player[@"health"] isKindOfClass:NSNumber.class]||
     ![enemy[@"health"] isKindOfClass:NSNumber.class])return NO;
  const auto booleans=[](id value,std::vector<bool>& output) {
    if(![value isKindOfClass:NSArray.class])return false;
    for(id item in (NSArray*)value) {
      if(![item isKindOfClass:NSNumber.class])return false;
      output.push_back([item boolValue]);
    }
    return true;
  };
  asterix::interactive::PersistentState persistent;
  if(![world[@"rewards"] isKindOfClass:NSNumber.class]||
     ![world[@"checkpoint"] isKindOfClass:NSNumber.class]||
     !booleans(world[@"triggers"],persistent.triggers_fired)||
     !booleans(world[@"levers"],persistent.levers_activated)||
     !booleans(world[@"rewardAvailable"],persistent.rewards_available)||
     !booleans(world[@"rewardCollected"],persistent.rewards_collected)||
     ![world[@"objects"] isKindOfClass:NSArray.class])return NO;
  persistent.snapshot.rewards=[world[@"rewards"] intValue];
  persistent.snapshot.active_checkpoint=[world[@"checkpoint"] unsignedIntValue];
  for(id item in (NSArray*)world[@"objects"]) {
    if(![item isKindOfClass:NSNumber.class])return NO;
    persistent.destructible_health.push_back([item intValue]);
  }
  id pushValues=world[@"pushBlocks"];
  if(pushValues==nil)persistent.push_block_offsets.assign(
      _interactiveRuntime->pushBlocks().size(),0);
  else {
    if(![pushValues isKindOfClass:NSArray.class])return NO;
    for(id item in (NSArray*)pushValues) {
      if(![item isKindOfClass:NSNumber.class]||!std::isfinite([item doubleValue]))return NO;
      persistent.push_block_offsets.push_back([item floatValue]);
    }
  }
  const int playerHealth=[player[@"health"] intValue];
  const int enemyHealth=[enemy[@"health"] intValue];
  if(playerHealth<0||playerHealth>_playerRuntime->config().maximum_health||
     enemyHealth<0||enemyHealth>3||
     !_interactiveRuntime->restorePersistent(persistent)||
     !_playerRuntime->restore(playerPosition,checkpoint,playerHealth)||
     !_enemyRuntime->restore(enemyPosition,enemyHealth))return NO;
  _combatRuntime->cancelAttack();
  _combatRuntime->setFighterHealth(1,playerHealth);
  _combatRuntime->setFighterHealth(2,enemyHealth);
  if(!persistent.destructible_health.empty())
    _combatRuntime->setFighterHealth(100,persistent.destructible_health.front());
  if(presentation!=nil) {
    _currentAnimationPhase=[presentation[@"simulationSeconds"] floatValue];
    _previousAnimationPhase=_currentAnimationPhase;
    if(_fogRuntime&&!_fogRuntime->restore({[presentation[@"simulationSeconds"] doubleValue],
                                           _fogRuntime->snapshot().streamed}))return NO;
  }
  return YES;
} }

- (BOOL)loadAssetPackageAtURL:(NSURL*)url {
  MTKView* view = _view;
  NSError* error = nil;
  NSData* package = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
  if (package.length < 48) {
    @synchronized(self) { _sceneError = error.localizedDescription ?: @"ASTPAK header is truncated"; }
    return NO;
  }
  const uint8_t* bytes = (const uint8_t*)package.bytes;
  const uint8_t magic[] = {'A','S','T','P','A','K','\r','\n'};
  uint64_t manifestLength = AsterixReadU64(bytes + 24);
  uint64_t payloadOffset = AsterixReadU64(bytes + 32);
  uint64_t payloadLength = AsterixReadU64(bytes + 40);
  if (memcmp(bytes, magic, 8) != 0 || AsterixReadU32(bytes + 8) != 1 ||
      manifestLength > package.length - 48 || payloadOffset > package.length ||
      payloadLength > package.length - payloadOffset) {
    @synchronized(self) { _sceneError = @"Invalid ASTPAK header or ranges"; }
    return NO;
  }
  NSData* manifestData = [package subdataWithRange:NSMakeRange(48, (NSUInteger)manifestLength)];
  NSDictionary* manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
  if (![manifest isKindOfClass:NSDictionary.class]) {
    @synchronized(self) { _sceneError = error.localizedDescription ?: @"Invalid ASTPAK manifest"; }
    return NO;
  }
  NSMutableDictionary<NSString*, NSDictionary*>* resources = [NSMutableDictionary dictionary];
  for (NSDictionary* item in manifest[@"resources"]) if ([item isKindOfClass:NSDictionary.class]) {
    NSString* identifier = item[@"id"];
    if (identifier) resources[identifier] = item;
  }
  NSData* audioData = nil;
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"audio"]) continue;
    uint64_t offset=[resource[@"offset"] unsignedLongLongValue];
    uint64_t length=[resource[@"length"] unsignedLongLongValue];
    if(offset<=payloadLength&&length<=payloadLength-offset)
      audioData=[package subdataWithRange:NSMakeRange((NSUInteger)(payloadOffset+offset),(NSUInteger)length)];
    break;
  }
  NSMutableDictionary<NSString*, id<MTLTexture>>* textures = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString*, NSNumber*>* textureAlphaModes = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString*, id<MTLSamplerState>>* samplerStates = [NSMutableDictionary dictionary];
  id<MTLTexture> selectedTexture = nil;
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"texture"]) continue;
    NSString* name = resource[@"metadata"][@"name"];
    uint64_t offset = [resource[@"offset"] unsignedLongLongValue];
    uint64_t length = [resource[@"length"] unsignedLongLongValue];
    if (!name || offset > payloadLength || length > payloadLength - offset || length < 40) continue;
    const uint8_t* textureBytes = bytes + payloadOffset + offset;
    if (memcmp(textureBytes, "ASTMTEX\n", 8) != 0 || AsterixReadU32(textureBytes + 8) != 1) continue;
    uint32_t levels = AsterixReadU32(textureBytes + 16), dataOffset = AsterixReadU32(textureBytes + 20);
    uint32_t width = AsterixReadU32(textureBytes + 24), height = AsterixReadU32(textureBytes + 28);
    if (levels == 0 || dataOffset > length || width == 0 || height == 0) continue;
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:levels > 1];
    id<MTLTexture> texture = [view.device newTextureWithDescriptor:descriptor];
    for (uint32_t level = 0; level < levels; ++level) {
      uint64_t entry = 24 + (uint64_t)level * 16;
      if (entry + 16 > length) break;
      uint32_t w = AsterixReadU32(textureBytes + entry), h = AsterixReadU32(textureBytes + entry + 4);
      uint32_t relative = AsterixReadU32(textureBytes + entry + 8), size = AsterixReadU32(textureBytes + entry + 12);
      if ((uint64_t)dataOffset + relative + size > length || size != w * h * 4) break;
      [texture replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:level withBytes:textureBytes + dataOffset + relative bytesPerRow:w * 4];
    }
    BOOL hasTransparent=NO,hasPartialAlpha=NO;
    if ((uint64_t)dataOffset + width * height * 4 <= length) {
      const uint8_t* pixels=textureBytes+dataOffset;
      for(uint64_t pixel=0;pixel<(uint64_t)width*height;++pixel) {
        const uint8_t alpha=pixels[pixel*4+3];
        if(alpha<255)hasTransparent=YES;
        if(alpha!=0&&alpha!=255){hasPartialAlpha=YES;break;}
      }
    }
    NSString* textureKey=AsterixTextureKey(name);
    if(textureKey) {
      textures[textureKey] = texture;
      textureAlphaModes[textureKey]=@(hasPartialAlpha?2:hasTransparent?1:0);
    }
  }
  std::vector<AsterixFireEmitter> fireEmitters;
  NSUInteger expectedFireEmitters=0;
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"environment-fx"] ||
        ![resource[@"metadata"][@"effect"] isEqual:@"burning-house-fire"]) continue;
    expectedFireEmitters += [resource[@"metadata"][@"emitterCount"] unsignedIntegerValue];
    uint64_t offset=[resource[@"offset"] unsignedLongLongValue];
    uint64_t length=[resource[@"length"] unsignedLongLongValue];
    if(offset>payloadLength||length>payloadLength-offset) continue;
    NSData* data=[package subdataWithRange:NSMakeRange(
        (NSUInteger)(payloadOffset+offset),(NSUInteger)length)];
    NSDictionary* effect=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(![effect isKindOfClass:NSDictionary.class]||
       [effect[@"schemaVersion"] integerValue]!=1||
       ![effect[@"kind"] isEqual:@"burning-house-fire"]) continue;
    for(NSDictionary* emitter in effect[@"emitters"]) {
      asterix::collision::Vec3 position;
      NSString* textureKey=AsterixTextureKey(emitter[@"texture"]);
      id<MTLTexture> texture=textureKey?textures[textureKey]:nil;
      const float rate=[emitter[@"rate"] floatValue];
      if(!AsterixReadVec3(emitter[@"position"],position)||texture==nil||
         !std::isfinite(rate)||rate<=0) continue;
      fireEmitters.push_back({
          {position.x,position.y,position.z},rate,
          (uint32_t)[emitter[@"mode"] unsignedIntValue],
          (uint32_t)[emitter[@"id"] unsignedIntValue],texture});
    }
  }
  if(fireEmitters.size()!=expectedFireEmitters) {
    @synchronized(self) { _sceneError=[NSString stringWithFormat:
        @"Burning-house fire bindings are incomplete (%lu/%lu)",
        (unsigned long)fireEmitters.size(),(unsigned long)expectedFireEmitters]; }
    return NO;
  }
  std::vector<asterix::fog_volume::Profile> fogProfiles;
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"fog-volume"]) continue;
    const uint64_t offset=[resource[@"offset"] unsignedLongLongValue];
    const uint64_t length=[resource[@"length"] unsignedLongLongValue];
    if(offset>payloadLength||length>payloadLength-offset)continue;
    NSData* data=[package subdataWithRange:NSMakeRange((NSUInteger)(payloadOffset+offset),(NSUInteger)length)];
    NSDictionary* fog=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray* matrices=fog[@"matrices"],*origin=fog[@"origin"],*stops=fog[@"colorStops"],*profile=fog[@"profile"];
    if([fog[@"schemaVersion"] integerValue]!=1||![fog[@"kind"] isEqual:@"authored-fog-volume"]||
       matrices.count==0||origin.count!=3||stops.count==0)continue;
    asterix::fog_volume::Vec3 lo={INFINITY,INFINITY,INFINITY},hi={-INFINITY,-INFINITY,-INFINITY};
    for(NSArray* matrix in matrices)if([matrix isKindOfClass:NSArray.class]&&matrix.count==16) {
      const asterix::fog_volume::Vec3 center={[matrix[12] floatValue],[matrix[13] floatValue],[matrix[14] floatValue]};
      lo={std::min(lo.x,center.x),std::min(lo.y,center.y),std::min(lo.z,center.z)};
      hi={std::max(hi.x,center.x),std::max(hi.y,center.y),std::max(hi.z,center.z)};
    }
    const float scale=std::max(.001f,[fog[@"scale"] floatValue]);
    const asterix::fog_volume::Vec3 extent={fabsf([origin[0] floatValue])*scale,
        fabsf([origin[1] floatValue])*scale,fabsf([origin[2] floatValue])*scale};
    lo={lo.x-extent.x,lo.y-extent.y,lo.z-extent.z}; hi={hi.x+extent.x,hi.y+extent.y,hi.z+extent.z};
    std::vector<asterix::fog_volume::Stop> authoredStops;
    for(NSDictionary* stop in stops)if([stop isKindOfClass:NSDictionary.class]) {
      const uint32_t packed=[stop[@"innerColor"] unsignedIntValue];
      authoredStops.push_back({[stop[@"position"] floatValue],std::max(0.0f,[stop[@"density"] floatValue]),
          {(float)(packed&255u)/255.0f,(float)((packed>>8)&255u)/255.0f,
           (float)((packed>>16)&255u)/255.0f,1}});
    }
    fogProfiles.push_back({(uint32_t)fogProfiles.size()+1,lo,hi,
        profile.count>9?std::max(.001f,[profile[9] floatValue]):1,
        profile.count>0?[profile[0] floatValue]:0,std::move(authoredStops)});
  }
  std::unique_ptr<asterix::fog_volume::Runtime> fogRuntime;
  try { if(!fogProfiles.empty())fogRuntime=std::make_unique<asterix::fog_volume::Runtime>(fogProfiles); }
  catch(const std::exception&) { [self reportSceneError:@"Authored fog-volume payload is invalid"]; return NO; }
  NSMutableData* vertexData = [NSMutableData data];
  NSMutableData* collisionVertexData = [NSMutableData data];
  std::vector<asterix::collision::Triangle> collisionTriangles;
  std::vector<asterix::collision::Triangle> visibleGroundTriangles;
  std::optional<asterix::collision::Vec3> authoredCheckpoint;
  std::vector<std::vector<AsterixMeshRange>> meshRanges;
  NSDictionary* playerSkin = nil;
  NSDictionary* playerAccessorySkin = nil;
  NSDictionary* renderComposition = nil;
  NSDictionary* animationBindings = nil;
  NSDictionary* authoredAnimationGraph = nil;
  NSMutableDictionary<NSString*, NSDictionary*>* playerAnimations = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString*, NSDictionary*>* reviewAnimations = [NSMutableDictionary dictionary];
  NSMutableArray<NSDictionary*>* reviewSelectors = [NSMutableArray array];
  std::vector<asterix::scene::Node> runtimeNodes;
  NSUInteger meshCount = 0;
  vector_float3 minimum = {INFINITY, INFINITY, INFINITY};
  vector_float3 maximum = {-INFINITY, -INFINITY, -INFINITY};
  asterix::scene::Runtime transformGraph;
  std::unordered_map<std::string, std::string> payloadNodes;
  std::unordered_map<std::string, std::string> payloadSections;
  NSMutableDictionary<NSString*, NSDictionary*>* pushMetadata=[NSMutableDictionary dictionary];
  std::unordered_map<std::string, vector_float3> sectionMinimums;
  std::unordered_map<std::string, vector_float3> sectionMaximums;
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"render-composition"]) continue;
    const uint64_t offset=[resource[@"offset"] unsignedLongLongValue];
    const uint64_t length=[resource[@"length"] unsignedLongLongValue];
    if(offset<=payloadLength&&length<=payloadLength-offset) {
      NSData* data=[package subdataWithRange:NSMakeRange(
          (NSUInteger)(payloadOffset+offset),(NSUInteger)length)];
      id decoded=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if([decoded isKindOfClass:NSDictionary.class])renderComposition=decoded;
    }
  }
  NSArray* playerLayers=nil;
  if([renderComposition[@"schemaVersion"] integerValue]==1&&
     [renderComposition[@"kind"] isEqual:@"render-composition-manifest"]) {
    for(NSDictionary* composition in renderComposition[@"compositions"]) {
      if(![composition[@"actor"] isEqual:@"asterix"]||
         ![composition[@"costume"] isEqual:@"default"]||
         ![composition[@"context"] isEqual:@"gameplay"])continue;
      if(playerLayers!=nil) {
        [self reportSceneError:@"Ambiguous render composition for asterix/default/gameplay"];
        return NO;
      }
      playerLayers=composition[@"layers"];
    }
  }
  if(playerLayers.count==0) {
    [self reportSceneError:@"Missing render composition for asterix/default/gameplay"];
    return NO;
  }
  NSMutableSet<NSNumber*>* playerSkinIds=[NSMutableSet set];
  for(NSDictionary* layer in playerLayers) {
    NSNumber* skin=layer[@"skin"];
    NSString* role=layer[@"role"];
    if(![skin isKindOfClass:NSNumber.class]||![role isKindOfClass:NSString.class]||
       ![layer[@"required"] boolValue]||[playerSkinIds containsObject:skin]) {
      [self reportSceneError:@"Malformed or duplicate asterix render-composition layer"];
      return NO;
    }
    [playerSkinIds addObject:skin];
  }
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"skin"]) continue;
    const NSInteger objectId=[resource[@"metadata"][@"objectId"] integerValue];
    if(![playerSkinIds containsObject:@(objectId)])continue;
    uint64_t offset=[resource[@"offset"] unsignedLongLongValue];
    uint64_t length=[resource[@"length"] unsignedLongLongValue];
    if(offset<=payloadLength&&length<=payloadLength-offset) {
      NSData* data=[package subdataWithRange:NSMakeRange(
          (NSUInteger)(payloadOffset+offset),(NSUInteger)length)];
      NSDictionary* skin=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      NSString* role=nil;
      for(NSDictionary* layer in playerLayers)
        if([layer[@"skin"] integerValue]==objectId){role=layer[@"role"];break;}
      if([role isEqual:@"body"])playerSkin=skin;
      else if(playerAccessorySkin==nil)playerAccessorySkin=skin;
      else {
        [self reportSceneError:@"Runtime does not support multiple accessory layers for asterix"];
        return NO;
      }
    }
  }
  if(playerSkin==nil||(playerLayers.count>1&&playerAccessorySkin==nil)) {
    [self reportSceneError:@"Required asterix render-composition skin payload is missing"];
    return NO;
  }
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"animation-bindings"]) continue;
    uint64_t offset=[resource[@"offset"] unsignedLongLongValue];
    uint64_t length=[resource[@"length"] unsignedLongLongValue];
    if(offset<=payloadLength&&length<=payloadLength-offset) {
      NSData* data=[package subdataWithRange:NSMakeRange((NSUInteger)(payloadOffset+offset),(NSUInteger)length)];
      id decoded=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if([decoded isKindOfClass:NSDictionary.class]) animationBindings=decoded;
    }
    break;
  }
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"authored-animation-graph"]) continue;
    uint64_t offset=[resource[@"offset"] unsignedLongLongValue];
    uint64_t length=[resource[@"length"] unsignedLongLongValue];
    if(offset<=payloadLength&&length<=payloadLength-offset) {
      NSData* data=[package subdataWithRange:NSMakeRange(
          (NSUInteger)(payloadOffset+offset),(NSUInteger)length)];
      id decoded=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if([decoded isKindOfClass:NSDictionary.class])
        authoredAnimationGraph=decoded;
    }
    break;
  }
  if (authoredAnimationGraph == nil) {
    [self reportSceneError:@"Asterix authored animation graph is missing"];
    return NO;
  }
  NSArray<NSString*>* requiredStates=@[
      @"idle",@"run",@"jump",@"double_jump",@"fall",@"attack",@"hurt",@"death"];
  NSMutableDictionary<NSString*, NSDictionary*>* stateBindings=[NSMutableDictionary dictionary];
  NSMutableSet<NSString*>* selectedBindings=[NSMutableSet set];
  NSDictionary* playerProfile=nil;
  NSDictionary* obelixProfile=nil;
  NSDictionary* idefixProfile=nil;
  NSDictionary* basicRomanProfile=nil;
  NSDictionary* romanLeaderEquipmentProfile=nil;
  NSDictionary* romanLeaderBodyProfile=nil;
  NSMutableArray<NSDictionary*>* scriptedCharacterProfiles=[NSMutableArray array];
  NSMutableArray<NSDictionary*>* worldRuntimeProfiles=[NSMutableArray array];
  NSMutableArray<NSDictionary*>* cinematicRuntimeProfiles=[NSMutableArray array];
  if ([animationBindings[@"schemaVersion"] integerValue]==1) {
    if ([animationBindings[@"runtimeProfileVersion"] integerValue]==1) {
      for (NSDictionary* profile in animationBindings[@"runtimeProfiles"]) {
        if (![profile isKindOfClass:NSDictionary.class]) continue;
        if ([profile[@"id"] isEqual:@"asterix-player"]) {
          if (playerProfile!=nil) {
            @synchronized(self) { _sceneError=@"Ambiguous asterix-player runtime profile"; }
            return NO;
          }
          playerProfile=profile;
        } else if ([profile[@"id"] isEqual:@"obelix-player"]) {
          if (obelixProfile!=nil) {
            @synchronized(self) { _sceneError=@"Ambiguous obelix-player runtime profile"; }
            return NO;
          }
          obelixProfile=profile;
        } else if ([profile[@"id"] isEqual:@"idefix-player"]) {
          if (idefixProfile!=nil) {
            @synchronized(self) { _sceneError=@"Ambiguous idefix-player runtime profile"; }
            return NO;
          }
          idefixProfile=profile;
        } else if ([profile[@"id"] isEqual:@"basic-roman-enemy"]) {
          if (basicRomanProfile!=nil) {
            @synchronized(self) { _sceneError=@"Ambiguous basic-roman-enemy runtime profile"; }
            return NO;
          }
          basicRomanProfile=profile;
        } else if ([profile[@"id"] isEqual:@"roman-leader-equipment"]) {
          if (romanLeaderEquipmentProfile!=nil) {
            @synchronized(self) { _sceneError=@"Ambiguous roman-leader-equipment runtime profile"; }
            return NO;
          }
          romanLeaderEquipmentProfile=profile;
        } else if ([profile[@"id"] isEqual:@"roman-leader-body"]) {
          if (romanLeaderBodyProfile!=nil) {
            @synchronized(self) { _sceneError=@"Ambiguous roman-leader-body runtime profile"; }
            return NO;
          }
          romanLeaderBodyProfile=profile;
        } else if ([profile[@"context"] isEqual:@"scripted"]) {
          [scriptedCharacterProfiles addObject:profile];
        } else if ([profile[@"context"] isEqual:@"world"]) {
          [worldRuntimeProfiles addObject:profile];
        } else if ([profile[@"context"] isEqual:@"cinematic"]) {
          [cinematicRuntimeProfiles addObject:profile];
        }
      }
    }
    NSDictionary* selectors=playerProfile[@"states"];
    if (![playerProfile[@"actor"] isEqual:@"asterix"] ||
        [playerProfile[@"skin"] integerValue]!=4 ||
        ![playerProfile[@"costume"] isEqual:@"default"] ||
        ![playerProfile[@"context"] isEqual:@"gameplay"] ||
        ![playerProfile[@"complete"] isKindOfClass:NSNumber.class] ||
        ![playerProfile[@"complete"] boolValue] ||
        ![selectors isKindOfClass:NSDictionary.class] ||
        selectors.count!=90) {
      @synchronized(self) { _sceneError=@"Missing or invalid asterix-player runtime profile"; }
      return NO;
    }
    for (NSString* state in selectors) {
      id rawSelector=selectors[state];
      if (![rawSelector isKindOfClass:NSDictionary.class]) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Invalid runtime selector for asterix/%@",state]; }
        return NO;
      }
      NSDictionary* selector=(NSDictionary*)rawSelector;
      NSString* action=selector[@"action"];
      NSString* variant=selector[@"variant"];
      if (![action isKindOfClass:NSString.class] ||
          ![variant isKindOfClass:NSString.class]) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Invalid runtime selector for asterix/%@",state]; }
        return NO;
      }
      NSString* selectorKey=[NSString stringWithFormat:@"%@|%@",action,variant];
      if ([selectedBindings containsObject:selectorKey]) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Duplicate runtime selector for asterix/%@",state]; }
        return NO;
      }
      [selectedBindings addObject:selectorKey];
      for (NSDictionary* binding in animationBindings[@"bindings"]) {
        if (![binding isKindOfClass:NSDictionary.class] ||
            ![binding[@"actor"] isEqual:playerProfile[@"actor"]] ||
            [binding[@"skin"] integerValue]!=[playerProfile[@"skin"] integerValue] ||
            ![binding[@"costume"] isEqual:playerProfile[@"costume"]] ||
            ![binding[@"context"] isEqual:playerProfile[@"context"]] ||
            ![binding[@"action"] isEqual:action] ||
            ![binding[@"variant"] isEqual:variant]) continue;
        if (stateBindings[state]!=nil) {
          @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Ambiguous runtime selector for asterix/%@",state]; }
          return NO;
        }
        stateBindings[state]=binding;
      }
    }
    if (stateBindings.count!=selectors.count) {
      @synchronized(self) { _sceneError=@"Incomplete asterix-player runtime profile"; }
      return NO;
    }
    NSDictionary* obelixSelectors=obelixProfile[@"states"];
    if (![obelixProfile[@"actor"] isEqual:@"obelix"] ||
        [obelixProfile[@"skin"] integerValue]!=2 ||
        ![obelixProfile[@"costume"] isEqual:@"default"] ||
        ![obelixProfile[@"context"] isEqual:@"gameplay"] ||
        ![obelixProfile[@"complete"] isKindOfClass:NSNumber.class] ||
        ![obelixProfile[@"complete"] boolValue] ||
        ![obelixSelectors isKindOfClass:NSDictionary.class] ||
        obelixSelectors.count!=72) {
      @synchronized(self) { _sceneError=@"Missing or invalid obelix-player runtime profile"; }
      return NO;
    }
    NSMutableSet<NSString*>* obelixSelected=[NSMutableSet set];
    NSUInteger obelixResolved=0;
    for (NSString* state in obelixSelectors) {
      NSDictionary* selector=obelixSelectors[state];
      NSString* action=[selector isKindOfClass:NSDictionary.class] ? selector[@"action"] : nil;
      NSString* variant=[selector isKindOfClass:NSDictionary.class] ? selector[@"variant"] : nil;
      if (![action isKindOfClass:NSString.class] ||
          ![variant isKindOfClass:NSString.class]) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Invalid runtime selector for obelix/%@",state]; }
        return NO;
      }
      NSString* selectorKey=[NSString stringWithFormat:@"%@|%@",action,variant];
      if ([obelixSelected containsObject:selectorKey]) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Duplicate runtime selector for obelix/%@",state]; }
        return NO;
      }
      [obelixSelected addObject:selectorKey];
      NSUInteger matches=0;
      for (NSDictionary* binding in animationBindings[@"bindings"]) {
        if (![binding isKindOfClass:NSDictionary.class] ||
            ![binding[@"actor"] isEqual:obelixProfile[@"actor"]] ||
            [binding[@"skin"] integerValue]!=[obelixProfile[@"skin"] integerValue] ||
            ![binding[@"costume"] isEqual:obelixProfile[@"costume"]] ||
            ![binding[@"context"] isEqual:obelixProfile[@"context"]] ||
            ![binding[@"action"] isEqual:action] ||
            ![binding[@"variant"] isEqual:variant]) continue;
        if ([binding[@"fallback"] boolValue] ||
            [binding[@"skeletonNodes"] integerValue]!=58) {
          @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Invalid runtime binding for obelix/%@",state]; }
          return NO;
        }
        matches++;
      }
      if (matches!=1) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Ambiguous runtime selector for obelix/%@",state]; }
        return NO;
      }
      obelixResolved++;
    }
    if (obelixResolved!=obelixSelectors.count) {
      @synchronized(self) { _sceneError=@"Incomplete obelix-player runtime profile"; }
      return NO;
    }
    NSDictionary* idefixSelectors=idefixProfile[@"states"];
    if (![idefixProfile[@"actor"] isEqual:@"idefix"] ||
        ![idefixProfile[@"skin"] isKindOfClass:NSNumber.class] ||
        [idefixProfile[@"skin"] integerValue]!=0 ||
        ![idefixProfile[@"costume"] isEqual:@"default"] ||
        ![idefixProfile[@"context"] isEqual:@"gameplay"] ||
        ![idefixProfile[@"complete"] isKindOfClass:NSNumber.class] ||
        ![idefixProfile[@"complete"] boolValue] ||
        ![idefixSelectors isKindOfClass:NSDictionary.class] ||
        idefixSelectors.count!=28) {
      @synchronized(self) { _sceneError=@"Missing or invalid idefix-player runtime profile"; }
      return NO;
    }
    NSMutableSet<NSString*>* idefixSelected=[NSMutableSet set];
    NSUInteger idefixResolved=0;
    for (NSString* state in idefixSelectors) {
      NSDictionary* selector=idefixSelectors[state];
      NSString* action=[selector isKindOfClass:NSDictionary.class] ? selector[@"action"] : nil;
      NSString* variant=[selector isKindOfClass:NSDictionary.class] ? selector[@"variant"] : nil;
      if (![action isKindOfClass:NSString.class] ||
          ![variant isKindOfClass:NSString.class]) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Invalid runtime selector for idefix/%@",state]; }
        return NO;
      }
      NSString* selectorKey=[NSString stringWithFormat:@"%@|%@",action,variant];
      if ([idefixSelected containsObject:selectorKey]) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Duplicate runtime selector for idefix/%@",state]; }
        return NO;
      }
      [idefixSelected addObject:selectorKey];
      NSUInteger matches=0;
      for (NSDictionary* binding in animationBindings[@"bindings"]) {
        if (![binding isKindOfClass:NSDictionary.class] ||
            ![binding[@"actor"] isEqual:idefixProfile[@"actor"]] ||
            [binding[@"skin"] integerValue]!=[idefixProfile[@"skin"] integerValue] ||
            ![binding[@"costume"] isEqual:idefixProfile[@"costume"]] ||
            ![binding[@"context"] isEqual:idefixProfile[@"context"]] ||
            ![binding[@"action"] isEqual:action] ||
            ![binding[@"variant"] isEqual:variant]) continue;
        if ([binding[@"fallback"] boolValue] ||
            [binding[@"skeletonNodes"] integerValue]!=31) {
          @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Invalid runtime binding for idefix/%@",state]; }
          return NO;
        }
        matches++;
      }
      if (matches!=1) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Ambiguous runtime selector for idefix/%@",state]; }
        return NO;
      }
      idefixResolved++;
    }
    if (idefixResolved!=idefixSelectors.count) {
      @synchronized(self) { _sceneError=@"Incomplete idefix-player runtime profile"; }
      return NO;
    }
    NSArray<NSDictionary*>* enemyProfileSpecs=@[
      @{@"profile":basicRomanProfile ?: @{}, @"id":@"basic-roman-enemy",
        @"actor":@"basic-enemy:roman", @"skin":@48, @"states":@41, @"nodes":@28},
      @{@"profile":romanLeaderEquipmentProfile ?: @{}, @"id":@"roman-leader-equipment",
        @"actor":@"basic-enemy-leader:roman", @"skin":@27, @"states":@41, @"nodes":@30},
      @{@"profile":romanLeaderBodyProfile ?: @{}, @"id":@"roman-leader-body",
        @"actor":@"basic-enemy-leader:roman", @"skin":@28, @"states":@3, @"nodes":@30}
    ];
    for (NSDictionary* spec in enemyProfileSpecs) {
      NSDictionary* profile=spec[@"profile"];
      NSDictionary* enemySelectors=profile[@"states"];
      NSString* profileId=spec[@"id"];
      if (![profile[@"actor"] isEqual:spec[@"actor"]] ||
          ![profile[@"skin"] isKindOfClass:NSNumber.class] ||
          [profile[@"skin"] integerValue]!=[spec[@"skin"] integerValue] ||
          ![profile[@"costume"] isEqual:@"roman-default"] ||
          ![profile[@"context"] isEqual:@"gameplay"] ||
          ![profile[@"complete"] isKindOfClass:NSNumber.class] ||
          ![profile[@"complete"] boolValue] ||
          ![enemySelectors isKindOfClass:NSDictionary.class] ||
          enemySelectors.count!=[spec[@"states"] unsignedIntegerValue]) {
        @synchronized(self) { _sceneError=[NSString stringWithFormat:
            @"Missing or invalid %@ runtime profile",profileId]; }
        return NO;
      }
      NSMutableSet<NSString*>* enemySelected=[NSMutableSet set];
      for (NSString* state in enemySelectors) {
        NSDictionary* selector=enemySelectors[state];
        NSString* action=[selector isKindOfClass:NSDictionary.class] ? selector[@"action"] : nil;
        NSString* variant=[selector isKindOfClass:NSDictionary.class] ? selector[@"variant"] : nil;
        NSString* selectorKey=(action&&variant)
            ? [NSString stringWithFormat:@"%@|%@",action,variant] : nil;
        if (selectorKey==nil || [enemySelected containsObject:selectorKey]) {
          @synchronized(self) { _sceneError=[NSString stringWithFormat:
              @"Invalid or duplicate runtime selector for %@/%@",profileId,state]; }
          return NO;
        }
        [enemySelected addObject:selectorKey];
        NSUInteger matches=0;
        for (NSDictionary* binding in animationBindings[@"bindings"]) {
          if (![binding isKindOfClass:NSDictionary.class] ||
              ![binding[@"actor"] isEqual:profile[@"actor"]] ||
              [binding[@"skin"] integerValue]!=[profile[@"skin"] integerValue] ||
              ![binding[@"costume"] isEqual:profile[@"costume"]] ||
              ![binding[@"context"] isEqual:profile[@"context"]] ||
              ![binding[@"action"] isEqual:action] ||
              ![binding[@"variant"] isEqual:variant]) continue;
          if ([binding[@"fallback"] boolValue] ||
              [binding[@"skeletonNodes"] integerValue]!=[spec[@"nodes"] integerValue]) {
            @synchronized(self) { _sceneError=[NSString stringWithFormat:
                @"Invalid runtime binding for %@/%@",profileId,state]; }
            return NO;
          }
          matches++;
        }
        if (matches!=1) {
          @synchronized(self) { _sceneError=[NSString stringWithFormat:
              @"Ambiguous runtime selector for %@/%@",profileId,state]; }
          return NO;
        }
      }
    }
    if (scriptedCharacterProfiles.count!=24) {
      @synchronized(self) { _sceneError=@"Incomplete scripted character runtime profiles"; }
      return NO;
    }
    NSMutableSet<NSNumber*>* scriptedSkins=[NSMutableSet set];
    NSMutableSet<NSString*>* scriptedInstances=[NSMutableSet set];
    NSMutableSet<NSString*>* scriptedEvents=[NSMutableSet set];
    for (NSDictionary* profile in scriptedCharacterProfiles) {
      NSNumber* skin=profile[@"skin"];
      NSString* expectedId=[skin isKindOfClass:NSNumber.class]
          ? [NSString stringWithFormat:@"scripted-dictionary-%@",skin] : nil;
      NSString* actor=profile[@"actor"];
      NSString* expectedInstance=nil;
      if ([actor isKindOfClass:NSString.class] &&
          [actor isEqual:[NSString stringWithFormat:@"animated-character:dictionary-%@",skin]])
        expectedInstance=[NSString stringWithFormat:@"animated-character-%@",skin];
      else if ([actor isKindOfClass:NSString.class] &&
               [actor isEqual:[NSString stringWithFormat:@"cinematic-scene:dictionary-%@",skin]])
        expectedInstance=[NSString stringWithFormat:@"cinematic-scene-%@",skin];
      NSString* expectedEvent=[skin isKindOfClass:NSNumber.class]
          ? [NSString stringWithFormat:@"script.character.dictionary-%@",skin] : nil;
      NSDictionary* scriptedSelectors=profile[@"states"];
      NSDictionary* selector=[scriptedSelectors isKindOfClass:NSDictionary.class]
          ? scriptedSelectors[@"script_event"] : nil;
      if (expectedId==nil || expectedInstance==nil ||
          ![profile[@"id"] isEqual:expectedId] ||
          ![profile[@"instance"] isEqual:expectedInstance] ||
          ![profile[@"scriptEvent"] isEqual:expectedEvent] ||
          ![profile[@"restorePolicy"] isEqual:@"snapshot-without-replay"] ||
          ![profile[@"costume"] isEqual:@"scene-default"] ||
          ![profile[@"complete"] isKindOfClass:NSNumber.class] ||
          ![profile[@"complete"] boolValue] ||
          ![scriptedSelectors isKindOfClass:NSDictionary.class] ||
          scriptedSelectors.count!=1 ||
          ![selector isKindOfClass:NSDictionary.class] ||
          [scriptedSkins containsObject:skin] ||
          [scriptedInstances containsObject:expectedInstance] ||
          [scriptedEvents containsObject:expectedEvent]) {
        @synchronized(self) { _sceneError=@"Invalid scripted character runtime profile"; }
        return NO;
      }
      [scriptedSkins addObject:skin];
      [scriptedInstances addObject:expectedInstance];
      [scriptedEvents addObject:expectedEvent];
      NSUInteger matches=0;
      for (NSDictionary* binding in animationBindings[@"bindings"]) {
        if (![binding isKindOfClass:NSDictionary.class] ||
            ![binding[@"actor"] isEqual:actor] ||
            [binding[@"skin"] integerValue]!=skin.integerValue ||
            ![binding[@"costume"] isEqual:profile[@"costume"]] ||
            ![binding[@"context"] isEqual:@"scripted"] ||
            ![binding[@"action"] isEqual:selector[@"action"]] ||
            ![binding[@"variant"] isEqual:selector[@"variant"]]) continue;
        if ([binding[@"fallback"] boolValue] ||
            [binding[@"skeletonNodes"] integerValue]<=0) {
          @synchronized(self) { _sceneError=@"Invalid scripted character runtime binding"; }
          return NO;
        }
        matches++;
      }
      if (matches!=1) {
        @synchronized(self) { _sceneError=@"Ambiguous scripted character runtime selector"; }
        return NO;
      }
    }
    if (worldRuntimeProfiles.count!=13) {
      @synchronized(self) { _sceneError=@"Incomplete world animation runtime profiles"; }
      return NO;
    }
    NSMutableSet<NSNumber*>* worldSkins=[NSMutableSet set];
    NSMutableSet<NSString*>* worldInstances=[NSMutableSet set];
    NSUInteger worldResolved=0;
    for (NSDictionary* profile in worldRuntimeProfiles) {
      NSNumber* skin=profile[@"skin"];
      NSString* expectedId=[skin isKindOfClass:NSNumber.class]
          ? [NSString stringWithFormat:@"world-dictionary-%@",skin] : nil;
      NSString* expectedInstance=[skin isKindOfClass:NSNumber.class]
          ? [NSString stringWithFormat:@"world-object-%@",skin] : nil;
      NSDictionary* worldSelectors=profile[@"states"];
      NSDictionary* eventStates=profile[@"eventStates"];
      NSString* synchronization=profile[@"synchronization"];
      NSString* entryState=profile[@"entryState"];
      if (expectedId==nil ||
          ![profile[@"id"] isEqual:expectedId] ||
          ![profile[@"instance"] isEqual:expectedInstance] ||
          ![profile[@"costume"] isEqual:@"default"] ||
          ![profile[@"restorePolicy"] isEqual:@"snapshot-without-replay"] ||
          ![profile[@"complete"] isKindOfClass:NSNumber.class] ||
          ![profile[@"complete"] boolValue] ||
          ![worldSelectors isKindOfClass:NSDictionary.class] ||
          ![eventStates isKindOfClass:NSDictionary.class] ||
          ![entryState isKindOfClass:NSString.class] ||
          worldSelectors[entryState]==nil ||
          ![@[@"object-state",@"material",@"particle"] containsObject:synchronization] ||
          [worldSkins containsObject:skin] ||
          [worldInstances containsObject:expectedInstance]) {
        @synchronized(self) { _sceneError=@"Invalid world animation runtime profile"; }
        return NO;
      }
      [worldSkins addObject:skin];
      [worldInstances addObject:expectedInstance];
      NSMutableSet<NSString*>* selectedStates=[NSMutableSet set];
      for (NSString* event in eventStates) {
        NSArray* states=eventStates[event];
        if (![states isKindOfClass:NSArray.class] || states.count==0) {
          @synchronized(self) { _sceneError=@"Invalid world animation event selectors"; }
          return NO;
        }
        for (NSString* state in states) {
          NSDictionary* selector=[state isKindOfClass:NSString.class]
              ? worldSelectors[state] : nil;
          if (![selector isKindOfClass:NSDictionary.class] ||
              [selectedStates containsObject:state]) {
            @synchronized(self) { _sceneError=@"Duplicate world animation runtime selector"; }
            return NO;
          }
          [selectedStates addObject:state];
          NSUInteger matches=0;
          for (NSDictionary* binding in animationBindings[@"bindings"]) {
            if (![binding isKindOfClass:NSDictionary.class] ||
                ![binding[@"actor"] isEqual:profile[@"actor"]] ||
                [binding[@"skin"] integerValue]!=skin.integerValue ||
                ![binding[@"costume"] isEqual:profile[@"costume"]] ||
                ![binding[@"context"] isEqual:@"world"] ||
                ![binding[@"action"] isEqual:selector[@"action"]] ||
                ![binding[@"variant"] isEqual:selector[@"variant"]] ||
                ![binding[@"trigger"] isEqual:event]) continue;
            if ([binding[@"fallback"] boolValue] ||
                [binding[@"skeletonNodes"] integerValue]<=0 ||
                ![binding[@"loop"] isKindOfClass:NSNumber.class] ||
                ![binding[@"phases"] isKindOfClass:NSDictionary.class]) {
              @synchronized(self) { _sceneError=@"Invalid world animation runtime binding"; }
              return NO;
            }
            matches++;
          }
          if (matches!=1) {
            @synchronized(self) { _sceneError=@"Ambiguous world animation runtime selector"; }
            return NO;
          }
          worldResolved++;
        }
      }
      if (selectedStates.count!=worldSelectors.count) {
        @synchronized(self) { _sceneError=@"Incomplete world animation runtime profile"; }
        return NO;
      }
    }
    if (worldResolved!=46) {
      @synchronized(self) { _sceneError=@"Incomplete world animation runtime selector catalog"; }
      return NO;
    }
    if (cinematicRuntimeProfiles.count!=14) {
      @synchronized(self) { _sceneError=@"Incomplete cinematic animation runtime profiles"; }
      return NO;
    }
    NSMutableSet<NSString*>* cinematicIds=[NSMutableSet set];
    NSMutableSet<NSString*>* cinematicEvents=[NSMutableSet set];
    NSUInteger cinematicResolved=0;
    for (NSDictionary* profile in cinematicRuntimeProfiles) {
      NSString* profileId=profile[@"id"];
      NSString* scene=[profileId isKindOfClass:NSString.class] &&
          [profileId hasPrefix:@"cinematic-scene-data-"]
          ? [profileId substringFromIndex:[@"cinematic-scene-data-" length]]
          : nil;
      NSString* timeline=scene
          ? [NSString stringWithFormat:@"scene-data-%@",scene] : nil;
      NSString* expectedEvent=scene
          ? [NSString stringWithFormat:@"script.cinematic.scene-data-%@",scene] : nil;
      NSString* expectedInstance=scene
          ? [NSString stringWithFormat:@"cinematic-timeline-%@",scene] : nil;
      NSDictionary* cinematicSelectors=profile[@"states"];
      NSDictionary* cueStates=profile[@"cueStates"];
      if (scene.length==0 ||
          ![profile[@"instance"] isEqual:expectedInstance] ||
          ![profile[@"scriptEvent"] isEqual:expectedEvent] ||
          ![profile[@"costume"] isEqual:
              [NSString stringWithFormat:@"scene-%@",scene]] ||
          ![profile[@"restorePolicy"] isEqual:@"snapshot-without-replay"] ||
          ![profile[@"controlPolicy"] isEqual:@"lock-on-start-return-on-terminal"] ||
          ![profile[@"skipPolicy"] isEqual:@"apply-terminal-state"] ||
          ![profile[@"interruptPolicy"] isEqual:@"checkpoint-current-cue"] ||
          ![profile[@"reentryPolicy"] isEqual:
              @"resume-checkpoint-or-restart-after-interrupt"] ||
          ![profile[@"complete"] boolValue] ||
          ![cinematicSelectors isKindOfClass:NSDictionary.class] ||
          ![cueStates isKindOfClass:NSDictionary.class] ||
          [cinematicIds containsObject:profileId] ||
          [cinematicEvents containsObject:expectedEvent]) {
        @synchronized(self) { _sceneError=@"Invalid cinematic animation runtime profile"; }
        return NO;
      }
      [cinematicIds addObject:profileId];
      [cinematicEvents addObject:expectedEvent];
      NSMutableSet<NSString*>* selectedStates=[NSMutableSet set];
      for (NSString* cue in cueStates) {
        if (![cue hasPrefix:@"cue_"] ||
            [cueStates[cue] isKindOfClass:NSArray.class]==NO) {
          @synchronized(self) { _sceneError=@"Invalid cinematic cue selectors"; }
          return NO;
        }
        NSString* cueIndex=[cue substringFromIndex:4];
        NSString* trigger=[NSString stringWithFormat:@"%@:cue-%@",
                            expectedEvent,cueIndex];
        for (NSString* state in cueStates[cue]) {
          NSDictionary* selector=[state isKindOfClass:NSString.class]
              ? cinematicSelectors[state] : nil;
          if (![selector isKindOfClass:NSDictionary.class] ||
              [selectedStates containsObject:state]) {
            @synchronized(self) { _sceneError=@"Duplicate cinematic runtime selector"; }
            return NO;
          }
          [selectedStates addObject:state];
          NSUInteger matches=0;
          for (NSDictionary* binding in animationBindings[@"bindings"]) {
            if (![binding[@"actor"] isEqual:profile[@"actor"]] ||
                [binding[@"skin"] integerValue]!=[profile[@"skin"] integerValue] ||
                ![binding[@"costume"] isEqual:profile[@"costume"]] ||
                ![binding[@"context"] isEqual:@"cinematic"] ||
                ![binding[@"action"] isEqual:selector[@"action"]] ||
                ![binding[@"variant"] isEqual:selector[@"variant"]] ||
                ![binding[@"timeline"] isEqual:timeline] ||
                ![binding[@"trigger"] isEqual:trigger] ||
                [binding[@"cueIndex"] integerValue]!=cueIndex.integerValue) continue;
            if ([binding[@"fallback"] boolValue] ||
                [binding[@"skeletonNodes"] integerValue]<=0) {
              @synchronized(self) { _sceneError=@"Invalid cinematic runtime binding"; }
              return NO;
            }
            matches++;
          }
          if (matches!=1) {
            @synchronized(self) { _sceneError=@"Ambiguous cinematic runtime selector"; }
            return NO;
          }
          cinematicResolved++;
        }
      }
      if (selectedStates.count!=cinematicSelectors.count) {
        @synchronized(self) { _sceneError=@"Incomplete cinematic runtime profile"; }
        return NO;
      }
    }
    if (cinematicResolved!=63) {
      @synchronized(self) { _sceneError=@"Incomplete cinematic runtime selector catalog"; }
      return NO;
    }
  }
  NSMutableSet<NSString*>* reviewClipKeys=[NSMutableSet set];
  for(NSDictionary* binding in animationBindings[@"bindings"]) {
    if(![binding isKindOfClass:NSDictionary.class]||
       ![binding[@"actor"] isEqual:@"asterix"]||
       [binding[@"skin"] integerValue]!=4||
       ![binding[@"costume"] isEqual:@"default"]||
       ![binding[@"context"] isEqual:@"gameplay"]||
       [binding[@"fallback"] boolValue]||
       [binding[@"skeletonNodes"] integerValue]!=58)continue;
    NSString* source=binding[@"clip"];
    if(![source isKindOfClass:NSString.class]||[reviewClipKeys containsObject:source])continue;
    [reviewClipKeys addObject:source];
    NSString* clipId=[source hasSuffix:@".animation.json"]
        ?[source substringToIndex:source.length-@".animation.json".length]
        :[source stringByDeletingPathExtension];
    [reviewSelectors addObject:@{
      @"clip":clipId,
      @"action":binding[@"action"] ?: @"unknown",
      @"variant":binding[@"variant"] ?: @""
    }];
  }
  [reviewSelectors sortUsingComparator:^NSComparisonResult(NSDictionary* left,NSDictionary* right) {
    return [left[@"clip"] compare:right[@"clip"] options:NSNumericSearch];
  }];
  NSMutableDictionary<NSString*, NSString*>* animationKeys=[NSMutableDictionary dictionary];
  for (NSString* state in stateBindings) {
    NSDictionary* binding=stateBindings[state];
    NSString* clip=binding[@"clip"];
    NSNumber* looping=binding[@"loop"];
    NSArray* transitions=binding[@"transitions"];
    if (![clip isKindOfClass:NSString.class] || ![looping isKindOfClass:NSNumber.class] ||
        ![transitions isKindOfClass:NSArray.class] || [binding[@"skeletonNodes"] integerValue]!=58) {
      @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Unknown or invalid animation binding for asterix/%@",state]; }
      return NO;
    }
    animationKeys[state]=clip;
  }
  for (NSString* state in requiredStates) {
    if (stateBindings[state]==nil) {
      @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Missing core runtime selector for asterix/%@",state]; }
      return NO;
    }
  }
  NSString* reviewClip = NSProcessInfo.processInfo.environment[@"ASTERIX_ANIMATION_REVIEW_CLIP"];
  NSCharacterSet* nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
  if (reviewClip.length == 4 && [reviewClip rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
    NSString* reviewSource = [reviewClip stringByAppendingString:@".animation.json"];
    for (NSString* state in animationKeys.allKeys) animationKeys[state] = reviewSource;
    NSLog(@"Animation review override: %@", reviewClip);
  }
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"animation"]) continue;
    NSString* sourceKey=resource[@"source"][@"key"];
    NSString* state=nil;
    for (NSString* candidate in animationKeys)
      if ([animationKeys[candidate] isEqual:sourceKey]) { state=candidate; break; }
    const BOOL isReviewClip=[reviewClipKeys containsObject:sourceKey];
    if (state==nil&&!isReviewClip) continue;
    uint64_t offset=[resource[@"offset"] unsignedLongLongValue];
    uint64_t length=[resource[@"length"] unsignedLongLongValue];
    if(offset>payloadLength||length>payloadLength-offset)continue;
    NSData* data=[package subdataWithRange:NSMakeRange((NSUInteger)(payloadOffset+offset),(NSUInteger)length)];
    NSDictionary* clip=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(state!=nil&&[clip[@"nodeCount"] unsignedIntegerValue]==58)playerAnimations[state]=clip;
    if(isReviewClip&&
       [clip[@"nodeCount"] unsignedIntegerValue]==58)reviewAnimations[sourceKey]=clip;
  }
  for (NSDictionary* resource in manifest[@"resources"]) {
    if ([resource[@"kind"] isEqual:@"checkpoint"]) {
      uint64_t offset=[resource[@"offset"] unsignedLongLongValue];
      uint64_t length=[resource[@"length"] unsignedLongLongValue];
      if(offset>payloadLength||length>payloadLength-offset) continue;
      NSData* data=[package subdataWithRange:NSMakeRange(
          (NSUInteger)(payloadOffset+offset),(NSUInteger)length)];
      NSDictionary* checkpoint=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      asterix::collision::Vec3 position;
      if([checkpoint[@"schemaVersion"] integerValue]==1&&
         [checkpoint[@"kind"] isEqual:@"asterix-checkpoint"]&&
         [checkpoint[@"hookClassId"] integerValue]==193&&
         AsterixReadVec3(checkpoint[@"position"],position)) authoredCheckpoint=position;
      continue;
    }
    if (![resource[@"kind"] isEqual:@"collision"]) continue;
    uint64_t offset = [resource[@"offset"] unsignedLongLongValue];
    uint64_t length = [resource[@"length"] unsignedLongLongValue];
    if (offset > payloadLength || length > payloadLength - offset) continue;
    NSData* data = [package subdataWithRange:NSMakeRange((NSUInteger)(payloadOffset + offset), (NSUInteger)length)];
    NSDictionary* collision = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    for (NSDictionary* mesh in collision[@"meshes"]) {
      NSArray* positions = mesh[@"vertices"];
      const uint32_t objectId = [mesh[@"objectId"] unsignedIntValue];
      matrix_float4x4 model = matrix_identity_float4x4;
      NSArray* transform = mesh[@"transform"] ?: mesh[@"wallTransform"];
      if ([transform isKindOfClass:NSArray.class] && transform.count == 16) {
        for (NSUInteger component = 0; component < 16; ++component)
          model.columns[component / 4][component % 4] = [transform[component] floatValue];
        model.columns[0].w = model.columns[1].w = model.columns[2].w = 0;
        model.columns[3].w = 1;
      }
      for (NSArray* triangle in mesh[@"triangles"]) {
        if (triangle.count < 3) continue;
        vector_float3 points[3];
        BOOL valid = YES;
        for (NSUInteger corner=0;corner<3;++corner) {
          const NSUInteger index = [triangle[corner] unsignedIntegerValue];
          if (index >= positions.count || [positions[index] count] < 3) { valid=NO; break; }
          NSArray* p = positions[index];
          vector_float4 world = simd_mul(model,(vector_float4){[p[0] floatValue],[p[1] floatValue],[p[2] floatValue],1});
          points[corner]=world.xyz;
        }
        if (!valid) continue;
        asterix::collision::Triangle collisionTriangle={
            {points[0].x,points[0].y,points[0].z},
            {points[1].x,points[1].y,points[1].z},
            {points[2].x,points[2].y,points[2].z},(int)objectId};
        collisionTriangles.push_back(collisionTriangle);
        for (vector_float3 point : points) {
          AsterixVertex vertex = {point,{1,.08f,.12f},{0,1,0},{0,0},1,1,0,
                                  {1,1,1,1},{0,0,0,0},{1,0,0,0},objectId};
          [collisionVertexData appendBytes:&vertex length:sizeof(vertex)];
        }
      }
    }
  }
  for (NSDictionary* object in manifest[@"objects"]) {
    if (![object[@"kind"] isEqual:@"scene-node"]) continue;
    NSString* objectId = object[@"id"];
    if (![objectId isKindOfClass:NSString.class]) continue;
    asterix::scene::Node node;
    node.id = objectId.UTF8String;
    NSString* parentId = object[@"metadata"][@"parentId"];
    if ([parentId isKindOfClass:NSString.class]) node.parent_id = parentId.UTF8String;
    NSArray* transform = object[@"metadata"][@"transform"];
    if (transform.count == 16) for (NSUInteger i = 0; i < 16; ++i)
      node.local.value[i] = [transform[i] floatValue];
    else node.local = asterix::scene::Matrix4::identity();
    transformGraph.addNode(std::move(node));
    NSArray* payloadIds = object[@"payloadIds"];
    if (payloadIds.count == 0) continue;
    NSString* payloadId = payloadIds.firstObject;
    if (![payloadId isKindOfClass:NSString.class]) continue;
    payloadNodes[payloadId.UTF8String] = objectId.UTF8String;
    NSString* section=object[@"metadata"][@"section"];
    if([section isKindOfClass:NSString.class])
      payloadSections[payloadId.UTF8String]=section.UTF8String;
    if([object[@"metadata"][@"interactiveKind"] isEqual:@"push-pull-stone"])
      pushMetadata[payloadId]=object[@"metadata"];
  }
  try {
    transformGraph.resolveHierarchy();
  } catch (const std::exception&) {
    [self reportSceneError:@"Scene graph contains a missing parent or cycle"];
    return NO;
  }
  std::unordered_map<std::string, asterix::scene::Matrix4> worldTransforms;
  std::vector<AsterixPushMesh> pushMeshes;
  for (const auto& node : transformGraph.nodes()) worldTransforms[node.id] = node.world;
  for (NSDictionary* resource in manifest[@"resources"]) {
    if (![resource[@"kind"] isEqual:@"mesh"]) continue;
    uint64_t offset = [resource[@"offset"] unsignedLongLongValue];
    uint64_t length = [resource[@"length"] unsignedLongLongValue];
    if (offset > payloadLength || length > payloadLength - offset) continue;
    NSData* meshData = [package subdataWithRange:NSMakeRange((NSUInteger)(payloadOffset + offset), (NSUInteger)length)];
    NSDictionary* mesh = [NSJSONSerialization JSONObjectWithData:meshData options:0 error:nil];
    NSArray* positions = mesh[@"vertices"];
    NSArray* normals = mesh[@"normals"];
    id prelightValue=mesh[@"prelightColors"];
    if(prelightValue!=nil&&![prelightValue isKindOfClass:NSArray.class]) {
      [self reportSceneError:@"Authored prelight payload is not an array"];
      return NO;
    }
    NSArray* prelightColors=(NSArray*)prelightValue;
    NSArray* triangles = mesh[@"triangles"];
    NSArray* materials = mesh[@"materials"];
    NSArray* uvSets = mesh[@"uvSets"];
    NSArray* uvs = uvSets.count > 0 ? uvSets[0] : nil;
    if (prelightColors.count > 0 && prelightColors.count != positions.count) {
      [self reportSceneError:[NSString stringWithFormat:
          @"Authored prelight vertex count mismatch for mesh %@", resource[@"id"]]];
      return NO;
    }
    for (NSArray* rgba in prelightColors) {
      if (![rgba isKindOfClass:NSArray.class] || rgba.count != 4) {
        [self reportSceneError:@"Authored prelight contains malformed RGBA"];
        return NO;
      }
      for (id channel in rgba) {
        if (![channel isKindOfClass:NSNumber.class]) {
          [self reportSceneError:@"Authored prelight channel is outside 0...1"];
          return NO;
        }
        const double value=[(NSNumber*)channel doubleValue];
        if (!std::isfinite(value) || value < 0 || value > 1) {
          [self reportSceneError:@"Authored prelight channel is outside 0...1"];
          return NO;
        }
      }
    }
    NSString* resourceId = resource[@"id"];
    matrix_float4x4 model = matrix_identity_float4x4;
    if ([resourceId isKindOfClass:NSString.class]) {
      const auto payloadNode = payloadNodes.find(resourceId.UTF8String);
      if (payloadNode != payloadNodes.end()) {
        const auto world = worldTransforms.find(payloadNode->second);
        if (world != worldTransforms.end()) for (NSUInteger i = 0; i < 16; ++i)
          model.columns[i / 4][i % 4] = world->second.value[i];
      }
    }
    NSUInteger before = vertexData.length;
    std::vector<AsterixMeshRange> materialRanges;
    vector_float3 meshMinimum = {INFINITY, INFINITY, INFINITY};
    vector_float3 meshMaximum = {-INFINITY, -INFINITY, -INFINITY};
    for (NSArray* triangle in triangles) {
      if (triangle.count < 4) continue;
      NSUInteger materialIndex = [triangle[3] unsignedIntegerValue];
      id color = materialIndex < materials.count ? materials[materialIndex][@"color"] : nil;
      vector_float3 c = {0.72f, 0.72f, 0.68f};
      float alpha = 1.0f, ambient = .35f, diffuse = .65f;
      if ([color isKindOfClass:NSArray.class] && [(NSArray*)color count] >= 3) {
        NSArray* channels = color;
        c = (vector_float3){[channels[0] floatValue] / 255.0f,
                            [channels[1] floatValue] / 255.0f,
                            [channels[2] floatValue] / 255.0f};
        if (channels.count >= 4) alpha = [channels[3] floatValue] / 255.0f;
      } else if ([color isKindOfClass:NSNumber.class]) {
        uint32_t packed = [(NSNumber*)color unsignedIntValue];
        c = (vector_float3){(packed & 0xff) / 255.0f,
                            ((packed >> 8) & 0xff) / 255.0f,
                            ((packed >> 16) & 0xff) / 255.0f};
        alpha = ((packed >> 24) & 0xff) / 255.0f;
        // Textured XXL materials commonly use opaque black as a neutral tint.
        // Without a per-material texture binding that value must not erase the
        // whole scene; use a readable neutral base colour instead.
        if (simd_length(c) < .02f) {
          const uint32_t objectId=[mesh[@"objectId"] unsignedIntValue];
          const uint32_t shade=objectId*1664525u+1013904223u;
          const float variation=(float)(shade&255u)/255.0f;
          c=(vector_float3){.34f+.22f*variation,
                            .38f+.18f*variation,
                            .30f+.12f*variation};
        }
      }
      NSDictionary* material = materialIndex < materials.count ? materials[materialIndex] : nil;
      NSString* textureName=material[@"texture"];
      NSString* textureKey=AsterixTextureKey(textureName);
      id<MTLTexture> materialTexture=
          textureKey?textures[textureKey]:nil;
      const NSUInteger alphaMode=textureKey?[textureAlphaModes[textureKey] unsignedIntegerValue]:0;
      MTLSamplerDescriptor* samplerDescriptor=[MTLSamplerDescriptor new];
      const NSUInteger filtering=[material[@"filtering"] unsignedIntegerValue];
      samplerDescriptor.minFilter=filtering==1?MTLSamplerMinMagFilterNearest:MTLSamplerMinMagFilterLinear;
      samplerDescriptor.magFilter=samplerDescriptor.minFilter;
      samplerDescriptor.mipFilter=[material[@"usesMipmaps"] boolValue]
          ?MTLSamplerMipFilterLinear:MTLSamplerMipFilterNotMipmapped;
      const auto addressMode=[](NSUInteger value) {
        if(value==2)return MTLSamplerAddressModeMirrorRepeat;
        if(value==3)return MTLSamplerAddressModeClampToEdge;
        if(value==4)return MTLSamplerAddressModeClampToZero;
        return MTLSamplerAddressModeRepeat;
      };
      samplerDescriptor.sAddressMode=addressMode([material[@"uAddressing"] unsignedIntegerValue]);
      samplerDescriptor.tAddressMode=addressMode([material[@"vAddressing"] unsignedIntegerValue]);
      NSString* samplerKey=[NSString stringWithFormat:@"%lu:%lu:%lu:%d",
          (unsigned long)filtering,
          (unsigned long)[material[@"uAddressing"] unsignedIntegerValue],
          (unsigned long)[material[@"vAddressing"] unsignedIntegerValue],
          [material[@"usesMipmaps"] boolValue]];
      id<MTLSamplerState> materialSampler=samplerStates[samplerKey];
      if(materialSampler==nil) {
        materialSampler=[view.device newSamplerStateWithDescriptor:samplerDescriptor];
        samplerStates[samplerKey]=materialSampler;
      }
      const BOOL blended=alphaMode==2||alpha<.999f;
      NSString* alphaTextureName=[material[@"alphaTexture"] isKindOfClass:NSString.class]
          ?material[@"alphaTexture"]:nil;
      const float alphaCutoff=alphaMode==1||alphaTextureName.length>0?.5f:.01f;
      NSDictionary* water=[material[@"waterAnimation"] isKindOfClass:NSDictionary.class]
          ?material[@"waterAnimation"]:nil;
      vector_float2 waterSpeed={0,0};
      float waterPhase=0;
      if(water!=nil&&[water[@"mechanism"] isEqual:@"uv-scroll"]&&
         [water[@"clock"] isEqual:@"simulation-time"]) {
        waterSpeed={(float)[water[@"uSpeed"] doubleValue],
                    (float)[water[@"vSpeed"] doubleValue]};
        waterPhase=(float)[water[@"phase"] doubleValue];
      }
      const NSUInteger triangleStart=vertexData.length/sizeof(AsterixVertex);
      vector_float3 triangleWorld[3];
      BOOL completeTriangle=YES;
      if ([material[@"ambient"] isKindOfClass:NSNumber.class]) ambient = [material[@"ambient"] floatValue];
      if ([material[@"diffuse"] isKindOfClass:NSNumber.class]) diffuse = [material[@"diffuse"] floatValue];
      // rpGEOMETRYPRELIT is already the authored fixed-function lighting
      // result. Applying Lambert again would double-darken both interiors and
      // streets. Non-prelit geometry retains material ambient + diffuse.
      if(prelightColors.count>0) { ambient=1; diffuse=0; }
      for (NSUInteger corner = 0; corner < 3; ++corner) {
        NSUInteger index = [triangle[corner] unsignedIntegerValue];
        if (index >= positions.count || [positions[index] count] < 3) {
          completeTriangle=NO;
          continue;
        }
        NSArray* p = positions[index];
        vector_float4 world = simd_mul(model, (vector_float4){[p[0] floatValue], [p[1] floatValue], [p[2] floatValue], 1});
        triangleWorld[corner]=world.xyz;
        minimum = simd_min(minimum, world.xyz);
        maximum = simd_max(maximum, world.xyz);
        meshMinimum = simd_min(meshMinimum, world.xyz);
        meshMaximum = simd_max(meshMaximum, world.xyz);
        vector_float2 uv = {0, 0};
        if (index < uvs.count && [uvs[index] count] >= 2)
          uv = (vector_float2){[uvs[index][0] floatValue], [uvs[index][1] floatValue]};
        vector_float3 normal = {0, 1, 0};
        if (index < normals.count && [normals[index] count] >= 3) {
          NSArray* n = normals[index];
          normal = simd_normalize(simd_mul((matrix_float3x3){model.columns[0].xyz, model.columns[1].xyz, model.columns[2].xyz},
                                           (vector_float3){[n[0] floatValue], [n[1] floatValue], [n[2] floatValue]}));
        }
        vector_float4 prelight={1,1,1,1};
        if(index<prelightColors.count&&[prelightColors[index] count]==4) {
          NSArray* rgba=prelightColors[index];
          prelight={(float)[rgba[0] doubleValue],(float)[rgba[1] doubleValue],
                    (float)[rgba[2] doubleValue],(float)[rgba[3] doubleValue]};
        }
        AsterixVertex vertex = {{world.x, world.y, world.z}, c, normal, uv,
                                alpha, ambient, diffuse, prelight, {0,0,0,0}, {1,0,0,0},
                                (uint32_t)[mesh[@"objectId"] unsignedIntValue]};
        [vertexData appendBytes:&vertex length:sizeof(vertex)];
      }
      if(completeTriangle) {
        const vector_float3 ab=triangleWorld[1]-triangleWorld[0];
        const vector_float3 ac=triangleWorld[2]-triangleWorld[0];
        const vector_float3 surface=simd_cross(ab,ac);
        if(simd_length_squared(surface)>1e-8f&&
           fabsf(simd_normalize(surface).y)>=cosf(50.0f*3.14159265358979323846f/180.0f))
          visibleGroundTriangles.push_back({
              {triangleWorld[0].x,triangleWorld[0].y,triangleWorld[0].z},
              {triangleWorld[1].x,triangleWorld[1].y,triangleWorld[1].z},
              {triangleWorld[2].x,triangleWorld[2].y,triangleWorld[2].z},
              (int)[mesh[@"objectId"] unsignedIntValue]});
      }
      const NSUInteger triangleCount=vertexData.length/sizeof(AsterixVertex)-triangleStart;
      if(triangleCount>0) {
        if(!materialRanges.empty()&&materialRanges.back().texture==materialTexture&&
           materialRanges.back().sampler==materialSampler&&
           materialRanges.back().alphaCutoff==alphaCutoff&&
           materialRanges.back().blended==blended&&
           simd_all(materialRanges.back().waterSpeed==waterSpeed)&&
           materialRanges.back().waterPhase==waterPhase&&
           materialRanges.back().vertexStart+materialRanges.back().vertexCount==triangleStart)
          materialRanges.back().vertexCount+=triangleCount;
        else materialRanges.push_back({triangleStart,triangleCount,materialTexture,
                                       materialSampler,alphaCutoff,blended,
                                       waterSpeed,waterPhase});
      }
    }
    if (vertexData.length > before) {
      const NSUInteger count = (vertexData.length - before) / sizeof(AsterixVertex);
      NSDictionary* push=[resourceId isKindOfClass:NSString.class]?pushMetadata[resourceId]:nil;
      if(push!=nil)pushMeshes.push_back({
          (uint32_t)(7400+[push[@"hookId"] unsignedIntValue]),
          before/sizeof(AsterixVertex),count,0});
      meshRanges.push_back(std::move(materialRanges));
      asterix::scene::Node node;
      node.id = [resourceId UTF8String] ?: "";
      const auto section=payloadSections.find(node.id);
      node.section_id=section==payloadSections.end()?"gaul-stage-1":section->second;
      node.resource_id = node.id;
      node.world_bounds = {{meshMinimum.x, meshMinimum.y, meshMinimum.z},
                           {meshMaximum.x, meshMaximum.y, meshMaximum.z}};
      node.full_vertex_count = (uint32_t)count;
      const auto sectionMinimum=sectionMinimums.find(node.section_id);
      if(sectionMinimum==sectionMinimums.end()) {
        sectionMinimums[node.section_id]=meshMinimum;
        sectionMaximums[node.section_id]=meshMaximum;
      } else {
        sectionMinimums[node.section_id]=simd_min(sectionMinimum->second,meshMinimum);
        sectionMaximums[node.section_id]=simd_max(sectionMaximums[node.section_id],meshMaximum);
      }
      runtimeNodes.push_back(std::move(node));
      meshCount++;
    }
    if (selectedTexture == nil) for (NSDictionary* material in materials) {
      NSString* textureName = material[@"texture"];
      if (![textureName isKindOfClass:NSString.class]) continue;
      id<MTLTexture> texture = textures[AsterixTextureKey(textureName)];
      if (texture != nil) { selectedTexture = texture; break; }
    }
  }
  id<MTLDevice> device = view.device;
  if (vertexData.length == 0 || device == nil) {
    @synchronized(self) { _sceneError = @"ASTPAK contains no renderable scene meshes"; }
    return NO;
  }
  auto runtime = std::make_unique<asterix::scene::Runtime>();
  std::unique_ptr<asterix::collision::World> collisionWorld;
  std::unique_ptr<asterix::collision::CapsuleController> capsuleController;
  std::unique_ptr<asterix::player::Runtime> playerRuntime;
  std::unique_ptr<asterix::player_animation::Runtime> playerAnimationRuntime;
  std::unique_ptr<asterix::collision::CapsuleController> enemyCapsuleController;
  std::unique_ptr<asterix::enemy::Runtime> enemyRuntime;
  std::unique_ptr<asterix::interactive::Runtime> interactiveRuntime;
  std::unique_ptr<asterix::camera::Runtime> cameraRuntime;
  std::unique_ptr<asterix::combat::Runtime> combatRuntime;
  NSUInteger playerMarkerVertexStart=NSNotFound,enemyMarkerVertexStart=NSNotFound;
  NSUInteger playerMeshVertexStart=NSNotFound,playerMeshVertexCount=0;
  std::vector<AsterixMeshRange> playerMeshRanges;
  std::vector<asterix::animation::Joint> playerJoints;
  std::unordered_map<std::string, asterix::animation::Clip> playerClips;
  std::vector<asterix::animation::Clip> animationReviewClips;
  NSMutableArray<NSDictionary*>* validReviewSelectors=[NSMutableArray array];
  if (!collisionTriangles.empty()) {
    collisionWorld=std::make_unique<asterix::collision::World>(std::move(collisionTriangles));
    std::optional<asterix::collision::CapsuleState> spawn;
    if(authoredCheckpoint) {
      // Checkpoints from LVL01 can overlap gameplay collision that has no
      // corresponding rendered surface. Never start or recover on one of
      // those phantom floors: require visible geometry at the same height.
      asterix::collision::World visibleWorld(visibleGroundTriangles);
      const auto visible=asterix::collision::groundedStateAt(
          visibleWorld,*authoredCheckpoint);
      const auto collided=asterix::collision::groundedStateAt(
          *collisionWorld,*authoredCheckpoint);
      if(visible&&collided&&fabsf(visible->position.y-collided->position.y)<.2f)
        spawn=collided;
      if(!spawn) {
        float bestDistance=INFINITY;
        for(const auto& triangle:visibleGroundTriangles) {
          const asterix::collision::Vec3 candidate={
              (triangle.a.x+triangle.b.x+triangle.c.x)/3,
              (triangle.a.y+triangle.b.y+triangle.c.y)/3,
              (triangle.a.z+triangle.b.z+triangle.c.z)/3};
          const float dx=candidate.x-authoredCheckpoint->x;
          const float dz=candidate.z-authoredCheckpoint->z;
          const float distance=dx*dx+dz*dz;
          if(distance>=bestDistance)continue;
          const auto visualState=asterix::collision::groundedStateAt(
              visibleWorld,candidate);
          const auto collisionState=asterix::collision::groundedStateAt(
              *collisionWorld,candidate);
          if(!visualState||!collisionState||
             fabsf(visualState->position.y-collisionState->position.y)>=.2f)continue;
          spawn=collisionState;
          bestDistance=distance;
        }
      }
    }
    capsuleController=std::make_unique<asterix::collision::CapsuleController>(*collisionWorld);
    if(!spawn) {
      @synchronized(self) { _sceneError=@"Authored checkpoint does not resolve to walkable collision"; }
      return NO;
    }
    asterix::collision::CapsuleState body=*spawn;
    playerRuntime=std::make_unique<asterix::player::Runtime>(*capsuleController,body);
    enemyCapsuleController=std::make_unique<asterix::collision::CapsuleController>(*collisionWorld);
    asterix::collision::CapsuleState enemyBody=body;
    const float slope=std::cos(50.0f*3.14159265358979323846f/180.0f);
    const asterix::collision::Vec3 offsets[]={{6,0,0},{-6,0,0},{0,0,6},{0,0,-6},
                                              {5,0,0},{-5,0,0},{0,0,5},{0,0,-5}};
    for(const auto offset:offsets) {
      const auto candidate=body.position+offset;
      const auto ground=collisionWorld->groundAt(candidate.x,candidate.z,
                                                  body.position.y+5.0f,slope);
      if(!ground)continue;
      enemyBody.position={candidate.x,ground->height+.9f,candidate.z};
      break;
    }
    enemyBody.checkpoint=enemyBody.position;
    asterix::enemy::Config enemyConfig;
    enemyConfig.perception_radius=5.0f;
    enemyRuntime=std::make_unique<asterix::enemy::Runtime>(
        *enemyCapsuleController,enemyBody,enemyConfig);
    interactiveRuntime=std::make_unique<asterix::interactive::Runtime>();
    interactiveRuntime->addTrigger({10,body.position,{1.5f,1,1.5f},true,false});
    interactiveRuntime->addLever({11,body.position+asterix::collision::Vec3{1,0,0},1.0f});
    interactiveRuntime->addDestructible({100,body.position+asterix::collision::Vec3{2,0,0},2,2,false});
    interactiveRuntime->addReward({12,body.position+asterix::collision::Vec3{2,0,0},100,1});
    interactiveRuntime->addCheckpoint({13,body.position,1.0f});
    for(NSDictionary* metadata in pushMetadata.allValues) {
      asterix::collision::Vec3 origin,axis;
      if(!AsterixReadVec3(metadata[@"origin"],origin)||
         !AsterixReadVec3(metadata[@"axis"],axis)||
         ![metadata[@"minimumOffset"] isKindOfClass:NSNumber.class]||
         ![metadata[@"maximumOffset"] isKindOfClass:NSNumber.class])continue;
      interactiveRuntime->addPushBlock({
          (uint32_t)(7400+[metadata[@"hookId"] unsignedIntValue]),origin,{},axis,
          {1.06f,1.07f,1.16f},[metadata[@"minimumOffset"] floatValue],
          [metadata[@"maximumOffset"] floatValue],0});
    }
    interactiveRuntime->update(body.position,false);
    cameraRuntime=std::make_unique<asterix::camera::Runtime>();
    combatRuntime=std::make_unique<asterix::combat::Runtime>();
    asterix::combat::Fighter playerFighter;
    playerFighter.id=1; playerFighter.team=1; playerFighter.position=body.position;
    combatRuntime->addFighter(playerFighter);
    asterix::combat::Fighter enemyFighter;
    enemyFighter.id=2; enemyFighter.team=2; enemyFighter.position=enemyBody.position;
    combatRuntime->addFighter(enemyFighter);
    asterix::combat::Fighter objectFighter;
    objectFighter.id=100; objectFighter.team=2;
    objectFighter.position=body.position+asterix::collision::Vec3{2,0,0};
    objectFighter.health=2; combatRuntime->addFighter(objectFighter);
    AsterixVertex marker[6];
    NSArray* skinPositions=playerSkin[@"vertices"];
    NSArray* skinNormals=playerSkin[@"normals"];
    NSArray* skinUvSets=playerSkin[@"uvSets"];
    NSArray* skinUvs=skinUvSets.count>0?skinUvSets[0]:nil;
    NSArray* skinMaterials=playerSkin[@"materials"];
    NSArray* skinTriangles=playerSkin[@"triangles"];
    NSDictionary* skin=playerSkin[@"skin"];
    NSArray* boneIndices=skin[@"vertexBoneIndices"];
    NSArray* boneWeights=skin[@"vertexWeights"];
    NSArray* inverseBind=skin[@"inverseBindMatrices"];
    NSArray* hierarchy=playerSkin[@"frames"][0][@"hierarchy"][@"bones"];
    if(hierarchy.count==inverseBind.count&&hierarchy.count>0) {
      std::vector<std::uint32_t> flags;
      for(NSDictionary* bone in hierarchy)flags.push_back([bone[@"flags"] unsignedIntValue]);
      const auto parents=asterix::animation::hierarchyParents(flags);
      for(NSUInteger i=0;i<inverseBind.count;++i) {
        asterix::animation::Joint joint; joint.parent=parents[i];
        if(!AsterixReadMatrix(inverseBind[i],joint.inverse_bind)){playerJoints.clear();break;}
        playerJoints.push_back(joint);
      }
    }
    if(playerJoints.size()==58)for(NSString* state in stateBindings) {
      asterix::animation::Clip clip;
      if(AsterixReadClip(playerAnimations[state],
                         [stateBindings[state][@"loop"] boolValue],clip))
        playerClips.emplace([state UTF8String],std::move(clip));
    }
    const auto graph=AsterixReadAuthoredGraph(
        authoredAnimationGraph,playerAnimations,stateBindings);
    if(!graph||playerClips.size()!=90) {
      [self reportSceneError:@"Asterix authored animation runtime is incomplete"];
      return NO;
    }
    try {
      playerAnimationRuntime=
          std::make_unique<asterix::player_animation::Runtime>(*graph);
    } catch(const std::exception&) {
      [self reportSceneError:@"Asterix authored animation graph is invalid"];
      return NO;
    }
    if(playerJoints.size()==58)for(NSDictionary* selector in reviewSelectors) {
      NSString* source=[selector[@"clip"] stringByAppendingPathExtension:@"animation.json"];
      asterix::animation::Clip clip;
      if(AsterixReadClip(reviewAnimations[source],false,clip)) {
        animationReviewClips.push_back(std::move(clip));
        [validReviewSelectors addObject:selector];
      }
    }
    const auto runClip=playerClips.find("run");
    if(runClip==playerClips.end()||
       asterix::animation::animatedTrackCount(runClip->second)<20) {
      [self reportSceneError:@"Asterix authored run clip is invalid"];
      return NO;
    }
    bool bindingsValid=boneIndices.count==skinPositions.count&&
        boneWeights.count==skinPositions.count;
    if(bindingsValid)for(NSUInteger vertex=0;vertex<boneIndices.count;++vertex) {
      if([boneIndices[vertex] count]!=4||[boneWeights[vertex] count]!=4){bindingsValid=false;break;}
      float total=0;
      for(NSUInteger influence=0;influence<4;++influence) {
        const float weight=[boneWeights[vertex][influence] floatValue];
        if(!std::isfinite(weight)||weight<0||[boneIndices[vertex][influence] unsignedIntegerValue]>=58) {
          bindingsValid=false; break;
        }
        total+=weight;
      }
      if(!bindingsValid||total<=0){bindingsValid=false;break;}
    }
    const bool animationReady=playerJoints.size()==58&&
        playerClips.size()==90&&playerAnimationRuntime!=nullptr;
    if(skinPositions.count>0&&skinTriangles.count>0&&animationReady&&
       bindingsValid) {
      playerMeshVertexStart=vertexData.length/sizeof(AsterixVertex);
      NSString* textureName=skinMaterials.count>0?skinMaterials[0][@"texture"]:nil;
      id<MTLTexture> playerTexture=[textureName isKindOfClass:NSString.class]
          ?textures[AsterixTextureKey(textureName)]:nil;
      for(NSArray* triangle in skinTriangles) for(NSUInteger corner=0;corner<3;++corner) {
        NSUInteger index=[triangle[corner] unsignedIntegerValue];
        if(index>=skinPositions.count)continue;
        NSArray* p=skinPositions[index];
        vector_float3 local={[p[0] floatValue],[p[1] floatValue],[p[2] floatValue]};
        vector_float3 normal={0,1,0};
        if(index<skinNormals.count) {
          NSArray* n=skinNormals[index];
          normal={(float)[n[0] doubleValue],(float)[n[1] doubleValue],(float)[n[2] doubleValue]};
        }
        vector_float2 uv={0,0};
        if(index<skinUvs.count) {
          NSArray* value=skinUvs[index]; uv={(float)[value[0] doubleValue],(float)[value[1] doubleValue]};
        }
        asterix::animation::VertexBinding binding;
        if(index<boneIndices.count&&index<boneWeights.count)for(NSUInteger influence=0;influence<4;++influence) {
          binding.joints[influence]=[boneIndices[index][influence] unsignedShortValue];
          binding.weights[influence]=[boneWeights[index][influence] floatValue];
        }
        AsterixVertex vertex={local,
            {1,1,1},normal,uv,1,1,1,
            {1,1,1,1},
            {binding.joints[0],binding.joints[1],binding.joints[2],binding.joints[3]},
            {binding.weights[0],binding.weights[1],binding.weights[2],binding.weights[3]},900001};
        [vertexData appendBytes:&vertex length:sizeof(vertex)];
      }
      playerMeshVertexCount=vertexData.length/sizeof(AsterixVertex)-playerMeshVertexStart;
      playerMeshRanges.push_back({playerMeshVertexStart,playerMeshVertexCount,
                                  playerTexture,_defaultSampler,.01f,false,{0,0},0});
      // Asterix's winged helmet is authored as a second skin atomic. It uses
      // the same 58-joint palette as the body and must be skinned and drawn
      // together with it.
      if(playerAccessorySkin!=nil) {
        NSArray* accessoryPositions=playerAccessorySkin[@"vertices"];
        NSArray* accessoryNormals=playerAccessorySkin[@"normals"];
        NSArray* accessoryUvSets=playerAccessorySkin[@"uvSets"];
        NSArray* accessoryUvs=accessoryUvSets.count>0?accessoryUvSets[0]:nil;
        NSArray* accessoryTriangles=playerAccessorySkin[@"triangles"];
        NSArray* accessoryMaterials=playerAccessorySkin[@"materials"];
        NSDictionary* accessorySkin=playerAccessorySkin[@"skin"];
        NSArray* accessoryIndices=accessorySkin[@"vertexBoneIndices"];
        NSArray* accessoryWeights=accessorySkin[@"vertexWeights"];
        const NSUInteger accessoryStart=vertexData.length/sizeof(AsterixVertex);
        if(accessoryIndices.count==accessoryPositions.count&&
           accessoryWeights.count==accessoryPositions.count) {
          for(NSArray* triangle in accessoryTriangles)for(NSUInteger corner=0;corner<3;++corner) {
            const NSUInteger index=[triangle[corner] unsignedIntegerValue];
            if(index>=accessoryPositions.count||[accessoryIndices[index] count]!=4||
               [accessoryWeights[index] count]!=4)continue;
            NSArray* p=accessoryPositions[index];
            vector_float3 normal={0,1,0};
            if(index<accessoryNormals.count) {
              NSArray* n=accessoryNormals[index];
              normal={(float)[n[0] doubleValue],(float)[n[1] doubleValue],(float)[n[2] doubleValue]};
            }
            vector_float2 uv={0,0};
            if(index<accessoryUvs.count) {
              NSArray* value=accessoryUvs[index];
              uv={(float)[value[0] doubleValue],(float)[value[1] doubleValue]};
            }
            AsterixVertex vertex={
                {(float)[p[0] doubleValue],(float)[p[1] doubleValue],(float)[p[2] doubleValue]},
                {1,1,1},normal,uv,1,1,1,{1,1,1,1},
                {(uint16_t)[accessoryIndices[index][0] unsignedIntegerValue],
                 (uint16_t)[accessoryIndices[index][1] unsignedIntegerValue],
                 (uint16_t)[accessoryIndices[index][2] unsignedIntegerValue],
                 (uint16_t)[accessoryIndices[index][3] unsignedIntegerValue]},
                {(float)[accessoryWeights[index][0] doubleValue],
                 (float)[accessoryWeights[index][1] doubleValue],
                 (float)[accessoryWeights[index][2] doubleValue],
                 (float)[accessoryWeights[index][3] doubleValue]},900001};
            [vertexData appendBytes:&vertex length:sizeof(vertex)];
          }
        }
        const NSUInteger accessoryCount=vertexData.length/sizeof(AsterixVertex)-accessoryStart;
        if(accessoryCount>0) {
          NSString* accessoryName=accessoryMaterials.count>0?accessoryMaterials[0][@"texture"]:nil;
          id<MTLTexture> accessoryTexture=[accessoryName isKindOfClass:NSString.class]
              ?textures[AsterixTextureKey(accessoryName)]:nil;
          playerMeshRanges.push_back({accessoryStart,accessoryCount,
                                      accessoryTexture,_defaultSampler,.01f,false,{0,0},0});
          playerMeshVertexCount+=accessoryCount;
        }
      }
    } else {
      playerMarkerVertexStart=vertexData.length/sizeof(AsterixVertex);
      AsterixWriteMarker(marker,body.position,(vector_float3){1.0f,.72f,.08f},900001);
      [vertexData appendBytes:marker length:sizeof(marker)];
    }
    enemyMarkerVertexStart=vertexData.length/sizeof(AsterixVertex);
    AsterixWriteMarker(marker,enemyBody.position,(vector_float3){.85f,.08f,.06f},900002);
    [vertexData appendBytes:marker length:sizeof(marker)];
  }
  id<MTLBuffer> buffer = [device newBufferWithBytes:vertexData.bytes length:vertexData.length options:MTLResourceStorageModeShared];
  id<MTLBuffer> collisionBuffer = collisionVertexData.length == 0 ? nil :
      [device newBufferWithBytes:collisionVertexData.bytes length:collisionVertexData.length options:MTLResourceStorageModeShared];
  id<MTLBuffer> fireBuffer = fireEmitters.empty() ? nil :
      [device newBufferWithLength:fireEmitters.size()*6*sizeof(AsterixVertex)
                         options:MTLResourceStorageModeShared];
  for(const auto& [sectionId,sectionMinimum]:sectionMinimums) {
    const auto sectionMaximum=sectionMaximums[sectionId];
    runtime->addSection({sectionId,
                         {{sectionMinimum.x,sectionMinimum.y,sectionMinimum.z},
                          {sectionMaximum.x,sectionMaximum.y,sectionMaximum.z}},
                         true,true,0});
  }
  if(sectionMinimums.empty())
    runtime->addSection({"gaul-stage-1",
                         {{minimum.x, minimum.y, minimum.z}, {maximum.x, maximum.y, maximum.z}},
                         true, true, 0});
  for (auto& node : runtimeNodes) runtime->addNode(std::move(node));
  runtime->resolveHierarchy();
  @synchronized(self) {
    _sceneVertices = buffer;
    _collisionVertices = collisionBuffer;
    _fireVertices = fireBuffer;
    _fireEmitters = std::move(fireEmitters);
    _pushMeshes = std::move(pushMeshes);
    _collisionTriangleCount = collisionVertexData.length / sizeof(AsterixVertex) / 3;
    _sceneTexture = selectedTexture;
    _sceneTextures = textures.allValues;
    _sceneSamplers = samplerStates.allValues;
    _sceneVertexCount = vertexData.length / sizeof(AsterixVertex);
    _sceneMeshCount = meshCount;
    _visibleMeshCount = meshCount;
    _drawBatchCount = meshCount > 0 ? 1 : 0;
    _playerMarkerVertexStart=playerMarkerVertexStart;
    _playerMeshVertexStart=playerMeshVertexStart;
    _playerMeshVertexCount=playerMeshVertexCount;
    _playerMeshRanges=std::move(playerMeshRanges);
    _playerJoints=std::move(playerJoints);
    _playerClips=std::move(playerClips);
    _animationReviewClips=std::move(animationReviewClips);
    _animationReviewCandidates=[validReviewSelectors copy];
    _animationReviewClip=nil;
    _animationReviewStartedAt=0;
    _enemyMarkerVertexStart=enemyMarkerVertexStart;
    _sceneMeshRanges = std::move(meshRanges);
    _sceneRuntime = std::move(runtime);
    _collisionWorld = std::move(collisionWorld);
    _capsuleController = std::move(capsuleController);
    _playerRuntime = std::move(playerRuntime);
    _playerAnimationRuntime = std::move(playerAnimationRuntime);
    if(_playerAnimationRuntime) {
      _previousPlayerPose=_playerAnimationRuntime->snapshot();
      _currentPlayerPose=_previousPlayerPose;
    }
    _enemyCapsuleController = std::move(enemyCapsuleController);
    _enemyRuntime = std::move(enemyRuntime);
    _interactiveRuntime = std::move(interactiveRuntime);
    _cameraRuntime = std::move(cameraRuntime);
    _combatRuntime = std::move(combatRuntime);
    _fogRuntime = std::move(fogRuntime);
    _combatAttackWasPressed = false;
    _interactPressed = false;
    _interactWasPressed = false;
    _sceneCenter = (minimum + maximum) * 0.5f;
    _sceneRadius = MAX(1.0f, simd_length(maximum - minimum) * 0.5f);
    _sceneError = nil;
  }
  if(audioData) {
    NSError* audioError=nil;
    if([_audioEngine loadWaveData:audioData error:&audioError]) {
      _audioRuntime->startBeds();
      _audioRuntime->drainEvents();
      [_audioEngine startBeds];
    } else {
      @synchronized(self) { _sceneError=[NSString stringWithFormat:@"Audio: %@",audioError.localizedDescription]; }
    }
  }
  return meshCount > 0;
}

- (void)resizeToDrawableSize:(CGSize)drawableSize {
  @synchronized(self) {
    if (_state != AsterixMetalRendererStateStopped) {
      _drawableSize = drawableSize;
      _depthTexture = nil;
    }
  }
}

- (void)setInputMoveX:(float)moveX moveZ:(float)moveZ jump:(BOOL)jump
               attack:(BOOL)attack interact:(BOOL)interact {
  @synchronized(self) {
    _playerInput.move_x=std::clamp(moveX,-1.0f,1.0f);
    _playerInput.move_z=std::clamp(moveZ,-1.0f,1.0f);
    _playerInput.jump=jump;
    _playerInput.attack=attack;
    _interactPressed=interact;
  }
}

- (void)suspend {
  @synchronized(self) {
    if (_state != AsterixMetalRendererStateRunning) {
      return;
    }
    _state = AsterixMetalRendererStateSuspended;
    _view.paused = YES;
    [_audioEngine suspend];
  }
}

- (void)resume {
  @synchronized(self) {
    if (_state == AsterixMetalRendererStateStopped) {
      return;
    }
    _state = AsterixMetalRendererStateRunning;
    _lastSimulationTime = CACurrentMediaTime();
    _view.paused = NO;
    [_audioEngine resume];
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
  [_audioEngine stop];

  @synchronized(self) {
    _commandQueue = nil;
    _pipeline = nil;
    _depthState = nil;
    _vertices = nil;
    _sceneVertices = nil;
    _collisionVertices = nil;
    _fireVertices = nil;
    _fireEmitters.clear();
    _fogRuntime.reset();
    _collisionTriangleCount = 0;
    _sceneTexture = nil;
    _sceneTextures = nil;
    _sceneSamplers = nil;
    _sceneVertexCount = 0;
    _sceneMeshCount = 0;
    _visibleMeshCount = 0;
    _drawBatchCount = 0;
    _sceneMeshRanges.clear();
    _sceneRuntime.reset();
    _playerRuntime.reset();
    _playerAnimationRuntime.reset();
    _enemyRuntime.reset();
    _interactiveRuntime.reset();
    _cameraRuntime.reset();
    _combatRuntime.reset();
    _audioRuntime.reset();
    _capsuleController.reset();
    _enemyCapsuleController.reset();
    _collisionWorld.reset();
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
      const double elapsed = MAX(0.0, cpuStart - _lastSimulationTime);
      _lastSimulationTime = cpuStart;
      asterix::camera::Snapshot cameraSnapshot;
      BOOL hasGameplayCamera = NO;
      @synchronized(self) {
        _simulationClock.advance(elapsed, [&](double step) {
          _previousAnimationPhase = _currentAnimationPhase;
          _currentAnimationPhase += (float)step;
          if(_fogRuntime)_fogRuntime->advance(step);
          asterix::collision::Vec3 previousPlayer{};
          if (_playerRuntime) {
            previousPlayer=_playerRuntime->snapshot().body.position;
            _playerRuntime->update((float)step,_playerInput);
          }
          if(_interactiveRuntime&&_playerRuntime) {
            const auto playerPosition=_playerRuntime->snapshot().body.position;
            _playerRuntime->resolveInteractivePosition(
                _interactiveRuntime->resolvePushBlocks(previousPlayer,playerPosition));
            const bool interactEdge=_interactPressed&&!_interactWasPressed;
            _interactWasPressed=_interactPressed;
            if(_playerRuntime->snapshot().state==asterix::player::State::death&&interactEdge) {
              const auto respawn=_interactiveRuntime->restoreCheckpoint();
              if(respawn) {
                _playerRuntime->respawn(*respawn);
                if(_enemyRuntime)_enemyRuntime->reset();
                if(_combatRuntime) {
                  _combatRuntime->cancelAttack();
                  _combatRuntime->setFighterHealth(
                      1,_playerRuntime->config().maximum_health);
                  _combatRuntime->resetFighter(2,3);
                  _combatRuntime->resetFighter(100,2);
                }
              }
            } else {
              _interactiveRuntime->update(_playerRuntime->snapshot().body.position,interactEdge);
              if(_playerRuntime->snapshot().body.recovered_from_fall) {
                _interactiveRuntime->restoreCheckpoint();
                if(_enemyRuntime)_enemyRuntime->reset();
                if(_combatRuntime) {
                  _combatRuntime->cancelAttack();
                  _combatRuntime->resetFighter(2,3);
                  _combatRuntime->resetFighter(100,2);
                }
              }
              for(const auto& event:_interactiveRuntime->drainEvents()) {
                if(_audioRuntime) {
                  using IT=asterix::interactive::EventType;
                  if(event.type==IT::lever_activated)_audioRuntime->play(asterix::audio::Cue::lever,_playerRuntime->snapshot().body.position);
                  else if(event.type==IT::reward_collected)_audioRuntime->play(asterix::audio::Cue::reward);
                  else if(event.type==IT::checkpoint_activated)_audioRuntime->play(asterix::audio::Cue::checkpoint);
                }
                if(event.type==asterix::interactive::EventType::checkpoint_activated)
                  for(const auto& checkpoint:_interactiveRuntime->checkpoints())
                    if(checkpoint.id==event.id)_playerRuntime->setCheckpoint(checkpoint.position);
              }
            }
          }
          if (_enemyRuntime && _playerRuntime) {
            const auto enemyResult=_enemyRuntime->update(
                (float)step,_playerRuntime->snapshot().body.position,
                _playerRuntime->snapshot().state!=asterix::player::State::death);
            if(enemyResult.dealt_damage) {
              _playerRuntime->applyDamage(_enemyRuntime->attackDamage());
              if(_audioRuntime) {
                _audioRuntime->play(asterix::audio::Cue::enemy_attack,enemyResult.snapshot->body.position);
                if(_playerRuntime->snapshot().state==asterix::player::State::death)
                  _audioRuntime->play(asterix::audio::Cue::death);
              }
            }
          }
          if (_combatRuntime && _playerRuntime) {
            const bool attackEdge=_playerInput.attack&&!_combatAttackWasPressed;
            _combatAttackWasPressed=_playerInput.attack;
            const bool playerAlive=
                _playerRuntime->snapshot().state!=asterix::player::State::death;
            if(attackEdge&&playerAlive)_combatRuntime->pressAttack(1);
            const auto playerSnapshot=_playerRuntime->snapshot();
            const auto body=playerSnapshot.body;
            _combatRuntime->setTransform(
                1,body.position,
                asterix::player::facingVector(playerSnapshot.facing_radians));
            if(_enemyRuntime) {
              const auto enemy=_enemyRuntime->snapshot();
              _combatRuntime->setTransform(2,enemy.body.position,enemy.facing);
            }
            if(_interactiveRuntime&&!_interactiveRuntime->destructibles().empty())
              _combatRuntime->setTransform(100,
                  _interactiveRuntime->destructibles().front().position,{1,0,0});
            const std::size_t previousStage=_combatRuntime->attack().stage;
            _combatRuntime->update((float)step);
            if(_combatRuntime->attack().active&&
               _combatRuntime->attack().stage!=previousStage)
              _playerRuntime->restartAttack();
            for(const auto& event:_combatRuntime->drainEvents()) {
              if(_audioRuntime) {
                if(event.type==asterix::combat::EventType::attack_started)
                  _audioRuntime->play(asterix::audio::Cue::attack,body.position);
                else if(event.type==asterix::combat::EventType::hit) {
                  auto hitPosition=body.position;
                  for(const auto& fighter:_combatRuntime->fighters())if(fighter.id==event.target)hitPosition=fighter.position;
                  _audioRuntime->play(asterix::audio::Cue::hit,hitPosition);
                }
              }
              if(event.type!=asterix::combat::EventType::hit||event.target!=2||
                 !_enemyRuntime) {
                if(event.type==asterix::combat::EventType::hit&&event.target==100&&
                   _interactiveRuntime)_interactiveRuntime->damage(100,event.damage);
                continue;
              }
              asterix::collision::Vec3 knockback{};
              for(const auto& fighter:_combatRuntime->fighters())
                if(fighter.id==2)knockback=fighter.knockback_velocity;
              _enemyRuntime->applyDamage(event.damage,knockback);
            }
          }
          if (_playerAnimationRuntime && _playerRuntime) {
            _previousPlayerPose=_currentPlayerPose;
            _playerAnimationRuntime->advance(step,_playerRuntime->snapshot());
            _currentPlayerPose=_playerAnimationRuntime->snapshot();
          }
          if (_cameraRuntime && _playerRuntime && _collisionWorld) {
            _cameraRuntime->update(_playerRuntime->snapshot().body.position,
                                   *_collisionWorld,(float)step);
          }
          if(_audioRuntime&&_playerRuntime) {
            _audioRuntime->update((float)step);
            const auto player=_playerRuntime->snapshot();
            if(player.state==asterix::player::State::run&&player.body.grounded) {
              _footstepSeconds+=(float)step;
              if(_footstepSeconds>=.34f) {
                _footstepSeconds=0;
                _audioRuntime->play(asterix::audio::Cue::footstep,player.body.position);
              }
            } else _footstepSeconds=.3f;
            for(const auto& request:_audioRuntime->drainEvents()) {
              vector_float3 position={request.position.x,request.position.y,request.position.z};
              [_audioEngine playCue:(NSUInteger)request.cue channel:request.channel position:position spatial:request.spatial gain:request.gain];
            }
          }
        });
        if (_cameraRuntime && _cameraRuntime->initialized()) {
          cameraSnapshot=_cameraRuntime->interpolatedSnapshot(
              _simulationClock.interpolationAlpha());
          hasGameplayCamera=YES;
          const auto forward=cameraSnapshot.target-cameraSnapshot.position;
          [_audioEngine setListenerPosition:(vector_float3){cameraSnapshot.position.x,cameraSnapshot.position.y,cameraSnapshot.position.z}
                                    forward:(vector_float3){forward.x,forward.y,forward.z}];
        }
      }
      const float seconds = asterix::simulation::interpolate(
          _previousAnimationPhase, _currentAnimationPhase,
          _simulationClock.interpolationAlpha());
      const float c = cosf(seconds * 0.7f), s = sinf(seconds * 0.7f);
      id<MTLBuffer> sceneVertices = nil;
      id<MTLTexture> sceneTexture = nil;
      id<MTLBuffer> collisionVertices = nil;
      id<MTLBuffer> fireVertices = nil;
      std::vector<AsterixFireEmitter> fireEmitters;
      NSUInteger sceneVertexCount = 0;
      NSUInteger collisionTriangleCount = 0;
      uint32_t debugOptions = 0;
      vector_float3 sceneCenter = {0, 0, 0};
      float sceneRadius = 1;
      @synchronized(self) {
        if(_sceneVertices&&_interactiveRuntime) {
          AsterixVertex* vertices=(AsterixVertex*)_sceneVertices.contents;
          for(auto& mesh:_pushMeshes)for(const auto& block:_interactiveRuntime->pushBlocks())
            if(block.id==mesh.id&&block.offset!=mesh.appliedOffset) {
              const auto delta=block.axis*(block.offset-mesh.appliedOffset);
              for(NSUInteger index=0;index<mesh.vertexCount;++index) {
                auto& position=vertices[mesh.vertexStart+index].position;
                position+=(vector_float3){delta.x,delta.y,delta.z};
              }
              mesh.appliedOffset=block.offset;
            }
        }
        if(_sceneVertices&&_playerRuntime&&_playerMarkerVertexStart!=NSNotFound)
          AsterixWriteMarker((AsterixVertex*)_sceneVertices.contents+_playerMarkerVertexStart,
                             _playerRuntime->snapshot().body.position,
                             (vector_float3){1.0f,.72f,.08f},900001);
        if(_sceneVertices&&_enemyRuntime&&_enemyMarkerVertexStart!=NSNotFound)
          AsterixWriteMarker((AsterixVertex*)_sceneVertices.contents+_enemyMarkerVertexStart,
                             _enemyRuntime->snapshot().body.position,
                             (vector_float3){.85f,.08f,.06f},900002);
        sceneVertices = _sceneVertices;
        sceneTexture = _sceneTexture;
        collisionVertices = _collisionVertices;
        fireVertices = _fireVertices;
        fireEmitters = _fireEmitters;
        sceneVertexCount = _sceneVertexCount;
        collisionTriangleCount = _collisionTriangleCount;
        debugOptions = _debugOptions;
        sceneCenter = _sceneCenter;
        sceneRadius = _sceneRadius;
      }
      BOOL hasScene = sceneVertices != nil && sceneVertexCount > 0;
      matrix_float4x4 rotation = hasScene && hasGameplayCamera
          ? AsterixLookAt(
              (vector_float3){cameraSnapshot.position.x,cameraSnapshot.position.y,cameraSnapshot.position.z},
              (vector_float3){cameraSnapshot.target.x,cameraSnapshot.target.y,cameraSnapshot.target.z})
          : hasScene
          ? (matrix_float4x4){{{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0},
                              {-sceneCenter.x, -sceneCenter.y, -sceneCenter.z - sceneRadius * 2.2f, 1}}}
          : (matrix_float4x4){{{c, 0, -s, 0}, {0, 1, 0, 0}, {s, 0, c, 0}, {0, 0, -2.4f, 1}}};
      const float aspect = MAX(0.01f, view.drawableSize.width / view.drawableSize.height);
      const float fieldOfView = hasGameplayCamera ? cameraSnapshot.field_of_view_degrees : 70.0f;
      const matrix_float4x4 viewProjection = simd_mul(AsterixPerspective(fieldOfView * 3.14159265358979323846f / 180.0f,
                                                                         aspect, 0.1f, 1000.0f), rotation);
      AsterixUniforms uniforms = {viewProjection,
                                  0u,
                                  sceneRadius * 1.2f, sceneRadius * 3.2f,
                                  debugOptions,.01f};
      if(_fogRuntime) {
        const asterix::fog_volume::Vec3 viewpoint=hasGameplayCamera
            ?asterix::fog_volume::Vec3{cameraSnapshot.position.x,cameraSnapshot.position.y,cameraSnapshot.position.z}
            :asterix::fog_volume::Vec3{sceneCenter.x,sceneCenter.y,sceneCenter.z+sceneRadius*2.2f};
        const auto fog=_fogRuntime->sample(viewpoint);
        uniforms.volumeFogColor={fog.color.r,fog.color.g,fog.color.b,1};
        uniforms.volumeFogAmount=fog.density;
      }
      if(fireVertices!=nil&&!fireEmitters.empty()) {
        vector_float3 right={1,0,0};
        if(hasGameplayCamera) {
          vector_float3 forward=simd_normalize((vector_float3){
              cameraSnapshot.target.x-cameraSnapshot.position.x,
              cameraSnapshot.target.y-cameraSnapshot.position.y,
              cameraSnapshot.target.z-cameraSnapshot.position.z});
          vector_float3 candidate=simd_cross(forward,(vector_float3){0,1,0});
          if(simd_length_squared(candidate)>.0001f)right=simd_normalize(candidate);
        }
        const vector_float3 up={0,1,0};
        AsterixVertex* output=(AsterixVertex*)fireVertices.contents;
        for(NSUInteger index=0;index<fireEmitters.size();++index) {
          const auto& emitter=fireEmitters[index];
          const float phase=seconds*emitter.rate+(float)(emitter.objectId%17u)*.137f;
          const BOOL smoke=emitter.mode==3;
          const float width=(smoke?1.25f:.9f)*(1+.12f*sinf(phase*12.566f));
          const float height=(smoke?1.8f:2.15f)*(1+.1f*cosf(phase*12.566f));
          const vector_float3 center=emitter.position+right*(.09f*sinf(phase*6.283f))+
              up*(height*.5f+.08f*cosf(phase*12.566f));
          const vector_float3 left=center-right*width*.5f, r=center+right*width*.5f;
          const vector_float3 bottom=up*height*.5f, top=up*height*.5f;
          const vector_float3 color=smoke?(vector_float3){.72f,.72f,.72f}:(vector_float3){1,1,1};
          const float alpha=smoke?.72f:.94f;
          const vector_float3 p[4]={left-bottom,r-bottom,left+top,r+top};
          const vector_float2 uv[4]={{0,1},{1,1},{0,0},{1,0}};
          const NSUInteger order[6]={0,1,2,2,1,3};
          for(NSUInteger corner=0;corner<6;++corner) {
            const NSUInteger source=order[corner];
            output[index*6+corner]={p[source],color,{0,0,1},uv[source],alpha,1,0,
                {0,0,0,0},{1,0,0,0},emitter.objectId};
          }
        }
      }
      [encoder setRenderPipelineState:_pipeline];
      [encoder setTriangleFillMode:(debugOptions & 1u) != 0 ? MTLTriangleFillModeLines : MTLTriangleFillModeFill];
      [encoder setDepthStencilState:_depthState];
      [encoder setVertexBuffer:hasScene ? sceneVertices : _vertices offset:0 atIndex:0];
      [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
      std::vector<matrix_float4x4> playerBones(
          std::max<std::size_t>(1,_playerJoints.size()),matrix_identity_float4x4);
      if (!hasScene) {
        const float angle = sinf(seconds * 2.0f) * .45f;
        playerBones.push_back((matrix_float4x4){{{cosf(angle), sinf(angle), 0, 0},
                                      {-sinf(angle), cosf(angle), 0, 0},
                                      {0, 0, 1, 0}, {0, 0, 0, 1}}});
      } else if(_playerRuntime&&!_playerJoints.empty()) {
        const auto snapshot=_playerRuntime->snapshot();
        NSString* reviewClip=nil;
        CFTimeInterval reviewStartedAt=0;
        NSUInteger reviewIndex=NSNotFound;
        @synchronized(self) {
          reviewClip=_animationReviewClip;
          reviewStartedAt=_animationReviewStartedAt;
          if(reviewClip!=nil)reviewIndex=[_animationReviewCandidates indexOfObjectPassingTest:
              ^BOOL(NSDictionary* candidate,NSUInteger _,BOOL* stop) {
                return [candidate[@"clip"] isEqual:reviewClip];
              }];
        }
        if(reviewIndex!=NSNotFound&&reviewIndex<_animationReviewClips.size()) {
          try {
            const auto palette=asterix::animation::skinningPalette(
                _animationReviewClips[reviewIndex],_playerJoints,
                std::max(0.0,CACurrentMediaTime()-reviewStartedAt));
            playerBones.clear(); playerBones.reserve(palette.size());
            const float yaw=asterix::player::authoredNegativeZYaw(snapshot.facing_radians);
            const matrix_float4x4 facing=(matrix_float4x4){{
                {cosf(yaw),0,-sinf(yaw),0},{0,1,0,0},
                {sinf(yaw),0,cosf(yaw),0},{0,0,0,1}}};
            for(const auto& matrix:palette) {
              auto metal=simd_mul(facing,AsterixMetalMatrix(matrix));
              constexpr float capsuleBottomOffset=.55f+.35f;
              metal.columns[3].xyz+=(vector_float3){snapshot.body.position.x,
                  snapshot.body.position.y-capsuleBottomOffset,snapshot.body.position.z};
              playerBones.push_back(metal);
            }
          } catch(const std::exception&) {}
        } else if(_playerAnimationRuntime) {
          try {
            const asterix::animation_pose::Playback playback(
                _playerClips,_playerJoints);
            const auto sampled=playback.sample(
                _previousPlayerPose,_currentPlayerPose,
                _simulationClock.interpolationAlpha());
            const auto& palette=sampled.palette;
            playerBones.clear(); playerBones.reserve(palette.size());
            // Convert the authored -Z forward axis from its column-vector
            // rotation convention to the canonical gameplay facing.
            const float yaw=
                asterix::player::authoredNegativeZYaw(snapshot.facing_radians);
            const matrix_float4x4 facing=(matrix_float4x4){{
                {cosf(yaw),0,-sinf(yaw),0},{0,1,0,0},
                {sinf(yaw),0,cosf(yaw),0},{0,0,0,1}}};
            for(const auto& matrix:palette) {
              auto metal=simd_mul(facing,AsterixMetalMatrix(matrix));
              // Gameplay stores the capsule centre; the authored skin origin
              // is at the soles. Keep presentation on the collision ground.
              constexpr float capsuleBottomOffset=.55f+.35f;
              metal.columns[3].xyz+=(vector_float3){snapshot.body.position.x,
                                                    snapshot.body.position.y-capsuleBottomOffset,
                                                    snapshot.body.position.z};
              playerBones.push_back(metal);
            }
          } catch(const std::exception&) { playerBones.assign(_playerJoints.size(),matrix_identity_float4x4); }
        }
      }
      matrix_float4x4 identityBone=matrix_identity_float4x4;
      [encoder setVertexBytes:&identityBone length:sizeof(identityBone) atIndex:2];
      [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
      if (sceneTexture != nil) [encoder setFragmentTexture:sceneTexture atIndex:0];
      if (!hasScene) {
        // A missing runtime package is a configuration error, not a playable
        // proof scene. Keep the viewport empty until the menu supplies ASTPAK.
      } else {
        std::vector<asterix::scene::DrawBatch> batches;
        std::vector<std::vector<AsterixMeshRange>> meshRanges;
        @synchronized(self) {
          if (_sceneRuntime) {
            auto renderFrustum = AsterixFrustum(viewProjection);
            auto preloadFrustum = renderFrustum;
            for (auto& plane : preloadFrustum.planes)
              plane.distance += sceneRadius * 0.15f;
            _sceneRuntime->updateStreaming(preloadFrustum, _frameCount);
            for (std::size_t section : _sceneRuntime->pendingSections())
              _sceneRuntime->markResident(section);
            const std::array<float,3> cameraPosition = hasGameplayCamera
                ? std::array<float,3>{cameraSnapshot.position.x,
                                      cameraSnapshot.position.y,
                                      cameraSnapshot.position.z}
                : std::array<float,3>{sceneCenter.x, sceneCenter.y,
                                      sceneCenter.z + sceneRadius * 2.2f};
            batches = _sceneRuntime->buildBatches(renderFrustum,
                                                  cameraPosition,
                                                  sceneRadius * 1.5f);
          }
          meshRanges = _sceneMeshRanges;
          _drawBatchCount = batches.size();
          _visibleMeshCount = 0;
          for (const auto& batch : batches) _visibleMeshCount += batch.items.size();
        }
        for(NSUInteger pass=0;pass<2;++pass) {
          const BOOL blended=pass==1;
          [encoder setDepthStencilState:blended?_readOnlyDepthState:_depthState];
          for (const auto& batch : batches) for (const auto& item : batch.items) {
            if (item.node_index >= meshRanges.size()) continue;
            for(const AsterixMeshRange& range:meshRanges[item.node_index]) {
              if(range.blended!=blended)continue;
              AsterixUniforms materialUniforms=uniforms;
              materialUniforms.textured=range.texture!=nil?1u:0u;
              materialUniforms.alphaCutoff=range.alphaCutoff;
              if(simd_length_squared(range.waterSpeed)>0) {
                materialUniforms.effect=2;
                materialUniforms.uvOffset={
                    range.waterPhase+range.waterSpeed.x*seconds,
                    range.waterPhase+range.waterSpeed.y*seconds};
              }
              [encoder setVertexBytes:&materialUniforms length:sizeof(materialUniforms) atIndex:1];
              [encoder setFragmentBytes:&materialUniforms length:sizeof(materialUniforms) atIndex:1];
              [encoder setFragmentTexture:range.texture atIndex:0];
              [encoder setFragmentSamplerState:range.sampler atIndex:0];
              [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:range.vertexStart
                          vertexCount:range.vertexCount];
            }
          }
        }
        if(fireVertices!=nil&&!fireEmitters.empty()) {
          [encoder setDepthStencilState:_readOnlyDepthState];
          [encoder setVertexBuffer:fireVertices offset:0 atIndex:0];
          AsterixUniforms fireUniforms=uniforms;
          fireUniforms.textured=1;
          fireUniforms.alphaCutoff=.01f;
          fireUniforms.effectTime=seconds;
          fireUniforms.effect=1;
          [encoder setVertexBytes:&fireUniforms length:sizeof(fireUniforms) atIndex:1];
          [encoder setFragmentBytes:&fireUniforms length:sizeof(fireUniforms) atIndex:1];
          [encoder setFragmentSamplerState:_defaultSampler atIndex:0];
          for(NSUInteger index=0;index<fireEmitters.size();++index) {
            [encoder setFragmentTexture:fireEmitters[index].texture atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:index*6 vertexCount:6];
          }
          [encoder setVertexBuffer:sceneVertices offset:0 atIndex:0];
          [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
          [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        }
        [encoder setDepthStencilState:nil];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        if(_playerMeshVertexStart!=NSNotFound) {
          [encoder setDepthStencilState:_depthState];
          [encoder setVertexBytes:playerBones.data()
                           length:playerBones.size()*sizeof(matrix_float4x4) atIndex:2];
          for(const auto& range:_playerMeshRanges) {
            AsterixUniforms playerUniforms=uniforms;
            playerUniforms.textured=range.texture!=nil?1u:0u;
            [encoder setVertexBytes:&playerUniforms length:sizeof(playerUniforms) atIndex:1];
            [encoder setFragmentBytes:&playerUniforms length:sizeof(playerUniforms) atIndex:1];
            [encoder setFragmentTexture:range.texture atIndex:0];
            [encoder setFragmentSamplerState:range.sampler?:_defaultSampler atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                        vertexStart:range.vertexStart vertexCount:range.vertexCount];
          }
          [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
          [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
          [encoder setVertexBytes:&identityBone length:sizeof(identityBone) atIndex:2];
          [encoder setDepthStencilState:nil];
        }
        if(_playerMarkerVertexStart!=NSNotFound)
          [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:_playerMarkerVertexStart vertexCount:6];
        if(_enemyMarkerVertexStart!=NSNotFound)
          [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:_enemyMarkerVertexStart vertexCount:6];
        [encoder setDepthStencilState:_depthState];
        if ((debugOptions & 2u) != 0 && collisionVertices != nil) {
          AsterixUniforms debugUniforms = uniforms;
          debugUniforms.textured = 0;
          [encoder setTriangleFillMode:MTLTriangleFillModeLines];
          [encoder setVertexBuffer:collisionVertices offset:0 atIndex:0];
          [encoder setVertexBytes:&debugUniforms length:sizeof(debugUniforms) atIndex:1];
          [encoder setFragmentBytes:&debugUniforms length:sizeof(debugUniforms) atIndex:1];
          [encoder setDepthBias:-1.0 slopeScale:-1.0 clamp:-4.0];
          [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0
                      vertexCount:collisionTriangleCount * 3];
          [encoder setDepthBias:0 slopeScale:0 clamp:0];
        }
      }
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
