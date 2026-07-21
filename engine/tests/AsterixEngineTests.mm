#import <XCTest/XCTest.h>

#include "asterix/audio_runtime.hpp"

#include "asterix/engine.h"
#include "asterix/animation_runtime.hpp"
#include "asterix/collision_runtime.hpp"
#include "asterix/scene_runtime.hpp"
#include "asterix/simulation_runtime.hpp"
#include "asterix/player_runtime.hpp"
#include "asterix/camera_runtime.hpp"
#include "asterix/combat_runtime.hpp"
#include "asterix/enemy_runtime.hpp"
#include "asterix/interactive_runtime.hpp"
#include <chrono>
#include <unistd.h>

@interface AsterixEngineTests : XCTestCase
@end

@implementation AsterixEngineTests

- (void)testInteractivesTriggerLeverDestructionAndReward {
  using namespace asterix::interactive;
  Runtime runtime;
  runtime.addTrigger({1,{0,0,0},{1,1,1},true,false});
  runtime.addLever({2,{2,0,0},1});
  runtime.addDestructible({3,{3,0,0},2,2,false});
  runtime.addReward({4,{3,0,0},3,2});
  runtime.update({0,0,0},false);
  runtime.update({0,0,0},false);
  runtime.update({2,0,0},true);
  XCTAssertTrue(runtime.levers().front().activated);
  XCTAssertTrue(runtime.damage(3,1));
  XCTAssertFalse(runtime.destructibles().front().destroyed);
  XCTAssertTrue(runtime.damage(3,1));
  XCTAssertTrue(runtime.destructibles().front().destroyed);
  runtime.update({3,0,0},false);
  XCTAssertEqual(runtime.snapshot().rewards,2);
  XCTAssertTrue(runtime.rewards().front().collected);
  int triggerEvents=0;
  for(const auto& event:runtime.drainEvents())
    if(event.type==EventType::trigger_entered)++triggerEvents;
  XCTAssertEqual(triggerEvents,1);
}

- (void)testCheckpointRestoresWorldAndRespawnsPlayer {
  using namespace asterix;
  interactive::Runtime worldState;
  worldState.addLever({1,{0,0,0},1});
  worldState.addDestructible({2,{1,0,0},2,2,false});
  worldState.addReward({3,{1,0,0},2,1});
  worldState.addCheckpoint({4,{0,.9f,0},1});
  worldState.update({0,.9f,0},false);
  XCTAssertEqual(worldState.snapshot().active_checkpoint,4u);
  worldState.update({0,0,0},true);
  worldState.damage(2,2);
  worldState.update({1,0,0},false);
  XCTAssertTrue(worldState.levers().front().activated);
  XCTAssertTrue(worldState.destructibles().front().destroyed);
  XCTAssertEqual(worldState.snapshot().rewards,1);
  const auto respawn=worldState.restoreCheckpoint();
  XCTAssertTrue(respawn.has_value());
  XCTAssertFalse(worldState.levers().front().activated);
  XCTAssertFalse(worldState.destructibles().front().destroyed);
  XCTAssertEqual(worldState.destructibles().front().health,2);
  XCTAssertFalse(worldState.rewards().front().available);
  XCTAssertEqual(worldState.snapshot().rewards,0);

  collision::World collisionWorld({{{-2,0,-2},{2,0,-2},{-2,0,2},1},
                                   {{2,0,-2},{2,0,2},{-2,0,2},1}});
  collision::CapsuleController controller(collisionWorld);
  collision::CapsuleState body; body.position={1,.9f,0}; body.checkpoint=body.position;
  player::Runtime player(controller,body);
  player.applyDamage(3);
  player.respawn(*respawn);
  XCTAssertEqual(player.snapshot().state,player::State::idle);
  XCTAssertEqual(player.snapshot().health,player.config().maximum_health);
  XCTAssertEqualWithAccuracy(player.snapshot().body.position.x,0,.001);
}

