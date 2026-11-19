"""Exact historical-to-vendored graph migration and bounded CI graph diagnostics."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
HISTORICAL = ROOT / "tests/fixtures/build17-original-Package.resolved"
HISTORICAL_SHA = "ff9369012927524e241f0cf3bcca1a72177947e02ef7933beef716377c87de72"
CANONICAL_SHA = "2d2f397374be883181f421002ba25ef80231dab94ed331d7651bb4ebe68ee5f6"
MIGRATOR_SHA = "0a063c0cda89eb80747c71a1fcbe9220948ad3f779bdb5b20d6e9659d08a0c87"
LIMIT = 262144


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def current_graph(raw):
    migrator = ROOT / "tools/frozen_vendored_graph.py"
    if digest(raw) != HISTORICAL_SHA or digest(migrator.read_bytes()) != MIGRATOR_SHA:
        raise ValueError("Unapproved historical graph or migration implementation")
    sys.path.insert(0, str(ROOT))
    from tools.frozen_vendored_graph import derive, OBSOLETE
    graph = derive(raw)
    old, current = json.loads(raw), json.loads(graph)
    if digest(graph) != CANONICAL_SHA or len(old["pins"]) != 41 or len(current["pins"]) != 40:
        raise ValueError("Expected canonical 40-pin graph")
    if current != {**old, "pins": [p for p in old["pins"] if p != OBSOLETE]}:
        raise ValueError("Canonical graph changed beyond the vendored ONNX migration")
    return graph


def dependencies(spec):
    match = re.search(r"(?ms)^    dependencies:\n(?P<target>.*?)(?=^    settings:)", spec)
    if not match:
        raise ValueError("Dependency anchor changed")
    rows = match.group("target").splitlines()
    remote_and_local = []
    for i, row in enumerate(rows):
        if row.startswith("    - package: "):
            tail = rows[i + 1] if i + 1 < len(rows) and rows[i + 1].startswith("      product: ") else ""
            remote_and_local.append(row + ("\n" + tail if tail else ""))
    if len(remote_and_local) != 3 or {x.splitlines()[0] for x in remote_and_local} != {
        "    - package: ONNXRuntime", "    - package: FluidAudio", "    - package: SpeechSwift",
    }:
        raise ValueError("Package target dependency set changed")
    return remote_and_local


def graph_projection(spec):
    prefix, target, _ = spec.partition("\n  VoiceMatrixPhysicalAudit:\n")
    if not target:
        raise ValueError("Audit target anchor changed")
    prefix, n = re.subn(r"(?m)^  preGenCommand: .+\n", "", prefix)
    if n != 1 or "path: Vendors/ONNXRuntime" not in prefix or "path: Vendors/FluidAudio" not in prefix:
        raise ValueError("Canonical local package dependencies are missing")
    return prefix + target + """    type: application
    platform: iOS
    sources:
    - .physical-audit-src/GraphProbe.swift
    dependencies:
""" + "\n".join(dependencies(spec)) + """
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.voicematrix.physicalaudit
"""


def summary(expected, observed):
    wanted = json.loads(expected)
    base = {"expectedSHA256": digest(expected), "expectedPins": len(wanted["pins"])}
    if observed is None:
        return {**base, "reason": "missing", "observedSHA256": None, "observedPins": None}
    sha = digest(observed)
    try:
        actual = json.loads(observed)
        pin_count = len(actual["pins"])
        if not isinstance(actual["pins"], list):
            raise TypeError
    except (ValueError, TypeError, KeyError):
        return {**base, "reason": "malformed", "observedSHA256": sha, "observedPins": None}
    if observed == expected:
        reason = "canonical-exact"
    elif actual == wanted:
        reason = "semantic-match-byte-drift"
    elif actual["pins"] != wanted["pins"]:
        reason = "pin-mismatch"
    elif actual.get("originHash") != wanted.get("originHash"):
        reason = "origin-hash-mismatch"
    else:
        reason = "other-graph-metadata-mismatch"
    return {**base, "reason": reason, "observedSHA256": sha, "observedPins": pin_count}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=("seed", "projection", "report"))
    p.add_argument("first", type=Path)
    p.add_argument("second", type=Path, nargs="?")
    a = p.parse_args()
    if a.action == "seed":
        with a.first.open("xb") as f:
            f.write(current_graph(HISTORICAL.read_bytes()))
    elif a.action == "projection":
        with a.second.open("x", encoding="utf-8") as f:
            f.write(graph_projection(a.first.read_text()))
    else:
        expected = current_graph(HISTORICAL.read_bytes())
        if a.first.is_file() and a.first.stat().st_size > LIMIT:
            report = {"reason": "oversized", "expectedSHA256": CANONICAL_SHA, "expectedPins": 40,
                      "observedSHA256": None, "observedPins": None}
        else:
            report = summary(expected, a.first.read_bytes() if a.first.is_file() else None)
        print(json.dumps(report, sort_keys=True))
        if report["reason"] != "canonical-exact":
            sys.exit(1)


if __name__ == "__main__":
    main()
