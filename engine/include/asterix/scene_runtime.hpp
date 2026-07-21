#ifndef ASTERIX_SCENE_RUNTIME_HPP
#define ASTERIX_SCENE_RUNTIME_HPP

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace asterix::scene {

struct Matrix4 {
  std::array<float, 16> value{};

  static Matrix4 identity() {
    Matrix4 result;
    result.value = {1, 0, 0, 0, 0, 1, 0, 0,
                    0, 0, 1, 0, 0, 0, 0, 1};
    return result;
  }
};

inline Matrix4 multiply(const Matrix4& a, const Matrix4& b) {
  Matrix4 result;
  for (std::size_t column = 0; column < 4; ++column) {
    for (std::size_t row = 0; row < 4; ++row) {
      float sum = 0;
      for (std::size_t k = 0; k < 4; ++k) {
        sum += a.value[k * 4 + row] * b.value[column * 4 + k];
      }
      result.value[column * 4 + row] = sum;
    }
  }
  return result;
}

struct Bounds {
  std::array<float, 3> minimum{};
  std::array<float, 3> maximum{};
};

struct Plane {
  float x = 0;
  float y = 0;
  float z = 0;
  float distance = 0;
};

struct Frustum {
  std::array<Plane, 6> planes{};

  bool intersects(const Bounds& bounds) const {
    for (const Plane& plane : planes) {
      const float x = plane.x >= 0 ? bounds.maximum[0] : bounds.minimum[0];
      const float y = plane.y >= 0 ? bounds.maximum[1] : bounds.minimum[1];
      const float z = plane.z >= 0 ? bounds.maximum[2] : bounds.minimum[2];
      if (plane.x * x + plane.y * y + plane.z * z + plane.distance < 0) {
        return false;
      }
    }
    return true;
  }
};

struct Node {
  std::string id;
  std::string parent_id;
  std::string section_id;
  std::string resource_id;
  Matrix4 local = Matrix4::identity();
  Matrix4 world = Matrix4::identity();
  Bounds world_bounds{};
  std::uint32_t material = 0;
  std::uint32_t full_vertex_count = 0;
};

struct Section {
  std::string id;
  Bounds bounds{};
  bool requested = false;
  bool resident = false;
  std::uint64_t last_visible_frame = 0;
};

struct DrawItem {
  std::size_t node_index = 0;
  std::uint32_t material = 0;
  std::uint8_t lod = 0;
  std::uint32_t vertex_count = 0;
};

struct DrawBatch {
  std::uint32_t material = 0;
  std::uint8_t lod = 0;
  std::vector<DrawItem> items;
};

class Runtime {
 public:
  std::size_t addSection(Section section) {
    if (section.id.empty() || section_by_id_.count(section.id) != 0) {
      throw std::invalid_argument("section IDs must be non-empty and unique");
    }
    const std::size_t index = sections_.size();
    section_by_id_[section.id] = index;
    sections_.push_back(std::move(section));
    return index;
  }

  std::size_t addNode(Node node) {
    if (node.id.empty() || node_by_id_.count(node.id) != 0) {
      throw std::invalid_argument("node IDs must be non-empty and unique");
    }
    const std::size_t index = nodes_.size();
    node_by_id_[node.id] = index;
    nodes_.push_back(std::move(node));
    return index;
  }

  void resolveHierarchy() {
    std::vector<std::uint8_t> state(nodes_.size(), 0);
    for (std::size_t index = 0; index < nodes_.size(); ++index) {
      resolveNode(index, state);
    }
  }

  void updateStreaming(const Frustum& preload_frustum, std::uint64_t frame,
                       std::uint64_t eviction_delay_frames = 120) {
    for (Section& section : sections_) {
      const bool visible = preload_frustum.intersects(section.bounds);
      section.requested = visible;
      if (visible) {
        section.last_visible_frame = frame;
      } else if (section.resident && frame > section.last_visible_frame &&
                 frame - section.last_visible_frame > eviction_delay_frames) {
        section.resident = false;
      }
    }
  }

  std::vector<std::size_t> pendingSections() const {
    std::vector<std::size_t> result;
    for (std::size_t i = 0; i < sections_.size(); ++i) {
      if (sections_[i].requested && !sections_[i].resident) result.push_back(i);
    }
    return result;
  }

  void markResident(std::size_t section_index, bool resident = true) {
    sections_.at(section_index).resident = resident;
  }

  std::vector<DrawBatch> buildBatches(const Frustum& frustum,
                                      const std::array<float, 3>& camera,
                                      float lod_distance) const {
    std::vector<DrawItem> items;
    for (std::size_t index = 0; index < nodes_.size(); ++index) {
      const Node& node = nodes_[index];
      const auto section = section_by_id_.find(node.section_id);
      if (section == section_by_id_.end() ||
          !sections_[section->second].resident ||
          node.full_vertex_count == 0 || !frustum.intersects(node.world_bounds)) {
        continue;
      }
      const float x = (node.world_bounds.minimum[0] + node.world_bounds.maximum[0]) * .5f - camera[0];
      const float y = (node.world_bounds.minimum[1] + node.world_bounds.maximum[1]) * .5f - camera[1];
      const float z = (node.world_bounds.minimum[2] + node.world_bounds.maximum[2]) * .5f - camera[2];
      const bool distant = x * x + y * y + z * z > lod_distance * lod_distance;
      const std::uint32_t reduced = std::max<std::uint32_t>(3, (node.full_vertex_count / 2 / 3) * 3);
      items.push_back({index, node.material, static_cast<std::uint8_t>(distant),
                       distant ? std::min(reduced, node.full_vertex_count)
                               : node.full_vertex_count});
    }
    std::stable_sort(items.begin(), items.end(), [](const DrawItem& a, const DrawItem& b) {
      return std::pair(a.material, a.lod) < std::pair(b.material, b.lod);
    });
    std::vector<DrawBatch> batches;
    for (const DrawItem& item : items) {
      if (batches.empty() || batches.back().material != item.material ||
          batches.back().lod != item.lod) {
        batches.push_back({item.material, item.lod, {}});
      }
      batches.back().items.push_back(item);
    }
    return batches;
  }

  const std::vector<Node>& nodes() const { return nodes_; }
  const std::vector<Section>& sections() const { return sections_; }

 private:
  void resolveNode(std::size_t index, std::vector<std::uint8_t>& state) {
    if (state[index] == 2) return;
    if (state[index] == 1) throw std::invalid_argument("scene graph contains a parent cycle");
    state[index] = 1;
    Node& node = nodes_[index];
    if (!node.parent_id.empty()) {
      const auto parent = node_by_id_.find(node.parent_id);
      if (parent == node_by_id_.end()) throw std::invalid_argument("scene node parent is missing");
      resolveNode(parent->second, state);
      node.world = multiply(nodes_[parent->second].world, node.local);
    } else {
      node.world = node.local;
    }
    state[index] = 2;
  }

  std::vector<Node> nodes_;
  std::vector<Section> sections_;
  std::unordered_map<std::string, std::size_t> node_by_id_;
  std::unordered_map<std::string, std::size_t> section_by_id_;
};

}  // namespace asterix::scene

#endif
