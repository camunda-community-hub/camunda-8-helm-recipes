#!/usr/bin/env python3
"""Generate a Camunda benchmark process-instance payload of an exact target size.

Usage:
  generate-payload.py <target-bytes> [output-file]

Schema matches recipes/benchmark/include/payload.json (var1-var13 + list), with
one extra "padding" field sized to hit the target byte count exactly.

Padding is high-entropy (base64 of os.urandom), not a repeated character. Highly
repetitive padding compresses to near-zero marginal cost under Elasticsearch's
Lucene block compression, which understates real-world storage growth — random,
UUID/hash-like padding is representative of actual variable payloads.
"""
import base64
import json
import os
import sys


def build(padding: str) -> dict:
    return {
        "var1": "value1",
        "var2": True,
        "var3": 15,
        "var4": {"var4-1": "value4-1", "var4-2": False, "var4-3": 111},
        "var5": "736d9100-0155-4af5-be14-b09c42de8417",
        "var6": "b2959d57-d091-42d4-b18c-9e2145b45074",
        "var7": "572c74fa-fb3d-4711-bb76-21d66b87fa86",
        "var8": "d091-42d4-b18c-9e2145b45074-b2959d57",
        "var9": "b18c-9e2145b45074-b2959d57-d091-42d4",
        "var10": "b2959d5742d4-b18c-d091-9e2145b45074",
        "var11": "b18c-9e2145b45074-b2959d57-d091-42d4",
        "var12": 7458,
        "var13": False,
        "list": ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
        "padding": padding,
    }


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    target = int(sys.argv[1])
    out_path = sys.argv[2] if len(sys.argv) > 2 else None

    base_len = len(json.dumps(build(""), indent=2).encode("utf-8"))
    pad_needed = max(0, target - base_len)
    raw_n = max(0, int(pad_needed * 3 / 4))
    padding = base64.b64encode(os.urandom(raw_n)).decode("ascii")

    doc = build(padding)
    data = json.dumps(doc, indent=2)
    diff = target - len(data.encode("utf-8"))
    if diff > 0:
        padding += base64.b64encode(os.urandom(diff)).decode("ascii")[:diff]
    elif diff < 0:
        padding = padding[:diff]
    doc["padding"] = padding
    data = json.dumps(doc, indent=2)

    if out_path:
        with open(out_path, "w") as f:
            f.write(data)
    else:
        sys.stdout.write(data)

    actual = len(data.encode("utf-8"))
    print(f"generated {actual} bytes -> {out_path or '(stdout)'}", file=sys.stderr)


if __name__ == "__main__":
    main()
