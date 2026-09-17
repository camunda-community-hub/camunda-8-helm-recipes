#!/usr/bin/env bash
# Measures Elasticsearch storage growth attributable to Camunda process instances,
# so it can be compared against the payload bytes fed into the benchmark.
#
# Usage:
#   ./es-storage-report.sh snapshot <label>
#   ./es-storage-report.sh active-count
#   ./es-storage-report.sh wait-drain [baseline-label]
#   ./es-storage-report.sh settle
#   ./es-storage-report.sh diff <before-label> <after-label> <payload-bytes-per-instance>
#
# Typical flow (driven by run-es-storage-test.sh, but can be run by hand):
#   ./es-storage-report.sh settle       # normalize segment state before the baseline
#   ./es-storage-report.sh snapshot before
#   # ... run the benchmark for a fixed window, then STOP starting new instances ...
#   ./es-storage-report.sh wait-drain before   # wait for THIS run's instances to finish
#   # ... `make clean-benchmark` ...
#   ./es-storage-report.sh settle
#   ./es-storage-report.sh snapshot after
#   ./es-storage-report.sh diff before after 583
#
# wait-drain with no baseline-label waits for the active count to hit an absolute 0,
# which will hang (up to the timeout) if any earlier interrupted run left orphaned
# instances behind — pass the 'before' label so it only waits for this run's own
# instances instead.
#
# Config (env vars):
#   BENCHMARK_NAMESPACE       default: camunda
#   CAMUNDA_RELEASE_NAME      default: camunda
#   ES_REPORT_DIR             default: ./es-storage-results
#   WAIT_DRAIN_MAX_SECONDS    default: 120  — max time wait-drain polls for in-flight
#                             instances to reach 0 before giving up and continuing
#   WAIT_DRAIN_POLL_SECONDS   default: 5
#   SETTLE_MAX_WAIT_SECONDS   default: 180  — max time settle polls the post-importer
#                             queue before giving up and continuing anyway
#   SETTLE_POLL_SECONDS       default: 5

set -euo pipefail

NAMESPACE="${BENCHMARK_NAMESPACE:-camunda}"
RELEASE="${CAMUNDA_RELEASE_NAME:-camunda}"
RESULTS_DIR="${ES_REPORT_DIR:-./es-storage-results}"

# Indices that actually grow with process instance activity. Deliberately excludes
# static/identity indices (camunda-authorization, camunda-role, camunda-tenant, ...)
# which don't scale with benchmark load.
INDEX_PATTERN="operate-list-view-*,operate-flownode-instance-*,operate-variable-*,operate-job-*,operate-event-*,operate-sequence-flow-*,operate-incident-*,tasklist-task-*,tasklist-task-variable-*"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required but not found in PATH" >&2; exit 1; }
}
require kubectl
require jq
require awk

es_pod() {
  kubectl get pod -n "$NAMESPACE" \
    -l "app.kubernetes.io/name=elasticsearch,app.kubernetes.io/instance=$RELEASE" \
    -o jsonpath='{.items[0].metadata.name}'
}

# es_curl <path> [extra curl args...]
es_curl() {
  local path="$1"; shift
  kubectl exec -n "$NAMESPACE" "$(es_pod)" -c elasticsearch -- \
    curl -s "http://localhost:9200${path}" "$@" 2>/dev/null
}

cmd_snapshot() {
  local label="${1:?usage: snapshot <label>}"
  mkdir -p "$RESULTS_DIR"

  local indices_file="$RESULTS_DIR/$label.indices.json"
  es_curl "/_cat/indices/${INDEX_PATTERN}?format=json&bytes=b&h=index,docs.count,store.size,pri.store.size" > "$indices_file"

  local completed
  completed=$(es_curl "/operate-list-view-*/_count" -H 'Content-Type: application/json' \
    -d '{"query":{"term":{"state":"COMPLETED"}}}' | jq '.count')
  echo "$completed" > "$RESULTS_DIR/$label.completed"

  local active
  active=$(cmd_active_count)
  echo "$active" > "$RESULTS_DIR/$label.active"

  local pri_total
  pri_total=$(jq '[.[]["pri.store.size"] | tonumber] | add // 0' "$indices_file")

  echo "Snapshot '$label' saved to $indices_file"
  echo "  completed instances so far : $completed"
  echo "  active (non-terminal) now  : $active"
  echo "  tracked-index primaries    : $pri_total bytes"
}

