#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
output_dir="$project_root/build/native_ffi"
mkdir -p "$output_dir"

xcrun clang++ \
  -std=c++20 \
  -dynamiclib \
  -fvisibility=default \
  -I "$project_root/engine/include" \
  "$project_root/engine/src/engine.cpp" \
  -o "$output_dir/libasterix_engine.dylib"
