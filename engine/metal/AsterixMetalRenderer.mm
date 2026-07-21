#import "AsterixMetalRenderer.h"

#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#include <string.h>
#include <memory>
#include <unordered_map>
#include <vector>
#include "asterix/scene_runtime.hpp"
#include "asterix/simulation_runtime.hpp"
#include "asterix/player_runtime.hpp"
#include "asterix/camera_runtime.hpp"
#include "asterix/combat_runtime.hpp"
#include "asterix/enemy_runtime.hpp"
#include "asterix/interactive_runtime.hpp"

typedef struct {
  vector_float3 position;
  vector_float3 color;
  vector_float3 normal;
  vector_float2 uv;
  float alpha;
  float ambient;
  float diffuse;
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
} AsterixUniforms;

typedef struct {
  NSUInteger vertexStart;
  NSUInteger vertexCount;
} AsterixMeshRange;

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

@implementation AsterixMetalRenderer {
  __weak MTKView* _view;
  id<MTLCommandQueue> _commandQueue;
  id<MTLRenderPipelineState> _pipeline;
  id<MTLDepthStencilState> _depthState;
  id<MTLBuffer> _vertices;
  id<MTLBuffer> _sceneVertices;
  id<MTLBuffer> _collisionVertices;
  id<MTLTexture> _sceneTexture;
  NSUInteger _sceneVertexCount;
  NSUInteger _sceneMeshCount;
  NSUInteger _collisionTriangleCount;
  NSUInteger _visibleMeshCount;
  NSUInteger _drawBatchCount;
  std::vector<AsterixMeshRange> _sceneMeshRanges;
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
  std::unique_ptr<asterix::collision::CapsuleController> _enemyCapsuleController;
  std::unique_ptr<asterix::enemy::Runtime> _enemyRuntime;
  std::unique_ptr<asterix::interactive::Runtime> _interactiveRuntime;
  std::unique_ptr<asterix::camera::Runtime> _cameraRuntime;
  std::unique_ptr<asterix::combat::Runtime> _combatRuntime;
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
      "struct V { float3 p; float3 c; float3 n; float2 uv; float a; float ambient; float diffuse; uint4 joints; float4 weights; uint objectId; }; struct U { float4x4 m; uint textured; float fogStart; float fogEnd; uint debugOptions; };\n"
      "struct O { float4 p [[position]]; float3 c; float3 n; float2 uv; float a; float distance; float ambient; float diffuse; };\n"
      "vertex O vs(uint i [[vertex_id]], constant V* v [[buffer(0)]], constant U& u [[buffer(1)]], constant float4x4* bones [[buffer(2)]]) { O o; float4 local=float4(v[i].p,1); float4 skinned=float4(0); float3 normal=float3(0); for(uint j=0;j<4;j++){ float4x4 bone=bones[v[i].joints[j]]; skinned+=bone*local*v[i].weights[j]; normal+=float3x3(bone[0].xyz,bone[1].xyz,bone[2].xyz)*v[i].n*v[i].weights[j]; } float4 p=u.m*skinned; o.p=p; uint h=v[i].objectId*1664525u+1013904223u; o.c=(u.debugOptions&16u)!=0?float3(float(h&255u),float((h>>8)&255u),float((h>>16)&255u))/255.0:v[i].c; o.n=normal; o.uv=v[i].uv; o.a=v[i].a; o.distance=abs(p.w); o.ambient=v[i].ambient; o.diffuse=v[i].diffuse; return o; }\n"
      "fragment float4 fs(O i [[stage_in]], constant U& u [[buffer(1)]], texture2d<float> t [[texture(0)]]) { constexpr sampler s(filter::linear, mip_filter::linear, address::repeat); float4 base=u.textured != 0 ? t.sample(s,i.uv)*float4(i.c,i.a) : float4(i.c,i.a); if(base.a<0.01) discard_fragment(); float light=saturate(i.ambient+i.diffuse*max(dot(normalize(i.n),normalize(float3(.35,.8,.45))),0.0)); base.rgb*=light; float fog=saturate((u.fogEnd-i.distance)/max(.001,u.fogEnd-u.fogStart)); return float4(mix(float3(.58,.68,.72),base.rgb,fog),base.a); }";
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
  const AsterixVertex vertices[] = {
      {{0.0f, 0.9f, 0.0f}, {1.0f, 0.75f, 0.12f}, {0, 0, 1}, {0.5f, 0}, 1, .35f, .65f, {1,0,0,0}, {1,0,0,0}, 1},
      {{-0.8f, -0.65f, 0.0f}, {0.12f, 0.65f, 1.0f}, {0, 0, 1}, {0, 1}, 1, .35f, .65f, {0,0,0,0}, {1,0,0,0}, 1},
      {{0.8f, -0.65f, 0.0f}, {0.95f, 0.2f, 0.15f}, {0, 0, 1}, {1, 1}, 1, .35f, .65f, {0,0,0,0}, {1,0,0,0}, 1},
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
- (NSInteger)playerHealth { @synchronized(self) { return _playerRuntime ? _playerRuntime->snapshot().health : 0; } }
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
  NSMutableDictionary<NSString*, id<MTLTexture>>* textures = [NSMutableDictionary dictionary];
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
    textures[name] = texture;
  }
  NSMutableData* vertexData = [NSMutableData data];
  NSMutableData* collisionVertexData = [NSMutableData data];
  std::vector<asterix::collision::Triangle> collisionTriangles;
  std::vector<AsterixMeshRange> meshRanges;
  std::vector<asterix::scene::Node> runtimeNodes;
  NSUInteger meshCount = 0;
  vector_float3 minimum = {INFINITY, INFINITY, INFINITY};
  vector_float3 maximum = {-INFINITY, -INFINITY, -INFINITY};
  asterix::scene::Runtime transformGraph;
  std::unordered_map<std::string, std::string> payloadNodes;
  for (NSDictionary* resource in manifest[@"resources"]) {
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
        collisionTriangles.push_back({{points[0].x,points[0].y,points[0].z},
                                      {points[1].x,points[1].y,points[1].z},
                                      {points[2].x,points[2].y,points[2].z},
                                      (int)objectId});
        for (vector_float3 point : points) {
          AsterixVertex vertex = {point,{1,.08f,.12f},{0,1,0},{0,0},1,1,0,
                                  {0,0,0,0},{1,0,0,0},objectId};
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
  }
  try {
    transformGraph.resolveHierarchy();
  } catch (const std::exception&) {
    [self reportSceneError:@"Scene graph contains a missing parent or cycle"];
    return NO;
  }
  std::unordered_map<std::string, asterix::scene::Matrix4> worldTransforms;
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
    NSArray* triangles = mesh[@"triangles"];
    NSArray* materials = mesh[@"materials"];
    NSArray* uvSets = mesh[@"uvSets"];
    NSArray* uvs = uvSets.count > 0 ? uvSets[0] : nil;
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
      }
      NSDictionary* material = materialIndex < materials.count ? materials[materialIndex] : nil;
      if ([material[@"ambient"] isKindOfClass:NSNumber.class]) ambient = [material[@"ambient"] floatValue];
      if ([material[@"diffuse"] isKindOfClass:NSNumber.class]) diffuse = [material[@"diffuse"] floatValue];
      for (NSUInteger corner = 0; corner < 3; ++corner) {
        NSUInteger index = [triangle[corner] unsignedIntegerValue];
        if (index >= positions.count || [positions[index] count] < 3) continue;
        NSArray* p = positions[index];
        vector_float4 world = simd_mul(model, (vector_float4){[p[0] floatValue], [p[1] floatValue], [p[2] floatValue], 1});
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
        AsterixVertex vertex = {{world.x, world.y, world.z}, c, normal, uv,
                                alpha, ambient, diffuse, {0,0,0,0}, {1,0,0,0},
                                (uint32_t)[mesh[@"objectId"] unsignedIntValue]};
        [vertexData appendBytes:&vertex length:sizeof(vertex)];
      }
    }
    if (vertexData.length > before) {
      const NSUInteger start = before / sizeof(AsterixVertex);
      const NSUInteger count = (vertexData.length - before) / sizeof(AsterixVertex);
      meshRanges.push_back({start, count});
      asterix::scene::Node node;
      node.id = [resourceId UTF8String] ?: "";
      node.section_id = "gaul-stage-1";
      node.resource_id = node.id;
      node.world_bounds = {{meshMinimum.x, meshMinimum.y, meshMinimum.z},
                           {meshMaximum.x, meshMaximum.y, meshMaximum.z}};
      node.full_vertex_count = (uint32_t)count;
      runtimeNodes.push_back(std::move(node));
      meshCount++;
    }
    if (selectedTexture == nil) for (NSDictionary* material in materials) {
      NSString* textureName = material[@"texture"];
      if (![textureName isKindOfClass:NSString.class]) continue;
      id<MTLTexture> texture = textures[textureName];
      if (texture != nil) { selectedTexture = texture; break; }
    }
  }
  id<MTLDevice> device = view.device;
  if (vertexData.length == 0 || device == nil) {
    @synchronized(self) { _sceneError = @"ASTPAK contains no renderable scene meshes"; }
    return NO;
  }
  id<MTLBuffer> buffer = [device newBufferWithBytes:vertexData.bytes length:vertexData.length options:MTLResourceStorageModeShared];
  id<MTLBuffer> collisionBuffer = collisionVertexData.length == 0 ? nil :
      [device newBufferWithBytes:collisionVertexData.bytes length:collisionVertexData.length options:MTLResourceStorageModeShared];
  auto runtime = std::make_unique<asterix::scene::Runtime>();
  std::unique_ptr<asterix::collision::World> collisionWorld;
  std::unique_ptr<asterix::collision::CapsuleController> capsuleController;
  std::unique_ptr<asterix::player::Runtime> playerRuntime;
  std::unique_ptr<asterix::collision::CapsuleController> enemyCapsuleController;
  std::unique_ptr<asterix::enemy::Runtime> enemyRuntime;
  std::unique_ptr<asterix::interactive::Runtime> interactiveRuntime;
  std::unique_ptr<asterix::camera::Runtime> cameraRuntime;
  std::unique_ptr<asterix::combat::Runtime> combatRuntime;
  if (!collisionTriangles.empty()) {
    auto spawn = std::find_if(collisionTriangles.begin(),collisionTriangles.end(),[](const auto& triangle) {
      const auto normal=asterix::collision::normalized(
          asterix::collision::cross(triangle.b-triangle.a,triangle.c-triangle.a));
      return std::abs(normal.y)>=std::cos(50.0f*3.14159265358979323846f/180.0f);
    });
    const auto spawnTriangle=spawn==collisionTriangles.end()?collisionTriangles.front():*spawn;
    collisionWorld=std::make_unique<asterix::collision::World>(std::move(collisionTriangles));
    capsuleController=std::make_unique<asterix::collision::CapsuleController>(*collisionWorld);
    asterix::collision::CapsuleState body;
    body.position={(spawnTriangle.a.x+spawnTriangle.b.x+spawnTriangle.c.x)/3,
                   (spawnTriangle.a.y+spawnTriangle.b.y+spawnTriangle.c.y)/3+.9f,
                   (spawnTriangle.a.z+spawnTriangle.b.z+spawnTriangle.c.z)/3};
    body.checkpoint=body.position;
    playerRuntime=std::make_unique<asterix::player::Runtime>(*capsuleController,body);
    enemyCapsuleController=std::make_unique<asterix::collision::CapsuleController>(*collisionWorld);
    asterix::collision::CapsuleState enemyBody=body;
    const float slope=std::cos(50.0f*3.14159265358979323846f/180.0f);
    const asterix::collision::Vec3 offsets[]={{3,0,0},{-3,0,0},{0,0,3},{0,0,-3},
                                              {2,0,0},{-2,0,0},{0,0,2},{0,0,-2}};
    for(const auto offset:offsets) {
      const auto candidate=body.position+offset;
      const auto ground=collisionWorld->groundAt(candidate.x,candidate.z,
                                                  body.position.y+5.0f,slope);
      if(!ground)continue;
      enemyBody.position={candidate.x,ground->height+.9f,candidate.z};
      break;
    }
    enemyBody.checkpoint=enemyBody.position;
    enemyRuntime=std::make_unique<asterix::enemy::Runtime>(*enemyCapsuleController,enemyBody);
    interactiveRuntime=std::make_unique<asterix::interactive::Runtime>();
    interactiveRuntime->addTrigger({10,body.position,{1.5f,1,1.5f},true,false});
    interactiveRuntime->addLever({11,body.position+asterix::collision::Vec3{1,0,0},1.0f});
    interactiveRuntime->addDestructible({100,body.position+asterix::collision::Vec3{2,0,0},2,2,false});
    interactiveRuntime->addReward({12,body.position+asterix::collision::Vec3{2,0,0},100,1});
    interactiveRuntime->addCheckpoint({13,body.position,1.0f});
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
  }
  runtime->addSection({"gaul-stage-1",
                       {{minimum.x, minimum.y, minimum.z}, {maximum.x, maximum.y, maximum.z}},
                       true, true, 0});
  for (auto& node : runtimeNodes) runtime->addNode(std::move(node));
  runtime->resolveHierarchy();
  @synchronized(self) {
    _sceneVertices = buffer;
    _collisionVertices = collisionBuffer;
    _collisionTriangleCount = collisionVertexData.length / sizeof(AsterixVertex) / 3;
    _sceneTexture = selectedTexture;
    _sceneVertexCount = vertexData.length / sizeof(AsterixVertex);
    _sceneMeshCount = meshCount;
    _visibleMeshCount = meshCount;
    _drawBatchCount = meshCount > 0 ? 1 : 0;
    _sceneMeshRanges = std::move(meshRanges);
    _sceneRuntime = std::move(runtime);
    _collisionWorld = std::move(collisionWorld);
    _capsuleController = std::move(capsuleController);
    _playerRuntime = std::move(playerRuntime);
    _enemyCapsuleController = std::move(enemyCapsuleController);
    _enemyRuntime = std::move(enemyRuntime);
    _interactiveRuntime = std::move(interactiveRuntime);
    _cameraRuntime = std::move(cameraRuntime);
    _combatRuntime = std::move(combatRuntime);
    _combatAttackWasPressed = false;
    _interactPressed = false;
    _interactWasPressed = false;
    _sceneCenter = (minimum + maximum) * 0.5f;
    _sceneRadius = MAX(1.0f, simd_length(maximum - minimum) * 0.5f);
    _sceneError = nil;
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
    _sceneVertices = nil;
    _collisionVertices = nil;
    _collisionTriangleCount = 0;
    _sceneTexture = nil;
    _sceneVertexCount = 0;
    _sceneMeshCount = 0;
    _visibleMeshCount = 0;
    _drawBatchCount = 0;
    _sceneMeshRanges.clear();
    _sceneRuntime.reset();
    _playerRuntime.reset();
    _enemyRuntime.reset();
    _interactiveRuntime.reset();
    _cameraRuntime.reset();
    _combatRuntime.reset();
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
          if (_playerRuntime) _playerRuntime->update((float)step,_playerInput);
          if(_interactiveRuntime&&_playerRuntime) {
            const bool interactEdge=_interactPressed&&!_interactWasPressed;
            _interactWasPressed=_interactPressed;
            if(_playerRuntime->snapshot().state==asterix::player::State::death&&interactEdge) {
              const auto respawn=_interactiveRuntime->restoreCheckpoint();
              if(respawn) {
                _playerRuntime->respawn(*respawn);
                if(_enemyRuntime)_enemyRuntime->reset();
                if(_combatRuntime) {
                  _combatRuntime->cancelAttack();
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
              for(const auto& event:_interactiveRuntime->drainEvents())
                if(event.type==asterix::interactive::EventType::checkpoint_activated)
                  for(const auto& checkpoint:_interactiveRuntime->checkpoints())
                    if(checkpoint.id==event.id)_playerRuntime->setCheckpoint(checkpoint.position);
            }
          }
          if (_enemyRuntime && _playerRuntime) {
            const auto enemyResult=_enemyRuntime->update(
                (float)step,_playerRuntime->snapshot().body.position,
                _playerRuntime->snapshot().state!=asterix::player::State::death);
            if(enemyResult.dealt_damage)
              _playerRuntime->applyDamage(_enemyRuntime->attackDamage());
          }
          if (_combatRuntime && _playerRuntime) {
            const bool attackEdge=_playerInput.attack&&!_combatAttackWasPressed;
            _combatAttackWasPressed=_playerInput.attack;
            const bool playerAlive=
                _playerRuntime->snapshot().state!=asterix::player::State::death;
            if(attackEdge&&playerAlive)_combatRuntime->pressAttack(1);
            const auto body=_playerRuntime->snapshot().body;
            asterix::collision::Vec3 facing={_playerInput.move_x,0,_playerInput.move_z};
            _combatRuntime->setTransform(1,body.position,facing);
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
          if (_cameraRuntime && _playerRuntime && _collisionWorld) {
            _cameraRuntime->update(_playerRuntime->snapshot().body.position,
                                   *_collisionWorld,(float)step);
          }
        });
        if (_cameraRuntime && _cameraRuntime->initialized()) {
          cameraSnapshot=_cameraRuntime->snapshot();
          hasGameplayCamera=YES;
        }
      }
      const float seconds = asterix::simulation::interpolate(
          _previousAnimationPhase, _currentAnimationPhase,
          _simulationClock.interpolationAlpha());
      const float c = cosf(seconds * 0.7f), s = sinf(seconds * 0.7f);
      id<MTLBuffer> sceneVertices = nil;
      id<MTLTexture> sceneTexture = nil;
      id<MTLBuffer> collisionVertices = nil;
      NSUInteger sceneVertexCount = 0;
      NSUInteger collisionTriangleCount = 0;
      uint32_t debugOptions = 0;
      vector_float3 sceneCenter = {0, 0, 0};
      float sceneRadius = 1;
      @synchronized(self) {
        sceneVertices = _sceneVertices;
        sceneTexture = _sceneTexture;
        collisionVertices = _collisionVertices;
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
                                  hasScene && sceneTexture != nil ? 1u : 0u,
                                  sceneRadius * 1.2f, sceneRadius * 3.2f,
                                  debugOptions};
      [encoder setRenderPipelineState:_pipeline];
      [encoder setTriangleFillMode:(debugOptions & 1u) != 0 ? MTLTriangleFillModeLines : MTLTriangleFillModeFill];
      [encoder setDepthStencilState:_depthState];
      [encoder setVertexBuffer:hasScene ? sceneVertices : _vertices offset:0 atIndex:0];
      [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
      matrix_float4x4 bones[2] = {matrix_identity_float4x4, matrix_identity_float4x4};
      if (!hasScene) {
        const float angle = sinf(seconds * 2.0f) * .45f;
        bones[1] = (matrix_float4x4){{{cosf(angle), sinf(angle), 0, 0},
                                      {-sinf(angle), cosf(angle), 0, 0},
                                      {0, 0, 1, 0}, {0, 0, 0, 1}}};
      }
      [encoder setVertexBytes:bones length:sizeof(bones) atIndex:2];
      [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
      if (sceneTexture != nil) [encoder setFragmentTexture:sceneTexture atIndex:0];
      if (!hasScene) {
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      } else {
        std::vector<asterix::scene::DrawBatch> batches;
        std::vector<AsterixMeshRange> meshRanges;
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
        for (const auto& batch : batches) for (const auto& item : batch.items) {
          if (item.node_index >= meshRanges.size()) continue;
          const AsterixMeshRange range = meshRanges[item.node_index];
          [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:range.vertexStart
                      vertexCount:MIN((NSUInteger)item.vertex_count, range.vertexCount)];
        }
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
