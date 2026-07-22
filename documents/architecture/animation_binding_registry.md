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