- (void)testPersistentWorldStateValidatesAndRestoresCheckpointBaseline {
  using namespace asterix::interactive;
  Runtime runtime;
  runtime.addTrigger({1,{0,0,0},{1,1,1},true,false});
  runtime.addLever({2,{0,0,0},1});
  runtime.addDestructible({3,{1,0,0},2,2,false});
  runtime.addReward({4,{1,0,0},3,1});
  runtime.addCheckpoint({5,{0,0,0},1});
  runtime.update({0,0,0},true);
  runtime.damage(3,1);
  auto saved=runtime.persistentState();
  runtime.damage(3,1);
  runtime.update({1,0,0},false);
  XCTAssertTrue(runtime.restorePersistent(saved));
  XCTAssertTrue(runtime.levers().front().activated);
  XCTAssertEqual(runtime.destructibles().front().health,1);
  XCTAssertEqual(runtime.snapshot().rewards,0);
  runtime.damage(3,1);
  XCTAssertTrue(runtime.destructibles().front().destroyed);
  XCTAssertTrue(runtime.restoreCheckpoint().has_value());
  XCTAssertEqual(runtime.destructibles().front().health,1);
  saved.destructible_health.front()=99;
  XCTAssertFalse(runtime.restorePersistent(saved));
}

- (void)testEnemyPerceivesPursuesAttacksAndCanDefeatPlayer {
  using namespace asterix;
  collision::World world({{{-20,0,-20},{20,0,-20},{-20,0,20},1},
                          {{20,0,-20},{20,0,20},{-20,0,20},1}});
  collision::CapsuleConfig capsuleConfig;
  collision::CapsuleController playerController(world,capsuleConfig);
  collision::CapsuleController enemyController(world,capsuleConfig);
  collision::CapsuleState playerBody;
  playerBody.position={0,.9f,0}; playerBody.checkpoint=playerBody.position;
  playerBody.grounded=true;
  player::Runtime player(playerController,playerBody);
  collision::CapsuleState enemyBody;
  enemyBody.position={4,.9f,0}; enemyBody.checkpoint=enemyBody.position;
  enemyBody.grounded=true;
  enemy::Runtime enemy(enemyController,enemyBody);
  bool sawPursuit=false,sawAttack=false;
  for(int tick=0;tick<600&&player.snapshot().health>0;++tick) {
    auto result=enemy.update(1.0f/60.0f,player.snapshot().body.position,
                             player.snapshot().health>0);
    sawPursuit|=result.snapshot->state==enemy::State::pursuit;
    sawAttack|=result.snapshot->state==enemy::State::attack;
    if(result.dealt_damage)player.applyDamage(enemy.attackDamage());
    player.update(1.0f/60.0f,{});
  }
  XCTAssertTrue(sawPursuit);
  XCTAssertTrue(sawAttack);
  XCTAssertEqual(player.snapshot().state,player::State::death);
}

- (void)testEnemyStunDeathAndReturnToLeashOrigin {
  using namespace asterix;
  collision::World world({{{-30,0,-30},{30,0,-30},{-30,0,30},1},
                          {{30,0,-30},{30,0,30},{-30,0,30},1}});
  collision::CapsuleConfig capsuleConfig;
  collision::CapsuleController controller(world,capsuleConfig);
  collision::CapsuleState body;
  body.position={0,.9f,0}; body.checkpoint=body.position; body.grounded=true;
  enemy::Config config; config.leash_radius=3;
  enemy::Runtime enemy(controller,body,config);
  for(int tick=0;tick<180;++tick)enemy.update(1.0f/60.0f,{8,.9f,0});
  XCTAssertTrue(enemy.snapshot().state==enemy::State::returning||
                enemy.snapshot().state==enemy::State::idle);
  for(int tick=0;tick<240&&enemy.snapshot().state!=enemy::State::idle;++tick)
    enemy.update(1.0f/60.0f,{20,.9f,0});
  XCTAssertLessThan(collision::length(enemy.snapshot().body.position-
                                      collision::Vec3{0,.9f,0}),.35f);
  XCTAssertTrue(enemy.applyDamage(1,{2,0,0}));
  XCTAssertEqual(enemy.snapshot().state,enemy::State::stun);
  XCTAssertTrue(enemy.applyDamage(2));
  XCTAssertEqual(enemy.snapshot().state,enemy::State::death);
  const auto deathPosition=enemy.snapshot().body.position;
  for(int tick=0;tick<120;++tick)enemy.update(1.0f/60.0f,{0,.9f,0});
  XCTAssertEqualWithAccuracy(enemy.snapshot().body.position.x,deathPosition.x,.001);
}

