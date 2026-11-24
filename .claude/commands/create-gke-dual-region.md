---
description: Create a dual-region Camunda 8.10 environment on two GKE clusters (Helm chart 15) with a zone-aware Orchestration Cluster stretched across both regions, Elasticsearch per region, Keycloak OIDC, Hub, Optimize, Traefik, Let's Encrypt TLS and a shared Prometheus/Grafana. Validates config first, then runs the full sequence with checks.
---

You are helping provision a dual-region Camunda 8.10 environment on Google GKE. Follow the steps in order and run them with the Bash tool so the user sees the output. Stop at the first failed check and investigate before moving on.

What gets built:
- Two regional GKE clusters (region 0 and region 1) in one VPC, with routable pod IPs and cross-cluster DNS (`recipes/google/gke-dual-region`).
- One Orchestration Cluster stretched over both: zone-aware partitioning, zone name = namespace = GCP region, 8 brokers, 8 partitions, replication factor 4 (2 replicas per region). Each region exports to its own and the other region's Elasticsearch.
- Region 0 is a combined release: its zone of the Orchestration Cluster plus Connectors, Management Identity, Keycloak, Hub and Optimize. Region 1 is an orchestration-only release that logs in through region 0's public Keycloak URL (`recipes/camunda/dual-region-es-oidc`).
- Prometheus in both clusters. Region 1 remote-writes to region 0, and one Grafana at `https://<HOST_NAME_0>/grafana` shows both.

The root of the repo is the git root: `git rev-parse --show-toplevel`. Below, `<gke>` is `<root>/recipes/google/gke-dual-region` and `<cam>` is `<root>/recipes/camunda/dual-region-es-oidc`.

**Never run two targets that switch the kube context at the same time.** Most region targets run `kubectl config use-context`. Only the two `kube` (cluster creation) steps may run in parallel.

---

## Step 0: Validate config

Read `<root>/config.mk`. If it exists, **never overwrite it**: check the variables below with `grep`, report what is missing, and offer to append the missing ones at the end. If it does not exist, ask for the values one at a time, then show a preview before writing.

| Variable | Example | Notes |
|---|---|---|
| `GCP_PROJECT` | `my-project` | |
| `CLUSTER_0`, `CLUSTER_1` | `<firstname>01`, `<firstname>02` | Cluster names. Also used for the firewall rule name (`DEPLOYMENT_NAME`) |
| `CAMUNDA_NAMESPACE_0`, `CAMUNDA_NAMESPACE_1` | `us-central1`, `us-east4` | Must equal `GCP_REGION_0` / `GCP_REGION_1` (defaults) and differ from each other. They are also the zone names |
| `KUBE_CONTEXT_0`, `KUBE_CONTEXT_1` | `gke_<project>_us-central1_<cluster0>` | `gke_<GCP_PROJECT>_<region>_<cluster>` |
| `HOST_NAME_0`, `HOST_NAME_1` | `<cluster0>.gke.example.com` | Must be in a Cloud DNS zone the user controls |
| `DUAL_REGION_GCP_DNS_ZONE` | `my-zone` | Zone **name**, not the domain |
| `CERT_MANAGER_EMAIL` | | Let's Encrypt account |
| `DEFAULT_PASSWORD`, `GRAFANA_PASSWORD` | | Flag `changeme`. Offer `openssl rand -hex 16`. Grafana is public |

Defaults worth showing the user (override in the root `config.mk` only if they want something else): regions `us-central1` and `us-east4`, `DUAL_REGION_MACHINE_TYPE=n1-standard-16`, `DUAL_REGION_NUM_NODES=2` per zone, autoscaling 1 to 4 per zone, standard (not spot) nodes, `DUAL_REGION_CLUSTER_SIZE=8`, `DUAL_REGION_PARTITION_COUNT=8`, `DUAL_REGION_REPLICATION_FACTOR=4`.

