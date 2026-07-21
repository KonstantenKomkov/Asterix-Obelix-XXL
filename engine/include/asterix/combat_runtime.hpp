#ifndef ASTERIX_COMBAT_RUNTIME_HPP
#define ASTERIX_COMBAT_RUNTIME_HPP

#include "asterix/collision_runtime.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <unordered_set>
#include <vector>

namespace asterix::combat {

using collision::Vec3;

struct Box {
  Vec3 center{};
  Vec3 half_extent{.4f, .8f, .4f};
};

struct Fighter {
  std::uint32_t id = 0;
  std::uint32_t team = 0;
  Vec3 position{};
  Vec3 facing{1, 0, 0};
  Vec3 knockback_velocity{};
  Box hurtbox{};
  std::int32_t health = 3;
  float invulnerability_seconds = 0;
};

struct AttackStage {
  float duration = .55f;
  float hit_start = .14f;
  float hit_end = .28f;
  float input_start = .28f;
  float input_end = .50f;
  float hitbox_forward = .85f;
  Vec3 hitbox_half_extent{.65f, .65f, .55f};
  std::int32_t damage = 1;
  float knockback = 3;
};

struct Config {
  std::vector<AttackStage> combo = {
      {},
      {.55f,.13f,.29f,.27f,.50f,.9f,{.7f,.65f,.6f},1,3.5f},
      {.55f,.16f,.34f,.30f,.50f,1.0f,{.8f,.7f,.65f},2,5.0f},
  };
  float invulnerability_seconds = .4f;
  float knockback_damping = 8;
  float recovery_seconds = .1f;
};

enum class EventType : std::uint8_t { attack_started, combo_queued, hit, defeated };
struct Event {
  EventType type = EventType::attack_started;
  std::uint32_t source = 0;
  std::uint32_t target = 0;
  std::size_t stage = 0;
  std::int32_t damage = 0;
};

struct AttackSnapshot {
  bool active = false;
  bool input_window = false;
  bool hit_window = false;
  std::size_t stage = 0;
  float stage_seconds = 0;
};

class Runtime {
 public:
  explicit Runtime(Config config = {}) : config_(std::move(config)) {
    if (config_.combo.empty() || config_.invulnerability_seconds < 0 ||
        config_.knockback_damping < 0 || config_.recovery_seconds < 0) {
      throw std::invalid_argument("combat configuration is invalid");
    }
    for (const AttackStage& stage : config_.combo) validate(stage);
  }

  void addFighter(Fighter fighter) {
    if (fighter.id == 0 || fighter.health <= 0 ||
        find(fighter.id) != fighters_.end()) {
      throw std::invalid_argument("combat fighter is invalid or duplicated");
    }
    fighter.hurtbox.center = fighter.position + fighter.hurtbox.center;
    fighters_.push_back(fighter);
  }

  void setTransform(std::uint32_t id, Vec3 position, Vec3 facing) {
    Fighter& fighter = require(id);
    const Vec3 local_center = fighter.hurtbox.center - fighter.position;
    fighter.position = position;
    fighter.hurtbox.center = position + local_center;
    facing.y = 0;
    fighter.facing = collision::length(facing) > 1e-5f
        ? collision::normalized(facing) : fighter.facing;
  }

  bool pressAttack(std::uint32_t id) {
    Fighter& fighter = require(id);
    if (fighter.health <= 0) return false;
    if (!attack_.active) {
      attack_ = {true, false, false, 0, 0};
      attacker_id_ = id;
      queued_ = false;
      hit_targets_.clear();
      events_.push_back({EventType::attack_started,id,0,0,0});
      return true;
    }
    if (attacker_id_ != id || !inInputWindow() || queued_ ||
        attack_.stage + 1 >= config_.combo.size()) return false;
    queued_ = true;
    events_.push_back({EventType::combo_queued,id,0,attack_.stage + 1,0});
    return true;
  }

