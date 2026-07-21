#import <XCTest/XCTest.h>

#include "asterix/engine.h"
#include "asterix/animation_runtime.hpp"
#include "asterix/scene_runtime.hpp"
#include <chrono>
#include <unistd.h>

@interface AsterixEngineTests : XCTestCase
@end

@implementation AsterixEngineTests

- (void)testAnimationPaletteSkinningAndFog {
  using namespace asterix::animation;
  Clip clip;
  clip.duration = 2;
  Track root;
  root.keys = {{0, {}}, {2, {{0, 0, 0, 1}, {2, 0, 0}}}};
  Track child;
  child.keys = {{0, {{0, 0, 0, 1}, {0, 1, 0}}},
                {2, {{0, 0, 0, 1}, {0, 1, 0}}}};
  clip.tracks = {root, child};
  const auto palette = skinningPalette(clip, {{-1}, {0}}, 1);
  VertexBinding binding;
  binding.joints = {1, 0, 0, 0};
  const auto position = skinPosition({0, 0, 0}, binding, palette);
  XCTAssertEqualWithAccuracy(position[0], 1, 0.001);
  XCTAssertEqualWithAccuracy(position[1], 1, 0.001);
  XCTAssertEqualWithAccuracy(fogFactor(5, 0, 10), .5, 0.001);
  XCTAssertEqualWithAccuracy(fogFactor(20, 0, 10), 0, 0.001);
}

- (void)testSceneGraphResolvesHierarchyAndRejectsCycles {
  using namespace asterix::scene;
  Runtime runtime;
  Node root;
  root.id = "root";
  root.local = Matrix4::identity();
  root.local.value[12] = 10;
  runtime.addNode(root);
  Node child;
  child.id = "child";
  child.parent_id = "root";
  child.local = Matrix4::identity();
  child.local.value[13] = 4;
  runtime.addNode(child);
  runtime.resolveHierarchy();
  XCTAssertEqualWithAccuracy(runtime.nodes()[1].world.value[12], 10, 0.001);
  XCTAssertEqualWithAccuracy(runtime.nodes()[1].world.value[13], 4, 0.001);

  Runtime cyclic;
  Node first; first.id = "first"; first.parent_id = "second";
  Node second; second.id = "second"; second.parent_id = "first";
  cyclic.addNode(first);
  cyclic.addNode(second);
  XCTAssertThrows(cyclic.resolveHierarchy());
}

- (void)testStreamingCullingBatchingAndLod {
  using namespace asterix::scene;
  const Frustum cube = {{{{1, 0, 0, 10}, {-1, 0, 0, 10},
                            {0, 1, 0, 10}, {0, -1, 0, 10},
                            {0, 0, 1, 10}, {0, 0, -1, 10}}}};
  Runtime runtime;
  runtime.addSection({"near", {{-5, -5, -5}, {5, 5, 5}}});
  runtime.addSection({"far", {{100, 100, 100}, {110, 110, 110}}});
  Node close;
  close.id = "close"; close.section_id = "near";
  close.world_bounds = {{-1, -1, -1}, {1, 1, 1}};
  close.material = 7; close.full_vertex_count = 12;
  runtime.addNode(close);
  Node distant = close;
  distant.id = "distant";
  distant.world_bounds = {{7, -1, -1}, {9, 1, 1}};
  runtime.addNode(distant);

  runtime.updateStreaming(cube, 1);
  XCTAssertEqual(runtime.pendingSections().size(), 1u);
  runtime.markResident(runtime.pendingSections().front());
  const auto batches = runtime.buildBatches(cube, {0, 0, 0}, 5);
  XCTAssertEqual(batches.size(), 2u);
  XCTAssertEqual(batches[0].items.front().lod, 0u);
  XCTAssertEqual(batches[1].items.front().lod, 1u);
  XCTAssertEqual(batches[1].items.front().vertex_count, 6u);

  runtime.updateStreaming(cube, 200, 120);
  XCTAssertTrue(runtime.sections()[0].resident);
  Frustum elsewhere = cube;
  for (auto& plane : elsewhere.planes) plane.distance = -1000;
  runtime.updateStreaming(elsewhere, 322, 120);
  XCTAssertFalse(runtime.sections()[0].resident);
}

