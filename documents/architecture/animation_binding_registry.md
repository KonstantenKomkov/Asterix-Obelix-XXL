# Data-driven animation binding registry

`assets/animation_bindings.v1.json` is the versioned source of runtime mappings.
Bindings are selected by actor, exact skin object ID, costume, action/event,
variant and context. Each entry also declares its skeleton size, loop policy,
priority, fallback role and legal outgoing transitions. Clip numbers therefore
do not appear in the renderer or gameplay state machine.

The slice extractor copies the registry beside the locally extracted animation
payloads. `SliceAssetPipeline` validates it before producing an
`animation-bindings` ASTPAK resource. Invalid field types, duplicate keys,
missing required states, unknown transition targets and incompatible skeleton
declarations stop the build with a diagnostic instead of selecting a pose.

At load time Metal resolves the seven currently reachable Asterix states for
skin `4`, costume `default` and context `gameplay`. The runtime rejects a
missing or ambiguous mapping and checks the declared 58-node skeleton before
any clip is sampled. Looping is read from the binding rather than inferred from
a state index. `ASTERIX_ANIMATION_REVIEW_CLIP` remains an explicit diagnostic
override and does not change the normal registry.

`graphVersion: 1` extends the same registry with the complete controllable-hero
graph. It contains all 183 confirmed hero clips: 90 for Asterix, 71 for Obelix
and 22 for Idefix. Each clip has an exact actor/skin/costume/action binding, a
stable `clip-NNNN` variant, loop policy, legal outgoing actions and normalized
clip phases. The imported catalogs contain only the confirmed `default`
costume, so no unverified costume fallback is invented; another costume must
add its own exact bindings before it can be selected.

`entryStates` and actor-local `requiredStates` make completeness machine
checkable. Parsing fails when an action is absent, a transition crosses actor
graphs, phase markers are unordered, or a required action is unreachable from
the actor's idle entry. Variant selection is deterministic for the same
selector. `phasesCrossed` exposes windup/impact/recovery, reaction/recovery,
interaction commit and locomotion contact/cycle boundaries to gameplay without
wall-clock timers. The richer versioned event-track transport, including
low-FPS and loop-boundary delivery guarantees, remains task 68.

The seven short Asterix aliases remain in the manifest for the current Metal
renderer. They resolve to the same confirmed clips and allow the renderer to
adopt the full semantic action names incrementally without reintroducing clip
numbers into code.

`characterGraphVersion: 1` adds exact profiles for enemies, leaders, NPC and
animated characters. The checked-in graph covers the confirmed 92 clips and
all 109 dictionary contexts. A profile is keyed by actor, dictionary-backed
skin, costume and runtime context, so clips with the same skeleton size cannot
be selected across archetypes accidentally. Every profile declares its entry,
complete required action set and state/event bindings; validation rejects
missing states, cross-profile transitions, unreachable actions and catalog
totals that drift from the binding list.

Enemy `idle`, `pursuit`/`returning`, `attack`, `stun` and `death` states map to
semantic graph actions. Spawn/perception, hit/knockback, despawn and special
actions are explicit event triggers in the registry. Variant selection combines
the stable entity seed and transition counter, while attack impact uses the
same normalized phase as the gameplay damage window. Rich fixed-tick event
track delivery remains deliberately assigned to task 68.

`worldGraphVersion: 1` adds 13 exact world/UI/FX profiles for all 45 confirmed
clips and 46 dictionary contexts. Every mechanism, shop, activator, checkpoint,
fauna, interface and environmental FX binding has a concrete world/state event,
loop policy, legal transition set and normalized phase. Profiles use
`snapshot-without-replay`: checkpoint/save restore selects the persisted visual
state directly instead of emitting activate, break, collect or respawn effects
again.

The native world-animation runtime consumes monotonically increasing persistent
event sequence numbers. Repeated or stale delivery is ignored, making one-shot
transitions idempotent across fixed ticks and checkpoint restoration. Binding
validation rejects missing event targets, cross-profile transitions,
unreachable states and catalog count drift. Sub-frame event-track sampling is
still owned by task 68.

`cinematicGraphVersion: 1` adds 14 independently addressable scene-data
timelines for all 63 confirmed cinematic contexts / 44 unique clips. A script
event (`script.cinematic.scene-data-N`) starts a timeline; every dictionary
slot is an exact actor/action cue rather than an inferred clip number. Generic
camera, audio and subtitle cues accompany timeline start. Scene data is kept
independent because the imported level proves four `CKCinematicScene` objects
and fourteen `CKCinematicSceneData` owners but does not yet prove a reliable
parent-scene mapping; no story grouping is invented.

The native coordinator supports multiple actor tracks on the same cue and
defines lifecycle behavior explicitly. Starting locks player control; normal
completion and skip apply the terminal state, clear presentation cues, restore
gameplay camera/audio and return control. Interrupt retains the current cue,
checkpoint restore changes state without replaying outputs, resume re-emits the
current actor poses, and a subsequent script event starts again at cue zero.
This makes entrance, exit and in-game timelines deterministic while leaving
sub-frame clip events to task 68.
