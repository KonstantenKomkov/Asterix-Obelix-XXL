#ifndef ASTERIX_INTERACTIVE_RUNTIME_HPP
#define ASTERIX_INTERACTIVE_RUNTIME_HPP

#include "asterix/collision_runtime.hpp"

#include <algorithm>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <unordered_set>
#include <vector>

namespace asterix::interactive {

using collision::Vec3;

enum class EventType : std::uint8_t {
  trigger_entered, lever_activated, object_damaged, object_destroyed,
  reward_collected, checkpoint_activated, checkpoint_restored
};
enum class Hint : std::uint8_t { none, activate_lever, collect_reward, respawn };
inline const char* hintName(Hint hint) {
  switch(hint) {
    case Hint::none:return "";
    case Hint::activate_lever:return "activate_lever";
    case Hint::collect_reward:return "collect_reward";
    case Hint::respawn:return "respawn";
  }
  return "";
}
struct Event { EventType type; std::uint32_t id; std::int32_t value = 0; };
struct Trigger { std::uint32_t id; Vec3 center; Vec3 half_extent{1,1,1}; bool one_shot=true; bool fired=false; };
struct Lever { std::uint32_t id; Vec3 position; float radius=1.2f; bool activated=false; };
struct Destructible { std::uint32_t id; Vec3 position; std::int32_t health=2; std::int32_t maximum_health=2; bool destroyed=false; };
struct Reward { std::uint32_t id; Vec3 position; std::uint32_t source_object=0; std::int32_t value=1; bool available=true; bool collected=false; };
struct Checkpoint { std::uint32_t id; Vec3 position; float radius=1.0f; bool activated=false; };
struct Snapshot { std::int32_t rewards=0; std::uint32_t active_checkpoint=0; };
struct PersistentState {
  Snapshot snapshot{};
  std::vector<bool> triggers_fired;
  std::vector<bool> levers_activated;
  std::vector<std::int32_t> destructible_health;
  std::vector<bool> rewards_available;
  std::vector<bool> rewards_collected;
};

class Runtime {
 public:
  void addTrigger(Trigger value) { validateId(value.id); if(value.half_extent.x<=0||value.half_extent.y<=0||value.half_extent.z<=0)invalid(); triggers_.push_back(value); }
  void addLever(Lever value) { validateId(value.id); if(value.radius<=0)invalid(); levers_.push_back(value); }
  void addDestructible(Destructible value) {
    validateId(value.id); if(value.health<=0||value.maximum_health<value.health)invalid(); destructibles_.push_back(value);
  }
  void addReward(Reward value) {
    validateId(value.id); if(value.value<=0)invalid();
    if(value.source_object!=0)value.available=false;
    rewards_.push_back(value);
  }
  void addCheckpoint(Checkpoint value) { validateId(value.id); if(value.radius<=0)invalid(); checkpoints_.push_back(value); }

  const Snapshot& snapshot() const { return snapshot_; }
  const std::vector<Trigger>& triggers() const { return triggers_; }
  const std::vector<Lever>& levers() const { return levers_; }
  const std::vector<Destructible>& destructibles() const { return destructibles_; }
  const std::vector<Reward>& rewards() const { return rewards_; }
  const std::vector<Checkpoint>& checkpoints() const { return checkpoints_; }
  PersistentState persistentState() const {
    PersistentState state; state.snapshot=snapshot_;
    for(const auto& value:triggers_)state.triggers_fired.push_back(value.fired);
    for(const auto& value:levers_)state.levers_activated.push_back(value.activated);
    for(const auto& value:destructibles_)state.destructible_health.push_back(value.health);
    for(const auto& value:rewards_) {
      state.rewards_available.push_back(value.available);
      state.rewards_collected.push_back(value.collected);
    }
    return state;
  }
  bool restorePersistent(const PersistentState& state) {
    if(state.triggers_fired.size()!=triggers_.size()||
       state.levers_activated.size()!=levers_.size()||
       state.destructible_health.size()!=destructibles_.size()||
       state.rewards_available.size()!=rewards_.size()||
       state.rewards_collected.size()!=rewards_.size())return false;
    if(state.snapshot.rewards<0)return false;
    const auto checkpoint=std::find_if(checkpoints_.begin(),checkpoints_.end(),
        [&state](const auto& value){return value.id==state.snapshot.active_checkpoint;});
    if(checkpoint==checkpoints_.end())return false;
    for(std::size_t i=0;i<destructibles_.size();++i)
      if(state.destructible_health[i]<0||state.destructible_health[i]>destructibles_[i].maximum_health)return false;
    snapshot_=state.snapshot;
    for(std::size_t i=0;i<triggers_.size();++i)triggers_[i].fired=state.triggers_fired[i];
    for(std::size_t i=0;i<levers_.size();++i)levers_[i].activated=state.levers_activated[i];
    for(std::size_t i=0;i<destructibles_.size();++i) {
      destructibles_[i].health=state.destructible_health[i];
      destructibles_[i].destroyed=destructibles_[i].health==0;
    }
    for(std::size_t i=0;i<rewards_.size();++i) {
      rewards_[i].available=state.rewards_available[i]; rewards_[i].collected=state.rewards_collected[i];
    }
    for(auto& value:checkpoints_)value.activated=value.id==snapshot_.active_checkpoint;
    saved_=Saved{triggers_,levers_,destructibles_,rewards_,snapshot_};
    inside_triggers_.clear(); events_.clear(); return true;
  }
  Hint hint(Vec3 player,bool player_dead) const {
    if(player_dead&&snapshot_.active_checkpoint!=0)return Hint::respawn;
    for(const auto& lever:levers_)
      if(!lever.activated&&near(player,lever.position,lever.radius))return Hint::activate_lever;
    for(const auto& reward:rewards_)
      if(reward.available&&!reward.collected&&near(player,reward.position,.75f))return Hint::collect_reward;
    return Hint::none;
  }

