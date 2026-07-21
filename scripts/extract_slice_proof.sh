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

sector="$game_root/LVL001/STR01_00.KWN"
level="$game_root/LVL001/LVL01.KWN"
module="$game_root/GameModule.elb"
audio="$game_root/LVL001/WINAS/WINAS8.rws"

for input in "$sector" "$level" "$module" "$audio"; do
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
fvm dart run bin/importer.dart extract-geometry "$sector" > "$output/scene.json"
fvm dart run bin/importer.dart extract-collision "$sector" "$output/collision.json"
rm -f "$output/collision.overlay.svg"
fvm dart run bin/importer.dart extract-textures "$sector" "$output/textures"
fvm dart run bin/importer.dart extract-animations "$level" "$module" "$output/animations"
fvm dart run bin/importer.dart decode-rws "$audio" "$output/audio.wav"

printf '%s\n' \
  '{' \
  '  "schemaVersion": 1,' \
  '  "slice": "gaul-stage-1",' \
  '  "sourceFiles": ["LVL001/STR01_00.KWN", "LVL001/LVL01.KWN", "GameModule.elb", "LVL001/WINAS/WINAS8.rws"],' \
  '  "outputs": {' \
  '    "scene": "scene.json",' \
  '    "collision": "collision.json",' \
  '    "textures": "textures/manifest.json",' \
  '    "animations": "animations/manifest.json",' \
  '    "audio": "audio.wav"' \
  '  }' \
  '}' > "$output/manifest.json"

echo "Importer proof written to $output"
