#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Inventory explicit Pascal heap calls in the editor's local unit closure.

This is review evidence, not a proof of control flow or allocation safety.
Conditional branches are included conservatively. RTL internals are outside
this source inventory; the compiler archive is pinned by the build manifest.
"""

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKEN = re.compile(r"\{.*?\}|\(\*.*?\*\)|//[^\n]*|'(?:[^']|'')*'", re.DOTALL)


def code_only(source):
    # Preserve offsets/newlines for source locations while masking comments and
    # strings. Keep all conditional branches instead of guessing compiler flags.
    return TOKEN.sub(lambda m: re.sub(r"[^\r\n]", " ", m.group()), source)


def inventory():
    units = {}
    files = []
    for directory in (ROOT / "SRC", ROOT / "vendor/system2"):
        for path in sorted(directory.iterdir()):
            if path.suffix.lower() != ".pas":
                continue
            source = path.read_bytes().decode("latin1")
            code = code_only(source)
            declaration = re.search(r"\bunit\s+(\w+)\s*;", code, re.IGNORECASE)
            if declaration:
                units.setdefault(declaration[1].lower(), path)
            files.append(path)
    pending = [ROOT / "SRC/DWEDOVL.PAS"]
    visited = set()
    external = set()
    graph = {}
    sites = []
    sources = {}
    while pending:
        path = pending.pop()
        if path in visited:
            continue
        visited.add(path)
        raw = path.read_bytes()
        source = raw.decode("latin1")
        code = code_only(source)
        name = str(path.relative_to(ROOT))
        sources[name] = hashlib.sha256(raw).hexdigest()
        dependencies = []
        for clause in re.finditer(r"\buses\s+([^;]+);", code, re.IGNORECASE):
            for unit in re.findall(r"\b\w+\b", clause[1]):
                unit = unit.lower()
                dependencies.append(unit)
                if unit in units:
                    pending.append(units[unit])
                else:
                    external.add(unit)
        graph[name] = sorted(set(dependencies))
        for call in re.finditer(
            r"\b(getmem|allocmem|reallocmem|new)\s*\(", code, re.IGNORECASE
        ):
            declarations = list(
                re.finditer(
                    r"\b(?:function|procedure)\s+(\w+)",
                    code[: call.start()],
                    re.IGNORECASE,
                )
            )
            line = source.count("\n", 0, call.start()) + 1
            lines = source.splitlines()
            sites.append(
                {
                    "path": name,
                    "line": line,
                    "allocator": call[1].lower(),
                    "preceding_routine_declaration": declarations[-1][1]
                    if declarations
                    else None,
                    "context_start_line": max(1, line - 12),
                    "context": lines[max(0, line - 13) : line + 4],
                }
            )
    return {
        "scope": "Explicit Pascal heap calls in the conservative local uses closure of SRC/DWEDOVL.PAS",
        "limitations": [
            "Not a call-graph or guard verifier",
            "Includes inactive conditional branches and unused routines in reachable units",
            "Excludes compiler RTL internals, DOS/EMS/XMS allocation APIs and assembly instructions",
        ],
        "source_sha256": dict(sorted(sources.items())),
        "unit_dependencies": dict(sorted(graph.items())),
        "external_units": sorted(external),
        "outside_local_unit_closure": sorted(
            str(p.relative_to(ROOT)) for p in files if p not in visited
        ),
        "heap_calls": sorted(sites, key=lambda s: (s["path"], s["line"])),
        "heap_call_count": len(sites),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", type=Path, help="reject stale review inventory")
    args = parser.parse_args()
    result = inventory()
    if args.check:
        if json.loads(args.check.read_text()) != result:
            raise SystemExit("Allocation inventory changed; repeat the source review.")
        print("Allocation inventory matches reviewed source snapshot.")
    elif args.output:
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    else:
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
