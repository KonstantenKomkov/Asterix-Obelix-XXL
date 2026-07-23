#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 GAME_ROOT OUTPUT_DIRECTORY" >&2
  exit 64
fi

game_root=${1%/}
output=${2%/}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname -- "$script_dir")

level="$game_root/LVL001/LVL01.KWN"
module="$game_root/GameModule.elb"
audio="$game_root/LVL001/WINAS/WINAS8.rws"

for input in "$level" "$module" "$audio"; do
  if [ ! -f "$input" ]; then
    echo "required input does not exist: $input" >&2
    exit 66
  fi
done
if [ -e "$output" ]; then
  echo "output path already exists: $output" >&2
  exit 73
fi

mkdir -p "$output"
cd "$repo_root"
for suffix in 00 01 02 03 04; do
  sector="$game_root/LVL001/STR01_$suffix.KWN"
  if [ ! -f "$sector" ]; then
    echo "required input does not exist: $sector" >&2
    exit 66
  fi
  sector_output="$output/sectors/STR01_$suffix"
  mkdir -p "$sector_output"
  fvm dart run bin/importer.dart extract-geometry "$sector" > "$sector_output/scene.json"
  fvm dart run bin/importer.dart extract-collision "$sector" "$sector_output/collision.json"
  rm -f "$sector_output/collision.overlay.svg"
  fvm dart run bin/importer.dart extract-textures "$sector" "$sector_output/textures"
done
fvm dart run bin/importer.dart extract-level-textures "$level" "$module" "$output/textures"
fvm dart run bin/importer.dart extract-animations "$level" "$module" "$output/animations"
fvm dart run bin/importer.dart extract-push-pull "$level" "$module" "$output/push_pull.json"
fvm dart run bin/importer.dart extract-checkpoint "$level" "$module" "$output/checkpoint.json"
fvm dart run bin/importer.dart extract-level-collision "$level" "$module" "$output/level_collision.json"
fvm dart run bin/importer.dart extract-water-surfaces "$level" "$module" "$output/water_surfaces.json"
cp "$repo_root/assets/animation_bindings.v1.json" "$output/animations/bindings.json"
cp "$repo_root/assets/animation_graphs/asterix.authored-graph.v1.json" \
  "$output/animations/asterix.authored-graph.v1.json"
cp "$repo_root/assets/animation_graphs/actors.authored-graphs.v1.json" \
  "$output/animations/actors.authored-graphs.v1.json"
cp "$repo_root/assets/render_composition_overrides.v1.json" "$output/animations/composition_overrides.json"
fvm dart run bin/importer.dart decode-rws "$audio" "$output/audio.wav"

printf '%s\n' \
  '{' \
  '  "schemaVersion": 2,' \
  '  "slice": "gaul-stage-1",' \
  '  "sectors": [' \
  '    {"source": "LVL001/STR01_00.KWN", "directory": "sectors/STR01_00"},' \
  '    {"source": "LVL001/STR01_01.KWN", "directory": "sectors/STR01_01"},' \
  '    {"source": "LVL001/STR01_02.KWN", "directory": "sectors/STR01_02"},' \
  '    {"source": "LVL001/STR01_03.KWN", "directory": "sectors/STR01_03"},' \
  '    {"source": "LVL001/STR01_04.KWN", "directory": "sectors/STR01_04"}' \
  '  ],' \
  '  "sourceFiles": ["LVL001/STR01_00.KWN", "LVL001/STR01_01.KWN", "LVL001/STR01_02.KWN", "LVL001/STR01_03.KWN", "LVL001/STR01_04.KWN", "LVL001/LVL01.KWN", "GameModule.elb", "LVL001/WINAS/WINAS8.rws"],' \
  '  "outputs": {' \
  '    "textures": "textures/manifest.json",' \
  '    "animations": "animations/manifest.json",' \
  '    "pushPull": "push_pull.json",' \
  '    "checkpoint": "checkpoint.json",' \
  '    "levelCollision": "level_collision.json",' \
  '    "waterSurfaces": "water_surfaces.json",' \
  '    "audio": "audio.wav"' \
  '  }' \
  '}' > "$output/manifest.json"

echo "Importer proof written to $output"
