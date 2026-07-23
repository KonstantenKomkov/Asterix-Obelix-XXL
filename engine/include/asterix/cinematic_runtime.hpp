#ifndef ASTERIX_CINEMATIC_RUNTIME_HPP
#define ASTERIX_CINEMATIC_RUNTIME_HPP

#include <algorithm>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace asterix::cinematic {

// A track may begin after cue zero and may contain multiple selectors at the
// same cue as other tracks. This mirrors scene-data timelines without padding
// them with synthetic/fallback actions.
struct Track {
  std::string actor;
  std::vector<std::string> actions;
  std::size_t first_cue = 0;
  std::string profile_id;
};
struct Timeline { std::string script_event; std::vector<Track> tracks; };
enum class State { idle, playing, interrupted, complete };
struct Snapshot { std::string timeline; State state=State::idle; std::size_t cue=0; };
struct Output {
  std::string type;
  std::string target;
  std::string value;
  std::string profile_id;
};

class Runtime {
 public:
  void add(std::string id, Timeline timeline) {
    if (id.empty() || timeline.script_event.empty() || timeline.tracks.empty() ||
        timelines_.contains(id) || events_.contains(timeline.script_event))
      throw std::invalid_argument("invalid cinematic timeline");
    for (const auto& track : timeline.tracks)
      if (track.actor.empty() || track.actions.empty())
        throw std::invalid_argument("invalid cinematic track");
    events_.emplace(timeline.script_event,id);
    timelines_.emplace(std::move(id),std::move(timeline));
  }

  bool start(const std::string& event) {
    const auto found=events_.find(event);
    if (found==events_.end() || state_==State::playing) return false;
    active_=found->second; state_=State::playing; cue_=0;
    emit("control","player","lock");
    emit("camera","main","cinematic:"+active_);
    emit("audio","main","cinematic:"+active_);
    emit("subtitle","main","cinematic."+active_);
    emitActions(); return true;
  }

  bool advance() {
    if (state_!=State::playing) return false;
    const auto& timeline=timelines_.at(active_);
    if (cue_<terminal(timeline)) { ++cue_; emitActions(); return true; }
    finish("complete"); return true;
  }
  bool interrupt() {
    if (state_!=State::playing) return false;
    state_=State::interrupted; emit("control","player","return"); return true;
  }
  bool resume() {
    if (state_!=State::interrupted) return false;
    state_=State::playing; emit("control","player","lock"); emitActions(); return true;
  }
  bool skip() {
    if (state_!=State::playing && state_!=State::interrupted) return false;
    finish("skip-terminal"); return true;
  }
  Snapshot snapshot() const { return {active_,state_,cue_}; }
  bool restore(const Snapshot& value) {
    if (value.timeline.empty()) {
      if (value.state!=State::idle || value.cue!=0) return false;
    } else {
      const auto found=timelines_.find(value.timeline);
      if (found==timelines_.end()) return false;
      if (value.state==State::idle ||
          value.cue>terminal(found->second)) return false;
    }
    active_=value.timeline; state_=value.state; cue_=value.cue; outputs_.clear(); return true;
  }
  std::vector<Output> drain() { auto result=std::move(outputs_); outputs_.clear(); return result; }

 private:
  void emit(std::string type,std::string target,std::string value,
            std::string profile_id={}) {
    outputs_.push_back({std::move(type),std::move(target),std::move(value),
                        std::move(profile_id)});
  }
  void emitActions() {
    for (const auto& track:timelines_.at(active_).tracks)
      if (cue_>=track.first_cue &&
          cue_-track.first_cue<track.actions.size())
        emit("animation",
             track.actor,
             track.actions[cue_-track.first_cue],
             track.profile_id);
  }
  static std::size_t terminal(const Timeline& timeline) {
    std::size_t result=0;
    for (const auto& track:timeline.tracks)
      result=std::max(result,track.first_cue+track.actions.size()-1);
    return result;
  }
  void finish(const std::string& reason) {
    state_=State::complete; emit("timeline",active_,reason);
    emit("subtitle","main","clear"); emit("camera","main","gameplay");
    emit("audio","main","gameplay"); emit("control","player","return");
  }
  std::unordered_map<std::string,Timeline> timelines_;
  std::unordered_map<std::string,std::string> events_;
  std::string active_; State state_=State::idle; std::size_t cue_=0;
  std::vector<Output> outputs_;
};
}  // namespace asterix::cinematic
#endif
