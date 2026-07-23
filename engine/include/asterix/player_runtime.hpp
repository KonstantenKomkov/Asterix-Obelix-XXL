#ifndef ASTERIX_PLAYER_RUNTIME_HPP
#define ASTERIX_PLAYER_RUNTIME_HPP

#include "asterix/collision_runtime.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>

namespace asterix::player {

enum class State : std::uint8_t {
  idle, run, jump, double_jump, fall, attack, hurt, death
};

enum class Gait : std::uint8_t { idle, walk, run };
enum class LocomotionMode : std::uint8_t { gameplay, scripted_walk };

inline const char* stateName(State state) {
  switch (state) {
    case State::idle: return "idle";
    case State::run: return "run";
    case State::jump: return "jump";
    case State::double_jump: return "double_jump";
    case State::fall: return "fall";
    case State::attack: return "attack";
    case State::hurt: return "hurt";
    case State::death: return "death";
  }
  return "idle";
}

struct Config {
  // Gameplay locomotion is a run, not the slower scripted traversal gait.
  // 4 H/s keeps the authored run readable at the scale of the imported map.
  float world_units_per_height = 1.8f;
  float run_speed = 7.2f;
  float scripted_walk_speed = 1.8f;
  float acceleration = 18.0f;
  float deceleration = 43.2f;
  float run_animation_rate = 1.65f;
  float jump_velocity = 8.4f;
  float jump_control_seconds = 0.2f;
  float jump_release_deceleration = 28.0f;
  float attack_seconds = 0.55f;
  float hurt_seconds = 0.4f;
  float invulnerability_seconds = 0.4f;
  std::int32_t maximum_health = 3;
};

struct Input {
  float move_x = 0;
  float move_z = 0;
  bool jump = false;
  bool attack = false;
};

inline collision::Vec3 canonicalMovementVector(const Input& input) {
  // Gaul map space advances towards -Z. Keep the action convention
  // (forward is positive) at the input boundary and convert it exactly once.
  return {input.move_x, 0, -input.move_z};
}

inline collision::Vec3 facingVector(float facing_radians) {
  return {std::sin(facing_radians), 0, -std::cos(facing_radians)};
}

inline float authoredNegativeZYaw(float facing_radians) {
  constexpr float pi = 3.14159265358979323846f;
  return pi - facing_radians;
}

inline collision::Vec3 authoredNegativeZForward(float facing_radians) {
  const float yaw = authoredNegativeZYaw(facing_radians);
  return {std::sin(yaw), 0, std::cos(yaw)};
}

struct Snapshot {
  State state = State::idle;
  Gait gait = Gait::idle;
  LocomotionMode locomotion_mode = LocomotionMode::gameplay;
  collision::CapsuleState body{};
  std::int32_t health = 3;
  float state_seconds = 0;
  float invulnerability_seconds = 0;
  float horizontal_speed = 0;
  float idle_animation_seconds = 0;
  float locomotion_seconds = 0;
  float locomotion_blend = 0;
  float facing_radians = 0;
};

class Runtime {
 public:
  Runtime(collision::CapsuleController& controller,
          collision::CapsuleState body, Config config = {})
      : controller_(controller), config_(config) {
    if (config.world_units_per_height <= 0 || config.run_speed <= 0 ||
        config.scripted_walk_speed <= 0 ||
        config.scripted_walk_speed >= config.run_speed ||
        config.acceleration <= 0 ||
        config.deceleration <= 0 || config.jump_velocity <= 0 ||
        config.run_animation_rate <= 0 ||
        config.jump_control_seconds <= 0 ||
        config.jump_release_deceleration <= 0 ||
        config.attack_seconds <= 0 || config.hurt_seconds <= 0 ||
        config.invulnerability_seconds < 0 || config.maximum_health <= 0) {
      throw std::invalid_argument("player configuration is invalid");
    }
    snapshot_.body = body;
    snapshot_.health = config.maximum_health;
    air_jump_available_ = body.grounded;
  }

  const Snapshot& snapshot() const { return snapshot_; }
  const Config& config() const { return config_; }

  void setLocomotionMode(LocomotionMode mode) {
    snapshot_.locomotion_mode = mode;
    if (mode == LocomotionMode::gameplay) snapshot_.gait = Gait::idle;
  }