Also flag:
- Any `SECRET_*` variables in the root `config.mk`. The generic `create-process-secrets` target turns **every** one of them into a process secret, so this runbook creates the process secret directly instead (Step 5).
- Single-region variables such as `HOST_NAME`, `CAMUNDA_CLUSTER_SIZE` or `MIN_SIZE` are fine: the dual-region recipes map their own `_0` / `_1` and `DUAL_REGION_*` variables with `:=`, so these do not leak in.

Ask the user to confirm before anything billable is created. Rough cost at list prices: about $9 to $10 per hour for both clusters (12 x n1-standard-16 plus disks and load balancers). Say it is an estimate.

## Prerequisites

- `gcloud auth list --filter=status:ACTIVE` shows an account. If not, tell the user to run `! gcloud auth login`.
- `kubectl`, `helm`, `yq` and `jq` are installed. `helm repo add camunda https://helm.camunda.io && helm repo update camunda`.
- Regional quota: `gcloud compute regions describe <region> --format="value(quotas)"` for both regions. `N1_CPUS` (or `CPUS`) must allow `DUAL_REGION_MAX_SIZE x 3 zones x 16` vCPUs if the pools may scale to the maximum. At least 96 vCPUs per region for the initial 6 nodes.
- The DNS zone exists: `gcloud dns managed-zones list --project <GCP_PROJECT>`.
- Something on the user's machine on port 9600 is common (a local Zeebe). The `topology` target uses local port 19600 for that reason.

---

## Step 1: Clusters (about 10 minutes)

Both may run in parallel (each writes its own log), then set the default storage class one at a time:

```
make -C <gke>/region0 kube    # background, log to a file
make -C <gke>/region1 kube    # background, log to a file
```

After both finish:

```
make -C <gke>/region0 default-ssd-storageclass
make -C <gke>/region1 default-ssd-storageclass
```

Check: `kubectl --context <KUBE_CONTEXT_x> get nodes -L topology.kubernetes.io/zone` shows 6 nodes over 3 zones per region, and `premium-rwo` is the only default storage class.

## Step 2: Cross-region networking

```
make -C <gke>              # firewall rule for the pod ranges, kube-dns internal LBs, dns-chain CoreDNS
make -C <gke> test-dns     # must pass both directions
make -C <gke> clean-dns-test
```

`test-dns` proves cross-cluster DNS, pod routing and the firewall rule. Do not continue if it fails.

## Step 3: Dependencies (about 10 minutes per region)

Region 0 gets Traefik, cert-manager, CloudNativePG Postgres, the Keycloak operator and Elasticsearch. Region 1 gets Traefik, cert-manager and Elasticsearch. Run them one after the other:

```
make -C <cam>/region0 dependencies
make -C <cam>/region1 dependencies
make -C <gke> sync-elasticsearch-passwords
```

`sync-elasticsearch-passwords` copies each region's `elastic` password into both namespaces, because every broker exports to both Elasticsearch clusters. Re-run it whenever an Elasticsearch cluster is recreated.

## Step 4: DNS and certificates

```
make -C <cam>/region0 dns
make -C <cam>/region1 dns
```

Wait until `dig +short <HOST_NAME_x>` and `dig +short grpc.<HOST_NAME_x>` return the Traefik IPs, then:

```
make -C <cam>/region0 certificate
make -C <cam>/region1 certificate
```

Let's Encrypt allows 5 certificates per week for the same set of names. If the environment is rebuilt often with the same hostnames, export the TLS secrets before teardown and re-apply them instead of requesting new ones.

## Step 5: Process secrets (before Camunda)

Both releases mount the `camunda-process-secrets` Secret (`orchestration-secret-store-file.yaml`), and brokers do not start without it. Ask the user which secrets the demo needs (names and where the values come from). Create the Secret in **both** namespaces with the same keys, so secrets still resolve after a failover:

- Write the values to an env file in the scratchpad with mode 600 (`umask 077`), never echo them, and delete the file afterwards.
- `kubectl --context <ctx> -n <ns> create secret generic camunda-process-secrets --from-env-file=<file> --dry-run=client -o yaml | kubectl --context <ctx> apply -f -`
- With no secrets yet, create it empty. Adding keys later: patch the Secret in both namespaces, then restart the brokers one region at a time (Step 9).

