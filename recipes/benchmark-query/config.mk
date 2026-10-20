# Kubernetes namespace where Camunda is installed
BENCHMARK_QUERY_NAMESPACE ?= camunda

# Helm release name of the existing Camunda installation (used to find the zeebe-gateway service)
CAMUNDA_RELEASE_NAME ?= camunda

# Load profile. Requests per second for each step, then seconds to hold and to ramp each step.
QUERY_STEPS ?= 10,25,50,100,200
QUERY_STEP_SECONDS ?= 120
QUERY_RAMP_SECONDS ?= 10

# A step counts as degraded when its p95 latency is above this many ms or its error rate is above the limit
QUERY_P95_MS ?= 500
QUERY_MAX_ERROR_RATE ?= 0.01