- (void)testPlayerComboCanDefeatEnemy {
  using namespace asterix;
  collision::World world({{{-10,0,-10},{10,0,-10},{-10,0,10},1},
                          {{10,0,-10},{10,0,10},{-10,0,10},1}});
  collision::CapsuleConfig capsuleConfig;
  collision::CapsuleController controller(world,capsuleConfig);
  collision::CapsuleState body;
  body.position={1,.9f,0}; body.checkpoint=body.position; body.grounded=true;
  enemy::Runtime enemy(controller,body);
  combat::Config combatConfig;
  combatConfig.invulnerability_seconds=.05f;
  combat::Runtime combat(combatConfig);
  combat::Fighter playerFighter;
  playerFighter.id=1; playerFighter.team=1; playerFighter.position={0,.9f,0};
  combat.addFighter(playerFighter);
  combat::Fighter enemyFighter;
  enemyFighter.id=2; enemyFighter.team=2; enemyFighter.position=body.position;
  combat.addFighter(enemyFighter);
  XCTAssertTrue(combat.pressAttack(1));
  bool sawStun=false;
  for(int tick=0;tick<180&&enemy.snapshot().state!=enemy::State::death;++tick) {
    if(combat.attack().input_window)combat.pressAttack(1);
    combat.setTransform(1,{0,.9f,0},{1,0,0});
    combat.setTransform(2,enemy.snapshot().body.position,enemy.snapshot().facing);
    combat.update(1.0f/60.0f);
    for(const auto& event:combat.drainEvents()) {
      if(event.type==combat::EventType::hit&&event.target==2) {
        enemy.applyDamage(event.damage);
        sawStun|=enemy.snapshot().state==enemy::State::stun;
      }
    }
  }
  XCTAssertTrue(sawStun);
  XCTAssertEqual(enemy.snapshot().state,enemy::State::death);
  XCTAssertEqual(enemy.snapshot().health,0);
}

- (void)testCombatHitboxDamagesOnceAppliesKnockbackAndInvulnerability {
  using namespace asterix::combat;
  Runtime combat;
  Fighter player; player.id=1; player.team=1; player.position={0,0,0};
  player.facing={0,0,1};
  Fighter enemy; enemy.id=2; enemy.team=2; enemy.position={0,0,1};
  combat.addFighter(player); combat.addFighter(enemy);
  combat.setTransform(1,{0,0,0},{0,0,0});
  XCTAssertTrue(combat.pressAttack(1));
  XCTAssertFalse(combat.pressAttack(1));
  for(int tick=0;tick<20;++tick)combat.update(1.0f/60.0f);
  XCTAssertEqual(combat.fighters()[1].health,2);
  XCTAssertGreaterThan(combat.fighters()[1].knockback_velocity.z,0);
  XCTAssertGreaterThan(combat.fighters()[1].invulnerability_seconds,0);
  auto events=combat.drainEvents();
  XCTAssertEqual(std::count_if(events.begin(),events.end(),[](const Event& event){
    return event.type==EventType::hit;
  }),1);
  for(int tick=0;tick<20;++tick)combat.update(1.0f/60.0f);
  XCTAssertEqual(combat.fighters()[1].health,2);
}

- (void)testCombatQueuesAndCompletesThreeStageCombo {
  using namespace asterix::combat;
  Config config; config.invulnerability_seconds=.05f;
  Runtime combat(config);
  Fighter player; player.id=1; player.team=1;
  Fighter enemy; enemy.id=2; enemy.team=2; enemy.position={1,0,0}; enemy.health=5;
  combat.addFighter(player); combat.addFighter(enemy);
  XCTAssertTrue(combat.pressAttack(1));
  for(int tick=0;tick<20;++tick)combat.update(1.0f/60.0f);
  XCTAssertTrue(combat.pressAttack(1));
  for(int tick=0;tick<33;++tick)combat.update(1.0f/60.0f);
  XCTAssertEqual(combat.attack().stage,1u);
  XCTAssertTrue(combat.pressAttack(1));
  for(int tick=0;tick<33;++tick)combat.update(1.0f/60.0f);
  XCTAssertEqual(combat.attack().stage,2u);
  for(int tick=0;tick<40;++tick)combat.update(1.0f/60.0f);
  XCTAssertFalse(combat.attack().active);
  XCTAssertEqual(combat.fighters()[1].health,1);
}

