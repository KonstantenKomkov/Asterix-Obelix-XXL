#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 GAME_ROOT OUTPUT.astpak [CACHE_DIRECTORY]" >&2
  exit 64
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname -- "$script_dir")
temporary=$(mktemp -d "${TMPDIR:-/tmp}/asterix-assets.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

"$script_dir/extract_slice_proof.sh" "$1" "$temporary/proof"
cd "$repo_root"
if [ "$#" -eq 3 ]; then
  fvm dart run bin/asset_pipeline.dart build-proof "$temporary/proof" "$2" --cache "$3" --force
else
  fvm dart run bin/asset_pipeline.dart build-proof "$temporary/proof" "$2"
fi
