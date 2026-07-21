#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 GAME_ROOT" >&2
  exit 64
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
destination="${HOME:?}/Library/Application Support/AsterixXXL/gaul-stage-1.astpak"
cache="${HOME}/Library/Caches/AsterixXXL/asset-pipeline"

mkdir -p "$(dirname -- "$destination")" "$cache"
"$script_dir/build_slice_assets.sh" "$1" "$destination" "$cache"
echo "Installed runtime package at $destination"
