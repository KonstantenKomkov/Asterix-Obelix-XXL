#ifndef ASTERIX_CAMERA_RUNTIME_HPP
#define ASTERIX_CAMERA_RUNTIME_HPP

#include "asterix/collision_runtime.hpp"

#include <algorithm>
#include <array>
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
  float near_plane_aspect_ratio = 4.0f / 3.0f;
  float collision_radius = .35f;
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
    const bool first_update = !initialized_;
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
    bool sightline_limited = false;
    const Vec3 visible_candidate = avoidCollision(
        snapshot_.target, candidate, world, parameters, sightline_limited);
    bool follow_limited = false;
    snapshot_.position = first_update
        ? visible_candidate
        : sweepCamera(previous_snapshot_.position, visible_candidate, world,
                      parameters, follow_limited);
    snapshot_.collision_limited = sightline_limited || follow_limited;
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
        value.near_distance <= 0 || value.near_distance >= value.distance ||
        !std::isfinite(value.near_plane_aspect_ratio) ||
        value.near_plane_aspect_ratio <= 0 ||
        !std::isfinite(value.collision_radius) || value.collision_radius <= 0) {
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
  static Vec3 closestPointOnSegment(Vec3 point, Vec3 start, Vec3 end) {
    const Vec3 segment = end - start;
    const float length_squared = collision::dot(segment, segment);
    if (length_squared <= 1e-12f) return start;
    const float amount = std::clamp(
        collision::dot(point - start, segment) / length_squared, 0.0f, 1.0f);
    return start + segment * amount;
  }
  static Vec3 closestPoint(Vec3 point, const collision::Triangle& triangle) {
    const Vec3 ab = triangle.b - triangle.a;
    const Vec3 ac = triangle.c - triangle.a;
    const Vec3 surface = collision::cross(ab, ac);
    if (collision::dot(surface, surface) <= 1e-12f) {
      const std::array<Vec3, 3> candidates = {
          closestPointOnSegment(point, triangle.a, triangle.b),
          closestPointOnSegment(point, triangle.b, triangle.c),
          closestPointOnSegment(point, triangle.c, triangle.a)};
      return *std::min_element(candidates.begin(), candidates.end(),
          [point](Vec3 left, Vec3 right) {
            return collision::dot(point - left, point - left) <
                   collision::dot(point - right, point - right);
          });
    }
    const Vec3 ap = point - triangle.a;
    const float d1 = collision::dot(ab, ap);
    const float d2 = collision::dot(ac, ap);
    if (d1 <= 0 && d2 <= 0) return triangle.a;
    const Vec3 bp = point - triangle.b;
    const float d3 = collision::dot(ab, bp);
    const float d4 = collision::dot(ac, bp);
    if (d3 >= 0 && d4 <= d3) return triangle.b;
    const float vc = d1 * d4 - d3 * d2;
    if (vc <= 0 && d1 >= 0 && d3 <= 0)
      return triangle.a + ab * (d1 / (d1 - d3));
    const Vec3 cp = point - triangle.c;
    const float d5 = collision::dot(ab, cp);
    const float d6 = collision::dot(ac, cp);
    if (d6 >= 0 && d5 <= d6) return triangle.c;
    const float vb = d5 * d2 - d1 * d6;
    if (vb <= 0 && d2 >= 0 && d6 <= 0)
      return triangle.a + ac * (d2 / (d2 - d6));
    const float va = d3 * d6 - d5 * d4;
    if (va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0)
      return triangle.b + (triangle.c - triangle.b) *
                              ((d4 - d3) / ((d4 - d3) + (d5 - d6)));
    const float denominator = 1 / (va + vb + vc);
    return triangle.a + ab * (vb * denominator) + ac * (vc * denominator);
  }
  static float volumeRadius(const Parameters& parameters) {
    constexpr float radians = 3.14159265358979323846f / 180.0f;
    const float half_height = parameters.near_distance *
                              std::tan(parameters.field_of_view_degrees *
                                       radians * .5f);
    const float half_width = half_height * parameters.near_plane_aspect_ratio;
    return std::max(parameters.collision_radius,
                    std::sqrt(half_width * half_width +
                              half_height * half_height));
  }
  static float clearance(Vec3 position, const collision::World& world,
                         float radius) {
    float nearest = std::numeric_limits<float>::infinity();
    for (const collision::Triangle& triangle : world.triangles()) {
      const Vec3 delta = position - closestPoint(position, triangle);
      nearest = std::min(nearest, collision::length(delta));
    }
    return nearest - radius;
  }
  static float sweepFraction(Vec3 start, Vec3 end,
                             const collision::World& world, float radius) {
    const Vec3 path = end - start;
    const float distance = collision::length(path);
    if (distance <= 1e-6f)
      return clearance(end, world, radius) <= 0 ? 0 : 1;
    // Point-to-triangle distance is 1-Lipschitz. Advancing by the current
    // clearance cannot cross even an infinitely thin surface, unlike sampling
    // the path at a fixed interval.
    float safe = 0;
    for (int iteration = 0; iteration < 128; ++iteration) {
      const float available = clearance(start + path * safe, world, radius);
      if (available <= 1e-5f) return safe;
      const float advance = available / distance;
      if (advance >= 1 - safe) return 1;
      safe += advance;
    }
    return safe;
  }
  static Vec3 sweepCamera(Vec3 start, Vec3 end,
                          const collision::World& world,
                          const Parameters& parameters, bool& limited) {
    const Vec3 path = end - start;
    const float distance = collision::length(path);
    const float fraction = sweepFraction(start, end, world,
                                         volumeRadius(parameters));
    limited = fraction < 1;
    if (!limited || distance <= 1e-6f) return end;
    const float padding_fraction = parameters.collision_padding / distance;
    return start + path * std::max(0.0f, fraction - padding_fraction);
  }
  static Vec3 avoidCollision(Vec3 target, Vec3 candidate,
                             const collision::World& world,
                             const Parameters& parameters, bool& limited) {
    const Vec3 ray = candidate - target;
    const float distance = collision::length(ray);
    if (distance <= 1e-6f) { limited = false; return candidate; }
    const float start_fraction = std::min(parameters.near_distance / distance, 1.0f);
    const Vec3 start = target + ray * start_fraction;
    const float fraction = sweepFraction(start, candidate, world,
                                         volumeRadius(parameters));
    limited = fraction < 1;
    if (!limited) return candidate;
    const float swept_distance = collision::length(candidate - start);
    const float padding_fraction = swept_distance <= 1e-6f
        ? 0 : parameters.collision_padding / swept_distance;
    return start + (candidate - start) *
                       std::max(0.0f, fraction - padding_fraction);
  }

  Parameters defaults_;
  std::vector<Zone> zones_;
  Snapshot previous_snapshot_{};
  Snapshot snapshot_{};
  bool initialized_ = false;
};

}  // namespace asterix::camera
#endif
