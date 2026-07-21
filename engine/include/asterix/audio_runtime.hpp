#ifndef ASTERIX_AUDIO_RUNTIME_HPP
#define ASTERIX_AUDIO_RUNTIME_HPP

#include "asterix/collision_runtime.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace asterix::audio {

using collision::Vec3;

enum class Bus : std::uint8_t { music, ambience, effects };
enum class Cue : std::uint8_t {
  music,
  ambience,
  footstep,
  attack,
  hit,
  enemy_attack,
  reward,
  lever,
  checkpoint,
  death,
};

struct Request {
  Cue cue = Cue::footstep;
  Bus bus = Bus::effects;
  std::uint8_t priority = 0;
  Vec3 position{};
  bool spatial = true;
  bool looping = false;
  float gain = 1;
  std::size_t channel = 0;
};

struct Snapshot {
  float music_volume = .8f;
  float effects_volume = .8f;
  std::size_t active_effects = 0;
  std::size_t dropped_effects = 0;
};

class Runtime {
 public:
  explicit Runtime(std::size_t effect_channels = 8)
      : channels_(effect_channels) {
    if (effect_channels == 0) throw std::invalid_argument("audio channels are invalid");
  }

  void setVolumes(float music, float effects) {
    if (!std::isfinite(music) || !std::isfinite(effects))
      throw std::invalid_argument("audio volume is invalid");
    snapshot_.music_volume = std::clamp(music, 0.0f, 1.0f);
    snapshot_.effects_volume = std::clamp(effects, 0.0f, 1.0f);
  }

  void startBeds() {
    if (beds_started_) return;
    beds_started_ = true;
    events_.push_back({Cue::music, Bus::music, 255, {}, false, true, 1, 0});
    events_.push_back({Cue::ambience, Bus::ambience, 254, {}, true, true, .35f, 0});
  }

  bool play(Cue cue, Vec3 position = {}) {
    Request request = describe(cue, position);
    std::size_t channel = channels_.size();
    for (std::size_t i = 0; i < channels_.size(); ++i) {
      if (channels_[i].remaining <= 0) { channel = i; break; }
    }
    if (channel == channels_.size()) {
      channel = static_cast<std::size_t>(std::min_element(
          channels_.begin(), channels_.end(), [](const Channel& a, const Channel& b) {
            return a.priority < b.priority;
          }) - channels_.begin());
      if (channels_[channel].priority >= request.priority) {
        ++snapshot_.dropped_effects;
        return false;
      }
    }
    channels_[channel] = {request.priority, duration(cue)};
    request.channel = channel;
    events_.push_back(request);
    updateActiveCount();
    return true;
  }

  void update(float dt) {
    if (!std::isfinite(dt) || dt <= 0) throw std::invalid_argument("audio dt is invalid");
    for (auto& channel : channels_) channel.remaining = std::max(0.0f, channel.remaining - dt);
    updateActiveCount();
  }

  std::vector<Request> drainEvents() { return std::exchange(events_, {}); }
  const Snapshot& snapshot() const { return snapshot_; }

 private:
  struct Channel { std::uint8_t priority = 0; float remaining = 0; };

  static Request describe(Cue cue, Vec3 position) {
    Request request{cue, Bus::effects, 80, position, true, false, 1};
    switch (cue) {
      case Cue::footstep: request.priority = 20; request.gain = .45f; break;
      case Cue::attack: request.priority = 50; request.gain = .7f; break;
      case Cue::hit: request.priority = 90; break;
      case Cue::enemy_attack: request.priority = 70; break;
      case Cue::reward: request.priority = 110; request.spatial = false; break;
      case Cue::lever: request.priority = 80; break;
      case Cue::checkpoint: request.priority = 120; request.spatial = false; break;
      case Cue::death: request.priority = 127; request.spatial = false; break;
      case Cue::music: case Cue::ambience: break;
    }
    return request;
  }

  static float duration(Cue cue) {
    switch (cue) {
      case Cue::footstep: return .12f;
      case Cue::attack: return .18f;
      case Cue::hit: return .25f;
      case Cue::enemy_attack: return .2f;
      case Cue::reward: return .45f;
      case Cue::lever: return .3f;
      case Cue::checkpoint: return .6f;
      case Cue::death: return .8f;
      case Cue::music: case Cue::ambience: return 0;
    }
    return 0;
  }

  void updateActiveCount() {
    snapshot_.active_effects = static_cast<std::size_t>(std::count_if(
        channels_.begin(), channels_.end(), [](const Channel& value) { return value.remaining > 0; }));
  }

  std::vector<Channel> channels_;
  std::vector<Request> events_;
  Snapshot snapshot_;
  bool beds_started_ = false;
};

}  // namespace asterix::audio

#endif
