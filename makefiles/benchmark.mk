BENCHMARK_NAMESPACE ?= $(CAMUNDA_NAMESPACE)
BENCHMARK_CLIENT_ID ?= benchmark
BENCHMARK_TOKEN_URL ?= http://camunda-keycloak/auth/realms/camunda-platform/protocol/openid-connect/token
BENCHMARK_TOKEN_AUDIENCE ?= zeebe-api
BENCHMARK_CLIENT_SECRET ?= changeme

.PHONY: benchmark # create the payload ConfigMap and deploy the benchmark tool (no auth)
benchmark: _benchmark-payload
	kubectl apply -f ./include/benchmark.yaml -n $(BENCHMARK_NAMESPACE)

.PHONY: benchmark-oidc # create the payload ConfigMap and deploy the benchmark tool (OIDC auth)
benchmark-oidc: create-benchmark-credentials _benchmark-payload
	BENCHMARK_CLIENT_ID=$(BENCHMARK_CLIENT_ID) \
	BENCHMARK_TOKEN_URL=$(BENCHMARK_TOKEN_URL) \
	BENCHMARK_TOKEN_AUDIENCE=$(BENCHMARK_TOKEN_AUDIENCE) \
	  envsubst '$$BENCHMARK_CLIENT_ID $$BENCHMARK_TOKEN_URL $$BENCHMARK_TOKEN_AUDIENCE' \
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

