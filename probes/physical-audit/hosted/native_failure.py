"""Project-independent, no-raw-output Xcode error categorizer. Never emits source or paths."""
import json
from pathlib import Path
import re
import sys

MAX_BYTES = 262144
FIXED = {
    "xcbuild-service-ipc": r"could not open connection to build service|unable to initiate PIF transfer session|IPCError|failed to initiate build service|build service connection (?:interrupted|invalidat|failed)|XCBBuildService.*(?:connection|crash)",
    "sandbox-permission-error": r"sandbox-exec:|Sandbox:.*deny\(|Operation not permitted|Permission denied",
    "audit-ui-diagnostic": r"(?:^|[/\\])AuditApp\.swift:[0-9]+(?::[0-9]+)?:\s*(?:fatal )?error:",
    "audit-generated-checks-diagnostic": r"(?:^|[/\\])AuditChecks\.swift:[0-9]+(?::[0-9]+)?:\s*(?:fatal )?error:",
    "audit-generated-production-views-diagnostic": r"(?:^|[/\\])ProductionViews\.swift:[0-9]+(?::[0-9]+)?:\s*(?:fatal )?error:",
    "python-runtime-build-phase": r"(?:PhaseScriptExecution|error:).*Install pinned on-device Python runtime|Pinned stdlib missing|Unrelocated Python extension library",
    "metal-build-resource": r"(?:error|failed).*\b(?:metal|metallib)(?:\b|[_-])",
    "swift-import-or-module": r"no such module|failed to build module|required module.*not found",
    "swift-symbol-resolution": r"cannot find .* in scope|has no member|cannot find type",
    "swift-type-or-protocol": r"type .* does not conform to protocol|cannot convert value of type|cannot convert return expression|generic parameter .* could not be inferred",
    "swift-actor-or-concurrency": r"actor-isolated|nonisolated context|main actor-isolated|Sendable.*unavailable|sending .* risks causing data races",
    "swift-syntax": r"expected (?:declaration|expression|identifier)|consecutive statements on a line|unterminated string literal",
    "swift-compiler-crash": r"Swift compiler error|unable to execute command: Segmentation fault|swift-frontend.*signal",
    "linker": r"Undefined symbols for architecture|linker command failed|library not found|framework not found",
    "build-setting-or-destination": r"unable to find a destination|SDK .* cannot be located|unable to find SDK|not configured to build for",
    "package-graph": r"could not resolve package dependencies|Package\.resolved file is out of date|failed downloading .* artifact|binary target .* not",
    "build-resource-or-project": r"Build input file cannot be found|Multiple commands produce|Unable to open project|does not contain a scheme|PhaseScriptExecution .* failed",
    "disk-space": r"No space left on device|disk quota exceeded",
}


def read_bounded(path):
    if not path.is_file():
        return None
    data_size = path.stat().st_size
    with path.open("rb") as handle:
        if data_size <= MAX_BYTES:
            raw = handle.read(MAX_BYTES)
        else:
            raw = handle.read(MAX_BYTES // 2)
            handle.seek(-MAX_BYTES // 2, 2)
            raw += b"\n" + handle.read(MAX_BYTES // 2)
    return raw.decode("utf-8", errors="replace")


def classify(raw, status):
    if type(status) is not int or not 1 <= status <= 255:
        raise ValueError("Failure exit status required")
    if raw is None:
        return {"exitCode": status, "categories": ["missing-build-log"], "swiftDiagnosticSeen": False}
    categories = [name for name, pattern in FIXED.items() if re.search(pattern, raw, flags=re.IGNORECASE)]
    swift_seen = re.search(r"\.swift:[0-9]+(?::[0-9]+)?:\s*(?:fatal )?error:", raw) is not None
    if swift_seen and not any(k.startswith("swift-") for k in categories):
        categories.append("swift-diagnostic-other")
    return {"exitCode": status, "categories": categories or ["unclassified"], "swiftDiagnosticSeen": swift_seen}


def failure_report(log, status):
    try:
        return classify(read_bounded(log), status)
    except OSError:
        return {"exitCode": status, "categories": ["unreadable-build-log"], "swiftDiagnosticSeen": False}


if __name__ == "__main__":
    status, log = sys.argv[1:]
    print(json.dumps(failure_report(Path(log), int(status)), sort_keys=True))
