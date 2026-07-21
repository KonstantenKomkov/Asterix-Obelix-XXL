# Imported static scene in Metal

**Status:** verified on 21 July 2026.

`AsterixMetalRenderer` loads ASTPAK 1.0 directly from a local path passed with
`ASTERIX_ASSET_PACKAGE`. The loader validates fixed container ranges, reads the
canonical manifest, creates one Metal buffer containing every mesh resource,
normalizes
scene-node affine transforms, uploads ASTMTEX mip levels as `rgba8Unorm`, and
draws the scene through the existing 70-degree perspective camera and
`Depth32Float` buffer. A package path starts the application directly in the
game viewport; the normal build still opens the main menu and proof triangle.

The local Gaul `STR01_00` package is not stored in Git. It contained 381 mesh
resources and 818 total resources. A profile run at 800×600 logical / 1600×1200
physical pixels displayed the recognizable sector silhouette and textured
surfaces at 60.0 FPS; a representative HUD snapshot reported CPU 0.07–0.10 ms,
GPU 0.18 ms, and 64.9 MiB Metal allocation. Geometry placement and orientation
were compared with the task 14 visual/collision overlay and the task 4 Gaul
reference capture. Per-material draw batching, lighting, transparency, fog,
and effects remain task 28 work.

Run with a package copied to an app-readable location:

```sh
make run-profile ASSET_PACKAGE=/absolute/path/to/gaul-stage-1.astpak
```

The HUD reports the loaded mesh count or a controlled configuration/load error.
