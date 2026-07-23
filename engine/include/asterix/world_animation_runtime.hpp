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

enum class Synchronization : std::uint8_t {
  object_state,
  material,
  particle,
};

struct Selector {
  std::string action;
  std::string variant;
  bool loop = false;
  std::optional<double> commit_phase;
  Synchronization synchronization = Synchronization::object_state;
};

struct Profile {
  std::string profile_id;
  std::string entry_state;
  std::unordered_map<std::string, Selector> states;
  std::unordered_map<std::string, std::vector<std::string>> event_states;
};

struct Snapshot {
  std::vector<std::string> states;
  std::uint64_t last_event_sequence = 0;
};

struct Output {
  std::uint32_t object_id = 0;
  std::string profile_id;
  std::vector<Selector> selectors;
  std::uint64_t event_sequence = 0;
};

// Object-local world graph. Persistent event sequence numbers make delivery
// idempotent across fixed ticks. An event may select multiple authored tracks
// (the kiosk transaction does); restore applies selectors without replaying
// object, material or particle side effects.
class Runtime {
 public:
  void add(std::uint32_t id, Profile profile) {
    if (id == 0 || profile.profile_id.empty() || profile.entry_state.empty() ||
        profile.states.empty() || profile.event_states.empty() ||
        !profile.states.contains(profile.entry_state) ||
        instances_.contains(id)) {
      throw std::invalid_argument("world animation profile is invalid");
    }
    for (const auto& [_, states] : profile.event_states) {
      if (states.empty()) {
        throw std::invalid_argument("world animation event is empty");
      }
      for (const auto& state : states) {
        if (!profile.states.contains(state)) {
          throw std::invalid_argument("world animation event is unbound");
        }
      }
    }
    const std::string entry = profile.entry_state;
    instances_.emplace(
        id, Instance{std::move(profile), std::vector<std::string>{entry}, 0});
  }

  bool dispatch(std::uint32_t id, const std::string& event,
                std::uint64_t sequence) {
    auto it = instances_.find(id);
    if (it == instances_.end() || sequence == 0) return false;
    Instance& instance = it->second;
    if (sequence <= instance.last_event_sequence) return false;
    const auto states = instance.profile.event_states.find(event);
    if (states == instance.profile.event_states.end()) return false;
    instance.states = states->second;
    instance.last_event_sequence = sequence;
    outputs_.push_back(
        Output{id, instance.profile.profile_id, selectors(instance), sequence});
    return true;
  }

  std::optional<Snapshot> snapshot(std::uint32_t id) const {
    const auto it = instances_.find(id);
    if (it == instances_.end()) return std::nullopt;
    return Snapshot{it->second.states, it->second.last_event_sequence};
  }

  bool restore(std::uint32_t id, const Snapshot& snapshot) {
    auto it = instances_.find(id);
    if (it == instances_.end() || snapshot.states.empty()) return false;
    for (const auto& state : snapshot.states) {
      if (!it->second.profile.states.contains(state)) return false;
    }
    it->second.states = snapshot.states;
    it->second.last_event_sequence = snapshot.last_event_sequence;
    std::erase_if(outputs_,
                  [id](const Output& output) { return output.object_id == id; });
    return true;
  }

  std::optional<Output> drain() {
    if (outputs_.empty()) return std::nullopt;
    auto result = std::move(outputs_.front());
    outputs_.erase(outputs_.begin());
    return result;
  }

 private:
  struct Instance {
    Profile profile;
    std::vector<std::string> states;
    std::uint64_t last_event_sequence;
  };

  static std::vector<Selector> selectors(const Instance& instance) {
    std::vector<Selector> result;
    result.reserve(instance.states.size());
    for (const auto& state : instance.states) {
      result.push_back(instance.profile.states.at(state));
    }
    return result;
  }

  std::unordered_map<std::uint32_t, Instance> instances_;
  std::vector<Output> outputs_;
};

}  // namespace asterix::world_animation
#endif
