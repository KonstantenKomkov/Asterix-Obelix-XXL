# Scene graph and section streaming

**Status:** verified on 21 July 2026.

The C++20 runtime in `engine/include/asterix/scene_runtime.hpp` owns the
renderer-independent scene model. It resolves local transforms into world
transforms in parent-first order and rejects duplicate IDs, missing parents and
cycles. The asset pipeline records the roles of `parent`, `child` and `next`
references in scene-node metadata instead of exposing them only as untyped
dependencies.

Each section has bounds and requested/resident state. A preload frustum requests
sections before they enter the render frustum; sections outside it remain alive
for a configurable grace period (120 frames by default), avoiding churn around
boundaries. Package parsing and Metal upload run away from the main/UI thread.
Prepared buffers, textures, mesh ranges and the runtime graph are then published
as one synchronized resource generation. A submitted Metal command buffer keeps
its generation alive until GPU completion, while a later load may safely replace
the renderer's current generation.

Per frame, world-space mesh AABBs are tested against six normalized frustum
planes. Visible items select full geometry or the initial distance LOD, are
stable-sorted by material/LOD, and are emitted in batches. The current importer
proof contains one Gaul sector, but the runtime and eviction policy accept any
number of sections. The HUD transport exposes loaded, visible, batch and resident
counts for later debug UI work in task 31.

Native tests cover hierarchy composition and cycles, section request/eviction,
frustum rejection, material/LOD batching and reduced LOD counts. A deterministic
moving-frustum regression traverses 381 synthetic meshes for 600 frames and
requires every selection update to remain below a 16 ms frame budget. No
original or derived game resources are stored in the test or repository.

Materials, transparency, lighting, fog and authored mesh simplification remain
task 28. The first LOD deliberately uses a triangle-aligned prefix of expanded
static geometry; it proves the runtime selection path without inventing source
content or blocking later authored/generated LOD payloads.