Reading real credentials from a file on the user's machine needs the user's explicit approval. Placeholder values do not.

Process models reference them as `=camunda.secrets.NAME`. The legacy `{{secrets.NAME}}` form is resolved by Connectors from their own providers and does **not** read this store unless the Connectors runtime sets `camunda.connector.secret-resolver.legacy.mode=FALLBACK`.

## Step 6: Camunda (about 10 minutes per region)

Region 0 first, because region 1 authenticates against region 0's Keycloak and Identity:

```
make -C <cam>/region0
make -C <cam>/region0 allow-region1-login
make -C <cam>/region1
```

`allow-region1-login` adds `https://<HOST_NAME_1>/*` to the `orchestration` Keycloak client, so users can log in to region 1's Operate and Tasklist.

Checks:
- `make -C <cam>/region0 topology`: 8 brokers (`<zone>_0` to `<zone>_3` per region), every partition ACTIVE, `pendingChange: null`.
- All pods Ready in both namespaces.
- `https://<HOST_NAME_0>/` and `https://<HOST_NAME_1>/` redirect to Keycloak on `HOST_NAME_0`.
- Both Elasticsearch clusters have the Camunda indices, and region 0's has `zeebe-record*` indices (Optimize).

## Step 7: Metrics

```
make -C <cam>/region0 metrics          # Prometheus + Grafana
make -C <cam>/region0 grafana-route    # certificate + IngressRoute for /grafana
make -C <gke> prometheus-lb            # internal LB, region 1 remote-writes to it
make -C <cam>/region1 metrics          # Prometheus only, remote write to region 0
```

The `metrics` target prints the Grafana password. Do not repeat it in your messages. The user is `camunda`, and the password is `GRAFANA_PASSWORD`.

Check through a port-forward to region 0's Prometheus (`svc/metrics-kube-prometheus-st-prometheus`, port 9090): `count by (namespace) (count by (namespace, pod) (atomix_role))` returns 4 for each namespace. Allow a minute or two for the first scrapes.

Dashboard: **Zeebe** (`/grafana/d/zeebe-dashboard/zeebe`). Leave the namespace variable on All, or select both regions, to see the stretched cluster as one. Throughput comes from partition leaders only, so it is not double counted. Leaders usually sit in region 0 (higher zone priority), so region 1 shows replication but no processing. That is expected.

## Step 8: Smoke test

Deploy and start a small process through both hosts with the `connectors` client (it has a CREATE/READ grant for this, see `my-camunda-values.yaml`), and check the instances complete and appear in Operate in both regions and in Optimize. Optimize imports with a delay of a minute or two.

## Step 9: Changing things later

- Helm values: `make -C <cam>/region0 use-context update-camunda`, wait for health, then the same for region 1. Never both at once.
- Restarting brokers (for example after changing process secrets): `kubectl --context <ctx> -n <ns> rollout restart sts camunda-zeebe-<ns>`, wait for `rollout status` and a healthy `topology`, then the other region.

---

## Gotchas found while building this

- GKE's managed kube-dns (CoreDNS based) ignores `stubDomains` for names under `cluster.local` and answers NXDOMAIN. That is why the recipe runs its own `dns-chain` CoreDNS and the brokers use `dnsConfig`. The cluster flag is `--cluster-dns=kubedns` (not `kube-dns`).
- ClusterIPs are not routable between the clusters. Cross-region traffic uses headless services (brokers, `elasticsearch-es-masters`) or public URLs.
- Optimize's partition count in chart 15 comes from the deprecated `optimize.partitionCount` (default 3), not from `orchestration.partitionCount`. The region 0 values set `zeebe.partitionCount` through `optimize.extraConfiguration`. Without it Optimize silently misses everything on partitions 4 to 8, including the agentic control plane data.
- The management API is at `:9600/orchestration/actuator/...` (context path).
- Hub, Management Identity, Keycloak and Optimize live only in region 0 and are not part of a failover. The documented dual-region failover procedure targets numbered brokers, not zone-aware ones. Treat failover as a talking point unless it has been tested on this setup.
