#ifndef ASTERIX_CAMERA_RUNTIME_HPP
#define ASTERIX_CAMERA_RUNTIME_HPP

#include "asterix/collision_runtime.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <vector>

namespace asterix::camera {

using collision::Vec3;

struct Parameters {
  float distance = 10;
  float height = 3;
  float field_of_view_degrees = 70;
  float horizontal_target_zone = .75f;
  float vertical_target_zone = .5f;
  float follow_sharpness = 8;
  float collision_padding = .2f;
  float near_distance = .5f;
};

struct Zone {
  Vec3 minimum{};
  Vec3 maximum{};
  Parameters parameters{};
};

struct Snapshot {
  Vec3 position{};
  Vec3 target{};
  float field_of_view_degrees = 70;
  bool collision_limited = false;
  int active_zone = -1;
};

class Runtime {
 public:
  explicit Runtime(Parameters defaults = {}, std::vector<Zone> zones = {})
      : defaults_(defaults), zones_(std::move(zones)) {
    validate(defaults_);
    for (const Zone& zone : zones_) {
      validate(zone.parameters);
      if (zone.minimum.x > zone.maximum.x || zone.minimum.y > zone.maximum.y ||
          zone.minimum.z > zone.maximum.z) {
        throw std::invalid_argument("camera zone bounds are invalid");
      }
    }
  }

  const Snapshot& snapshot() const { return snapshot_; }
  Snapshot interpolatedSnapshot(double alpha) const {
    if (!initialized_ || !std::isfinite(alpha)) {
      if (!std::isfinite(alpha))
        throw std::invalid_argument("camera interpolation is invalid");
      return snapshot_;
    }
    const float amount = static_cast<float>(std::clamp(alpha, 0.0, 1.0));
    Snapshot result = snapshot_;
    result.position = previous_snapshot_.position +
                      (snapshot_.position - previous_snapshot_.position) * amount;
    result.target = previous_snapshot_.target +
                    (snapshot_.target - previous_snapshot_.target) * amount;
    result.field_of_view_degrees =
        previous_snapshot_.field_of_view_degrees +
        (snapshot_.field_of_view_degrees -
         previous_snapshot_.field_of_view_degrees) *
            amount;
    return result;
  }
  bool initialized() const { return initialized_; }

  const Snapshot& update(Vec3 player_position,
                         const collision::World& world, float dt) {
    if (!finite(player_position) || !std::isfinite(dt) || dt <= 0) {
      throw std::invalid_argument("camera update is invalid");
    }
    const int zone_index = activeZone(player_position);
    const Parameters& parameters =
        zone_index < 0 ? defaults_ : zones_[zone_index].parameters;
    if (!initialized_) {
      snapshot_.target = player_position;
      snapshot_.position = desiredPosition(snapshot_.target, parameters);
      initialized_ = true;
      previous_snapshot_ = snapshot_;
    } else {
      previous_snapshot_ = snapshot_;
      followAxis(snapshot_.target.x, player_position.x,
                 parameters.horizontal_target_zone);
      followAxis(snapshot_.target.z, player_position.z,
                 parameters.horizontal_target_zone);
      followAxis(snapshot_.target.y, player_position.y,
                 parameters.vertical_target_zone);
    }
    snapshot_.active_zone = zone_index;
    snapshot_.field_of_view_degrees = parameters.field_of_view_degrees;

    const Vec3 desired = desiredPosition(snapshot_.target, parameters);
    const float blend = 1 - std::exp(-parameters.follow_sharpness * dt);
    const Vec3 candidate = snapshot_.position +
                           (desired - snapshot_.position) * blend;
    snapshot_.position = avoidCollision(snapshot_.target, candidate, world,
                                        parameters, snapshot_.collision_limited);
    return snapshot_;
  }

 private:
  static bool finite(Vec3 value) {
    return std::isfinite(value.x) && std::isfinite(value.y) &&
           std::isfinite(value.z);
  }
  static void validate(const Parameters& value) {
    if (!std::isfinite(value.distance) || value.distance <= 0 ||
        !std::isfinite(value.height) ||
        !std::isfinite(value.field_of_view_degrees) ||
        value.field_of_view_degrees <= 1 || value.field_of_view_degrees >= 179 ||
        value.horizontal_target_zone < 0 || value.vertical_target_zone < 0 ||
        value.follow_sharpness <= 0 || value.collision_padding < 0 ||
        value.near_distance <= 0 || value.near_distance >= value.distance) {
      throw std::invalid_argument("camera parameters are invalid");
    }
  }
  int activeZone(Vec3 point) const {
    for (std::size_t index = 0; index < zones_.size(); ++index) {
      const Zone& zone = zones_[index];
      if (point.x >= zone.minimum.x && point.x <= zone.maximum.x &&
          point.y >= zone.minimum.y && point.y <= zone.maximum.y &&
          point.z >= zone.minimum.z && point.z <= zone.maximum.z) {
        return static_cast<int>(index);
      }
    }
    return -1;
  }
  static void followAxis(float& target, float player, float half_extent) {
    if (player > target + half_extent) target = player - half_extent;
    if (player < target - half_extent) target = player + half_extent;
  }
  static Vec3 desiredPosition(Vec3 target, const Parameters& parameters) {
    return {target.x, target.y + parameters.height,
            target.z + parameters.distance};
  }
  static bool segmentTriangle(Vec3 origin, Vec3 direction,
                              const collision::Triangle& triangle, float& t) {
    const Vec3 edge1 = triangle.b - triangle.a;
    const Vec3 edge2 = triangle.c - triangle.a;
    const Vec3 p = collision::cross(direction, edge2);
    const float determinant = collision::dot(edge1, p);
    if (std::abs(determinant) < 1e-7f) return false;
    const float inverse = 1 / determinant;
    const Vec3 offset = origin - triangle.a;
    const float u = collision::dot(offset, p) * inverse;
    if (u < 0 || u > 1) return false;
    const Vec3 q = collision::cross(offset, edge1);
    const float v = collision::dot(direction, q) * inverse;
    if (v < 0 || u + v > 1) return false;
    t = collision::dot(edge2, q) * inverse;
    return t >= 0 && t <= 1;
  }
  static Vec3 avoidCollision(Vec3 target, Vec3 candidate,
                             const collision::World& world,
                             const Parameters& parameters, bool& limited) {
    const Vec3 ray = candidate - target;
    const float distance = collision::length(ray);
    if (distance <= 1e-6f) { limited = false; return candidate; }
    float nearest = 1;
    for (const collision::Triangle& triangle : world.triangles()) {
      float t = 0;
      if (segmentTriangle(target, ray, triangle, t)) nearest = std::min(nearest, t);
    }
    limited = nearest < 1;
    if (!limited) return candidate;
    const float safe_distance = std::max(
        parameters.near_distance, nearest * distance - parameters.collision_padding);
    return target + ray * (std::min(safe_distance, distance) / distance);
  }

  Parameters defaults_;
  std::vector<Zone> zones_;
  Snapshot previous_snapshot_{};
  Snapshot snapshot_{};
  bool initialized_ = false;
};

}  // namespace asterix::camera
#endif
