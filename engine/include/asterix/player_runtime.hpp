#ifndef ASTERIX_PLAYER_RUNTIME_HPP
#define ASTERIX_PLAYER_RUNTIME_HPP

#include "asterix/collision_runtime.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>

namespace asterix::player {

enum class State : std::uint8_t { idle, run, jump, fall, attack, hurt, death };

inline const char* stateName(State state) {
  switch (state) {
    case State::idle: return "idle";
    case State::run: return "run";
    case State::jump: return "jump";
    case State::fall: return "fall";
    case State::attack: return "attack";
    case State::hurt: return "hurt";
    case State::death: return "death";
  }
  return "idle";
}

struct Config {
  float run_speed = 2.4f;
  float acceleration = 10.0f;
  float deceleration = 12.0f;
  float jump_velocity = 8.4f;
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

struct Snapshot {
  State state = State::idle;
  collision::CapsuleState body{};
  std::int32_t health = 3;
  float state_seconds = 0;
  float invulnerability_seconds = 0;
};

class Runtime {
 public:
  Runtime(collision::CapsuleController& controller,
          collision::CapsuleState body, Config config = {})
      : controller_(controller), config_(config) {
    if (config.run_speed <= 0 || config.acceleration <= 0 ||
        config.deceleration <= 0 || config.jump_velocity <= 0 ||
        config.attack_seconds <= 0 || config.hurt_seconds <= 0 ||
        config.invulnerability_seconds < 0 || config.maximum_health <= 0) {
      throw std::invalid_argument("player configuration is invalid");
    }
    snapshot_.body = body;
    snapshot_.health = config.maximum_health;
  }

  const Snapshot& snapshot() const { return snapshot_; }
  const Config& config() const { return config_; }

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
    snapshot_.invulnerability_seconds =
        std::max(0.0f, snapshot_.invulnerability_seconds - dt);

    const bool jump_edge = input.jump && !jump_was_pressed_;
    const bool attack_edge = input.attack && !attack_was_pressed_;
    jump_was_pressed_ = input.jump;
    attack_was_pressed_ = input.attack;

    if (snapshot_.state == State::death) return snapshot_;

    const float magnitude = std::sqrt(input.move_x * input.move_x +
                                      input.move_z * input.move_z);
    const float scale = magnitude > 1 ? 1 / magnitude : 1;
    const collision::Vec3 target = {
        input.move_x * scale * config_.run_speed, 0,
        input.move_z * scale * config_.run_speed};
    const float rate = magnitude > .01f ? config_.acceleration
                                        : config_.deceleration;
    horizontal_velocity_.x = approach(horizontal_velocity_.x, target.x, rate * dt);
    horizontal_velocity_.z = approach(horizontal_velocity_.z, target.z, rate * dt);

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
    if (jump_edge && snapshot_.body.grounded &&
        snapshot_.state != State::attack) {
      snapshot_.body.velocity.y = config_.jump_velocity;
      snapshot_.body.grounded = false;
      enter(State::jump);
    }

    snapshot_.body = controller_.move(snapshot_.body, horizontal_velocity_, dt);
    if (snapshot_.body.recovered_from_fall) {
      enter(State::fall);
    } else if (snapshot_.state == State::attack &&
               snapshot_.state_seconds < config_.attack_seconds) {
      // Keep the one-shot animation authoritative until its configured end.
    } else if (!snapshot_.body.grounded) {
      enterIfChanged(snapshot_.body.velocity.y > 0 ? State::jump : State::fall);
    } else if (std::sqrt(horizontal_velocity_.x * horizontal_velocity_.x +
                         horizontal_velocity_.z * horizontal_velocity_.z) > .05f) {
      enterIfChanged(State::run);
    } else {
      enterIfChanged(State::idle);
    }
    return snapshot_;
  }

 private:
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
};

}  // namespace asterix::player
#endif
