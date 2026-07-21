#ifndef ASTERIX_COLLISION_RUNTIME_HPP
#define ASTERIX_COLLISION_RUNTIME_HPP

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>
#include <optional>
#include <stdexcept>
#include <vector>

namespace asterix::collision {

struct Vec3 { float x = 0, y = 0, z = 0; };
inline Vec3 operator+(Vec3 a, Vec3 b) { return {a.x+b.x,a.y+b.y,a.z+b.z}; }
inline Vec3 operator-(Vec3 a, Vec3 b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
inline Vec3 operator*(Vec3 a, float s) { return {a.x*s,a.y*s,a.z*s}; }
inline float dot(Vec3 a, Vec3 b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
inline Vec3 cross(Vec3 a, Vec3 b) {
  return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};
}
inline float length(Vec3 a) { return std::sqrt(dot(a,a)); }
inline Vec3 normalized(Vec3 a) {
  const float l=length(a); return l>1e-6f?a*(1.0f/l):Vec3{};
}

struct Triangle {
  Vec3 a, b, c;
  int object_id = 0;
  bool dynamic = false;
  Vec3 velocity{};
};

struct CapsuleConfig {
  float radius = .35f;
  float half_height = .55f;
  float step_height = .35f;
  float maximum_slope_degrees = 50;
  float gravity = 24;
  float probe_distance = .12f;
  float kill_y = -20;
};

struct CapsuleState {
  Vec3 position{};
  Vec3 velocity{};
  Vec3 checkpoint{};
  bool grounded = false;
  bool recovered_from_fall = false;
  int ground_object_id = -1;
};

struct GroundHit { float height; Vec3 normal; int object_id; Vec3 velocity; };

class World {
 public:
  explicit World(std::vector<Triangle> triangles) : triangles_(std::move(triangles)) {}
  const std::vector<Triangle>& triangles() const { return triangles_; }
  void advanceDynamic(float dt) {
    for (Triangle& triangle : triangles_) if (triangle.dynamic) {
      const Vec3 displacement=triangle.velocity*dt;
      triangle.a=triangle.a+displacement;
      triangle.b=triangle.b+displacement;
      triangle.c=triangle.c+displacement;
    }
  }

  std::optional<GroundHit> groundAt(float x, float z, float maximum_y,
                                    float minimum_normal_y) const {
    std::optional<GroundHit> best;
    for (const Triangle& triangle : triangles_) {
      const Vec3 normal = normalized(cross(triangle.b-triangle.a,
                                           triangle.c-triangle.a));
      const float up = std::abs(normal.y);
      if (up < minimum_normal_y) continue;
      const float denominator = (triangle.b.z-triangle.c.z)*(triangle.a.x-triangle.c.x)+
                                (triangle.c.x-triangle.b.x)*(triangle.a.z-triangle.c.z);
      if (std::abs(denominator) < 1e-7f) continue;
      const float u=((triangle.b.z-triangle.c.z)*(x-triangle.c.x)+
                     (triangle.c.x-triangle.b.x)*(z-triangle.c.z))/denominator;
      const float v=((triangle.c.z-triangle.a.z)*(x-triangle.c.x)+
                     (triangle.a.x-triangle.c.x)*(z-triangle.c.z))/denominator;
      const float w=1-u-v;
      if (u < -1e-4f || v < -1e-4f || w < -1e-4f) continue;
      const float height=u*triangle.a.y+v*triangle.b.y+w*triangle.c.y;
      if (height > maximum_y || (best && height <= best->height)) continue;
      Vec3 oriented=normal.y<0?normal*-1:normal;
      best=GroundHit{height,oriented,triangle.object_id,
                     triangle.dynamic?triangle.velocity:Vec3{}};
    }
    return best;
  }

 private:
  std::vector<Triangle> triangles_;
};

class CapsuleController {
 public:
  CapsuleController(World& world, CapsuleConfig config = {})
      : world_(world), config_(config) {
    if (config.radius <= 0 || config.half_height < 0 || config.step_height < 0)
      throw std::invalid_argument("capsule dimensions are invalid");
  }

  CapsuleState move(CapsuleState state, Vec3 desired_velocity, float dt) {
    if (!std::isfinite(dt) || dt <= 0) throw std::invalid_argument("movement dt is invalid");
    state.recovered_from_fall=false;
    if (state.grounded) {
      for (const Triangle& triangle : world_.triangles()) {
        if (triangle.dynamic && triangle.object_id==state.ground_object_id) {
          state.position=state.position+triangle.velocity*dt;
          break;
        }
      }
    }
    world_.advanceDynamic(dt);
    state.velocity.x=desired_velocity.x;
    state.velocity.z=desired_velocity.z;
    if (state.grounded && state.velocity.y<0) state.velocity.y=0;
    state.velocity.y-=config_.gravity*dt;

    const float distance=std::sqrt(state.velocity.x*state.velocity.x+
                                   state.velocity.z*state.velocity.z)*dt;
    const int substeps=std::max(1,(int)std::ceil(distance/(config_.radius*.5f)));
    const float subdt=dt/substeps;
    for(int substep=0;substep<substeps;++substep) {
      Vec3 candidate=state.position+state.velocity*subdt;
      resolveObstacles(candidate);
      const float foot=state.position.y-config_.half_height-config_.radius;
      const float candidate_foot=candidate.y-config_.half_height-config_.radius;
      const float maximum_ground=std::max(foot+config_.step_height,
                                          candidate_foot+config_.probe_distance);
      const auto ground=world_.groundAt(candidate.x,candidate.z,maximum_ground,
                                         slopeCosine());
      if (ground && candidate_foot<=ground->height+config_.probe_distance &&
          ground->height-foot<=config_.step_height+1e-4f) {
        candidate.y=ground->height+config_.half_height+config_.radius;
        state.velocity.y=0;
        state.grounded=true;
        state.ground_object_id=ground->object_id;
      } else {
        state.grounded=false;
        state.ground_object_id=-1;
      }
      state.position=candidate;
    }
    if (state.position.y<config_.kill_y) {
      state.position=state.checkpoint;
      state.velocity={};
      state.grounded=false;
      state.ground_object_id=-1;
      state.recovered_from_fall=true;
    }
    return state;
  }

 private:
  float slopeCosine() const {
    return std::cos(config_.maximum_slope_degrees*3.14159265358979323846f/180);
  }

  static Vec3 closestPoint(Vec3 p,const Triangle& t) {
    const Vec3 ab=t.b-t.a, ac=t.c-t.a, ap=p-t.a;
    const float d1=dot(ab,ap),d2=dot(ac,ap);
    if(d1<=0&&d2<=0)return t.a;
    const Vec3 bp=p-t.b; const float d3=dot(ab,bp),d4=dot(ac,bp);
    if(d3>=0&&d4<=d3)return t.b;
    const float vc=d1*d4-d3*d2;
    if(vc<=0&&d1>=0&&d3<=0)return t.a+ab*(d1/(d1-d3));
    const Vec3 cp=p-t.c; const float d5=dot(ab,cp),d6=dot(ac,cp);
    if(d6>=0&&d5<=d6)return t.c;
    const float vb=d5*d2-d1*d6;
    if(vb<=0&&d2>=0&&d6<=0)return t.a+ac*(d2/(d2-d6));
    const float va=d3*d6-d5*d4;
    if(va<=0&&(d4-d3)>=0&&(d5-d6)>=0)
      return t.b+(t.c-t.b)*((d4-d3)/((d4-d3)+(d5-d6)));
    const float denominator=1/(va+vb+vc);
    return t.a+ab*(vb*denominator)+ac*(vc*denominator);
  }

  void resolveObstacles(Vec3& position) const {
    for(int iteration=0;iteration<4;++iteration) for(const Triangle& triangle:world_.triangles()) {
      const Vec3 surface=normalized(cross(triangle.b-triangle.a,triangle.c-triangle.a));
      if(std::abs(surface.y)>=slopeCosine())continue;
      const std::array<Vec3,3> samples={
        Vec3{position.x,position.y-config_.half_height,position.z}, position,
        Vec3{position.x,position.y+config_.half_height,position.z}};
      for(const Vec3& sample:samples) {
        const Vec3 point=closestPoint(sample,triangle);
        const Vec3 delta=sample-point; const float d=length(delta);
        if(d>=config_.radius||d<=1e-6f)continue;
        Vec3 push=delta*(1/d);
        push.y=0; push=normalized(push);
        position=position+push*(config_.radius-d+1e-4f);
      }
    }
  }

  World& world_;
  CapsuleConfig config_;
};

}  // namespace asterix::collision
#endif
