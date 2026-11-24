# Dual-region Camunda 8.10 with Elasticsearch and OIDC

Installs Camunda 8.10 (Helm chart 15) across two Kubernetes clusters that can reach each other's pods and resolve
each other's namespaces, for example the ones from [`recipes/google/gke-dual-region`](../../google/gke-dual-region).
For the full sequence with checks, use the `/create-gke-dual-region` Claude Code command.

## Layout

- **Orchestration Cluster stretched over both regions** with zone-aware partitioning: the zone name is the namespace,
  4 brokers and 2 replicas per partition in each region (`DUAL_REGION_CLUSTER_SIZE=8`,
  `DUAL_REGION_REPLICATION_FACTOR=4`, `DUAL_REGION_PARTITION_COUNT=8`).
  See [`orchestration-dual-region-es.yaml`](../../../camunda-values.yaml.d/orchestration-dual-region-es.yaml).
- **Elasticsearch per region.** Every broker exports to both (two Camunda exporters). A legacy Elasticsearch exporter
  writes `zeebe-record*` to region 0 for Optimize.
- **Region 0** (`region0/`): combined release with its zone, Connectors, Management Identity, Keycloak (operator),
  Hub and Optimize. Hub, Identity and Optimize are single region and not part of a failover.
- **Region 1** (`region1/`): orchestration-only release (`global.topology.mode: orchestration`) that uses region 0's
  public Keycloak and Identity URLs.

This uses a combined release in region 0 instead of the separate Hub and Optimize releases the docs recommend for
dual region, to reuse the tested single-region pieces.

## Usage

Set the `_0` / `_1` variables in the root `config.mk` (see [`config.mk`](config.mk)). The region Makefiles map them
with `:=`, so single-region values such as `HOST_NAME` in the root `config.mk` do not leak in.

```bash
make -C region0 dependencies && make -C region1 dependencies   # Traefik, cert-manager, ES (+ Postgres, Keycloak in region 0)
make -C region0 dns certificate && make -C region1 dns certificate
# create camunda-process-secrets in both namespaces (orchestration-secret-store-file.yaml)
make -C region0 && make -C region0 allow-region1-login
make -C region1
make -C region0 topology                                       # 8 brokers, all partitions ACTIVE
```

Metrics: `make -C region0 metrics grafana-route`, then `prometheus-lb` in the networking recipe, then
`make -C region1 metrics`. Grafana is at `https://<HOST_NAME_0>/grafana`. Select both namespaces in the Zeebe dashboard
to see the stretched cluster as one.

Upgrades and restarts: one region at a time, region 0 first, and check `topology` in between.

## Cleanup

```bash
make -C region1 clean-metrics clean clean-dependencies clean-dns
make -C region0 clean-metrics clean clean-dependencies clean-dns
```

## Known limitations

- The documented dual-region failover procedure targets numbered brokers, not zone-aware ones. It is untested here.
- Optimize's partition count must be set through `optimize.extraConfiguration` (done in `region0/my-camunda-values.yaml`).
  Chart 15 otherwise uses the deprecated `optimize.partitionCount`, default 3, and Optimize misses partitions 4 to 8.
- The legacy `{{secrets.NAME}}` syntax is resolved by Connectors from their own providers, not from the file store,
  unless the Connectors runtime sets `camunda.connector.secret-resolver.legacy.mode=FALLBACK`.
