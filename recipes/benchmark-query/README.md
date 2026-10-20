# Query Benchmark Recipe

Finds how many query requests per second the Orchestration Cluster REST API can take before it degrades.
It runs a [k6](https://grafana.com/docs/k6/) script as a Kubernetes Job inside the cluster. The request rate
steps up (10, 25, 50, 100, 200 req/s by default) and each step holds long enough to read stable latency and error numbers.

This is the read-side companion to the [`benchmark`](../benchmark) recipe, which only generates write load.

## What it queries

A weighted mix of search and get calls under `/v2`:

| Query | Weight |
|---|---|
| `process-instances-active` (search, state ACTIVE, newest first) | 30 |
| `process-instance-by-key` (GET) | 20 |
| `process-instances-by-definition` (search, COMPLETED) | 15 |
| `variables-by-instance` (search) | 10 |
| `user-tasks-created` (search) | 10 |
| `element-instances-by-instance` (search) | 5 |
| `incidents-active` (search) | 5 |
| `process-definitions` (search) | 5 |

The by-key queries use process instance keys found in the cluster when the Job starts. Before the load begins, the Job
runs each query once and logs the status and the number of items returned, so you can see right away if one is
forbidden or empty.

## Prerequisites

- A running Camunda 8.10 Orchestration Cluster with secondary storage (Elasticsearch, OpenSearch or RDBMS).
  Search endpoints do not work without it.
- **Data to query.** Queries against an empty cluster are meaningless. Run the write benchmark first and let it build up data.
  Results depend on the data volume, so a tiny dataset gives optimistic numbers.
- `kubectl` pointed at the cluster, and `envsubst` (part of GNU gettext).
- For OIDC: a client that can fetch a token and has READ permission on the queried resources
  (process instances, process definitions, user tasks, incidents, variables). The setup log shows a 403 or empty results if it does not.
- Prometheus and Grafana (see [`recipes/metrics`](../metrics)) to watch the cluster side.

## Usage

OIDC is the default. It reuses the write benchmark's variables. Set the secret in your root `config.mk` (not committed):

```makefile
BENCHMARK_CLIENT_ID = connectors
BENCHMARK_TOKEN_URL = http://keycloak-service:18080/auth/realms/camunda-platform/protocol/openid-connect/token
BENCHMARK_TOKEN_AUDIENCE = orchestration-api
BENCHMARK_CLIENT_SECRET = <your-client-secret>
```

Run it:

```bash
cd recipes/benchmark-query
make                      # start the Job
make logs-benchmark-query # follow it, the per step table is printed at the end
make clean                # remove the Job, script ConfigMap and credentials secret
```

For a cluster without authentication use `make QUERY_AUTH=none`.

A quick check that everything works (one step, 30 seconds):

```bash
make QUERY_STEPS=10 QUERY_STEP_SECONDS=30 QUERY_RAMP_SECONDS=5
```

## Reading the results

The Job prints one line per step:

```
step req/s | achieved | p50 ms | p95 ms | p99 ms | max ms | errors % | verdict
        10 |     10.0 |     21 |     32 |     46 |     91 |     0.00 | ok
```

- **achieved** is requests per second over the hold of that step. If it falls below the step rate, the cluster could not keep up.
- **verdict** is `DEGRADED` when p95 is above `QUERY_P95_MS` or the error rate is above `QUERY_MAX_ERROR_RATE`.
- **dropped iterations** above 0 means k6 ran out of virtual users, so the client limited the rate and not the cluster.
  Raise `QUERY_MAX_VUS` or `K6_CPU`.

Only the hold is measured. The first seconds of each step are a ramp and are tagged separately.

In Grafana, watch these while the steps run:

- Zeebe pod CPU and CPU throttling (the Camunda pods serve both the REST API and the engine)
- Elasticsearch CPU and search latency
- `zeebe_backpressure_requests_limit` and dropped requests
- Exporter backlog and data availability

Two ways to run it:

1. **Queries alone** on a populated cluster gives the read ceiling.
2. **Queries on top of the write benchmark** at a steady rate is closer to production. Compare the write side
   (backpressure, throughput, data availability) with and without the query load. That shows how much the reads cost the writes.

## Configuration

Override in your root `config.mk` or on the command line.

| Variable | Default | Description |
|---|---|---|
| `BENCHMARK_QUERY_NAMESPACE` | `camunda` | Namespace of the Camunda installation |
| `CAMUNDA_RELEASE_NAME` | `camunda` | Helm release name, used for the service name |
| `QUERY_BASE_URL` | `http://<release>-zeebe-gateway:8080/orchestration` | REST API base, including the context path |
| `QUERY_AUTH` | `oidc` | `oidc` or `none` |
| `QUERY_STEPS` | `10,25,50,100,200` | Requests per second for each step |
| `QUERY_STEP_SECONDS` | `120` | Hold time per step |
| `QUERY_RAMP_SECONDS` | `10` | Ramp time into each step |
| `QUERY_P95_MS` | `500` | p95 latency that counts as degraded |
| `QUERY_MAX_ERROR_RATE` | `0.01` | Error rate that counts as degraded |
| `QUERY_PROCESS_ID` | empty | Narrow the by-definition query to one process |
| `QUERY_DISABLED` | empty | Comma separated query names to leave out |
| `QUERY_BATCH` | `1` | Requests each virtual user sends in parallel per iteration. `QUERY_STEPS` stay in requests per second, so a batch of 10 needs about 10 times fewer VUs and 10 times fewer Keycloak tokens |
| `QUERY_PREALLOCATED_VUS` / `QUERY_MAX_VUS` | `100` / `1000` | k6 virtual users |
| `K6_IMAGE` | `grafana/k6:1.0.0` | k6 image |
| `K6_CPU` / `K6_MEMORY` | `2` / `2Gi` | k6 pod resources |

## Limitations

- With `QUERY_BATCH` above 1, the requests of one VU arrive in small bursts instead of evenly spaced.
- Every VU fetches its own OIDC token, so thousands of VUs mean thousands of token requests to Keycloak at once. Use `QUERY_BATCH` to keep the VU count low at high rates.
- The load generator is open model (`ramping-arrival-rate`). It keeps sending at the step rate even when the server slows down, which is what
  you want here, but a badly overloaded cluster will pile up in-flight requests until `QUERY_MAX_VUS` is reached.
- The query mix and filters are a generic starting point. For a sizing exercise, adjust `k6/query-benchmark.js` to match the queries
  your applications really run.
- Results are only as good as the data behind them. Index size, retention and payload size all change query latency.
- Reads are eventually consistent. This recipe measures query latency and throughput, not how long data takes to appear after an instance starts.
- Results go to the Job log only. They are not sent to Prometheus.