  void setCheckpoint(collision::Vec3 position) { snapshot_.body.checkpoint=position; }
  void resolveInteractivePosition(collision::Vec3 position) {
    if(!finite(position))throw std::invalid_argument("interactive position is invalid");
    snapshot_.body.position=position;
  }
  void respawn(collision::Vec3 position) {
    snapshot_.body.position=position; snapshot_.body.checkpoint=position;
    snapshot_.body.velocity={}; snapshot_.body.grounded=false;
    snapshot_.health=config_.maximum_health; snapshot_.invulnerability_seconds=0;
    horizontal_velocity_={}; jump_was_pressed_=false; attack_was_pressed_=false;
    air_jump_available_=false; jump_control_active_=false;
    jump_cut_active_=false; jump_control_elapsed_=0;
    snapshot_.horizontal_speed=0; snapshot_.idle_animation_seconds=0;
    snapshot_.locomotion_seconds=0;
    snapshot_.locomotion_blend=0;
    snapshot_.gait=Gait::idle;
    snapshot_.locomotion_mode=LocomotionMode::gameplay;
    enter(State::idle);
  }
  bool restore(collision::Vec3 position,collision::Vec3 checkpoint,
               std::int32_t health) {
    if(health<0||health>config_.maximum_health||!finite(position)||!finite(checkpoint))return false;
    snapshot_.body.position=position; snapshot_.body.checkpoint=checkpoint;
    snapshot_.body.velocity={}; snapshot_.body.grounded=false;
    snapshot_.health=health; snapshot_.invulnerability_seconds=0;
    horizontal_velocity_={}; jump_was_pressed_=false; attack_was_pressed_=false;
    air_jump_available_=false; jump_control_active_=false;
    jump_cut_active_=false; jump_control_elapsed_=0;
    snapshot_.horizontal_speed=0; snapshot_.idle_animation_seconds=0;
    snapshot_.locomotion_seconds=0;
    snapshot_.locomotion_blend=0;
    snapshot_.gait=Gait::idle;
    snapshot_.locomotion_mode=LocomotionMode::gameplay;
    enter(health==0?State::death:State::idle); return true;
  }

  void restartAttack() {
    if (snapshot_.state != State::death && snapshot_.state != State::hurt) {
      enter(State::attack);
    }
  }

  bool applyDamage(std::int32_t amount) {
    if (amount <= 0 || snapshot_.state == State::death ||
        snapshot_.invulnerability_seconds > 0) return false;
    snapshot_.health = std::max(0, snapshot_.health - amount);
    enter(snapshot_.health == 0 ? State::death : State::hurt);
    snapshot_.invulnerability_seconds = config_.invulnerability_seconds;
    return true;
  }

