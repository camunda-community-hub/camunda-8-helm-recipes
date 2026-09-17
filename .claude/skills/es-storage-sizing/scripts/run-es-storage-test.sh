#!/usr/bin/env bash
# Runs one full Elasticsearch storage-overhead measurement:
#   snapshot -> deploy benchmark (OIDC) -> run for a fixed window -> drain in-flight
#   instances -> tear down -> settle -> snapshot -> diff
#
# Usage:
#   BENCHMARK_DIR=/path/to/recipes/benchmark ./run-es-storage-test.sh [duration_seconds] [label]
#
# Example:
#   BENCHMARK_DIR=~/code/camunda-8-helm-recipes/recipes/benchmark \
#   PAYLOAD_SIZE_BYTES=10240 \
#     ./run-es-storage-test.sh 300 10kb-run1
#
# Config (env vars):
#   BENCHMARK_DIR    required — path to the recipe's recipes/benchmark directory
#                    (the one with Makefile, config.mk, include/). Provides the
#                    `make benchmark-oidc` / `make clean-benchmark` targets and the
#                    default payload/results locations.
#   PAYLOAD_FILE     explicit payload file to use. Takes precedence over
#                    PAYLOAD_SIZE_BYTES. Default: $BENCHMARK_DIR/include/payload.json
#   PAYLOAD_SIZE_BYTES  if set (and PAYLOAD_FILE is not), a payload of exactly this
#                    many bytes is generated via generate-payload.py into
#                    $BENCHMARK_DIR/include/payload-generated-<n>b.json
#   WAIT_DRAIN_MAX_SECONDS  default: 120 — max time to wait for in-flight instances
#                    to reach a terminal state after load stops, before the benchmark
#                    pod (which is also the job worker) is torn down anyway. Without
#                    this wait, instances still in flight at teardown never complete,
#                    and can leave Operate's post-importer queue stuck forever.
#   BENCHMARK_NAMESPACE, CAMUNDA_RELEASE_NAME — passed through to es-storage-report.sh
#
# Prerequisites (see SKILL.md for the full explanation):
#   - BENCHMARK_BPMN_PROCESS_ID (set in the target repo's config.mk) must already be
#     deployed to Zeebe by some means OTHER than this benchmark tool's autoDeploy —
#     the benchmark image's autoDeployProcess path has a known bug that silently
#     kills job-worker registration. The bundled benchmark-oidc.yaml already forces
#     -Dbenchmark.autoDeployProcess=false, so this is enforced, not optional.
#   - The Helm release's OIDC client (BENCHMARK_CLIENT_ID) must be authorized to
#     start/complete instances of that process (see the target repo's
#     orchestration.security.initialization.authorizations Helm value).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT="$SCRIPT_DIR/es-storage-report.sh"
GENERATE_PAYLOAD="$SCRIPT_DIR/generate-payload.py"

BENCHMARK_DIR="${BENCHMARK_DIR:?set BENCHMARK_DIR to the target recipes/benchmark directory (contains Makefile, config.mk, include/)}"
[ -f "$BENCHMARK_DIR/Makefile" ] || { echo "error: $BENCHMARK_DIR/Makefile not found — is BENCHMARK_DIR correct?" >&2; exit 1; }

DURATION="${1:-300}"
LABEL="${2:-run-$(date +%Y%m%d-%H%M%S)}"
export WAIT_DRAIN_MAX_SECONDS="${WAIT_DRAIN_MAX_SECONDS:-120}"
export ES_REPORT_DIR="${ES_REPORT_DIR:-$BENCHMARK_DIR/es-storage-results}"

[ -x "$REPORT" ] || { echo "error: $REPORT not found or not executable" >&2; exit 1; }

if [ -n "${PAYLOAD_FILE:-}" ]; then
  : # explicit override, use as-is
elif [ -n "${PAYLOAD_SIZE_BYTES:-}" ]; then
  PAYLOAD_FILE="$BENCHMARK_DIR/include/payload-generated-${PAYLOAD_SIZE_BYTES}b.json"
  echo "--- generating ${PAYLOAD_SIZE_BYTES}-byte payload ---"
  python3 "$GENERATE_PAYLOAD" "$PAYLOAD_SIZE_BYTES" "$PAYLOAD_FILE"
  echo
else
  PAYLOAD_FILE="$BENCHMARK_DIR/include/payload.json"
fi

[ -f "$PAYLOAD_FILE" ] || { echo "error: payload file not found: $PAYLOAD_FILE" >&2; exit 1; }
PAYLOAD_BYTES=$(wc -c < "$PAYLOAD_FILE" | tr -d ' ')
PAYLOAD_FILE_ABS="$(cd "$(dirname "$PAYLOAD_FILE")" && pwd)/$(basename "$PAYLOAD_FILE")"

echo "=== ES storage test: $LABEL ==="
echo "payload file      : $PAYLOAD_FILE_ABS ($PAYLOAD_BYTES bytes)"
echo "load duration     : ${DURATION}s"
echo "max drain wait    : ${WAIT_DRAIN_MAX_SECONDS}s"
echo

echo "--- settling before baseline (normalize segment state) ---"
"$REPORT" settle
echo

echo "--- snapshot: before ---"
"$REPORT" snapshot "${LABEL}-before"
echo

echo "--- deploying benchmark (OIDC) ---"
make -C "$BENCHMARK_DIR" benchmark-oidc BENCHMARK_PAYLOAD_FILE="$PAYLOAD_FILE_ABS"
echo

echo "--- running load for ${DURATION}s ---"
sleep "$DURATION"
echo

echo "--- draining: letting this run's in-flight instances reach a terminal state ---"
"$REPORT" wait-drain "${LABEL}-before"
echo

echo "--- tearing down benchmark ---"
make -C "$BENCHMARK_DIR" clean-benchmark
echo

echo "--- settling (drain importer queue, flush, force-merge) ---"
"$REPORT" settle
echo

echo "--- snapshot: after ---"
"$REPORT" snapshot "${LABEL}-after"
echo

"$REPORT" diff "${LABEL}-before" "${LABEL}-after" "$PAYLOAD_BYTES"
