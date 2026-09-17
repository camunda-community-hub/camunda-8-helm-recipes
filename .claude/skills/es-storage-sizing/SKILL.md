---
name: es-storage-sizing
description: Measure how much Elasticsearch storage a Camunda 8 deployment consumes per process instance, as a function of process-variable payload size — for answering customer capacity-planning questions. Use when asked to estimate ES disk usage, benchmark storage overhead, or size a cluster's ES/OpenSearch footprint against expected instance volume and payload size.
---

# ES storage sizing

Empirically measures Elasticsearch storage growth per completed process instance
on a live Camunda 8 cluster, at one or more payload sizes, then fits a
fixed-overhead + marginal-rate model:

```
bytes_per_instance = intercept + slope × payload_bytes
```

This lets you answer "how much ES storage will N instances/day at payload size X
consume" for a customer, backed by a real measurement on their (or a representative)
cluster rather than a guess.

## How it works

1. Snapshot the size of Camunda's ES indices (`operate-*`, `tasklist-*`) and the
   count of completed process instances.
2. Run the `camunda-8-benchmark` load-generation tool against the cluster for a
   fixed window, using a payload of a known byte size, targeting an
   **already-deployed** process.
3. Let in-flight instances drain, tear the benchmark tool down, let Elasticsearch
   settle (flush + force-merge to 1 segment — otherwise Lucene segment-compaction
   state biases the size comparison).
4. Snapshot again and diff: `(ES bytes added) / (instances completed)` gives
   per-instance storage cost at that payload size.
5. Repeat at 2-4 different payload sizes (e.g. 1KB, 5KB, 10KB, 20KB) and fit a
   line through the results to separate the fixed per-instance overhead (workflow
   history, flow-node/variable documents, indices overhead) from the marginal
   cost of payload bytes.

## Prerequisites

- `kubectl` context pointed at the target cluster, with access to the namespace
  Camunda is installed in and the Elasticsearch pod within it.
- `jq`, `awk`, `python3` on PATH.
- A recipe directory with a working benchmark setup — i.e. one of this repo's
  `recipes/*/` directories that has a sibling `recipes/benchmark/` with `Makefile`,
  `config.mk`, and `include/benchmark-oidc.yaml` (every recipe under `recipes/camunda/`
  does). You'll point `BENCHMARK_DIR` at that `recipes/benchmark/` directory.
- **A process already deployed to Zeebe**, matching `BENCHMARK_BPMN_PROCESS_ID` in
  that recipe's `config.mk`. See the warning below — do not rely on the benchmark
  tool's auto-deploy.
- The Helm release's benchmark OIDC client must be authorized to start/complete
  process instances. If you see `FORBIDDEN: Insufficient permissions ... RESOURCE`,
  grant it via the chart's Identity-as-Code mechanism in the recipe's
  `my-camunda-values.yaml`:
  ```yaml
  orchestration:
    security:
      initialization:
        authorizations:
          - ownerType: ROLE
            ownerId: connectors          # or whatever BENCHMARK_CLIENT_ID's role is
            resourceType: RESOURCE
            resourceId: "*"
            permissions:
              - CREATE
              - READ
  ```
  then `make camunda-values.yaml && make install-camunda` (editing `my-camunda-values.yaml`
  alone does nothing — `make camunda` does not regenerate the merged values file).

### Known bug: never use `autoDeployProcess=true`

The community `camunda-8-benchmark` tool (`camundacommunityhub/camunda-8-benchmark:main`)
has a bug where deploying a process via its own auto-deploy path corrupts a shared
classpath resource stream, which later crashes job-worker registration with an
uncaught `SAXException` in the main thread — instances start but their jobs never
get picked up, so nothing ever completes. `benchmark-oidc.yaml` in this skill hardcodes
`-Dbenchmark.autoDeployProcess=false`; keep it that way. Always point
`BENCHMARK_BPMN_PROCESS_ID` at a process deployed some other way (Modeler, `zbctl`,
Console).

## Usage

```bash
export BENCHMARK_DIR=/Users/dave/code/camunda-8-helm-recipes/recipes/benchmark

# 300s load window, payload auto-generated to exactly 10240 bytes
PAYLOAD_SIZE_BYTES=10240 \
  .claude/skills/es-storage-sizing/scripts/run-es-storage-test.sh 300 10kb-run1

# Or with a specific payload file
PAYLOAD_FILE=/path/to/payload.json \
  .claude/skills/es-storage-sizing/scripts/run-es-storage-test.sh 300 custom-run1
```

Run this 2-4 times at different `PAYLOAD_SIZE_BYTES` values (a good spread:
~500B, ~1-2KB, ~10KB, ~20KB) with distinct labels. Results land in
`$BENCHMARK_DIR/es-storage-results/<label>-{before,after}.{indices.json,completed,active}`.

Each run prints a report ending in:

```
Per-instance ES bytes (primaries) : NNNNN bytes  (payload was NNNN bytes/instance)
Per-instance ES bytes (total)     : NNNNN bytes
Expansion ratio, primaries only   : N.NNx (NNN%)
Expansion ratio, incl. replicas   : N.NNx (NNN%)
```

Collect these across runs, then fit `bytes_per_instance = intercept + slope × payload_bytes`
via least-squares over the (payload_bytes, per-instance-bytes) pairs — separately
for primaries and primaries+replicas — and report R² alongside it.

### Reusable sub-commands

`scripts/es-storage-report.sh` also works standalone if you need to recover from an
interrupted run (e.g. the load step got killed mid-sleep) without repeating the
whole 300s window:

```bash
export ES_REPORT_DIR=$BENCHMARK_DIR/es-storage-results
export BENCHMARK_NAMESPACE=camunda CAMUNDA_RELEASE_NAME=camunda
.claude/skills/es-storage-sizing/scripts/es-storage-report.sh settle
.claude/skills/es-storage-sizing/scripts/es-storage-report.sh snapshot <label>-after
.claude/skills/es-storage-sizing/scripts/es-storage-report.sh diff <label>-before <label>-after <payload-bytes>
```

## Methodology notes / caveats to carry into any report

- **Force-merge before every snapshot.** Without normalizing segment state, Lucene
  compaction noise can swamp the actual delta, especially at small payload sizes.
- **Use high-entropy padding**, not a repeated character, when generating payloads
  (this is what `generate-payload.py` does). Repetitive content compresses far
  better than real variable data (UUIDs, hashes, free text) and understates
  storage growth — this was measured directly: a repeated-character 5KB payload
  produced a *lower* per-instance byte count than a 1KB payload.
- **`operate-list-view-*` is a joined index** (processInstance + activity + variable
  docs share it via a `joinRelation` field). Any custom query for "active" or
  "completed" counts must filter on `joinRelation:processInstance`, or
  activity/variable docs (which have `state: null`) will inflate an "active" count
  by orders of magnitude. `es-storage-report.sh` already does this correctly.
- **A handful of in-flight instances per run will not drain** within the wait
  window and become a small, known noise source — this is normal and reported as
  a warning, not a failure.
- **Don't trust a single run's regression fit as a firm capacity commitment.**
  Ratios are not always perfectly monotonic run-to-run (single-run noise); repeat
  runs at each size before quoting numbers a customer will hold you to.
- The report should distinguish **primaries-only** delta (actual disk cost) from
  **primaries+replicas** delta (cluster-wide storage budget) — customers usually
  want the replicated total for capacity planning, but the primaries number is the
  cleaner "true cost per instance" figure.
