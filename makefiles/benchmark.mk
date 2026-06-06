BENCHMARK_NAMESPACE ?= $(CAMUNDA_NAMESPACE)
BENCHMARK_REPLICAS ?= 1
BENCHMARK_START_PI_PER_SECOND ?= 5
BENCHMARK_BPMN_PROCESS_ID ?= BenchmarkProcess
BENCHMARK_MULTIPLE_JOB_TYPES ?= 8
BENCHMARK_WARMUP_DURATION_MS ?= 3000
BENCHMARK_TENANT_ID ?= <default>
BENCHMARK_CLIENT_ID ?= benchmark
BENCHMARK_TOKEN_URL ?= http://camunda-keycloak/auth/realms/camunda-platform/protocol/openid-connect/token
BENCHMARK_TOKEN_AUDIENCE ?= zeebe-api
BENCHMARK_CLIENT_SECRET ?= changeme

# Common env exports and envsubst variable list shared by both deploy targets
_BENCHMARK_ENV = \
  BENCHMARK_REPLICAS=$(BENCHMARK_REPLICAS) \
  BENCHMARK_START_PI_PER_SECOND=$(BENCHMARK_START_PI_PER_SECOND) \
  BENCHMARK_BPMN_PROCESS_ID=$(BENCHMARK_BPMN_PROCESS_ID) \
  BENCHMARK_MULTIPLE_JOB_TYPES=$(BENCHMARK_MULTIPLE_JOB_TYPES) \
  BENCHMARK_WARMUP_DURATION_MS=$(BENCHMARK_WARMUP_DURATION_MS)
_BENCHMARK_VARS = $$BENCHMARK_REPLICAS $$BENCHMARK_START_PI_PER_SECOND $$BENCHMARK_BPMN_PROCESS_ID $$BENCHMARK_MULTIPLE_JOB_TYPES $$BENCHMARK_WARMUP_DURATION_MS

.PHONY: benchmark # create the payload ConfigMap and deploy the benchmark tool (no auth)
benchmark: _benchmark-payload
	$(_BENCHMARK_ENV) \
	  envsubst '$(_BENCHMARK_VARS)' \
	  < ./include/benchmark.yaml | kubectl apply -f - -n $(BENCHMARK_NAMESPACE)

.PHONY: benchmark-oidc # create the payload ConfigMap and deploy the benchmark tool (OIDC auth)
benchmark-oidc: create-benchmark-credentials _benchmark-payload
	$(_BENCHMARK_ENV) \
	BENCHMARK_TENANT_ID='$(BENCHMARK_TENANT_ID)' \
	BENCHMARK_CLIENT_ID=$(BENCHMARK_CLIENT_ID) \
	BENCHMARK_TOKEN_URL=$(BENCHMARK_TOKEN_URL) \
	BENCHMARK_TOKEN_AUDIENCE=$(BENCHMARK_TOKEN_AUDIENCE) \
	  envsubst '$(_BENCHMARK_VARS) $$BENCHMARK_TENANT_ID $$BENCHMARK_CLIENT_ID $$BENCHMARK_TOKEN_URL $$BENCHMARK_TOKEN_AUDIENCE' \
	  < ./include/benchmark-oidc.yaml | kubectl apply -f - -n $(BENCHMARK_NAMESPACE)

.PHONY: _benchmark-payload
_benchmark-payload:
	-kubectl delete configmap benchmark-payload -n $(BENCHMARK_NAMESPACE) 2>/dev/null || true
	kubectl create configmap benchmark-payload \
	  --from-file=payload.json=./include/payload.json \
	  -n $(BENCHMARK_NAMESPACE)

.PHONY: create-benchmark-credentials # create the benchmark-credentials secret from BENCHMARK_CLIENT_SECRET
create-benchmark-credentials:
	-kubectl delete secret benchmark-credentials -n $(BENCHMARK_NAMESPACE) 2>/dev/null || true
	kubectl create secret generic benchmark-credentials \
	  --from-literal=client-secret=$(BENCHMARK_CLIENT_SECRET) \
	  -n $(BENCHMARK_NAMESPACE)

.PHONY: clean-benchmark # remove the benchmark deployment, credentials, and payload ConfigMap
clean-benchmark:
	-kubectl delete deployment benchmark -n $(BENCHMARK_NAMESPACE)
	-kubectl delete configmap benchmark-payload -n $(BENCHMARK_NAMESPACE)
	-kubectl delete secret benchmark-credentials -n $(BENCHMARK_NAMESPACE)

.PHONY: logs-benchmark # stream logs from the running benchmark pod
logs-benchmark:
	kubectl logs -f -l app=benchmark -n $(BENCHMARK_NAMESPACE)

