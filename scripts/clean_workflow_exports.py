#!/usr/bin/env python3
"""Strip instance-specific / personal fields from exported n8n workflows (stdlib only).

`n8n export:workflow` embeds the owner project ("shared": name + email) and any
pinned node data ("pinData" — may hold real transcripts from test audio) —
neither may end up in a public repo. Run after every export (`make export` does it).

Usage:
  scripts/clean_workflow_exports.py workflows/*.json
"""
import json
import sys
from pathlib import Path

DROP_KEYS = ("shared",)


def main() -> int:
    for arg in sys.argv[1:]:
        path = Path(arg)
        data = json.loads(path.read_text())
        removed = [k for k in DROP_KEYS if data.pop(k, None) is not None]
        if data.get("pinData"):
            data["pinData"] = {}
            removed.append("pinData")
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        print(f"{path}: removed {removed or 'nothing'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
