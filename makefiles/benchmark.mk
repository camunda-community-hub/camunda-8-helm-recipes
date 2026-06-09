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
	  < $(root)/recipes/benchmark/include/benchmark.yaml | kubectl apply -f - -n $(BENCHMARK_NAMESPACE)

.PHONY: benchmark-oidc # create the payload ConfigMap and deploy the benchmark tool (OIDC auth)
benchmark-oidc: create-benchmark-credentials _benchmark-payload
	$(_BENCHMARK_ENV) \
	BENCHMARK_TENANT_ID='$(BENCHMARK_TENANT_ID)' \
	BENCHMARK_CLIENT_ID=$(BENCHMARK_CLIENT_ID) \
	BENCHMARK_TOKEN_URL=$(BENCHMARK_TOKEN_URL) \
	BENCHMARK_TOKEN_AUDIENCE=$(BENCHMARK_TOKEN_AUDIENCE) \
	  envsubst '$(_BENCHMARK_VARS) $$BENCHMARK_TENANT_ID $$BENCHMARK_CLIENT_ID $$BENCHMARK_TOKEN_URL $$BENCHMARK_TOKEN_AUDIENCE' \
	  < $(root)/recipes/benchmark/include/benchmark-oidc.yaml | kubectl apply -f - -n $(BENCHMARK_NAMESPACE)

.PHONY: _benchmark-payload
_benchmark-payload:
	-kubectl delete configmap benchmark-payload -n $(BENCHMARK_NAMESPACE) 2>/dev/null || true
	kubectl create configmap benchmark-payload \
	  --from-file=payload.json=$(root)/recipes/benchmark/include/payload.json \
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

# Cluster scaling via the Zeebe gateway management API (port 9600)
# Docs: https://docs.camunda.io/docs/self-managed/components/orchestration-cluster/zeebe/operations/cluster-scaling/
SCALE_BROKER_COUNT ?= 3
SCALE_PARTITION_COUNT ?= 9
SCALE_REPLICATION_FACTOR ?= 3
ZEEBE_MANAGEMENT_PORT ?= 9600

# Port-forwards the gateway management port, captures PID, and traps cleanup on shell exit.
# Expanded inline in each target so port-forward and curl share the same shell process.
_zeebe_mgmt_pf = kubectl port-forward svc/$(CAMUNDA_RELEASE_NAME)-zeebe-gateway $(ZEEBE_MANAGEMENT_PORT):$(ZEEBE_MANAGEMENT_PORT) -n $(BENCHMARK_NAMESPACE) >/dev/null 2>&1 & PF_PID=$$!; trap "kill $$PF_PID 2>/dev/null" EXIT; sleep 2

# NOTE: safe for scale-up only. Use scale-down for reducing broker count — it drains
# partitions via the cluster API before scaling the StatefulSet down.
.PHONY: scale-up # scale StatefulSet to SCALE_BROKER_COUNT replicas then rebalance partitions via the cluster API
scale-up:
	kubectl scale statefulset $(CAMUNDA_RELEASE_NAME)-zeebe \
	  --replicas=$(SCALE_BROKER_COUNT) -n $(BENCHMARK_NAMESPACE)
	$(_zeebe_mgmt_pf); \
	curl -sf -X PATCH 'http://localhost:$(ZEEBE_MANAGEMENT_PORT)/orchestration/actuator/cluster' \
	  -H 'Content-Type: application/json' \
	  -d '{"brokers":{"count":$(SCALE_BROKER_COUNT)},"partitions":{"count":$(SCALE_PARTITION_COUNT),"replicationFactor":$(SCALE_REPLICATION_FACTOR)}}'

# NOTE: partition scale-down is not supported by Zeebe. Only broker count can be reduced.
# Brokers are drained via the cluster API before the StatefulSet is scaled down.
.PHONY: scale-down # drain brokers via cluster API then scale StatefulSet down (partition count is unchanged)
scale-down:
	$(_zeebe_mgmt_pf); \
	echo "Scaling brokers down to $(SCALE_BROKER_COUNT)..."; \
	curl -s -X PATCH 'http://localhost:$(ZEEBE_MANAGEMENT_PORT)/orchestration/actuator/cluster' \
	  -H 'Content-Type: application/json' \
	  -d '{"brokers":{"count":$(SCALE_BROKER_COUNT)}}' | jq .; \
	for i in 1 2 3 4 5 6; do \
	  sleep 5; \
	  curl -sf 'http://localhost:$(ZEEBE_MANAGEMENT_PORT)/orchestration/actuator/cluster' \
	    | jq -e '.pendingChange != null' >/dev/null 2>&1 && break; \
	  echo "Waiting for broker change to register (attempt $$i/6)..."; \
	done; \
	until curl -sf 'http://localhost:$(ZEEBE_MANAGEMENT_PORT)/orchestration/actuator/cluster' \
	  | jq -e '.pendingChange == null' >/dev/null 2>&1; do \
	  sleep 10; \
	  echo "Still rebalancing brokers..."; \
	done; \
	echo "Broker scale-down complete."
	kubectl scale statefulset $(CAMUNDA_RELEASE_NAME)-zeebe \
	  --replicas=$(SCALE_BROKER_COUNT) -n $(BENCHMARK_NAMESPACE)
	kubectl rollout status statefulset/$(CAMUNDA_RELEASE_NAME)-zeebe \
	  -n $(BENCHMARK_NAMESPACE)

.PHONY: scale-up-dry-run # preview scale-up changes without applying them
scale-up-dry-run:
	$(_zeebe_mgmt_pf); \
	curl -sf -X PATCH 'http://localhost:$(ZEEBE_MANAGEMENT_PORT)/orchestration/actuator/cluster?dryRun=true' \
	  -H 'Content-Type: application/json' \
	  -d '{"brokers":{"count":$(SCALE_BROKER_COUNT)},"partitions":{"count":$(SCALE_PARTITION_COUNT),"replicationFactor":$(SCALE_REPLICATION_FACTOR)}}'

.PHONY: cluster-status # show current cluster topology and any in-progress scaling operation
cluster-status:
	$(_zeebe_mgmt_pf); \
	curl -sf 'http://localhost:$(ZEEBE_MANAGEMENT_PORT)/orchestration/actuator/cluster' | \
	jq '{version, brokers: [.brokers[] | {id, state, partitions: [.partitions[] | {id, state, priority}]}], routing, lastChange, pendingChange}'