- (void)testMovingFrustumKeepsSceneSelectionBelowFrameBudget {
  using namespace asterix::scene;
  Runtime runtime;
  runtime.addSection({"section", {{-500, -20, -20}, {500, 20, 20}}, true, true, 0});
  for (int index = 0; index < 381; ++index) {
    Node node;
    node.id = std::to_string(index);
    node.section_id = "section";
    const float x = static_cast<float>(index) * 2.5f - 475;
    node.world_bounds = {{x, -1, -1}, {x + 2, 1, 1}};
    node.material = static_cast<std::uint32_t>(index % 8);
    node.full_vertex_count = 300;
    runtime.addNode(std::move(node));
  }
  double worstMilliseconds = 0;
  for (int frame = 0; frame < 600; ++frame) {
    const float center = -450 + frame * 1.5f;
    const Frustum moving = {{{{1, 0, 0, 50 - center}, {-1, 0, 0, 50 + center},
                               {0, 1, 0, 20}, {0, -1, 0, 20},
                               {0, 0, 1, 20}, {0, 0, -1, 20}}}};
    const auto start = std::chrono::steady_clock::now();
    runtime.updateStreaming(moving, frame);
    const auto batches = runtime.buildBatches(moving, {center, 0, 0}, 35);
    XCTAssertFalse(batches.empty());
    const auto end = std::chrono::steady_clock::now();
    worstMilliseconds = std::max(
        worstMilliseconds,
        std::chrono::duration<double, std::milli>(end - start).count());
  }
  XCTAssertLessThan(worstMilliseconds, 16.0);
}

- (void)testVersionedBatchTransportPublishesSnapshotAndEvents {
  XCTAssertEqual(asterix_engine_abi_version(), ASTERIX_ENGINE_ABI_VERSION);

  AsterixEngineConfig config = {
      sizeof(AsterixEngineConfig), ASTERIX_ENGINE_ABI_VERSION, 4, 4};
  AsterixEngineHandle* handle = nullptr;
  XCTAssertEqual(asterix_engine_create(&config, &handle), ASTERIX_STATUS_OK);
  XCTAssertNotEqual(handle, nullptr);

  AsterixCommand commands[] = {
      {ASTERIX_COMMAND_ADD_SCORE, 0, 7},
      {ASTERIX_COMMAND_SET_PAUSED, 0, 1},
  };
  AsterixCommandBatch batch = {sizeof(AsterixCommandBatch),
                               ASTERIX_ENGINE_ABI_VERSION, commands, 2};
  XCTAssertEqual(asterix_engine_enqueue(handle, &batch), ASTERIX_STATUS_OK);

  AsterixUiSnapshot snapshot = {
      sizeof(AsterixUiSnapshot), ASTERIX_ENGINE_ABI_VERSION};
  for (int attempt = 0; attempt < 100; ++attempt) {
    XCTAssertEqual(asterix_engine_copy_ui_snapshot(handle, &snapshot),
                   ASTERIX_STATUS_OK);
    if (snapshot.generation == 2) break;
    usleep(1000);
  }
  XCTAssertEqual(snapshot.generation, 2u);
  XCTAssertEqual(snapshot.score, 7);
  XCTAssertEqual(snapshot.paused, 1u);

  AsterixEvent events[4]{};
  size_t event_count = 4;
  XCTAssertEqual(asterix_engine_drain_events(handle, events, &event_count),
                 ASTERIX_STATUS_OK);
  XCTAssertEqual(event_count, 2u);
  XCTAssertEqual(events[1].generation, 2u);

  asterix_engine_destroy(handle);
}

- (void)testRejectsIncompatibleAbiAndOversizedBatch {
  AsterixEngineConfig invalid = {sizeof(AsterixEngineConfig), 99, 2, 2};
  AsterixEngineHandle* handle = nullptr;
  XCTAssertEqual(asterix_engine_create(&invalid, &handle),
                 ASTERIX_STATUS_INCOMPATIBLE_ABI);
  XCTAssertEqual(handle, nullptr);

  AsterixEngineConfig config = {
      sizeof(AsterixEngineConfig), ASTERIX_ENGINE_ABI_VERSION, 2, 2};
  XCTAssertEqual(asterix_engine_create(&config, &handle), ASTERIX_STATUS_OK);
  AsterixCommand commands[3] = {
      {ASTERIX_COMMAND_ADD_SCORE, 0, 1},
      {ASTERIX_COMMAND_ADD_SCORE, 0, 2},
      {ASTERIX_COMMAND_ADD_SCORE, 0, 3},
  };
  AsterixCommandBatch batch = {sizeof(AsterixCommandBatch),
                               ASTERIX_ENGINE_ABI_VERSION, commands, 3};
  XCTAssertEqual(asterix_engine_enqueue(handle, &batch),
                 ASTERIX_STATUS_QUEUE_FULL);
  asterix_engine_destroy(handle);
}

@end
