#ifndef ASTERIX_SIMULATION_RUNTIME_HPP
#define ASTERIX_SIMULATION_RUNTIME_HPP

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

namespace asterix::simulation {

class FixedTimestep {
 public:
  explicit FixedTimestep(double step_seconds = 1.0 / 60.0,
                         std::uint32_t maximum_steps_per_frame = 8)
      : step_seconds_(step_seconds),
        maximum_steps_per_frame_(maximum_steps_per_frame) {
    if (!std::isfinite(step_seconds_) || step_seconds_ <= 0 ||
        maximum_steps_per_frame_ == 0) {
      throw std::invalid_argument("fixed timestep configuration is invalid");
    }
  }

  template <typename Step>
  std::uint32_t advance(double elapsed_seconds, Step&& step) {
    if (!std::isfinite(elapsed_seconds) || elapsed_seconds < 0)
      throw std::invalid_argument("elapsed simulation time is invalid");
    accumulator_seconds_ += elapsed_seconds;
    std::uint32_t count = 0;
    while (accumulator_seconds_ + 1e-12 >= step_seconds_ &&
           count < maximum_steps_per_frame_) {
      step(step_seconds_);
      accumulator_seconds_ -= step_seconds_;
      simulated_seconds_ += step_seconds_;
      ++tick_;
      ++count;
    }
    if (count == maximum_steps_per_frame_ &&
        accumulator_seconds_ >= step_seconds_) {
      dropped_seconds_ += accumulator_seconds_ -
                          std::fmod(accumulator_seconds_, step_seconds_);
      accumulator_seconds_ = std::fmod(accumulator_seconds_, step_seconds_);
    }
    return count;
  }

  double interpolationAlpha() const {
    return std::clamp(accumulator_seconds_ / step_seconds_, 0.0, 1.0);
  }
  double stepSeconds() const { return step_seconds_; }
  double simulatedSeconds() const { return simulated_seconds_; }
  double droppedSeconds() const { return dropped_seconds_; }
  std::uint64_t tick() const { return tick_; }

  void reset() {
    accumulator_seconds_ = 0;
    simulated_seconds_ = 0;
    dropped_seconds_ = 0;
    tick_ = 0;
  }

 private:
  double step_seconds_;
  std::uint32_t maximum_steps_per_frame_;
  double accumulator_seconds_ = 0;
  double simulated_seconds_ = 0;
  double dropped_seconds_ = 0;
  std::uint64_t tick_ = 0;
};

template <typename Value>
Value interpolate(const Value& previous, const Value& current, double alpha) {
  const double clamped = std::clamp(alpha, 0.0, 1.0);
  return static_cast<Value>(previous + (current - previous) * clamped);
}

}  // namespace asterix::simulation

#endif
