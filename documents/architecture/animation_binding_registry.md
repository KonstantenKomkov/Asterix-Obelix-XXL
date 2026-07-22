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

The registry deliberately covers only states reachable before task 64. Later
animation graphs may add actors, costumes, variants and event bindings without
changing renderer code or the schema; `requiredStates` should be expanded with
each graph so incomplete content fails during packaging.
