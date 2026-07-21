# Metal renderer

Metal shaders and Objective-C++ renderer sources live in this directory. The
renderer target is introduced when the `MTKView` integration starts; the
platform-neutral native core must not import Metal types.
