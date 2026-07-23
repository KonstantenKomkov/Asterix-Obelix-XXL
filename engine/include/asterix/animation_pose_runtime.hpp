#ifndef ASTERIX_ANIMATION_POSE_RUNTIME_HPP
#define ASTERIX_ANIMATION_POSE_RUNTIME_HPP

#include "asterix/animation_controller.hpp"
#include "asterix/animation_runtime.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace asterix::animation_pose {

struct Sample {
  std::vector<animation::Matrix4> palette;
  // Authored displacement is an input for the capsule owner. It is never
  // applied to the render root independently, which prevents visual/physical
  // actor divergence.
  std::array<float, 3> authored_root_motion{};
  float blend_weight = 1;
  double cursor_seconds = 0;
};

class Playback {
 public:
  Playback(const std::unordered_map<std::string, animation::Clip>& clips,
           const std::vector<animation::Joint>& joints,
           std::size_t motion_root_joint = 1)
      : clips_(clips), joints_(joints), motion_root_joint_(motion_root_joint) {}

  Sample sample(const animation_controller::Snapshot& previous,
                const animation_controller::Snapshot& current,
                double interpolation_alpha) const {
    if (!std::isfinite(interpolation_alpha))
      throw std::invalid_argument("pose interpolation alpha is invalid");
    const float alpha =
        static_cast<float>(std::clamp(interpolation_alpha, 0.0, 1.0));
    const animation::Clip& to = clip(current.state, current.binding);
    const bool same_activation = previous.activation == current.activation;
    const double cursor = same_activation
        ? interpolateCursor(previous.cursor_seconds, current.cursor_seconds,
                            to.duration,
                            current.completion ==
                                animation_controller::Completion::loop,
                            alpha)
        : current.cursor_seconds;
    Sample result;
    result.cursor_seconds = cursor;
    if (!current.blend) {
      result.palette = policyPalette(to, joints_, cursor, current.root_motion,
                                     &result.authored_root_motion);
      return result;
    }

    const auto& blend = *current.blend;
    const animation::Clip& from =
        clip(blend.from_state, blend.from_binding);
    const double elapsed = same_activation
        ? previous.blend
              ? previous.blend->elapsed_seconds +
                    (blend.elapsed_seconds -
                     previous.blend->elapsed_seconds) * alpha
              : blend.elapsed_seconds
        : blend.elapsed_seconds * alpha;
    result.blend_weight = blend.duration_seconds > 0
        ? static_cast<float>(
              std::clamp(elapsed / blend.duration_seconds, 0.0, 1.0))
        : 1;
    const bool from_loop =
        blend.from_completion == animation_controller::Completion::loop;
    const double from_cursor = same_activation && previous.blend
        ? interpolateCursor(previous.blend->from_cursor_seconds,
                            blend.from_cursor_seconds, from.duration,
                            from_loop, alpha)
        : rewindCursor(
              blend.from_cursor_seconds,
              (blend.elapsed_seconds - elapsed) * blend.from_playback_rate,
              from.duration, from_loop);
    std::array<float, 3> from_motion{}, to_motion{};
    const auto from_pose = localPose(from, from_cursor, blend.from_root_motion,
                                     &from_motion);
    const auto to_pose =
        localPose(to, cursor, current.root_motion, &to_motion);
    result.palette =
        blendedPalette(from_pose, to_pose, joints_, result.blend_weight);
    for (std::size_t axis = 0; axis < 3; ++axis)
      result.authored_root_motion[axis] =
          from_motion[axis] +
          (to_motion[axis] - from_motion[axis]) * result.blend_weight;
    return result;
  }

 private:
  const std::unordered_map<std::string, animation::Clip>& clips_;
  const std::vector<animation::Joint>& joints_;
  std::size_t motion_root_joint_;

  static double interpolateCursor(double start, double end, double duration,
                                  bool looping, double alpha) {
    if (looping && duration > 0 && end < start) end += duration;
    double result = start + (end - start) * alpha;
    if (looping && duration > 0) result = std::fmod(result, duration);
    return result;
  }

  static double rewindCursor(double cursor, double amount, double duration,
                             bool looping) {
    double result = cursor - amount;
    if (!looping || duration <= 0) return std::max(0.0, result);
    result = std::fmod(result, duration);
    return result < 0 ? result + duration : result;
  }

  const animation::Clip& clip(
      const std::string& state,
      const animation_controller::Binding& binding) const {
    constexpr std::string_view prefix = "binding:";
    std::string key = state.rfind(prefix, 0) == 0
        ? state.substr(prefix.size())
        : state;
    auto found = clips_.find(key);
    if (found == clips_.end()) {
      key = binding.asset;
      found = clips_.find(key);
    }
    if (found == clips_.end()) {
      throw std::out_of_range("authored pose clip is missing");
    }
    return found->second;
  }

  std::vector<animation::Transform> localPose(
      const animation::Clip& clip, double requested_time,
      animation_controller::RootMotionPolicy policy,
      std::array<float, 3>* authored_motion) const {
    if (clip.tracks.size() != joints_.size())
      throw std::invalid_argument("animation track and joint counts differ");
    float time = static_cast<float>(requested_time);
    if (clip.duration > 0)
      time = clip.looping ? std::fmod(std::max(0.0f, time), clip.duration)
                          : std::clamp(time, 0.0f, clip.duration);
    std::vector<animation::Transform> pose;
    pose.reserve(clip.tracks.size());
    for (const auto& track : clip.tracks)
      pose.push_back(animation::sampleTrack(track, time));
    if (motion_root_joint_ < pose.size()) {
      const auto origin =
          animation::sampleTrack(clip.tracks[motion_root_joint_], 0);
      std::array<float, 3> delta{};
      for (std::size_t axis = 0; axis < 3; ++axis)
        delta[axis] =
            pose[motion_root_joint_].translation[axis] -
            origin.translation[axis];
      if (policy == animation_controller::RootMotionPolicy::authored)
        *authored_motion = delta;
      // All policies keep skeletal motion relative to the capsule. Authored
      // motion is returned above for deterministic physics consumption.
      for (std::size_t axis = 0; axis < 3; ++axis)
        pose[motion_root_joint_].translation[axis] -= delta[axis];
    }
    return pose;
  }

  static std::vector<animation::Matrix4> blendedPalette(
      const std::vector<animation::Transform>& from,
      const std::vector<animation::Transform>& to,
      const std::vector<animation::Joint>& joints, float weight) {
    std::vector<animation::Matrix4> world(joints.size()), result(joints.size());
    for (std::size_t joint = 0; joint < joints.size(); ++joint) {
      const auto local =
          animation::matrix(animation::interpolate(from[joint], to[joint],
                                                   weight));
      world[joint] = joints[joint].parent < 0
          ? local
          : scene::multiply(world[joints[joint].parent], local);
      result[joint] =
          scene::multiply(world[joint], joints[joint].inverse_bind);
    }
    return result;
  }

  std::vector<animation::Matrix4> policyPalette(
      const animation::Clip& clip, const std::vector<animation::Joint>& joints,
      double time, animation_controller::RootMotionPolicy policy,
      std::array<float, 3>* authored_motion) const {
    const auto pose = localPose(clip, time, policy, authored_motion);
    return blendedPalette(pose, pose, joints, 0);
  }
};

}  // namespace asterix::animation_pose
#endif