- (void)testCameraTargetZonesFollowPlayerWithoutLosingTarget {
  using namespace asterix;
  collision::World empty({});
  camera::Runtime camera;
  auto initial=camera.update({0,1,0},empty,1.0f/60.0f);
  XCTAssertEqualWithAccuracy(initial.position.z,10,.001);
  auto inside=camera.update({.5f,1.25f,.5f},empty,1.0f/60.0f);
  XCTAssertEqualWithAccuracy(inside.target.x,0,.001);
  XCTAssertEqualWithAccuracy(inside.target.y,1,.001);
  for(int tick=0;tick<120;++tick)camera.update({4,2,6},empty,1.0f/60.0f);
  const auto followed=camera.snapshot();
  XCTAssertEqualWithAccuracy(followed.target.x,3.25,.001);
  XCTAssertEqualWithAccuracy(followed.target.y,1.5,.001);
  XCTAssertEqualWithAccuracy(followed.target.z,5.25,.001);
  XCTAssertLessThan(collision::length(
      followed.target-collision::Vec3{4,2,6}),1.3f);
}

- (void)testCameraCollisionAvoidanceAndZoneFov {
  using namespace asterix;
  collision::World world({{{-5,-5,5},{5,-5,5},{-5,8,5},7},
                          {{5,-5,5},{5,8,5},{-5,8,5},7}});
  camera::Parameters zoneParameters; zoneParameters.distance=8;
  zoneParameters.field_of_view_degrees=55;
  camera::Zone zone{{-2,-2,-2},{2,3,2},zoneParameters};
  camera::Runtime camera({}, {zone});
  for(int tick=0;tick<120;++tick)camera.update({0,1,0},world,1.0f/60.0f);
  const auto snapshot=camera.snapshot();
  XCTAssertEqual(snapshot.active_zone,0);
  XCTAssertEqualWithAccuracy(snapshot.field_of_view_degrees,55,.001);
  XCTAssertTrue(snapshot.collision_limited);
  XCTAssertLessThan(snapshot.position.z,5);
  XCTAssertGreaterThan(snapshot.position.z,0);
}

- (void)testPlayerTransitionsIdleRunJumpFallAndLand {
  using namespace asterix;
  collision::World world({{{-20,0,-20},{20,0,-20},{-20,0,20},1},
                          {{20,0,-20},{20,0,20},{-20,0,20},1}});
  collision::CapsuleConfig capsuleConfig;
  collision::CapsuleController controller(world, capsuleConfig);
  collision::CapsuleState body;
  body.position={0,capsuleConfig.half_height+capsuleConfig.radius,0};
  body.checkpoint=body.position; body.grounded=true; body.ground_object_id=1;
  player::Runtime player(controller,body);
  player::Input input; input.move_x=1;
  for(int tick=0;tick<30;++tick) player.update(1.0f/60.0f,input);
  XCTAssertEqual(player.snapshot().state,player::State::run);
  XCTAssertGreaterThan(player.snapshot().body.position.x,.5f);
  input.jump=true; player.update(1.0f/60.0f,input);
  XCTAssertEqual(player.snapshot().state,player::State::jump);
  input.jump=false;
  bool sawFall=false;
  for(int tick=0;tick<120;++tick) {
    player.update(1.0f/60.0f,input);
    sawFall |= player.snapshot().state==player::State::fall;
    if(sawFall&&player.snapshot().body.grounded)break;
  }
  XCTAssertTrue(sawFall);
  XCTAssertEqual(player.snapshot().state,player::State::run);
}

