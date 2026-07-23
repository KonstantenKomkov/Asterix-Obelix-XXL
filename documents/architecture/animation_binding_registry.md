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

At load time Metal resolves complete controllable-hero graphs through versioned
runtime profiles. `asterix-player` contains 90 bindings: eight stable automatic
locomotion/combat states and 82 exact source dictionary-slot entry points.
`obelix-player` contains all 72 gameplay bindings: stable idle, run, attack,
hurt and death states plus 67 exact `hero_slot_N` event entry points covering
directional locomotion, idle variants, combo/contextual attacks, airborne
damage and recovery, interaction, ledge, water and swim.
`idefix-player` contains all 28 gameplay bindings: stable idle, run and death
states plus 25 exact `hero_slot_N` entry points for directional locomotion,
idle variants, attacks, interactions and swim.
Enemy runtime uses three complete actor-instance profiles:
`basic-roman-enemy` selects all 41 dictionary-48 bindings,
`roman-leader-equipment` selects all 41 dictionary-27 bindings and
`roman-leader-body` selects all three dictionary-28 bindings. The two leader
profiles are one authored render composition (body skin 28 plus equipment skin
27); they are validated together and cannot substitute skeletons across
profiles. Entity seed and animation transition produce a deterministic variant
index for idle, perception/pursuit/return, attack, hit/stun/knockback, special
and death/despawn events.

Twenty-four `scripted-dictionary-N` profiles bind every animated-character and
cinematic-scene dictionary owner to one concrete scene instance, unique
`script.character.dictionary-N` event and exact authored selector. The native
scripted-character coordinator records a monotonically increasing event
sequence and explicit playing/interrupted/complete state. Completion and
interrupt restore the prior actor pose; checkpoint restore changes the state
without emitting the one-shot again. The two cinematic-scene dictionary owners
remain independent instances and are not folded into scene-data timelines.

Every state selects one exact semantic binding by actor, skin, costume, context,
action and variant. Reused authored clips remain separate selectors when the
source slots have different semantic actions; notably Obelix clip 0151 resolves
independently as `combat.attack` and `combat.attack-variant`, while Idefix clips
0176, 0184, 0187 and 0190 retain their distinct state/event meanings. A profile marked
`complete` is accepted only when it selects every matching binding exactly
once. Registry and Metal reject missing, duplicate, fallback, ambiguous or
incompatible 58-node hero / 31-node Idefix / 28- or 30-node Roman selectors
before sampling. Looping, phases, transitions, root
motion and animation events are read from binding data rather than inferred
from a state index.
`ASTERIX_ANIMATION_REVIEW_CLIP` remains an explicit diagnostic override and
does not change the normal registry.

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

The old short Asterix aliases are not part of the registry. Gameplay enum and
source-slot event names are mapped to semantic actions only by
`runtimeProfiles`; clip IDs remain in data and do not appear in the renderer or
gameplay state machine. `resolveRuntimeState` is the shared strict entry point
used by scenario tests and higher-level event orchestration.

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

Thirteen complete `world-dictionary-N` runtime profiles bind those contexts to
exact dictionary-slot selectors. Event-to-state lists preserve simultaneous
tracks, including both authored kiosk transaction slots. The native
world-animation runtime consumes monotonically increasing persistent sequence
numbers and returns selector playback data with authored loop/clamp, commit
phase and object/material/particle synchronization. Repeated or stale delivery
is ignored; checkpoint restore applies the selector snapshot without emitting
one-shot side effects.

Registry and Metal require all 13 profiles and 46 selectors and reject missing,
duplicate, ambiguous, fallback, cross-trigger or incomplete profiles. The
world graph still owns legal transitions, while versioned event tracks deliver
sub-frame object-state commits.

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
sub-frame clip events to the shared transport below.

## Versioned animation events

`eventTrackVersion: 1` defines typed, ordered events against exact
actor/action/context bindings. Gameplay windows, impulses/root motion, object
state commits, VFX/SFX, camera cues, footsteps and one-shot completion are no
longer inferred from unrelated wall-clock timers. A non-looping track must end
with an explicit `one-shot-complete` event.

The native sampler advances an absolute fixed-tick phase and samples the
half-open interval `(previous, current]`. It enumerates every crossed loop, so a
low render frame rate cannot drop events at a loop boundary. Delivery identity
is `track:instance:loop:event`; the same clip instance sampled by both branches
of a blend therefore emits once. Pause does not advance the cursor, and a save
stores the instance and absolute phase; restore resumes without replaying
already delivered side effects. Manifest validation rejects unknown bindings,
unordered/duplicate events, unsupported types and one-shots without completion.

## End-to-end acceptance

Task 69 adds a dataset-specific gate which joins the confirmed local catalog,
all dictionary memberships and this registry by exact animation filename. It
also derives a verified selection path for every binding from hero entry
graphs, character states/events, world events or cinematic script cues. The
machine-readable report must cover exactly 345 catalog clips and report zero
unbound, unexplained, unreachable or unknown clips. Representative visual
sequence metadata is versioned separately; original captures and extracted
animation payloads remain local. See
`documents/gameplay/animation_binding_acceptance.md` for the reproducible
command and accepted report digest.
