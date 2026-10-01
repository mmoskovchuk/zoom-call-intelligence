#!/usr/bin/env python3
"""Summarize an n8n execution read from Postgres (stdlib only).

Prints status, executed nodes, errors and binary metadata — never item JSON,
which may contain private transcripts.

Input (stdin): one line "<id>|<status>|<execution_data.data>", e.g.
  make last-execution
  make test-download   # uses --expect-node

Exit code 1 if the execution is not successful or an expected node did not run.
"""
import argparse
import json
import sys


def unflatten(arr: list):
    """Decode n8n's `flatted` serialization (strings inside objects are indexes into arr)."""
    memo: dict[int, object] = {}

    def resolve(value):
        if isinstance(value, str):
            idx = int(value)
            target = arr[idx]
            if isinstance(target, str):
                return target
            if idx in memo:
                return memo[idx]
            return build(target, idx)
        return build(value, None)

    def build(value, idx):
        if isinstance(value, dict):
            out: dict = {}
            if idx is not None:
                memo[idx] = out
            out.update({k: resolve(v) for k, v in value.items()})
            return out
        if isinstance(value, list):
            out_list: list = []
            if idx is not None:
                memo[idx] = out_list
            out_list.extend(resolve(v) for v in value)
            return out_list
        return value

    return build(arr[0], 0)


def shape(value, indent: str = "    ") -> list[str]:
    """Describe structure without revealing content: keys, types, string lengths, array sizes."""
    lines = []
    if isinstance(value, dict):
        for key, sub in value.items():
            if isinstance(sub, (dict, list)):
                size = f"[{len(sub)}]" if isinstance(sub, list) else ""
                lines.append(f"{indent}{key}: {type(sub).__name__}{size}")
                first = sub[0] if isinstance(sub, list) and sub else sub
                if isinstance(first, (dict, list)) and first:
                    lines.extend(shape(first, indent + "  "))
            elif isinstance(sub, str):
                lines.append(f"{indent}{key}: str({len(sub)})")
            else:
                lines.append(f"{indent}{key}: {type(sub).__name__}")
    elif isinstance(value, list) and value:
        lines.extend(shape(value[0], indent))
    return lines


def first_item_json(run_data: dict, node: str) -> dict:
    runs = run_data.get(node) or [{}]
    outputs = (runs[-1].get("data") or {}).get("main") or [[]]
    return ((outputs[0] or [{}])[0]).get("json") or {}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expect-node", action="append", default=[])
    parser.add_argument(
        "--text-stats",
        metavar="NODE",
        help="print length/word count of json.text from NODE (content itself is never printed)",
    )
    parser.add_argument(
        "--shape",
        metavar="NODE",
        help="print the structure (keys, types, lengths) of NODE's first output item — no values",
    )
    args = parser.parse_args()

    line = sys.stdin.read().strip()
    if not line:
        print("no executions found")
        return 1
    exec_id, status, raw = line.split("|", 2)
    result = unflatten(json.loads(raw)).get("resultData", {})
    run_data = result.get("runData", {})

    print(f"execution {exec_id}: {status}")
    for node, runs in run_data.items():
        run = runs[-1]
        mark = "✗" if run.get("error") else "✓"
        details = []
        for output in (run.get("data") or {}).get("main") or []:
            for item in output or []:
                for prop, meta in (item.get("binary") or {}).items():
                    details.append(
                        f"binary '{prop}': {meta.get('fileName')} {meta.get('mimeType')} {meta.get('fileSize')}"
                    )
        print(f"  {mark} {node}" + (f"  [{'; '.join(details)}]" if details else ""))
        if run.get("error"):
            print(f"      error: {run['error'].get('message')}")

    ok = status == "success"
    if args.shape:
        print(f"shape of '{args.shape}' output (no values):")
        print("\n".join(shape(first_item_json(run_data, args.shape))) or "    (empty)")
    if args.text_stats:
        text = first_item_json(run_data, args.text_stats).get("text")
        if isinstance(text, str) and text.strip():
            print(f"text from '{args.text_stats}': {len(text)} chars, {len(text.split())} words")
        else:
            print(f"no json.text in '{args.text_stats}'")
            ok = False
    for node in args.expect_node:
        if node not in run_data:
            print(f"expected node did not run: {node}")
            ok = False
    print("OK" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
