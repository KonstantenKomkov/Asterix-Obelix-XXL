#!/usr/bin/env bash

set -euo pipefail

readonly forbidden_pattern='(^|/)(original_data|assets_generated)(/|$)|\.(exe|dll|kwn|rws|sav|mdf|mds|iso)$'

check_paths() {
  local scope="$1"
  local paths="$2"
  local matches

  matches="$(printf '%s\n' "$paths" | grep -Ei "$forbidden_pattern" || true)"
  if [[ -n "$matches" ]]; then
    printf 'Resource policy violation in %s:\n%s\n' "$scope" "$matches" >&2
    return 1
  fi
}

tracked_paths="$(git ls-files)"
history_paths="$(git log --all --format= --name-only | sed '/^$/d' | sort -u)"

check_paths 'tracked files' "$tracked_paths"
check_paths 'Git history' "$history_paths"

printf 'Resource policy check passed.\n'