  void update(float dt) {
    if (!std::isfinite(dt) || dt <= 0) {
      throw std::invalid_argument("combat dt is invalid");
    }
    for (Fighter& fighter : fighters_) {
      fighter.invulnerability_seconds =
          std::max(0.0f, fighter.invulnerability_seconds - dt);
      fighter.position = fighter.position + fighter.knockback_velocity * dt;
      fighter.hurtbox.center = fighter.hurtbox.center + fighter.knockback_velocity * dt;
      fighter.knockback_velocity = fighter.knockback_velocity *
          std::exp(-config_.knockback_damping * dt);
    }
    if (!attack_.active) return;
    attack_.stage_seconds += dt;
    const AttackStage& stage = config_.combo[attack_.stage];
    attack_.input_window = inInputWindow();
    attack_.hit_window = attack_.stage_seconds >= stage.hit_start &&
                         attack_.stage_seconds <= stage.hit_end;
    if (attack_.hit_window) resolveHits(stage);
    if (attack_.stage_seconds < stage.duration) return;
    if (queued_ && attack_.stage + 1 < config_.combo.size()) {
      ++attack_.stage;
      attack_.stage_seconds = 0;
      attack_.input_window = false;
      attack_.hit_window = false;
      queued_ = false;
      hit_targets_.clear();
      events_.push_back({EventType::attack_started,attacker_id_,0,attack_.stage,0});
    } else if (attack_.stage_seconds >=
               stage.duration + config_.recovery_seconds) {
      attack_ = {};
      attacker_id_ = 0;
      queued_ = false;
      hit_targets_.clear();
    }
  }

  const std::vector<Fighter>& fighters() const { return fighters_; }
  const AttackSnapshot& attack() const { return attack_; }
  std::vector<Event> drainEvents() {
    std::vector<Event> result;
    result.swap(events_);
    return result;
  }

 private:
  static void validate(const AttackStage& stage) {
    if (stage.duration <= 0 || stage.hit_start < 0 ||
        stage.hit_end < stage.hit_start || stage.hit_end > stage.duration ||
        stage.input_start < 0 || stage.input_end < stage.input_start ||
        stage.input_end > stage.duration || stage.hitbox_forward < 0 ||
        stage.hitbox_half_extent.x <= 0 || stage.hitbox_half_extent.y <= 0 ||
        stage.hitbox_half_extent.z <= 0 || stage.damage <= 0 ||
        stage.knockback < 0) {
      throw std::invalid_argument("combat attack stage is invalid");
    }
  }
  std::vector<Fighter>::iterator find(std::uint32_t id) {
    return std::find_if(fighters_.begin(), fighters_.end(),
                        [id](const Fighter& value) { return value.id == id; });
  }
  Fighter& require(std::uint32_t id) {
    const auto fighter = find(id);
    if (fighter == fighters_.end()) throw std::out_of_range("combat fighter missing");
    return *fighter;
  }
  bool inInputWindow() const {
    if (!attack_.active) return false;
    const AttackStage& stage = config_.combo[attack_.stage];
    return attack_.stage_seconds >= stage.input_start &&
           attack_.stage_seconds <= stage.input_end;
  }
  static bool overlaps(const Box& a, const Box& b) {
    return std::abs(a.center.x-b.center.x) <= a.half_extent.x+b.half_extent.x &&
           std::abs(a.center.y-b.center.y) <= a.half_extent.y+b.half_extent.y &&
           std::abs(a.center.z-b.center.z) <= a.half_extent.z+b.half_extent.z;
  }
  void resolveHits(const AttackStage& stage) {
    Fighter& attacker = require(attacker_id_);
    Box hitbox;
    hitbox.center = attacker.position + attacker.facing * stage.hitbox_forward;
    hitbox.half_extent = stage.hitbox_half_extent;
    for (Fighter& target : fighters_) {
      if (target.id == attacker.id || target.team == attacker.team ||
          target.health <= 0 || target.invulnerability_seconds > 0 ||
          hit_targets_.contains(target.id) || !overlaps(hitbox,target.hurtbox)) continue;
      hit_targets_.insert(target.id);
      target.health=std::max(0,target.health-stage.damage);
      target.invulnerability_seconds=config_.invulnerability_seconds;
      target.knockback_velocity=attacker.facing*stage.knockback;
      events_.push_back({EventType::hit,attacker.id,target.id,attack_.stage,stage.damage});
      if(target.health==0)
        events_.push_back({EventType::defeated,attacker.id,target.id,attack_.stage,stage.damage});
    }
  }

  Config config_;
  std::vector<Fighter> fighters_;
  AttackSnapshot attack_{};
  std::uint32_t attacker_id_ = 0;
  bool queued_ = false;
  std::unordered_set<std::uint32_t> hit_targets_;
  std::vector<Event> events_;
};

}  // namespace asterix::combat
#endif