cmd_active_count() {
  # Instances not yet in a terminal state (COMPLETED or CANCELED). Used to decide
  # when it's safe to tear down the benchmark worker without orphaning in-flight
  # instances (they'd never complete, and can leave the post-importer queue stuck).
  #
  # operate-list-view-* is a joined index holding processInstance, activity (flow
  # node), and variable documents together. Only processInstance docs carry a
  # meaningful "state"; activity/variable docs have state=null, which satisfies a
  # naive "not in [COMPLETED,CANCELED]" filter and wildly inflates the count. Must
  # restrict to joinRelation=processInstance.
  es_curl "/operate-list-view-*/_count" -H 'Content-Type: application/json' \
    -d '{"query":{"bool":{"must":[{"term":{"joinRelation":"processInstance"}}],"must_not":[{"terms":{"state":["COMPLETED","CANCELED"]}}]}}}' | jq '.count'
}

cmd_wait_drain() {
  # Optional baseline label: wait for the active count to fall back to what it was
  # at that snapshot (i.e. wait for THIS run's new instances to finish), rather than
  # an absolute 0 — a pre-existing stuck backlog from an earlier interrupted run
  # would otherwise block every future wait-drain forever.
  local baseline_label="${1:-}"
  local target=0
  if [ -n "$baseline_label" ]; then
    local baseline_file="$RESULTS_DIR/$baseline_label.active"
    [ -f "$baseline_file" ] || { echo "error: no active-count baseline found for '$baseline_label' (run snapshot first)" >&2; exit 1; }
    target=$(cat "$baseline_file")
  fi

  local max_wait="${WAIT_DRAIN_MAX_SECONDS:-120}"
  local poll="${WAIT_DRAIN_POLL_SECONDS:-5}"
  local elapsed=0

  echo "Waiting for in-flight (non-terminal) instances to drain back to baseline ($target) (max ${max_wait}s)..."
  while true; do
    local active
    active=$(cmd_active_count)
    echo "  active: $active / baseline: $target (elapsed ${elapsed}s)"
    [ "$active" -le "$target" ] && { echo "Back to baseline — this run's instances reached a terminal state."; return 0; }
    if [ "$elapsed" -ge "$max_wait" ]; then
      local stuck=$(( active - target ))
      echo "warning: ~$stuck instance(s) from this run still active after ${max_wait}s — giving up and continuing." >&2
      echo "warning: these instances will never complete once the benchmark worker is torn down; they're a small, known source of noise in the diff." >&2
      return 0
    fi
    sleep "$poll"
    elapsed=$(( elapsed + poll ))
  done
}

cmd_settle() {
  local max_wait="${SETTLE_MAX_WAIT_SECONDS:-180}"
  local poll="${SETTLE_POLL_SECONDS:-5}"
  local elapsed=0

  echo "Waiting for operate-post-importer-queue to drain (max ${max_wait}s)..."
  while true; do
    local pending
    pending=$(es_curl "/operate-post-importer-queue-*/_count" | jq '.count')
    echo "  pending: $pending (elapsed ${elapsed}s)"
    [ "$pending" -eq 0 ] && break
    if [ "$elapsed" -ge "$max_wait" ]; then
      echo "warning: $pending item(s) still pending in the post-importer queue after ${max_wait}s — giving up and continuing." >&2
      echo "warning: this usually means some instances were orphaned mid-flight (see wait-drain); the diff is still usable, just slightly noisier." >&2
      break
    fi
    sleep "$poll"
    elapsed=$(( elapsed + poll ))
  done

  echo "Flushing tracked indices..."
  es_curl "/${INDEX_PATTERN}/_flush" -X POST > /dev/null

  echo "Force-merging to 1 segment (may take a while)..."
  es_curl "/${INDEX_PATTERN}/_forcemerge?max_num_segments=1" -X POST > /dev/null

  echo "Settled. Safe to snapshot now."
}

