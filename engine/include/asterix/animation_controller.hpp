#ifndef ASTERIX_ANIMATION_CONTROLLER_HPP
#define ASTERIX_ANIMATION_CONTROLLER_HPP

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace asterix::animation_controller {

enum class Completion : std::uint8_t {
  loop,
  authored_clip_end,
  landing,
  terminal,
};

enum class Operation : std::uint8_t { start, change };
enum class Request : std::uint8_t { interrupt, queue };

struct Binding {
  std::int32_t dictionary = 0;
  std::int32_t slot = 0;
  std::string asset;

  bool operator==(const Binding& other) const {
    return dictionary == other.dictionary && slot == other.slot &&
           asset == other.asset;
  }
};

struct State {
  std::string id;
  Binding binding;
  double duration_seconds = 0;
  double playback_rate = 1;
  double initial_phase = 0;
};

struct Transition {
  std::string id;
  std::string from_state = "*";
  std::string to_state;
  Completion completion = Completion::loop;
  Operation operation = Operation::change;
  double blend_seconds = 0;
};

struct Graph {
  std::string profile;
  std::string entry_state;
  std::vector<State> states;
  std::vector<Transition> transitions;
};

struct Blend {
  std::string from_state;
  Binding from_binding;
  double from_cursor_seconds = 0;
  double elapsed_seconds = 0;
  double duration_seconds = 0;
};

struct Snapshot {
  std::string profile;
  std::string state;
  std::string transition;
  Binding binding;
  Completion completion = Completion::loop;
  double cursor_seconds = 0;
  double phase = 0;
  bool completed = false;
  std::uint64_t activation = 0;
  std::optional<Blend> blend;
  std::optional<std::string> queued_transition;
};

// Owns authored animation playback state. It deliberately accepts graph
// transition IDs instead of gameplay enums or semantic clip names: gameplay
// facts and guards are resolved by the graph-facing orchestration layer.
class AnimationController {
 public:
  explicit AnimationController(Graph graph) : graph_(std::move(graph)) {
    validateAndIndex();
    activateState(graph_.entry_state, nullptr, 0);
  }

  const Snapshot& snapshot() const { return snapshot_; }

  // Requests are explicit about interrupt/queue policy. Re-selecting the
  // active state is a no-op, so a held fact cannot replay a one-shot.
  bool request(const std::string& transition_id, Request request) {
    const Transition& transition = findTransition(transition_id);
    if (transition.from_state != "*" &&
        transition.from_state != snapshot_.state) {
      return false;
    }
    if (transition.to_state == snapshot_.state) return false;
    if (request == Request::queue && !snapshot_.completed) {
      snapshot_.queued_transition = transition.id;
      return true;
    }
    activateTransition(transition);
    return true;
  }

  // Advances only on a simulation tick. A paused tick cannot alter the
  // cursor, blend, completion, queue, or activation serial.
  const Snapshot& advance(double fixed_dt, bool paused = false) {
    if (!std::isfinite(fixed_dt) || fixed_dt <= 0)
      throw std::invalid_argument("animation fixed dt is invalid");
    if (paused || snapshot_.completed) return snapshot_;

    const State& state = findState(snapshot_.state);
    const double scaled = fixed_dt * state.playback_rate;
    if (snapshot_.blend) {
      snapshot_.blend->elapsed_seconds =
          std::min(snapshot_.blend->duration_seconds,
                   snapshot_.blend->elapsed_seconds + fixed_dt);
      if (snapshot_.blend->elapsed_seconds >=
          snapshot_.blend->duration_seconds) {
        snapshot_.blend.reset();
      }
    }

    snapshot_.cursor_seconds += scaled;
    const Completion completion = active_completion_;
    if (completion == Completion::loop) {
      snapshot_.cursor_seconds =
          std::fmod(snapshot_.cursor_seconds, state.duration_seconds);
      snapshot_.phase = snapshot_.cursor_seconds / state.duration_seconds;
      return snapshot_;
    }
    if (snapshot_.cursor_seconds >= state.duration_seconds) {
      snapshot_.cursor_seconds = state.duration_seconds;
      snapshot_.phase = 1;
      if (completion == Completion::authored_clip_end ||
          completion == Completion::terminal) {
        finish();
      }
    } else {
      snapshot_.phase = snapshot_.cursor_seconds / state.duration_seconds;
    }
    return snapshot_;
  }

  // Non-duration authored boundaries (for example landing) are reported as
  // facts by gameplay. They never make the controller infer gameplay state.
  bool complete(Completion signal) {
    if (snapshot_.completed || signal != active_completion_ ||
        signal == Completion::loop ||
        signal == Completion::authored_clip_end) {
      return false;
    }
    finish();
    return true;
  }

  // Restore is transactional and emits no activation: the saved activation
  // serial is restored verbatim and queued work remains queued.
  bool restore(const Snapshot& saved) {
    if (!validSnapshot(saved)) return false;
    snapshot_ = saved;
    active_completion_ = saved.completion;
    return true;
  }

 private:
  Graph graph_;
  std::unordered_map<std::string, std::size_t> states_;
  std::unordered_map<std::string, std::size_t> transitions_;
  Snapshot snapshot_;
  Completion active_completion_ = Completion::loop;

  static bool finiteNonNegative(double value) {
    return std::isfinite(value) && value >= 0;
  }

  void validateAndIndex() {
    if (graph_.profile.empty() || graph_.entry_state.empty() ||
        graph_.states.empty() || graph_.transitions.empty()) {
      throw std::invalid_argument("animation graph is incomplete");
    }
    for (std::size_t index = 0; index < graph_.states.size(); ++index) {
      const State& state = graph_.states[index];
      if (state.id.empty() || state.binding.dictionary < 0 ||
          state.binding.slot < 0 || state.binding.asset.empty() ||
          !std::isfinite(state.duration_seconds) ||
          state.duration_seconds <= 0 ||
          !std::isfinite(state.playback_rate) || state.playback_rate <= 0 ||
          !std::isfinite(state.initial_phase) || state.initial_phase < 0 ||
          state.initial_phase > 1 ||
          !states_.emplace(state.id, index).second) {
        throw std::invalid_argument("animation graph state is invalid");
      }
    }
    if (states_.find(graph_.entry_state) == states_.end())
      throw std::invalid_argument("animation graph entry is unknown");
    for (std::size_t index = 0; index < graph_.transitions.size(); ++index) {
      const Transition& transition = graph_.transitions[index];
      if (transition.id.empty() ||
          states_.find(transition.to_state) == states_.end() ||
          (transition.from_state != "*" &&
           states_.find(transition.from_state) == states_.end()) ||
          !finiteNonNegative(transition.blend_seconds) ||
          !transitions_.emplace(transition.id, index).second) {
        throw std::invalid_argument("animation graph transition is invalid");
      }
    }
    for (const State& state : graph_.states) {
      std::size_t selectors = 0;
      for (const Transition& transition : graph_.transitions)
        if (transition.to_state == state.id) ++selectors;
      if (selectors != 1)
        throw std::invalid_argument(
            "animation graph state selector is missing or ambiguous");
    }
  }

  const State& findState(const std::string& id) const {
    const auto found = states_.find(id);
    if (found == states_.end()) throw std::out_of_range("animation state is unknown");
    return graph_.states[found->second];
  }

  const Transition& findTransition(const std::string& id) const {
    const auto found = transitions_.find(id);
    if (found == transitions_.end())
      throw std::out_of_range("animation transition is unknown");
    return graph_.transitions[found->second];
  }

  const Transition* transitionForState(const std::string& state) const {
    for (const Transition& transition : graph_.transitions) {
      if (transition.to_state == state) return &transition;
    }
    return nullptr;
  }

  void activateState(const std::string& id, const Blend* blend,
                     double blend_seconds) {
    const State& state = findState(id);
    const Transition* selector = transitionForState(id);
    snapshot_.profile = graph_.profile;
    snapshot_.state = state.id;
    snapshot_.transition = selector == nullptr ? std::string{} : selector->id;
    snapshot_.binding = state.binding;
    snapshot_.completion =
        selector == nullptr ? Completion::loop : selector->completion;
    snapshot_.cursor_seconds = state.initial_phase * state.duration_seconds;
    snapshot_.phase = state.initial_phase;
    snapshot_.completed = false;
    ++snapshot_.activation;
    snapshot_.queued_transition.reset();
    snapshot_.blend.reset();
    if (blend != nullptr && blend_seconds > 0) {
      snapshot_.blend = *blend;
      snapshot_.blend->duration_seconds = blend_seconds;
      snapshot_.blend->elapsed_seconds = 0;
    }
    active_completion_ = snapshot_.completion;
  }

  void activateTransition(const Transition& transition) {
    Blend from{snapshot_.state, snapshot_.binding, snapshot_.cursor_seconds};
    activateState(transition.to_state, &from, transition.blend_seconds);
    snapshot_.transition = transition.id;
    snapshot_.completion = transition.completion;
    active_completion_ = transition.completion;
  }

  void finish() {
    snapshot_.completed = true;
    if (!snapshot_.queued_transition) return;
    const std::string queued = *snapshot_.queued_transition;
    snapshot_.queued_transition.reset();
    const Transition& transition = findTransition(queued);
    if (transition.from_state == "*" ||
        transition.from_state == snapshot_.state) {
      activateTransition(transition);
    }
  }

  bool validSnapshot(const Snapshot& saved) const {
    if (saved.profile != graph_.profile || saved.activation == 0 ||
        !finiteNonNegative(saved.cursor_seconds) ||
        !std::isfinite(saved.phase) || saved.phase < 0 || saved.phase > 1)
      return false;
    const auto state = states_.find(saved.state);
    if (state == states_.end()) return false;
    const auto transition = transitions_.find(saved.transition);
    if (transition == transitions_.end() ||
        graph_.transitions[transition->second].to_state != saved.state ||
        graph_.transitions[transition->second].completion != saved.completion)
      return false;
    const State& definition = graph_.states[state->second];
    if (!(saved.binding == definition.binding) ||
        saved.cursor_seconds > definition.duration_seconds + 1e-9)
      return false;
    const double expected_phase =
        saved.cursor_seconds / definition.duration_seconds;
    if (std::abs(saved.phase - expected_phase) > 1e-9 ||
        (saved.completion == Completion::loop && saved.completed))
      return false;
    if (saved.queued_transition) {
      const auto queued = transitions_.find(*saved.queued_transition);
      if (queued == transitions_.end()) return false;
      const std::string& from = graph_.transitions[queued->second].from_state;
      if (from != "*" && from != saved.state) return false;
    }
    if (saved.blend) {
      const auto from = states_.find(saved.blend->from_state);
      if (from == states_.end() ||
          !(saved.blend->from_binding ==
            graph_.states[from->second].binding) ||
          !finiteNonNegative(saved.blend->from_cursor_seconds) ||
          saved.blend->from_cursor_seconds >
              graph_.states[from->second].duration_seconds + 1e-9 ||
          !finiteNonNegative(saved.blend->elapsed_seconds) ||
          !finiteNonNegative(saved.blend->duration_seconds) ||
          saved.blend->duration_seconds <= 0 ||
          saved.blend->elapsed_seconds > saved.blend->duration_seconds)
        return false;
    }
    return true;
  }
};

}  // namespace asterix::animation_controller
#endif
