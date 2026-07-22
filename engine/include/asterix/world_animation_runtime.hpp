#ifndef ASTERIX_WORLD_ANIMATION_RUNTIME_HPP
#define ASTERIX_WORLD_ANIMATION_RUNTIME_HPP

#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace asterix::world_animation {

struct Profile {
  std::string entry_action;
  std::unordered_map<std::string, std::string> event_actions;
};

struct Snapshot {
  std::string action;
  std::uint64_t last_event_sequence = 0;
};

// Actor-local world graph. Event sequence numbers are persistent and make
// delivery idempotent across fixed ticks. Restore applies the saved visual
// state directly: it never replays gameplay events or one-shot side effects.
class Runtime {
 public:
  void add(std::uint32_t id, Profile profile) {
    if (id == 0 || profile.entry_action.empty() ||
        profile.event_actions.empty() || instances_.contains(id)) {
      throw std::invalid_argument("world animation profile is invalid");
    }
    instances_.emplace(id, Instance{std::move(profile), {}, 0});
    instances_.at(id).action = instances_.at(id).profile.entry_action;
  }

  bool dispatch(std::uint32_t id, const std::string& event,
                std::uint64_t sequence) {
    auto it = instances_.find(id);
    if (it == instances_.end() || sequence == 0) return false;
    Instance& instance = it->second;
    if (sequence <= instance.last_event_sequence) return false;
    const auto action = instance.profile.event_actions.find(event);
    if (action == instance.profile.event_actions.end()) return false;
    instance.action = action->second;
    instance.last_event_sequence = sequence;
    return true;
  }

  std::optional<Snapshot> snapshot(std::uint32_t id) const {
    const auto it = instances_.find(id);
    if (it == instances_.end()) return std::nullopt;
    return Snapshot{it->second.action, it->second.last_event_sequence};
  }

  bool restore(std::uint32_t id, const Snapshot& snapshot) {
    auto it = instances_.find(id);
    if (it == instances_.end() || snapshot.action.empty()) return false;
    bool known = snapshot.action == it->second.profile.entry_action;
    for (const auto& [_, action] : it->second.profile.event_actions) {
      if (action == snapshot.action) known = true;
    }
    if (!known) return false;
    it->second.action = snapshot.action;
    it->second.last_event_sequence = snapshot.last_event_sequence;
    return true;
  }

 private:
  struct Instance {
    Profile profile;
    std::string action;
    std::uint64_t last_event_sequence;
  };
  std::unordered_map<std::uint32_t, Instance> instances_;
};

}  // namespace asterix::world_animation
#endif
