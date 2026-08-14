#!/usr/bin/env python3
"""Compare model-visible structure in two Codex JSONL session files.

This is a read-only, best-effort verifier for an internal, version-sensitive format.
It intentionally ignores outer timestamps, repeated turn-context telemetry, and null-only
serialization differences introduced by a native fork.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


CONTENT_TYPES = ("response_item", "compacted", "world_state")


def without_nulls(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: without_nulls(item) for key, item in value.items() if item is not None}
    if isinstance(value, list):
        return [without_nulls(item) for item in value]
    return value


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        without_nulls(value),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def read_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
            if not isinstance(value, dict):
                raise ValueError(f"{path}:{line_number}: expected a JSON object")
            yield value


def summarize(path: Path, prefix_limits: dict[str, int] | None = None) -> dict[str, Any]:
    hashes = {name: hashlib.sha256() for name in (*CONTENT_TYPES, "task_ids")}
    prefix_hashes = {name: hashlib.sha256() for name in (*CONTENT_TYPES, "task_ids")}
    counts: Counter[str] = Counter()
    semantic_counts: Counter[str] = Counter()
    line_count = 0

    for record in read_jsonl(path):
        line_count += 1
        record_type = str(record.get("type", "<missing>"))
        payload = record.get("payload", {})
        counts[record_type] += 1

        if record_type in CONTENT_TYPES:
            serialized = canonical_bytes(payload)
            hashes[record_type].update(serialized)
            if prefix_limits is not None and semantic_counts[record_type] < prefix_limits[record_type]:
                prefix_hashes[record_type].update(serialized)
            semantic_counts[record_type] += 1

        if record_type == "event_msg" and isinstance(payload, dict):
            event_type = payload.get("type")
            if event_type in ("task_started", "task_complete"):
                marker = f"{event_type}:{payload.get('turn_id')}\n".encode("utf-8")
                hashes["task_ids"].update(marker)
                if prefix_limits is not None and semantic_counts["task_ids"] < prefix_limits["task_ids"]:
                    prefix_hashes["task_ids"].update(marker)
                semantic_counts["task_ids"] += 1

    result = {
        "path": str(path),
        "lines": line_count,
        "bytes": path.stat().st_size,
        "counts": dict(counts),
        "semantic_counts": dict(semantic_counts),
        "semantic_hashes": {name: digest.hexdigest() for name, digest in hashes.items()},
    }
    if prefix_limits is not None:
        result["prefix_hashes"] = {name: digest.hexdigest() for name, digest in prefix_hashes.items()}
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("clone", type=Path)
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    parser.add_argument(
        "--allow-clone-tail",
        action="store_true",
        help="Require the source semantic sequence to be an exact prefix of a continued clone.",
    )
    args = parser.parse_args()

    for path in (args.source, args.clone):
        if not path.is_file():
            parser.error(f"not a file: {path}")

    try:
        source = summarize(args.source)
        clone = summarize(args.clone, source["semantic_counts"])
    except ValueError as exc:
        parser.error(str(exc))

    compared_keys = (*CONTENT_TYPES, "task_ids")
    if args.allow_clone_tail:
        matches = {
            key: (
                clone["semantic_counts"].get(key, 0) >= source["semantic_counts"].get(key, 0)
                and source["semantic_hashes"][key] == clone["prefix_hashes"][key]
            )
            for key in compared_keys
        }
        match_mode = "source-prefix"
    else:
        matches = {
            key: source["semantic_hashes"][key] == clone["semantic_hashes"][key]
            for key in compared_keys
        }
        match_mode = "exact"

    public_clone = {key: value for key, value in clone.items() if key != "prefix_hashes"}
    result = {
        "source": source,
        "clone": public_clone,
        "match_mode": match_mode,
        "matches": matches,
        "passed": all(matches.values()),
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"Source: {source['path']}")
        print(f"Clone:  {clone['path']}")
        print(f"Mode:   {match_mode}")
        for key in compared_keys:
            status = "MATCH" if matches[key] else "DIFF"
            source_count = source["semantic_counts"].get(key, 0)
            clone_count = clone["semantic_counts"].get(key, 0)
            print(f"{status:5} {key:13} source_count={source_count} clone_count={clone_count}")
        print("PASS" if result["passed"] else "FAIL")

    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
