# Metal renderer

Metal shaders and Objective-C++ renderer sources live in this directory. The
renderer target is introduced when the `MTKView` integration starts; the
platform-neutral native core must not import Metal types. The M2 triangle,
camera, depth buffer and HUD statistics proof is documented in
[`documents/architecture/metal_scene_proof.md`](../../documents/architecture/metal_scene_proof.md).
