"""Exact package-context error templates. Never emit captured text."""
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hosted"))
from native_failure import MAX_BYTES as LIMIT

TEMPLATES = (
    ("manifest-invalid", r"(?:error: )?(?:'[^'\r\n]+': )?[Ii]nvalid manifest(?:(?: \(compiled with: [^\r\n]*\))|(?: \(evaluation failed\)))?"),
    ("sandbox-apply-refused", r"sandbox-exec: sandbox_apply: Operation not permitted"),
    ("sandbox-apply-container-refused", r"sandbox-exec: sandbox_apply_container: Operation not permitted"),
    ("compiler-plugin-not-loaded", r"(?:(?:<unknown>:0: )?(?:error|warning): )?compiler plugin not loaded: '[^'\r\n]+'; failed to initialize"),
    ("output-file-permission", r"(?:error: )?unable to open output file '[^'\r\n]+': '?(?:Operation not permitted|Permission denied)'?"),
)


def identify(raw):
    if raw is None:
        return []
    lines = [line.strip() for line in raw.splitlines() if len(line) <= 65536]
    return [name for name, pattern in TEMPLATES if any(re.fullmatch(pattern, line) for line in lines)]


def observed_templates(path):
    try:
        with path.open("rb") as handle:
            handle.seek(0, 2)
            size = handle.tell()
            handle.seek(0)
            if size <= LIMIT:
                spans = (handle.read(LIMIT),)
            else:
                half = LIMIT // 2
                # Exclude partial lines at both interior truncation boundaries.
                head = handle.read(half).rpartition(b"\n")[0]
                handle.seek(-half - 1, 2)
                previous = handle.read(1)
                tail = handle.read(half)
                if previous != b"\n":
                    tail = tail.partition(b"\n")[2]
                spans = (head, tail)
    except OSError:
        return []
    seen = {name for span in spans for name in identify(span.decode("utf-8", errors="replace"))}
    return [name for name, _ in TEMPLATES if name in seen]


if __name__ == "__main__":
    print(json.dumps({"packageContextTemplates": observed_templates(Path(sys.argv[1]))}, sort_keys=True))
