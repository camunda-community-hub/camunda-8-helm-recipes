BENCHMARK_QUERY_NAMESPACE ?= $(CAMUNDA_NAMESPACE)
CAMUNDA_RELEASE_NAME ?= camunda

# Where to send the queries. The REST API lives under the Orchestration context path.
QUERY_BASE_URL ?= http://$(CAMUNDA_RELEASE_NAME)-zeebe-gateway:8080/orchestration
QUERY_AUTH ?= oidc

# true: fetch one token in setup() and share it across all VUs. Needed against Camunda SaaS, whose token endpoint
# allows about one request per second per source IP.
QUERY_SHARED_TOKEN ?= false

# Load profile: requests per second per step, seconds to hold and ramp each step
QUERY_STEPS ?= 10,25,50,100,200
QUERY_STEP_SECONDS ?= 120
QUERY_RAMP_SECONDS ?= 10

# What counts as degraded
QUERY_P95_MS ?= 500
QUERY_MAX_ERROR_RATE ?= 0.01

# Optional narrowing of the query mix
QUERY_PROCESS_ID ?=
QUERY_DISABLED ?=

# k6 client sizing. QUERY_BATCH is the number of requests each VU sends in parallel per iteration.
QUERY_BATCH ?= 1
QUERY_PREALLOCATED_VUS ?= 100
QUERY_MAX_VUS ?= 1000
K6_IMAGE ?= grafana/k6:1.0.0
K6_CPU ?= 2
K6_MEMORY ?= 2Gi

# OIDC client, shared with the write benchmark (makefiles/benchmark.mk). Set the secret in the root config.mk.
BENCHMARK_CLIENT_ID ?= benchmark
BENCHMARK_TOKEN_URL ?= http://keycloak-service:18080/auth/realms/camunda-platform/protocol/openid-connect/token
BENCHMARK_TOKEN_AUDIENCE ?= orchestration-api
BENCHMARK_CLIENT_SECRET ?= changeme

BENCHMARK_QUERY_SCRIPT ?= $(root)/recipes/benchmark-query/k6/query-benchmark.js

_QUERY_VARS = $$K6_IMAGE $$QUERY_BASE_URL $$QUERY_AUTH $$QUERY_SHARED_TOKEN $$QUERY_STEPS $$QUERY_STEP_SECONDS $$QUERY_RAMP_SECONDS \
  $$QUERY_P95_MS $$QUERY_MAX_ERROR_RATE $$QUERY_PROCESS_ID $$QUERY_DISABLED $$QUERY_BATCH $$QUERY_PREALLOCATED_VUS \
  $$QUERY_MAX_VUS $$K6_CPU $$K6_MEMORY $$BENCHMARK_TOKEN_URL $$BENCHMARK_CLIENT_ID $$BENCHMARK_TOKEN_AUDIENCE

.PHONY: benchmark-query # run the k6 query benchmark as a Job (stepped request rate against the REST search API)
benchmark-query: clean-benchmark-query
	@kubectl create secret generic benchmark-query-credentials \
	  --from-literal=client-secret='$(BENCHMARK_CLIENT_SECRET)' \
	  -n $(BENCHMARK_QUERY_NAMESPACE)
	kubectl create configmap benchmark-query-script \
	  --from-file=query-benchmark.js=$(BENCHMARK_QUERY_SCRIPT) \
	  -n $(BENCHMARK_QUERY_NAMESPACE)
	K6_IMAGE='$(K6_IMAGE)' QUERY_BASE_URL='$(QUERY_BASE_URL)' QUERY_AUTH='$(QUERY_AUTH)' QUERY_SHARED_TOKEN='$(QUERY_SHARED_TOKEN)' \
	QUERY_STEPS='$(QUERY_STEPS)' QUERY_STEP_SECONDS='$(QUERY_STEP_SECONDS)' QUERY_RAMP_SECONDS='$(QUERY_RAMP_SECONDS)' \
	QUERY_P95_MS='$(QUERY_P95_MS)' QUERY_MAX_ERROR_RATE='$(QUERY_MAX_ERROR_RATE)' \
	QUERY_PROCESS_ID='$(QUERY_PROCESS_ID)' QUERY_DISABLED='$(QUERY_DISABLED)' QUERY_BATCH='$(QUERY_BATCH)' \
	QUERY_PREALLOCATED_VUS='$(QUERY_PREALLOCATED_VUS)' QUERY_MAX_VUS='$(QUERY_MAX_VUS)' \
	K6_CPU='$(K6_CPU)' K6_MEMORY='$(K6_MEMORY)' BENCHMARK_TOKEN_URL='$(BENCHMARK_TOKEN_URL)' \
	BENCHMARK_CLIENT_ID='$(BENCHMARK_CLIENT_ID)' BENCHMARK_TOKEN_AUDIENCE='$(BENCHMARK_TOKEN_AUDIENCE)' \
	  envsubst '$(_QUERY_VARS)' \
	  < $(root)/recipes/benchmark-query/include/benchmark-query-job.yaml | kubectl apply -f - -n $(BENCHMARK_QUERY_NAMESPACE)

# Camunda SaaS. Set these in the root config.mk. They are separate from the BENCHMARK_* variables,
# so the self-managed settings stay untouched.
SAAS_CLUSTER_ID ?=
SAAS_REGION ?=
SAAS_CLIENT_ID ?=
SAAS_CLIENT_SECRET ?=

.PHONY: benchmark-query-saas # run the k6 query benchmark against a Camunda SaaS cluster (one shared token)
benchmark-query-saas:
	@test -n "$(SAAS_CLUSTER_ID)" -a -n "$(SAAS_REGION)" -a -n "$(SAAS_CLIENT_ID)" -a -n "$(SAAS_CLIENT_SECRET)" || \
		(echo "Set SAAS_CLUSTER_ID, SAAS_REGION, SAAS_CLIENT_ID and SAAS_CLIENT_SECRET in the root config.mk" && exit 1)
	@$(MAKE) benchmark-query \
	  QUERY_BASE_URL='https://$(SAAS_REGION).api.camunda.io/$(SAAS_CLUSTER_ID)' \
	  QUERY_AUTH=oidc QUERY_SHARED_TOKEN=true \
	  BENCHMARK_TOKEN_URL='https://login.cloud.camunda.io/oauth/token' \
	  BENCHMARK_TOKEN_AUDIENCE='zeebe.camunda.io' \
	  BENCHMARK_CLIENT_ID='$(SAAS_CLIENT_ID)' \
	  BENCHMARK_CLIENT_SECRET='$(SAAS_CLIENT_SECRET)'

.PHONY: logs-benchmark-query # stream logs (including the per step summary) from the k6 query benchmark
logs-benchmark-query:
	kubectl logs -f job/benchmark-query -n $(BENCHMARK_QUERY_NAMESPACE)

.PHONY: clean-benchmark-query # remove the k6 query benchmark Job, script ConfigMap and credentials secret
clean-benchmark-query:
	-kubectl delete job benchmark-query -n $(BENCHMARK_QUERY_NAMESPACE) --ignore-not-found
	-kubectl delete configmap benchmark-query-script -n $(BENCHMARK_QUERY_NAMESPACE) --ignore-not-found
	-kubectl delete secret benchmark-query-credentials -n $(BENCHMARK_QUERY_NAMESPACE) --ignore-not-found
