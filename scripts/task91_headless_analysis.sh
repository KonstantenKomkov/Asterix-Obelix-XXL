#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 GAME_DIR WORKSPACE" >&2
  exit 2
fi

readonly game_dir="$(cd "$1" && pwd)"
readonly workspace="$2"
readonly script_dir="$(cd "$(dirname "$0")/ghidra" && pwd)"
readonly repo_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -e "$workspace" ]]; then
  echo "WORKSPACE must not exist; the analysis always starts from scratch: $workspace" >&2
  exit 2
fi

mkdir -p "$workspace/projects" "$workspace/exports"
python3 "$(dirname "$0")/task91_corpus.py" \
  "$game_dir" "$workspace/corpus.json"
python3 - "$workspace/corpus.json" "$repo_root/tools/task91/toolchain.v1.json" <<'PY'
import json
import sys

corpus = json.load(open(sys.argv[1], encoding="utf-8"))
config = json.load(open(sys.argv[2], encoding="utf-8"))
actual = {item["path"]: item["sha256"] for item in corpus["modules"]}
if actual != config["expectedModules"]:
    raise SystemExit("binary identity does not match task 91.1 corpus")
if corpus["summary"]["dataFileCount"] != config["expectedKwnCount"]:
    raise SystemExit("KWN count does not match task 91.1 corpus")
PY

if [[ "${TASK91_ANALYZER:-metadata}" == "metadata" ]]; then
  python3 - "$workspace" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
corpus = json.loads((root / "corpus.json").read_text(encoding="utf-8"))
for module in corpus["modules"]:
    report = {
        "format": "task91-metadata-v1",
        "imageBase": module["imageBase"],
        "language": "x86:LE:32:default",
        "sha256": module["sha256"],
    }
    output = root / "exports" / f"{module['path']}.json"
    output.write_text(json.dumps(report, sort_keys=True) + "\n", encoding="utf-8")
PY
elif [[ "$TASK91_ANALYZER" == "ghidra" ]]; then
  if [[ -n "${GHIDRA_HOME:-}" ]]; then
    analyze_headless="$GHIDRA_HOME/support/analyzeHeadless"
  elif command -v analyzeHeadless >/dev/null 2>&1; then
    analyze_headless="$(command -v analyzeHeadless)"
  else
    analyze_headless="$(find /Applications /opt/homebrew/Cellar/ghidra \
      -type f -path '*/support/analyzeHeadless' -perm -111 -print -quit 2>/dev/null || true)"
  fi
  if [[ -z "$analyze_headless" || ! -x "$analyze_headless" ]]; then
    echo "Set GHIDRA_HOME to Ghidra 12.1.2" >&2
    exit 2
  fi
  ghidra_root="$(cd "$(dirname "$analyze_headless")/.." && pwd)"
  if ! grep -Eq '^application\.version=12\.1\.2$' \
      "$ghidra_root/Ghidra/application.properties"; then
    echo "Task 91.1 requires Ghidra 12.1.2" >&2
    exit 2
  fi
  java_binary="${JAVA_HOME:+$JAVA_HOME/bin/}java"
  if ! "$java_binary" -version 2>&1 | head -1 | grep -Eq '"21(\.|")'; then
    echo "Task 91.1 requires OpenJDK 21" >&2
    exit 2
  fi
  for module in Asterix.exe GameModule.elb; do
    project_name="${module//./_}"
    "$analyze_headless" "$workspace/projects" "$project_name" \
      -import "$game_dir/$module" \
      -processor x86:LE:32:default \
      -cspec windows \
      -analysisTimeoutPerFile 1800 \
      -scriptPath "$script_dir" \
      -postScript ExportTask91Summary.java "$workspace/exports/$module.json"
  done
else
  echo "TASK91_ANALYZER must be metadata or ghidra" >&2
  exit 2
fi

python3 "$(dirname "$0")/task91_verify_replay.py" "$workspace"
