---
description: Start a Camunda benchmark against an existing cluster. Checks Camunda health, configures load parameters, deploys the benchmark, and streams logs.
---

You are helping start a Camunda benchmark against an existing Camunda 8 installation using the `makefiles/benchmark.mk` targets.

## Repo context

- Benchmark targets are in `makefiles/benchmark.mk`
- The benchmark recipe config is at `recipes/benchmark/config.mk`
- Two deploy modes: `benchmark` (no auth) and `benchmark-oidc` (Keycloak OIDC auth)
- Key variables: `BENCHMARK_START_PI_PER_SECOND`, `BENCHMARK_REPLICAS`, `BENCHMARK_NAMESPACE`, `CAMUNDA_RELEASE_NAME`
- Run from any recipe directory that includes `benchmark.mk` (e.g. `recipes/camunda/oidc-gateway-traefik-tls-es/`)

## Steps to follow

### 1. Confirm Camunda is running

Check the current namespace and that Zeebe is healthy:
```bash
kubectl get pods -n <BENCHMARK_NAMESPACE>
```

Look for Zeebe broker and gateway pods in `Running` state. If pods are not ready, stop and tell the user to wait or troubleshoot Camunda first.

### 2. Show current benchmark config

Read the effective values (from `recipes/benchmark/config.mk` and root `config.mk` overrides):
- `BENCHMARK_NAMESPACE`
- `BENCHMARK_REPLICAS`
- `BENCHMARK_START_PI_PER_SECOND`
- `BENCHMARK_BPMN_PROCESS_ID`
- `BENCHMARK_MULTIPLE_JOB_TYPES`
- `BENCHMARK_WARMUP_DURATION_MS`

Display them and ask the user to confirm, or adjust via root `config.mk`.

### 3. Determine auth mode

Ask the user: **Does your Camunda installation use OIDC/Keycloak authentication?**

- **Yes (OIDC)** → use `benchmark-oidc`. Also confirm these variables are set in root `config.mk`:
  - `BENCHMARK_CLIENT_SECRET` (the Keycloak client secret — never commit this)
  - `BENCHMARK_TOKEN_URL`
  - `BENCHMARK_CLIENT_ID`
  - `BENCHMARK_TENANT_ID` (use `<default>` for single-tenant)

- **No (plain)** → use `benchmark`

### 4. Stop any existing benchmark

Before deploying, clean up any previous run:
```bash
make clean-benchmark
```

(This is safe to run even if nothing is deployed.)

### 5. Deploy the benchmark

From the recipe directory (e.g. `recipes/camunda/oidc-gateway-traefik-tls-es/`):

**Plain (no auth):**
```bash
make benchmark
```

**OIDC:**
```bash
make benchmark-oidc
```

This will:
1. Create a `benchmark-payload` ConfigMap with the BPMN payload
2. For OIDC: create a `benchmark-credentials` secret
3. Deploy the benchmark pod

### 6. Wait for pod to start

```bash
kubectl rollout status deployment/benchmark -n <BENCHMARK_NAMESPACE>
```

### 7. Stream logs

Once the pod is running, stream logs so the user can see throughput:
```bash
make logs-benchmark
```

Look for lines showing process instances per second. A warmup period runs first (`BENCHMARK_WARMUP_DURATION_MS`), then steady-state load begins.

### 8. Optional: cluster scaling

If the user wants to test with a scaled cluster, offer these targets:

```bash
# Scale up (add brokers + rebalance partitions)
make scale-up SCALE_BROKER_COUNT=6 SCALE_PARTITION_COUNT=18 SCALE_REPLICATION_FACTOR=3

# Check scaling status
make cluster-status

# Scale down (drains partitions first, then reduces StatefulSet)
make scale-down SCALE_BROKER_COUNT=3
```

## Stopping the benchmark

```bash
make clean-benchmark
```

This removes the benchmark deployment, payload ConfigMap, and credentials secret.

## Config variable reference

| Variable | Default | Description |
|---|---|---|
| `BENCHMARK_NAMESPACE` | `camunda` | Kubernetes namespace |
| `CAMUNDA_RELEASE_NAME` | `camunda` | Helm release name (used to find gateway service) |
| `BENCHMARK_REPLICAS` | `1` | Number of benchmark worker pods |
| `BENCHMARK_START_PI_PER_SECOND` | `5` | Process instances to start per second |
| `BENCHMARK_BPMN_PROCESS_ID` | `PaymentProcessingCardAuthorizationProcess` | BPMN process to benchmark |
| `BENCHMARK_MULTIPLE_JOB_TYPES` | `10` | Number of distinct job types |
| `BENCHMARK_WARMUP_DURATION_MS` | `60000` | Warmup period before load starts (ms) |
| `BENCHMARK_CLIENT_SECRET` | `changeme` | Keycloak client secret (OIDC only — set in root config.mk) |
| `BENCHMARK_TOKEN_URL` | `http://camunda-keycloak/...` | Token endpoint (OIDC only) |

Override these in root `config.mk` (gitignored). Never commit secrets.
