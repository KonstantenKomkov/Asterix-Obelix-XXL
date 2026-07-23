#ifndef ASTERIX_SCRIPTED_CHARACTER_RUNTIME_HPP
#define ASTERIX_SCRIPTED_CHARACTER_RUNTIME_HPP

#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>

namespace asterix::scripted_character {

enum class State : std::uint8_t { restored, playing, interrupted, complete };

struct Definition {
  std::string profile_id;
  std::string script_event;
  std::string restore_action;
};

struct Snapshot {
  State state = State::restored;
  std::uint64_t event_sequence = 0;
};

struct Output {
  std::string instance;
  std::string profile_id;
  std::string action;
  std::uint64_t event_sequence = 0;
};

class Runtime {
 public:
  void add(std::string instance, Definition definition) {
    if (instance.empty() || definition.profile_id.empty() ||
        definition.script_event.empty() || definition.restore_action.empty() ||
        instances_.contains(instance) || events_.contains(definition.script_event))
      throw std::invalid_argument("invalid scripted character instance");
    events_.emplace(definition.script_event, instance);
    instances_.emplace(std::move(instance),
                       Entry{std::move(definition), Snapshot{}});
  }

  bool start(const std::string& script_event, std::uint64_t sequence) {
    const auto event = events_.find(script_event);
    if (event == events_.end()) return false;
    Entry& entry = instances_.at(event->second);
    if (sequence <= entry.snapshot.event_sequence ||
        entry.snapshot.state == State::playing)
      return false;
    entry.snapshot = {State::playing, sequence};
    output_ = Output{event->second, entry.definition.profile_id,
                     "script_event", sequence};
    return true;
  }

  bool complete(const std::string& instance) {
    return transition(instance, State::playing, State::complete);
  }

  bool interrupt(const std::string& instance) {
    return transition(instance, State::playing, State::interrupted);
  }

  bool restore(const std::string& instance, const Snapshot& snapshot) {
    const auto found = instances_.find(instance);
    if (found == instances_.end()) return false;
    found->second.snapshot = snapshot;
    output_.reset();
    return true;
  }

  std::optional<Snapshot> snapshot(const std::string& instance) const {
    const auto found = instances_.find(instance);
    if (found == instances_.end()) return std::nullopt;
    return found->second.snapshot;
  }

  std::optional<Output> drain() {
    auto result = std::move(output_);
    output_.reset();
    return result;
  }

 private:
  struct Entry {
    Definition definition;
    Snapshot snapshot;
  };

  bool transition(const std::string& instance, State from, State to) {
    const auto found = instances_.find(instance);
    if (found == instances_.end() || found->second.snapshot.state != from)
      return false;
    found->second.snapshot.state = to;
    output_ = Output{instance, found->second.definition.profile_id,
                     found->second.definition.restore_action,
                     found->second.snapshot.event_sequence};
    return true;
  }

  std::unordered_map<std::string, Entry> instances_;
  std::unordered_map<std::string, std::string> events_;
  std::optional<Output> output_;
};

}  // namespace asterix::scripted_character
#endif
