#ifndef ASTERIX_ENEMY_RUNTIME_HPP
#define ASTERIX_ENEMY_RUNTIME_HPP

#include "asterix/collision_runtime.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>

namespace asterix::enemy {

using collision::Vec3;

enum class State : std::uint8_t { idle, pursuit, attack, stun, death, returning };
inline const char* stateName(State state) {
  switch (state) {
    case State::idle: return "idle";
    case State::pursuit: return "pursuit";
    case State::attack: return "attack";
    case State::stun: return "stun";
    case State::death: return "death";
    case State::returning: return "returning";
  }
  return "idle";
}

struct Config {
  float perception_radius = 8;
  float attack_range = 1.4f;
  float move_speed = 1.8f;
  float leash_radius = 10;
  float return_tolerance = .2f;
  float attack_duration = .65f;
  float attack_impact_seconds = .25f;
  float attack_cooldown = 1.2f;
  float stun_seconds = .4f;
  std::int32_t health = 3;
  std::int32_t attack_damage = 1;
};

struct Snapshot {
  State state = State::idle;
  collision::CapsuleState body{};
  Vec3 facing{1,0,0};
  std::int32_t health = 3;
  float state_seconds = 0;
  float cooldown_seconds = 0;
};

struct UpdateResult {
  const Snapshot* snapshot = nullptr;
  bool dealt_damage = false;
};

class Runtime {
 public:
  Runtime(collision::CapsuleController& controller,
          collision::CapsuleState body, Config config = {})
      : controller_(controller), config_(config), spawn_(body.position) {
    if (config.perception_radius <= 0 || config.attack_range <= 0 ||
        config.move_speed <= 0 || config.leash_radius <= config.attack_range ||
        config.return_tolerance < 0 || config.attack_duration <= 0 ||
        config.attack_impact_seconds < 0 ||
        config.attack_impact_seconds > config.attack_duration ||
        config.attack_cooldown < 0 || config.stun_seconds <= 0 ||
        config.health <= 0 || config.attack_damage <= 0) {
      throw std::invalid_argument("enemy configuration is invalid");
    }
    snapshot_.body=body;
    snapshot_.health=config.health;
  }

  const Snapshot& snapshot() const { return snapshot_; }
  std::int32_t attackDamage() const { return config_.attack_damage; }

  bool applyDamage(std::int32_t damage, Vec3 knockback = {}) {
    if (damage <= 0 || snapshot_.state == State::death) return false;
    snapshot_.health=std::max(0,snapshot_.health-damage);
    snapshot_.body.velocity=knockback;
    enter(snapshot_.health==0?State::death:State::stun);
    return true;
  }

  UpdateResult update(float dt, Vec3 target, bool target_alive = true) {
    if (!std::isfinite(dt) || dt <= 0 || !finite(target)) {
      throw std::invalid_argument("enemy update is invalid");
    }
    snapshot_.state_seconds+=dt;
    snapshot_.cooldown_seconds=std::max(0.0f,snapshot_.cooldown_seconds-dt);
    if(snapshot_.state==State::death)return {&snapshot_,false};

    const Vec3 to_target=horizontal(target-snapshot_.body.position);
    const float target_distance=collision::length(to_target);
    const float leash_distance=collision::length(horizontal(snapshot_.body.position-spawn_));
    bool dealt_damage=false;

    if(snapshot_.state==State::stun) {
      Vec3 knockback={snapshot_.body.velocity.x,0,snapshot_.body.velocity.z};
      snapshot_.body=controller_.move(snapshot_.body,knockback,dt,false);
      snapshot_.body.velocity.x*=std::exp(-8.0f*dt);
      snapshot_.body.velocity.z*=std::exp(-8.0f*dt);
      if(snapshot_.state_seconds<config_.stun_seconds)return {&snapshot_,false};
      enter(leash_distance>config_.leash_radius?State::returning:State::idle);
    }
    if(leash_distance>config_.leash_radius&&snapshot_.state!=State::returning)
      enter(State::returning);

    if(snapshot_.state==State::attack) {
      if(!impact_done_&&snapshot_.state_seconds>=config_.attack_impact_seconds) {
        impact_done_=true;
        dealt_damage=target_alive&&target_distance<=config_.attack_range;
      }
      snapshot_.body=controller_.move(snapshot_.body,{},dt,false);
      if(snapshot_.state_seconds<config_.attack_duration)return {&snapshot_,dealt_damage};
      snapshot_.cooldown_seconds=config_.attack_cooldown;
      enter(State::pursuit);
    }

    if(snapshot_.state==State::returning) {
      const Vec3 home=horizontal(spawn_-snapshot_.body.position);
      if(collision::length(home)<=config_.return_tolerance) {
        enter(State::idle);
        return {&snapshot_,dealt_damage};
      }
      move(home,dt);
      return {&snapshot_,dealt_damage};
    }

    if(!target_alive||target_distance>config_.perception_radius) {
      if(snapshot_.state!=State::idle)enter(State::returning);
      return {&snapshot_,dealt_damage};
    }
    if(target_distance<=config_.attack_range&&snapshot_.cooldown_seconds<=0) {
      if(target_distance>1e-5f)snapshot_.facing=collision::normalized(to_target);
      enter(State::attack);
      impact_done_=false;
      snapshot_.body=controller_.move(snapshot_.body,{},dt,false);
      return {&snapshot_,dealt_damage};
    }
    enterIfChanged(State::pursuit);
    move(to_target,dt);
    return {&snapshot_,dealt_damage};
  }

 private:
  static bool finite(Vec3 value) {
    return std::isfinite(value.x)&&std::isfinite(value.y)&&std::isfinite(value.z);
  }
  static Vec3 horizontal(Vec3 value) { value.y=0; return value; }
  void move(Vec3 direction,float dt) {
    if(collision::length(direction)>1e-5f)
      snapshot_.facing=collision::normalized(direction);
    snapshot_.body=controller_.move(
        snapshot_.body,snapshot_.facing*config_.move_speed,dt,false);
  }
  void enter(State state) {
    snapshot_.state=state; snapshot_.state_seconds=0;
  }
  void enterIfChanged(State state) {
    if(snapshot_.state!=state)enter(state);
  }

  collision::CapsuleController& controller_;
  Config config_;
  Vec3 spawn_{};
  Snapshot snapshot_{};
  bool impact_done_=false;
};

}  // namespace asterix::enemy
#endif