  const Snapshot& update(float dt, const Input& input) {
    if (!std::isfinite(dt) || dt <= 0) {
      throw std::invalid_argument("player dt is invalid");
    }
    snapshot_.state_seconds += dt;
    snapshot_.idle_animation_seconds += dt;
    snapshot_.invulnerability_seconds =
        std::max(0.0f, snapshot_.invulnerability_seconds - dt);

    const bool jump_edge = input.jump && !jump_was_pressed_;
    const bool jump_release = !input.jump && jump_was_pressed_;
    const bool attack_edge = input.attack && !attack_was_pressed_;
    jump_was_pressed_ = input.jump;
    attack_was_pressed_ = input.attack;

    if (snapshot_.state == State::death) return snapshot_;

    const collision::Vec3 canonicalMovement = canonicalMovementVector(input);
    const float magnitude = collision::length(canonicalMovement);
    const float scale = magnitude > 1 ? 1 / magnitude : 1;
    const bool gameplay =
        snapshot_.locomotion_mode == LocomotionMode::gameplay;
    const float movementSpeed = gameplay ? config_.run_speed
                                         : config_.scripted_walk_speed;
    const collision::Vec3 target =
        canonicalMovement * (scale * movementSpeed);
    if (gameplay && magnitude > .01f) {
      // The original enters gameplay locomotion at its authored run speed.
      // Acceleration-based gait inference made every launch look like a walk.
      horizontal_velocity_ = target;
    } else {
      const float rate = magnitude > .01f ? config_.acceleration
                                          : config_.deceleration;
      horizontal_velocity_.x = approach(horizontal_velocity_.x, target.x, rate * dt);
      horizontal_velocity_.z = approach(horizontal_velocity_.z, target.z, rate * dt);
    }

    if (snapshot_.state == State::hurt) {
      horizontal_velocity_ = {};
      if (snapshot_.state_seconds < config_.hurt_seconds) {
        snapshot_.body = controller_.move(snapshot_.body, {}, dt);
        return snapshot_;
      }
    }

    if (snapshot_.state == State::attack &&
        snapshot_.state_seconds < config_.attack_seconds) {
      snapshot_.body = controller_.move(snapshot_.body, {}, dt);
      return snapshot_;
    }

    if (attack_edge) enter(State::attack);
    if (jump_edge && snapshot_.state != State::attack &&
        (snapshot_.body.grounded || air_jump_available_)) {
      const bool airJump = !snapshot_.body.grounded;
      if (airJump) air_jump_available_ = false;
      snapshot_.body.velocity.y = config_.jump_velocity;
      snapshot_.body.grounded = false;
      jump_control_active_ = true;
      jump_cut_active_ = false;
      jump_control_elapsed_ = 0;
      enter(airJump ? State::double_jump : State::jump);
    }

    if (jump_release && jump_control_active_ &&
        snapshot_.body.velocity.y > 0) {
      jump_control_active_ = false;
      jump_cut_active_ = true;
    }
    if (jump_control_active_) {
      jump_control_elapsed_ += dt;
      if (jump_control_elapsed_ >= config_.jump_control_seconds) {
        jump_control_active_ = false;
      }
    }
    if (jump_cut_active_ && snapshot_.body.velocity.y > 0) {
      snapshot_.body.velocity.y = std::max(
          0.0f, snapshot_.body.velocity.y -
                    config_.jump_release_deceleration * dt);
    } else if (snapshot_.body.velocity.y <= 0) {
      jump_cut_active_ = false;
    }

    const collision::Vec3 previousPosition = snapshot_.body.position;
    snapshot_.body = controller_.move(snapshot_.body, horizontal_velocity_, dt);
    const float movedX = snapshot_.body.position.x - previousPosition.x;
    const float movedZ = snapshot_.body.position.z - previousPosition.z;
    snapshot_.horizontal_speed = std::sqrt(movedX * movedX + movedZ * movedZ) / dt;
    if (snapshot_.horizontal_speed > .01f) {
      snapshot_.facing_radians = std::atan2(movedX, -movedZ);
      snapshot_.locomotion_seconds +=
          dt * snapshot_.horizontal_speed / config_.run_speed *
          config_.run_animation_rate;
    }
    if (!snapshot_.body.grounded || snapshot_.horizontal_speed <= .05f) {
      snapshot_.gait = Gait::idle;
    } else {
      snapshot_.gait = gameplay ? Gait::run : Gait::walk;
    }
    const float locomotionTarget = snapshot_.body.grounded &&
            snapshot_.horizontal_speed > .05f
        ? 1.0f : 0.0f;
    snapshot_.locomotion_blend = approach(
        snapshot_.locomotion_blend, locomotionTarget, dt / .12f);
    if (snapshot_.body.grounded) {
      air_jump_available_ = true;
      jump_control_active_ = false;
      jump_cut_active_ = false;
    }
    if (snapshot_.body.recovered_from_fall) {
      enter(State::fall);
    } else if (snapshot_.state == State::attack &&
               snapshot_.state_seconds < config_.attack_seconds) {
      // Keep the one-shot animation authoritative until its configured end.
    } else if (!snapshot_.body.grounded) {
      if (snapshot_.body.velocity.y > 0 &&
          snapshot_.state == State::double_jump) {
        // Keep the authored somersault authoritative for the second ascent.
      } else {
        enterIfChanged(snapshot_.body.velocity.y > 0 ? State::jump
                                                     : State::fall);
      }
    } else if (snapshot_.horizontal_speed > .05f) {
      enterIfChanged(State::run);
    } else {
      enterIfChanged(State::idle);
    }
    return snapshot_;
  }

 private:
  static bool finite(collision::Vec3 value) {
    return std::isfinite(value.x)&&std::isfinite(value.y)&&std::isfinite(value.z);
  }
  static float approach(float value, float target, float delta) {
    if (value < target) return std::min(value + delta, target);
    return std::max(value - delta, target);
  }
  void enter(State state) { snapshot_.state = state; snapshot_.state_seconds = 0; }
  void enterIfChanged(State state) { if (snapshot_.state != state) enter(state); }

  collision::CapsuleController& controller_;
  Config config_;
  Snapshot snapshot_{};
  collision::Vec3 horizontal_velocity_{};
  bool jump_was_pressed_ = false;
  bool attack_was_pressed_ = false;
  bool air_jump_available_ = false;
  bool jump_control_active_ = false;
  bool jump_cut_active_ = false;
  float jump_control_elapsed_ = 0;
};

}  // namespace asterix::player
#endif
