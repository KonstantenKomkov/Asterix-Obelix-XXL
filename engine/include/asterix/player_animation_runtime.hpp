#ifndef ASTERIX_PLAYER_ANIMATION_RUNTIME_HPP
#define ASTERIX_PLAYER_ANIMATION_RUNTIME_HPP

#include "asterix/animation_controller.hpp"
#include "asterix/player_runtime.hpp"

#include <string>
#include <unordered_set>
#include <utility>

namespace asterix::player_animation {

// Resolves gameplay facts into authored selectors. PlayerRuntime remains the
// owner of movement/combat facts; AnimationController remains the sole owner
// of the selected binding, cursor, completion and transition snapshot.
class Runtime {
 public:
  explicit Runtime(animation_controller::Graph graph)
      : controller_(std::move(graph)) {
    previous_grounded_ = true;
  }

  const animation_controller::Snapshot& snapshot() const {
    return controller_.snapshot();
  }

  // Every selector in the 90-state authored graph is exposed through this
  // graph-only entry point. Callers never select a clip or dictionary slot.
  bool select(const std::string& binding,
              animation_controller::Request request =
                  animation_controller::Request::interrupt) {
    return controller_.request("select:" + binding, request);
  }

  const animation_controller::Snapshot& advance(
      double fixed_dt, const player::Snapshot& gameplay, bool paused = false) {
    if (paused) return controller_.advance(fixed_dt, true);

    const bool landed = !previous_grounded_ && gameplay.body.grounded;
    if (landed &&
        controller_.snapshot().completion ==
            animation_controller::Completion::landing) {
      controller_.complete(animation_controller::Completion::landing);
    }

    const char* requested = nullptr;
    switch (gameplay.state) {
      case player::State::death: requested = "death"; break;
      case player::State::hurt: requested = "hurt"; break;
      case player::State::attack: requested = "attack"; break;
      case player::State::double_jump: requested = "double_jump"; break;
      case player::State::jump:
        // A velocity apex is not an authored animation guard. Keep the
        // current single-jump clip until a proven interrupt (double jump,
        // damage) or landing.
        if (gameplay.body.grounded ||
            controller_.snapshot().state != "binding:jump") {
          requested = "jump";
        }
        break;
      case player::State::fall:
        // PlayerRuntime uses fall as a physics fact at the apex. That fact
        // alone must not replace an authored single/double-jump clip.
        if (controller_.snapshot().state != "binding:jump" &&
            controller_.snapshot().state != "binding:double_jump") {
          requested = "fall";
        }
        break;
      case player::State::run:
        if (gameplay.body.grounded) requested = "run";
        break;
      case player::State::idle:
        if (gameplay.body.grounded) requested = "idle";
        break;
    }
    if (landed)
      requested = gameplay.horizontal_speed > .05f ? "run" : "idle";
    if (requested != nullptr) select(requested);

    previous_grounded_ = gameplay.body.grounded;
    return controller_.advance(fixed_dt);
  }

 private:
  animation_controller::AnimationController controller_;
  bool previous_grounded_ = true;
};

}  // namespace asterix::player_animation
#endif
