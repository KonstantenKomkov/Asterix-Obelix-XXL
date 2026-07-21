#ifndef ASTERIX_ANIMATION_RUNTIME_HPP
#define ASTERIX_ANIMATION_RUNTIME_HPP

#include "asterix/scene_runtime.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace asterix::animation {
using scene::Matrix4;

struct Transform {
  std::array<float, 4> rotation{0, 0, 0, 1};
  std::array<float, 3> translation{};
};
struct Keyframe { float time = 0; Transform transform; };
struct Track { std::vector<Keyframe> keys; };
struct Clip { float duration = 0; bool looping = true; std::vector<Track> tracks; };
struct Joint { int parent = -1; Matrix4 inverse_bind = Matrix4::identity(); };
struct VertexBinding {
  std::array<std::uint16_t, 4> joints{};
  std::array<float, 4> weights{1, 0, 0, 0};
};

inline Transform interpolate(const Transform& a, const Transform& b, float t) {
  Transform result;
  for (std::size_t i = 0; i < 3; ++i)
    result.translation[i] = a.translation[i] + (b.translation[i] - a.translation[i]) * t;
  float dot = 0;
  for (std::size_t i = 0; i < 4; ++i) dot += a.rotation[i] * b.rotation[i];
  const float sign = dot < 0 ? -1.0f : 1.0f;
  float length = 0;
  for (std::size_t i = 0; i < 4; ++i) {
    result.rotation[i] = a.rotation[i] + (b.rotation[i] * sign - a.rotation[i]) * t;
    length += result.rotation[i] * result.rotation[i];
  }
  if (length <= 1e-12f) throw std::invalid_argument("animation quaternion is zero");
  const float reciprocal = 1.0f / std::sqrt(length);
  for (float& value : result.rotation) value *= reciprocal;
  return result;
}

inline Matrix4 matrix(const Transform& value) {
  const float x = value.rotation[0], y = value.rotation[1];
  const float z = value.rotation[2], w = value.rotation[3];
  Matrix4 result;
  result.value = {
      1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
      2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
      2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
      value.translation[0], value.translation[1], value.translation[2], 1};
  return result;
}

inline Transform sampleTrack(const Track& track, float time) {
  if (track.keys.empty()) throw std::invalid_argument("animation track has no keys");
  if (time <= track.keys.front().time) return track.keys.front().transform;
  for (std::size_t i = 1; i < track.keys.size(); ++i) {
    if (track.keys[i].time < track.keys[i - 1].time)
      throw std::invalid_argument("animation keys are not ordered");
    if (time <= track.keys[i].time) {
      const float span = track.keys[i].time - track.keys[i - 1].time;
      return interpolate(track.keys[i - 1].transform, track.keys[i].transform,
                         span > 0 ? (time - track.keys[i - 1].time) / span : 0);
    }
  }
  return track.keys.back().transform;
}

inline std::vector<Matrix4> skinningPalette(const Clip& clip,
                                            const std::vector<Joint>& joints,
                                            float requested_time) {
  if (clip.tracks.size() != joints.size())
    throw std::invalid_argument("animation track and joint counts differ");
  float time = requested_time;
  if (clip.duration > 0)
    time = clip.looping ? std::fmod(std::max(0.0f, time), clip.duration)
                        : std::clamp(time, 0.0f, clip.duration);
  std::vector<Matrix4> world(joints.size()), palette(joints.size());
  for (std::size_t i = 0; i < joints.size(); ++i) {
    if (joints[i].parent >= static_cast<int>(i) || joints[i].parent < -1)
      throw std::invalid_argument("skeleton parents must precede children");
    const Matrix4 local = matrix(sampleTrack(clip.tracks[i], time));
    world[i] = joints[i].parent < 0 ? local : scene::multiply(world[joints[i].parent], local);
    palette[i] = scene::multiply(world[i], joints[i].inverse_bind);
  }
  return palette;
}

inline std::array<float, 3> skinPosition(const std::array<float, 3>& position,
                                         const VertexBinding& binding,
                                         const std::vector<Matrix4>& palette) {
  std::array<float, 3> result{};
  float total = 0;
  for (std::size_t influence = 0; influence < 4; ++influence) {
    const float weight = binding.weights[influence];
    if (weight <= 0) continue;
    const std::size_t joint = binding.joints[influence];
    if (joint >= palette.size()) throw std::out_of_range("skin joint is outside palette");
    const auto& m = palette[joint].value;
    for (std::size_t row = 0; row < 3; ++row)
      result[row] += weight * (m[row] * position[0] + m[4 + row] * position[1] +
                              m[8 + row] * position[2] + m[12 + row]);
    total += weight;
  }
  if (total <= 1e-6f) throw std::invalid_argument("skin vertex has no positive weights");
  for (float& value : result) value /= total;
  return result;
}

struct Material {
  std::array<float, 4> color{1, 1, 1, 1};
  float ambient = 1;
  float diffuse = 1;
  float alpha_cutoff = 0.01f;
  bool transparent = false;
};

inline float fogFactor(float distance, float start, float end) {
  if (end <= start) return distance < end ? 1.0f : 0.0f;
  return std::clamp((end - distance) / (end - start), 0.0f, 1.0f);
}
}  // namespace asterix::animation
#endif