- (void)testPlayerAttackHurtInvulnerabilityAndDeathTransitions {
  using namespace asterix;
  collision::World world({{{-5,0,-5},{5,0,-5},{-5,0,5},1},
                          {{5,0,-5},{5,0,5},{-5,0,5},1}});
  collision::CapsuleConfig capsuleConfig;
  collision::CapsuleController controller(world,capsuleConfig);
  collision::CapsuleState body;
  body.position={0,capsuleConfig.half_height+capsuleConfig.radius,0};
  body.checkpoint=body.position; body.grounded=true;
  player::Runtime player(controller,body);
  player::Input input; input.attack=true;
  player.update(1.0f/60.0f,input);
  XCTAssertEqual(player.snapshot().state,player::State::attack);
  input.attack=false;
  for(int tick=0;tick<40;++tick)player.update(1.0f/60.0f,input);
  XCTAssertEqual(player.snapshot().state,player::State::idle);
  XCTAssertTrue(player.applyDamage(1));
  XCTAssertEqual(player.snapshot().state,player::State::hurt);
  XCTAssertFalse(player.applyDamage(1));
  for(int tick=0;tick<30;++tick)player.update(1.0f/60.0f,input);
  XCTAssertTrue(player.applyDamage(2));
  XCTAssertEqual(player.snapshot().health,0);
  XCTAssertEqual(player.snapshot().state,player::State::death);
  for(int tick=0;tick<60;++tick)player.update(1.0f/60.0f,{1,0,true,true});
  XCTAssertEqual(player.snapshot().state,player::State::death);
}

- (void)testCapsuleTraversesFloorSlopeAndStepWithoutCrossingWall {
  using namespace asterix::collision;
  std::vector<Triangle> triangles = {
      {{-5,0,-3},{2,0,-3},{-5,0,3},1}, {{2,0,-3},{2,0,3},{-5,0,3},1},
      {{2,0,-3},{5,.6f,-3},{2,0,3},2}, {{5,.6f,-3},{5,.6f,3},{2,0,3},2},
      {{5,.85f,-3},{8,.85f,-3},{5,.85f,3},3}, {{8,.85f,-3},{8,.85f,3},{5,.85f,3},3},
      {{8,-1,-3},{8,3,-3},{8,-1,3},4}, {{8,3,-3},{8,3,3},{8,-1,3},4},
  };
  World world(std::move(triangles));
  CapsuleConfig config;
  config.step_height=.3f;
  CapsuleController controller(world,config);
  CapsuleState state;
  state.position={0,config.half_height+config.radius,0};
  state.checkpoint=state.position;
  state.grounded=true;
  state.ground_object_id=1;
  for(int tick=0;tick<360;++tick)
    state=controller.move(state,{3,0,0},1.0f/60.0f);
  XCTAssertTrue(state.grounded);
  XCTAssertGreaterThan(state.position.x,5.0f);
  XCTAssertLessThanOrEqual(state.position.x,8.0f-config.radius+0.02f);
  XCTAssertEqualWithAccuracy(state.position.y,.85f+config.half_height+config.radius,.02f);
}

- (void)testCapsuleFollowsDynamicGroundAndRecoversFromFall {
  using namespace asterix::collision;
  World world({{{-2,0,-2},{2,0,-2},{-2,0,2},9,true,{1,0,0}},
               {{2,0,-2},{2,0,2},{-2,0,2},9,true,{1,0,0}}});
  CapsuleConfig config;
  config.kill_y=-2;
  CapsuleController controller(world,config);
  CapsuleState state;
  state.position={0,config.half_height+config.radius,0};
  state.checkpoint={4,config.half_height+config.radius,0};
  state.grounded=true;
  state.ground_object_id=9;
  state=controller.move(state,{0,0,0},.1f);
  XCTAssertEqualWithAccuracy(state.position.x,.1f,.001f);
  for(int tick=0;tick<9;++tick) state=controller.move(state,{0,0,0},.1f);
  XCTAssertTrue(state.grounded);
  XCTAssertEqualWithAccuracy(state.position.x,1,.001f);
  state.position.y=-3;
  state=controller.move(state,{0,0,0},1.0f/60.0f);
  XCTAssertTrue(state.recovered_from_fall);
  XCTAssertEqualWithAccuracy(state.position.x,4,.001f);
  XCTAssertEqualWithAccuracy(state.velocity.y,0,.001f);
}

