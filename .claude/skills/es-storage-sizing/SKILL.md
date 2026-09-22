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

1. Snapshot the size of Camunda's ES indices and the count of completed process
   instances. Two categories are tracked **separately** as well as combined:
   - **Orchestration cluster**: `operate-*` / `tasklist-*` (a curated list of the
     families that actually scale with instance volume — see `es-storage-report.sh`).
   - **Optimize**: `optimize-*` (all of it — see the caveat below).
2. Run the `camunda-8-benchmark` load-generation tool against the cluster for a
   fixed window, using a payload of a known byte size, targeting an
   **already-deployed** process.
3. Let in-flight instances drain, tear the benchmark tool down, let Elasticsearch
   settle (flush + force-merge to 1 segment on every tracked index, orchestration
   and Optimize alike — otherwise Lucene segment-compaction state biases the size
   comparison).
4. Snapshot again and diff, per category and combined: `(ES bytes added) / (instances
   completed)` gives per-instance storage cost at that payload size.
5. Repeat at 2-4 different payload sizes (e.g. 1KB, 5KB, 10KB, 20KB) and fit a
   line through the results to separate the fixed per-instance overhead (workflow
   history, flow-node/variable documents, indices overhead) from the marginal
   cost of payload bytes — do this once for orchestration, once for Optimize, and
   once combined, since they may not share the same slope/intercept.

### Optimize: what "separately" means here

Optimize is only enabled if the target cluster has `optimize.enabled: true` (in
the recipe's `my-camunda-values.yaml`, overriding the chart's own default). If
it's disabled, the Optimize category will simply report ~0 delta throughout —
that's expected, not a bug.

**Confirmed by measurement**: Optimize *does* store a full per-instance record —
it's just not visible until instances actually flow through it. Its per-process
index is named `optimize-process-instance-<bpmnProcessId, lowercased>_v<N>` (e.g.
`optimize-process-instance-eighttasksprocess_v8`), created lazily on first import,
which is why it looked absent on first inspection before any load had run.
Internally it uses Elasticsearch nested fields for flow-node/variable data, so
`docs.count` from `_cat/indices` on that index is inflated by hidden nested child
documents (~30x the actual instance count observed) — use `_count` (a real search
query) for the true per-instance document count, not `_cat/indices`.

Measured Optimize storage cost is **substantially higher per instance than
Orchestration's**, and grows faster than linearly with payload size in the one
sweep run so far (see the customer report for the actual figures) — plausibly
because the nested doc structure duplicates variable content with more overhead
per byte than Operate's flatter model. This is a first measurement, not a settled
characterization: repeat runs, and ideally engineering input on Optimize's
storage model, would be needed before treating the scaling shape as reliable.

Because per-index scaling behavior isn't fully characterized, `OPTIMIZE_INDEX_PATTERN`
in `es-storage-report.sh` stays a blanket `optimize-*` wildcard rather than a
curated list — report the Optimize number as "total Optimize footprint growth,"
and call out in any customer-facing writeup whether it turned out to scale with
instances or stayed flat.

**Optimize import lag is real and must be waited out separately from Operate's.**
Optimize imports from Zeebe/orchestration data on its own cadence, decoupled from
Operate's post-importer-queue. `cmd_settle` in `es-storage-report.sh` now also
polls `optimize-process-instance-*` doc counts and waits for them to stop growing
before flushing/force-merging (`cmd_wait_optimize_import`, `OPTIMIZE_IMPORT_MAX_WAIT_SECONDS`,
default 300s) — without this, a run's "before" snapshot can be taken while
Optimize is still draining a *prior* run's backlog, which then lands inside the
*current* run's measured delta and inflates its per-instance number. This was
observed directly: an early run without this wait measured ~4.7x the expected
per-instance cost. Two things to know about this check:
- It only confirms *count* has stabilized, not that all in-place *updates* to
  existing documents (e.g. late-arriving nested variable data) have finished —
  it's a reasonable proxy, not a guarantee. If a run's Optimize number looks
  anomalously high, check whether `optimize-process-instance-*` size (not just
  count) was still moving right after that run.
- Also watch the primaries-vs-replicas ratio for `optimize-process-instance-*`
  in the raw indices — it should sit at a stable ~2x (1 replica) between snapshots.
  If it doesn't, one snapshot likely landed mid-replica-sync, which inflates the
  "incl. replicas" delta without the "primaries" delta being affected. When in
  doubt, trust the primaries-only figures over the replicated total for a given run.

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

Each run prints three blocks — Orchestration cluster, Optimize, and Combined —
each shaped like:

```
--- Orchestration cluster (operate-*, tasklist-*) ---
ES delta, primaries only          : NNNNN bytes
ES delta, primaries + replicas    : NNNNN bytes
Per-instance ES bytes (primaries) : NNNNN bytes
Per-instance ES bytes (total)     : NNNNN bytes
Expansion ratio, primaries only   : N.NNx (NNN%)
Expansion ratio, incl. replicas   : N.NNx (NNN%)
```

Collect the per-instance-bytes figures across runs, then fit
`bytes_per_instance = intercept + slope × payload_bytes` via least-squares over
the (payload_bytes, per-instance-bytes) pairs — separately for each of the three
blocks, and separately for primaries vs. primaries+replicas within each — and
report R² alongside every fit. Present Orchestration and Optimize numbers next
to each other in any customer-facing report; don't only report Combined, since
a customer with Optimize disabled needs the Orchestration-only numbers.

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
- **Optimize's per-instance cost, if any, is a separate line item from Orchestration's**,
  not a multiplier on it — don't assume a fixed ratio between the two categories
  transfers across payload sizes or process complexity (Optimize's cost, if
  nonzero, likely scales with flow-node/variable count and reporting configuration,
  not raw payload bytes, since it isn't measured against payload bytes the way
  Operate's document size is).
