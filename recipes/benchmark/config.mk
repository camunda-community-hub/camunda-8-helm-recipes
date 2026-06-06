# Kubernetes namespace where Camunda is installed
BENCHMARK_NAMESPACE ?= camunda

# Helm release name of the existing Camunda installation
# Used to construct the Zeebe gateway service name: <release>-zeebe-gateway
CAMUNDA_RELEASE_NAME ?= camunda

# Benchmark load profile
BENCHMARK_REPLICAS ?= 1
BENCHMARK_START_PI_PER_SECOND ?= 5
BENCHMARK_BPMN_PROCESS_ID ?= BenchmarkProcess
BENCHMARK_MULTIPLE_JOB_TYPES ?= 8
BENCHMARK_WARMUP_DURATION_MS ?= 3000

# OIDC authentication (required for benchmark-oidc target)
# Override these in the root config.mk - do not commit secrets
BENCHMARK_TENANT_ID ?= <default>
BENCHMARK_CLIENT_ID ?= benchmark
BENCHMARK_TOKEN_URL ?= http://camunda-keycloak/auth/realms/camunda-platform/protocol/openid-connect/token
BENCHMARK_TOKEN_AUDIENCE ?= zeebe-api
BENCHMARK_CLIENT_SECRET ?= changeme
