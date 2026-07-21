# macOS bridge

The AppKit/`MTKView` bridge lives in this directory. `macos/Runner` remains the
thin Swift composition layer and calls into this bridge instead of owning
runtime state.