cmd_diff() {
  local before="${1:?usage: diff <before-label> <after-label> <payload-bytes-per-instance>}"
  local after="${2:?usage: diff <before-label> <after-label> <payload-bytes-per-instance>}"
  local payload_bytes="${3:?usage: diff <before-label> <after-label> <payload-bytes-per-instance>}"

  local before_file="$RESULTS_DIR/$before.indices.json"
  local after_file="$RESULTS_DIR/$after.indices.json"
  [ -f "$before_file" ] || { echo "error: no snapshot found for '$before'" >&2; exit 1; }
  [ -f "$after_file" ] || { echo "error: no snapshot found for '$after'" >&2; exit 1; }

  local before_completed after_completed
  before_completed=$(cat "$RESULTS_DIR/$before.completed")
  after_completed=$(cat "$RESULTS_DIR/$after.completed")
  local instances=$(( after_completed - before_completed ))

  if [ "$instances" -le 0 ]; then
    echo "error: completed-instance count did not increase between '$before' ($before_completed) and '$after' ($after_completed)" >&2
    exit 1
  fi

  local pri_before pri_after total_before total_after
  pri_before=$(jq '[.[]["pri.store.size"] | tonumber] | add // 0' "$before_file")
  pri_after=$(jq '[.[]["pri.store.size"] | tonumber] | add // 0' "$after_file")
  total_before=$(jq '[.[]["store.size"] | tonumber] | add // 0' "$before_file")
  total_after=$(jq '[.[]["store.size"] | tonumber] | add // 0' "$after_file")

  local pri_delta=$(( pri_after - pri_before ))
  local total_delta=$(( total_after - total_before ))
  local payload_total=$(( instances * payload_bytes ))

  echo "=== ES storage report: $before -> $after ==="
  echo "Completed instances in window     : $instances"
  echo "Payload bytes per instance        : $payload_bytes"
  echo "Total payload bytes ingested      : $payload_total"
  echo
  echo "ES delta, primaries only          : $pri_delta bytes"
  echo "ES delta, primaries + replicas    : $total_delta bytes"
  echo
  awk -v p="$pri_delta" -v n="$instances" -v pb="$payload_bytes" 'BEGIN {
    printf "Per-instance ES bytes (primaries) : %d bytes  (payload was %d bytes/instance)\n", p/n, pb
  }'
  awk -v t="$total_delta" -v n="$instances" 'BEGIN {
    printf "Per-instance ES bytes (total)     : %d bytes\n", t/n
  }'
  echo
  awk -v p="$pri_delta" -v t="$payload_total" 'BEGIN {
    printf "Expansion ratio, primaries only   : %.2fx (%.0f%%)\n", p/t, (p/t)*100
  }'
  awk -v tot="$total_delta" -v t="$payload_total" 'BEGIN {
    printf "Expansion ratio, incl. replicas   : %.2fx (%.0f%%)\n", tot/t, (tot/t)*100
  }'
  echo
  echo "Note: run this at 2-3 different payload sizes and compare per-instance bytes"
  echo "to separate fixed per-instance overhead from the marginal cost of payload bytes."
}

case "${1:-}" in
  snapshot)     shift; cmd_snapshot "$@" ;;
  active-count) shift; cmd_active_count "$@" ;;
  wait-drain)   shift; cmd_wait_drain "$@" ;;
  settle)       shift; cmd_settle "$@" ;;
  diff)         shift; cmd_diff "$@" ;;
  *)
    echo "usage: $0 {snapshot <label> | active-count | wait-drain | settle | diff <before-label> <after-label> <payload-bytes-per-instance>}" >&2
    exit 1
    ;;
esac
