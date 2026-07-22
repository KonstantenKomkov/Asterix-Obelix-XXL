#ifndef ASTERIX_ANIMATION_EVENT_RUNTIME_HPP
#define ASTERIX_ANIMATION_EVENT_RUNTIME_HPP

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace asterix::animation_event {
enum class Type { footstep, hit_window_open, hit_window_close, hurt_window_open,
  hurt_window_close, impulse, root_motion, object_state, vfx, sfx, camera,
  one_shot_complete };
struct Event { std::string id; float phase=0; Type type=Type::sfx;
  std::string target; std::string value; float x=0,y=0,z=0; };
struct Track { std::string id; std::uint32_t version=1; bool looping=false;
  std::vector<Event> events; };
struct Delivery { Event event; std::uint64_t instance=0,loop=0; std::string identity; };
struct Cursor { std::uint64_t instance=0; double absolute_phase=0; };

class Runtime {
 public:
  void add(Track track) {
    if(track.id.empty()||track.version==0||track.events.empty()||tracks_.contains(track.id))
      throw std::invalid_argument("animation event track is invalid");
    float previous=-1; std::unordered_set<std::string> ids;
    for(const auto& event:track.events) {
      if(event.id.empty()||!ids.insert(event.id).second||event.phase<0||
         event.phase>1||event.phase<previous)
        throw std::invalid_argument("animation events must be unique and ordered");
      previous=event.phase;
    }
    tracks_.emplace(track.id,std::move(track));
  }
  Cursor start(const std::string& track,std::uint64_t instance) const {
    if(!tracks_.contains(track)||instance==0)
      throw std::invalid_argument("unknown animation event track instance");
    return {instance,0};
  }
  // Samples (previous,current]. An arbitrarily large fixed-tick step may cross
  // many events and loops without losing occurrences.
  std::vector<Delivery> sample(const std::string& id,Cursor& cursor,
                               double current,bool paused=false) {
    const auto found=tracks_.find(id);
    if(found==tracks_.end()||cursor.instance==0)
      throw std::invalid_argument("unknown animation event track instance");
    if(!std::isfinite(current)||current<cursor.absolute_phase)
      throw std::invalid_argument("animation phase must be finite and monotonic");
    if(paused)return {};
    const Track& track=found->second;
    const double end=track.looping?current:std::min(1.0,current);
    std::vector<Delivery> result;
    if(end<=cursor.absolute_phase)return result;
    const auto first=static_cast<std::uint64_t>(std::floor(cursor.absolute_phase));
    const auto last=static_cast<std::uint64_t>(std::floor(end));
    for(std::uint64_t loop=first;loop<=last;++loop)for(const auto& event:track.events) {
      const double occurrence=static_cast<double>(loop)+event.phase;
      const bool starts_at_zero=occurrence==0&&cursor.absolute_phase==0;
      if((occurrence>cursor.absolute_phase||starts_at_zero)&&occurrence<=end&&
         (track.looping||loop==0)) {
        const std::string identity=id+":"+std::to_string(cursor.instance)+":"+
          std::to_string(loop)+":"+event.id;
        if(delivered_.insert(identity).second)
          result.push_back({event,cursor.instance,loop,identity});
      }
    }
    cursor.absolute_phase=end; return result;
  }
  bool restore(const std::string& id,Cursor& cursor,const Cursor& snapshot) const {
    if(!tracks_.contains(id)||snapshot.instance==0||
       !std::isfinite(snapshot.absolute_phase)||snapshot.absolute_phase<0)return false;
    cursor=snapshot; return true;
  }
 private:
  std::unordered_map<std::string,Track> tracks_;
  // Shared identities also suppress duplicate delivery from both blend branches.
  std::unordered_set<std::string> delivered_;
};
} // namespace asterix::animation_event
#endif