- (void)testSafeSpawnUsesWalkableSurfaceNearestSectorOrigin {
  using namespace asterix::collision;
  const std::vector<Triangle> triangles = {
      {{0,5,0},{0,5,1},{1,5,0},1},
      {{-4,2,-4},{4,2,-4},{-4,2,4},2},
      {{-.5f,3,-.5f},{.5f,3,-.5f},{-.5f,3,.5f},4},
      {{10,-10,-10},{10,10,-10},{10,-10,10},3},
  };
  const auto spawn=safeSpawnPoint(triangles);
  XCTAssertTrue(spawn.has_value());
  XCTAssertEqualWithAccuracy(spawn->x,-1.0f/6.0f,.001f);
  XCTAssertEqualWithAccuracy(spawn->y,3.9f,.001f);
  XCTAssertEqualWithAccuracy(spawn->z,-1.0f/6.0f,.001f);
}

- (void)testFixedTimestepMatchesAtThirtySixtyAndOneTwentyHertz {
  using asterix::simulation::FixedTimestep;
  auto scenario = [](double renderRate) {
    FixedTimestep clock;
    double previous = 0, current = 0;
    const int frames = static_cast<int>(renderRate * 10);
    for (int frame = 0; frame < frames; ++frame) {
      clock.advance(1.0 / renderRate, [&](double step) {
        previous = current;
        current += 7.5 * step;
      });
    }
    const double rendered = asterix::simulation::interpolate(
        previous, current, clock.interpolationAlpha());
    return std::array<double, 3>{current, rendered,
                                 static_cast<double>(clock.tick())};
  };
  const auto at30 = scenario(30);
  const auto at60 = scenario(60);
  const auto at120 = scenario(120);
  XCTAssertEqual(at30[2], 600);
  XCTAssertEqual(at30[2], at60[2]);
  XCTAssertEqual(at60[2], at120[2]);
  XCTAssertEqualWithAccuracy(at30[0], at120[0], 0.000001);
  XCTAssertEqualWithAccuracy(at30[1], at120[1], 0.000001);
}

- (void)testFixedTimestepInterpolatesAndBoundsCatchUp {
  using namespace asterix::simulation;
  FixedTimestep clock(0.1, 3);
  double previous = 0, current = 0;
  clock.advance(0.25, [&](double step) {
    previous = current;
    current += step * 10;
  });
  XCTAssertEqual(clock.tick(), 2u);
  XCTAssertEqualWithAccuracy(clock.interpolationAlpha(), .5, 0.000001);
  XCTAssertEqualWithAccuracy(interpolate(previous, current,
                                         clock.interpolationAlpha()),
                             1.5, 0.000001);
  clock.advance(1.0, [&](double) {});
  XCTAssertEqual(clock.tick(), 5u);
  XCTAssertGreaterThan(clock.droppedSeconds(), .6);
  XCTAssertLessThan(clock.interpolationAlpha(), 1.0);
}

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

- (void)testAudioRoutingVolumesAndBeds {
  asterix::audio::Runtime audio(2);
  audio.setVolumes(2, -.5f);
  audio.startBeds();
  audio.startBeds();
  const auto events = audio.drainEvents();
  XCTAssertEqual(events.size(), 2u);
  XCTAssertEqual(events[0].bus, asterix::audio::Bus::music);
  XCTAssertTrue(events[0].looping);
  XCTAssertFalse(events[0].spatial);
  XCTAssertEqual(events[1].bus, asterix::audio::Bus::ambience);
  XCTAssertTrue(events[1].spatial);
  XCTAssertEqualWithAccuracy(audio.snapshot().music_volume, 1, .001);
  XCTAssertEqualWithAccuracy(audio.snapshot().effects_volume, 0, .001);
}

- (void)testAudioChannelPrioritiesAndExpiry {
  asterix::audio::Runtime audio(2);
  XCTAssertTrue(audio.play(asterix::audio::Cue::footstep));
  XCTAssertTrue(audio.play(asterix::audio::Cue::attack));
  XCTAssertFalse(audio.play(asterix::audio::Cue::footstep));
  XCTAssertTrue(audio.play(asterix::audio::Cue::death));
  XCTAssertEqual(audio.snapshot().active_effects, 2u);
  XCTAssertEqual(audio.snapshot().dropped_effects, 1u);
  auto events = audio.drainEvents();
  XCTAssertEqual(events.size(), 3u);
  XCTAssertEqual(events.back().cue, asterix::audio::Cue::death);
  XCTAssertEqual(events.back().channel, 0u);
  XCTAssertFalse(events.back().spatial);
  audio.update(1);
  XCTAssertEqual(audio.snapshot().active_effects, 0u);
}

@end