  void update(Vec3 player, bool interact_edge) {
    for(auto& trigger:triggers_) {
      const bool inside=contains(trigger,player);
      if(inside&&!inside_triggers_.contains(trigger.id)&&(!trigger.one_shot||!trigger.fired)) {
        trigger.fired=true; events_.push_back({EventType::trigger_entered,trigger.id});
      }
      if(inside)inside_triggers_.insert(trigger.id); else inside_triggers_.erase(trigger.id);
    }
    if(interact_edge)for(auto& lever:levers_) if(!lever.activated&&near(player,lever.position,lever.radius)) {
      lever.activated=true; events_.push_back({EventType::lever_activated,lever.id}); break;
    }
    for(auto& reward:rewards_) if(reward.available&&!reward.collected&&near(player,reward.position,.75f)) {
      reward.collected=true; snapshot_.rewards+=reward.value;
      events_.push_back({EventType::reward_collected,reward.id,reward.value});
    }
    for(auto& checkpoint:checkpoints_) if(!checkpoint.activated&&near(player,checkpoint.position,checkpoint.radius)) {
      for(auto& value:checkpoints_)value.activated=false;
      checkpoint.activated=true; snapshot_.active_checkpoint=checkpoint.id;
      saved_=Saved{triggers_,levers_,destructibles_,rewards_,snapshot_};
      events_.push_back({EventType::checkpoint_activated,checkpoint.id});
    }
  }

  bool damage(std::uint32_t id,std::int32_t amount) {
    if(amount<=0)return false;
    auto it=std::find_if(destructibles_.begin(),destructibles_.end(),[id](const auto& v){return v.id==id;});
    if(it==destructibles_.end()||it->destroyed)return false;
    it->health=std::max(0,it->health-amount);
    events_.push_back({EventType::object_damaged,id,amount});
    if(it->health==0) {
      it->destroyed=true; events_.push_back({EventType::object_destroyed,id});
      for(auto& reward:rewards_)if(reward.source_object==id)reward.available=true;
    }
    return true;
  }

  std::optional<Vec3> restoreCheckpoint() {
    if(!saved_)return std::nullopt;
    triggers_=saved_->triggers; levers_=saved_->levers;
    destructibles_=saved_->destructibles; rewards_=saved_->rewards;
    snapshot_=saved_->snapshot; inside_triggers_.clear();
    const auto it=std::find_if(checkpoints_.begin(),checkpoints_.end(),[this](const auto& v){return v.id==snapshot_.active_checkpoint;});
    if(it==checkpoints_.end())return std::nullopt;
    events_.push_back({EventType::checkpoint_restored,it->id});
    return it->position;
  }
  std::vector<Event> drainEvents() { std::vector<Event> result; result.swap(events_); return result; }

 private:
  struct Saved { std::vector<Trigger> triggers; std::vector<Lever> levers; std::vector<Destructible> destructibles; std::vector<Reward> rewards; Snapshot snapshot; };
  static bool near(Vec3 a,Vec3 b,float radius) { auto d=a-b; return collision::dot(d,d)<=radius*radius; }
  static bool contains(const Trigger& t,Vec3 p) { auto d=p-t.center; return std::abs(d.x)<=t.half_extent.x&&std::abs(d.y)<=t.half_extent.y&&std::abs(d.z)<=t.half_extent.z; }
  void validateId(std::uint32_t id) const {
    if(id==0)invalid();
    for(const auto& v:triggers_)if(v.id==id)invalid(); for(const auto& v:levers_)if(v.id==id)invalid();
    for(const auto& v:destructibles_)if(v.id==id)invalid(); for(const auto& v:rewards_)if(v.id==id)invalid();
    for(const auto& v:checkpoints_)if(v.id==id)invalid();
  }
  [[noreturn]] static void invalid() { throw std::invalid_argument("interactive configuration is invalid"); }
  std::vector<Trigger> triggers_; std::vector<Lever> levers_; std::vector<Destructible> destructibles_;
  std::vector<Reward> rewards_; std::vector<Checkpoint> checkpoints_; Snapshot snapshot_{};
  std::optional<Saved> saved_; std::unordered_set<std::uint32_t> inside_triggers_; std::vector<Event> events_;
};

}  // namespace asterix::interactive
#endif
