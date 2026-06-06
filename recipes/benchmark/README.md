# Benchmark Recipe

Runs the [camunda-8-benchmark](https://github.com/camunda-community-hub/camunda-8-benchmark) tool against an existing Camunda 8 installation to measure throughput and latency under load.

## Prerequisites

- A running Camunda 8 installation in Kubernetes (any recipe under `recipes/camunda/` works)
- `kubectl` configured to point at the cluster
- Prometheus + Grafana installed (see `recipes/metrics/`) for observing results

## Usage

```bash
cd recipes/benchmark

# Start the benchmark (creates ConfigMap + deploys benchmark pod)
make

# Stream benchmark logs
make logs-benchmark

# Stop the benchmark
make clean
```

## Configuration

### Namespace / release name

Create a `config.mk` in the **project root** (not committed) to override defaults:

```makefile
BENCHMARK_NAMESPACE = camunda        # namespace where Camunda is running
CAMUNDA_RELEASE_NAME = camunda       # Helm release name (used to find the gateway service)
```

If your release name is not `camunda`, also update the `grpc-address` in `benchmark.yaml`:

```yaml
-Dcamunda.client.zeebe.grpc-address=http://<your-release-name>-zeebe-gateway:26500
```

### Benchmark parameters

Edit `benchmark.yaml` to tune the load profile. Key settings:

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

Edit `payload.json` to change the variables sent with each process instance. The default payload is a representative mix of strings, booleans, numbers, and UUIDs.

## Analysing results

Open the **Zeebe** dashboard in Grafana and observe:

- **Throughput** — process instances started and completed per second
- **Latency** — time from instance start to completion (heatmap)

Increase `startPiPerSecond` (or let `backpressure` mode ramp up automatically) until latency becomes unacceptable to find the throughput ceiling of your cluster.

## Make targets

| Target | Description |
|--------|-------------|
| `make` / `make all` | Deploy benchmark (same as `make benchmark`) |
| `make benchmark` | Create payload ConfigMap and deploy benchmark pod |
| `make clean` / `make clean-benchmark` | Remove benchmark deployment and ConfigMap |
| `make logs-benchmark` | Stream live logs from the benchmark pod |
