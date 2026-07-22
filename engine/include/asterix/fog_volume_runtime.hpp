#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace asterix::fog_volume {

struct Vec3 { float x=0,y=0,z=0; };
struct Color { float r=0,g=0,b=0,a=1; };
struct Stop { float position=0,density=0; Color color{}; };
struct Profile {
  std::uint32_t id=0;
  Vec3 minimum{},maximum{};
  float transition=1;
  float pulse_rate=0;
  std::vector<Stop> stops;
};
struct Snapshot { double simulation_seconds=0; std::vector<std::uint32_t> streamed; };
struct Sample { Color color{}; float density=0; float weight=0; };

class Runtime {
 public:
  explicit Runtime(std::vector<Profile> profiles) : profiles_(std::move(profiles)) {
    for(const auto& p:profiles_) {
      if(p.id==0||!finite(p.minimum)||!finite(p.maximum)||
         p.minimum.x>p.maximum.x||p.minimum.y>p.maximum.y||p.minimum.z>p.maximum.z||
         !std::isfinite(p.transition)||p.transition<=0||p.stops.empty()||
         !std::isfinite(p.pulse_rate)) throw std::invalid_argument("fog volume profile is invalid");
      for(const auto& stop:p.stops)if(!std::isfinite(stop.position)||
          !std::isfinite(stop.density)||stop.density<0)throw std::invalid_argument("fog stop is invalid");
      streamed_.push_back(p.id);
    }
    std::sort(streamed_.begin(),streamed_.end());
  }
  void advance(double elapsed,bool paused=false) {
    if(!std::isfinite(elapsed)||elapsed<0)throw std::invalid_argument("fog elapsed time is invalid");
    if(!paused)seconds_+=elapsed;
  }
  void setStreamed(std::vector<std::uint32_t> ids) {
    std::sort(ids.begin(),ids.end()); ids.erase(std::unique(ids.begin(),ids.end()),ids.end());
    streamed_=std::move(ids);
  }
  Snapshot snapshot() const { return {seconds_,streamed_}; }
  bool restore(const Snapshot& value) {
    if(!std::isfinite(value.simulation_seconds)||value.simulation_seconds<0)return false;
    for(auto id:value.streamed)if(!find(id))return false;
    seconds_=value.simulation_seconds; setStreamed(value.streamed); return true;
  }
  Sample sample(Vec3 point) const {
    Sample result; float accumulated=0;
    for(const auto& p:profiles_) {
      if(!std::binary_search(streamed_.begin(),streamed_.end(),p.id))continue;
      const float outside=std::max({p.minimum.x-point.x,point.x-p.maximum.x,
          p.minimum.y-point.y,point.y-p.maximum.y,p.minimum.z-point.z,point.z-p.maximum.z,0.0f});
      const float weight=std::clamp(1-outside/p.transition,0.0f,1.0f);
      if(weight<=0)continue;
      const float phase=.5f+.5f*std::sin(static_cast<float>(seconds_)*p.pulse_rate*6.283185307f);
      const Stop stop=interpolated(p.stops,phase);
      const float contribution=weight*stop.density;
      result.color.r+=stop.color.r*contribution; result.color.g+=stop.color.g*contribution;
      result.color.b+=stop.color.b*contribution; accumulated+=contribution;
      result.weight=std::max(result.weight,weight);
    }
    if(accumulated>0) { result.color.r/=accumulated; result.color.g/=accumulated; result.color.b/=accumulated; }
    result.color.a=1; result.density=1-std::exp(-accumulated); return result;
  }

 private:
  static bool finite(Vec3 p){return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z);}
  static Stop interpolated(std::vector<Stop> stops,float phase) {
    std::sort(stops.begin(),stops.end(),[](const Stop& a,const Stop& b){return a.position<b.position;});
    if(stops.size()==1||phase<=stops.front().position)return stops.front();
    for(std::size_t i=1;i<stops.size();++i)if(phase<=stops[i].position) {
      const auto& a=stops[i-1];const auto& b=stops[i];
      const float t=std::clamp((phase-a.position)/std::max(.0001f,b.position-a.position),0.0f,1.0f);
      return {phase,a.density+(b.density-a.density)*t,
          {a.color.r+(b.color.r-a.color.r)*t,a.color.g+(b.color.g-a.color.g)*t,
           a.color.b+(b.color.b-a.color.b)*t,1}};
    }
    return stops.back();
  }
  const Profile* find(std::uint32_t id)const{for(const auto& p:profiles_)if(p.id==id)return &p;return nullptr;}
  std::vector<Profile> profiles_;
  std::vector<std::uint32_t> streamed_;
  double seconds_=0;
};

}  // namespace asterix::fog_volume
