#!/usr/bin/env python3

import hashlib
import json
import sys
from pathlib import Path


def main() -> int:
    root = Path(sys.argv[1])
    corpus = json.loads((root / "corpus.json").read_text(encoding="utf-8"))
    exports = []
    for module in corpus["modules"]:
        path = root / "exports" / f"{module['path']}.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        if report["sha256"] != module["sha256"]:
            raise SystemExit(f"identity mismatch for {module['path']}")
        exports.append(report)
    canonical = json.dumps(exports, sort_keys=True, separators=(",", ":")).encode()
    digest = hashlib.sha256(canonical).hexdigest()
    (root / "analysis.sha256").write_text(digest + "\n", encoding="ascii")
    print(f"Headless analysis verified: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
