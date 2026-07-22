#pragma once

#include <cmath>
#include <stdexcept>

namespace asterix::water_animation {

struct Profile { float u_speed=0, v_speed=0, phase=0; };
struct Snapshot { double simulation_seconds=0; };
struct Offset { float u=0, v=0; };

class Runtime {
 public:
  explicit Runtime(Profile profile) : profile_(profile) {
    if (!std::isfinite(profile.u_speed) || !std::isfinite(profile.v_speed) ||
        !std::isfinite(profile.phase))
      throw std::invalid_argument("water UV profile is invalid");
  }

  void advance(double elapsed, bool paused=false) {
    if (!std::isfinite(elapsed) || elapsed < 0)
      throw std::invalid_argument("water elapsed time is invalid");
    if (!paused) seconds_ += elapsed;
  }
  Snapshot snapshot() const { return {seconds_}; }
  bool restore(Snapshot value) {
    if (!std::isfinite(value.simulation_seconds) || value.simulation_seconds < 0)
      return false;
    seconds_ = value.simulation_seconds;
    return true;
  }
  Offset offset() const {
    return {wrapped(profile_.phase + profile_.u_speed * seconds_),
            wrapped(profile_.phase + profile_.v_speed * seconds_)};
  }

 private:
  static float wrapped(double value) {
    value -= std::floor(value);
    return static_cast<float>(value);
  }
  Profile profile_;
  double seconds_=0;
};

}  // namespace asterix::water_animation
