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

The easiest way to tune the load profile is via `config.mk` in the project root (not committed). All variables use `?=` so any value set there takes precedence over the defaults in `recipes/benchmark/config.mk`.

```makefile
BENCHMARK_REPLICAS             = 1               # number of benchmark pods
BENCHMARK_START_PI_PER_SECOND  = 5               # initial process instance creation rate
BENCHMARK_BPMN_PROCESS_ID      = BenchmarkProcess  # process to instantiate
BENCHMARK_MULTIPLE_JOB_TYPES   = 8               # number of distinct job types
BENCHMARK_WARMUP_DURATION_MS   = 3000            # warmup period before rate adjustment begins
```

You can also edit `include/benchmark.yaml` or `include/benchmark-oidc.yaml` directly to change settings not exposed as variables. Key YAML fields:

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

## Horizontal cluster scaling

The benchmark recipe includes targets to scale the Zeebe broker StatefulSet up or down while keeping partitions balanced. The targets use the Zeebe cluster management API (port 9600) via a temporary `kubectl port-forward`.

### Configuration

Set these in the root `config.mk`:

```makefile
SCALE_BROKER_COUNT      = 3   # target number of Zeebe brokers
SCALE_PARTITION_COUNT   = 9   # total partitions (scale-up only; partition reduction is not supported)
SCALE_REPLICATION_FACTOR = 3  # replication factor per partition (scale-up only)
```

### Scale up

Scales the StatefulSet to `SCALE_BROKER_COUNT` replicas and then calls the cluster API to rebalance partitions:

```bash
make scale-up
```

Preview the changes without applying them:

```bash
make scale-up-dry-run
```

### Scale down

Drains brokers gracefully via the cluster API first (waits for rebalancing to complete), then scales the StatefulSet down. Only broker count can be reduced — partition count is not changed on scale-down.

```bash
make scale-down
```

### Check cluster status

Show current topology and any in-progress scaling operation:

```bash
make cluster-status
```

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
| `make scale-up` | Scale StatefulSet to `SCALE_BROKER_COUNT` and rebalance partitions via cluster API |
| `make scale-up-dry-run` | Preview scale-up changes without applying them |
| `make scale-down` | Drain brokers via cluster API, then scale StatefulSet down |
| `make cluster-status` | Show current cluster topology and any in-progress scaling operation |
