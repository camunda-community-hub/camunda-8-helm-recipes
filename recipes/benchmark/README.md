# Benchmark Recipe

Runs the [camunda-8-benchmark](https://github.com/camunda-community-hub/camunda-8-benchmark) tool against an existing Camunda 8 installation to measure throughput and latency under load.

## Prerequisites

- A running Camunda 8 installation in Kubernetes (any recipe under `recipes/camunda/` works)
- `kubectl` configured to point at the cluster
- Prometheus + Grafana installed (see `recipes/metrics/`) for observing results

## Usage

### No authentication

```bash
cd recipes/benchmark
make
make logs-benchmark
make clean
```

### OIDC authentication

1. Create a machine-to-machine client in Keycloak/Identity with access to the `zeebe-api` audience.

2. Set the auth variables in your root `config.mk` (not committed):

   ```makefile
   BENCHMARK_CLIENT_ID = benchmark
   BENCHMARK_TOKEN_URL = http://camunda-keycloak/auth/realms/camunda-platform/protocol/openid-connect/token
   BENCHMARK_TOKEN_AUDIENCE = zeebe-api
   BENCHMARK_CLIENT_SECRET = <your-client-secret>
   ```

4. Run:

   ```bash
   make benchmark-oidc
   make logs-benchmark
   make clean
   ```

## Configuration

### Namespace / release name

Override in the **project root** `config.mk`:

```makefile
BENCHMARK_NAMESPACE = camunda        # namespace where Camunda is running
CAMUNDA_RELEASE_NAME = camunda       # Helm release name (used to find the gateway service)
```

If your release name is not `camunda`, also update the `grpc-address` in the relevant include file:

```yaml
-Dcamunda.client.zeebe.grpc-address=http://<your-release-name>-zeebe-gateway:26500
```

### Benchmark parameters

Edit `include/benchmark.yaml` or `include/benchmark-oidc.yaml` to tune the load profile. Key settings:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `benchmark.startPiPerSecond` | `5` | Initial process instance creation rate |
| `benchmark.startRateAdjustmentStrategy` | `backpressure` | `backpressure` ramps up automatically; `fixed` holds the start rate steady |
| `benchmark.startPiIncreaseFactor` | `0.1` | Rate ramp-up increment (0.1 = +10% per cycle) |
| `benchmark.maxBackpressurePercentage` | `1.0` | Stop increasing rate above this backpressure ratio |
| `benchmark.taskCompletionDelay` | `10` | Simulated worker processing time in milliseconds |
| `benchmark.multipleJobTypes` | `8` | Number of distinct job types (simulates a process with N service tasks) |
| `benchmark.warmupPhaseDurationMillis` | `3000` | Warmup period before rate adjustment begins |
| `benchmark.autoDeployProcess` | `true` | Deploys the built-in `BenchmarkProcess` automatically |
| `benchmark.bpmnProcessId` | `BenchmarkProcess` | Process to instantiate; set to your process ID if `autoDeployProcess=false` |

### Payload

Edit `include/payload.json` to change the variables sent with each process instance. The default payload is a representative mix of strings, booleans, numbers, and UUIDs.

## Analysing results

Open the **Zeebe** dashboard in Grafana and observe:

- **Throughput** — process instances started and completed per second
- **Latency** — time from instance start to completion (heatmap)

Increase `startPiPerSecond` (or let `backpressure` mode ramp up automatically) until latency becomes unacceptable to find the throughput ceiling of your cluster.

## Make targets

| Target | Description |
|--------|-------------|
| `make` / `make all` | Deploy benchmark without auth (same as `make benchmark`) |
| `make benchmark` | Create payload ConfigMap and deploy benchmark pod (no auth) |
| `make benchmark-oidc` | Create credentials secret, payload ConfigMap, and deploy benchmark pod (OIDC) |
| `make create-benchmark-credentials` | Create the `benchmark-credentials` K8s secret from `BENCHMARK_CLIENT_SECRET` |
| `make clean` / `make clean-benchmark` | Remove benchmark deployment, credentials secret, and payload ConfigMap |
| `make logs-benchmark` | Stream live logs from the benchmark pod |
