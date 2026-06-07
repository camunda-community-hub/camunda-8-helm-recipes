# Provision GCP Google Kubernetes Engine (GKE)

This recipe provisions a GKE cluster using **Spot VMs** by default (lower cost, but subject to preemption by Google). It also includes optional targets for an NGINX Ingress Controller, Let's Encrypt TLS, and Prometheus/Grafana metrics.

## Prerequisites

- A GCP account with permissions to create GKE clusters.
- [Google Cloud CLI (`gcloud`)](https://cloud.google.com/cli) installed and configured.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed.
- [Helm](https://helm.sh/docs/intro/install/) installed.

Verify your `gcloud` setup with:
```sh
make check-gcloud
```

## Configuration

Copy `config.mk` and set your values before running any targets:

| Variable | Default | Description |
|---|---|---|
| `DEPLOYMENT_NAME` | `mydeployment` | Name of the GKE cluster |
| `GCP_PROJECT` | `xyz` | GCP project ID |
| `GCP_REGION` | `us-east4-a` | GCP region or zone |
| `GCP_MACHINE_TYPE` | `n1-standard-16` | Machine type for the default node pool |
| `MIN_SIZE` | `1` | Minimum nodes for autoscaling |
| `MAX_SIZE` | `10` | Maximum nodes for autoscaling |
| `GCP_USE_SPOT` | `true` | Use Spot VMs (`true`) or standard VMs (`false`) |

## Install

Creates a GKE cluster with autoscaling enabled. By default uses Spot VMs (lower cost, subject to preemption). Set `GCP_USE_SPOT = false` in `config.mk` for standard VMs:

```sh
make                       # spot VMs (default)
make GCP_USE_SPOT=false    # standard VMs
```

Connect to an existing cluster (refreshes `kubectl` credentials):
```sh
make connect-gke
```

## Uninstall

```sh
make clean
```

> **Note:** PVCs (persistent disks) are not automatically deleted. Check the [GCP Disks console](https://console.cloud.google.com/compute/disks) and delete any orphaned disks to avoid ongoing charges.

## Node Pools

### Default node pool

The cluster is created with autoscaling enabled in both modes. Spot VMs are cheaper but can be preempted by Google at any time — fine for development and testing, but risky for demos or production. Standard VMs are stable but cost more.

Create an additional high-performance Spot node pool (c3-standard-8, with a `dedicated=high-performance:PreferNoSchedule` taint):
```sh
make node-pool
```

### Migrating to a standard (non-spot) node pool for demos

To avoid preemption during a demo, migrate your workloads to a standard node pool before the demo and restore afterwards.

**Before the demo** — creates a standard autoscaling node pool and drains all pods off spot nodes:
```sh
make migrate-to-standard-pool
```

This runs three steps in sequence:
1. `make node-pool-standard` — creates a non-spot node pool with autoscaling (`MIN_SIZE`/`MAX_SIZE` apply, overridable via `STANDARD_POOL_MIN_NODES` / `STANDARD_POOL_MAX_NODES`; default 1–6 nodes)
2. `make cordon-spot-nodes` — prevents new pods from being scheduled on spot nodes
3. `make drain-spot-nodes` — reschedules all pods onto the standard pool

The standard pool autoscales: if you scale up Zeebe brokers and the cluster runs out of CPU, GKE will add nodes automatically (allow 2–4 minutes for provisioning).

**After the demo** — uncordons spot nodes and deletes the standard pool:
```sh
make restore-spot-pool
```

Verify the migration at any point:
```sh
kubectl get nodes
kubectl get pods -o wide
```

## Ingress and TLS

Install NGINX Ingress Controller, cert-manager, and a Let's Encrypt production certificate issuer:
```sh
make setup-ingress-nginx
```

This runs: `make ingress-nginx cert-manager letsencrypt-prod`

Requires `CERT_MANAGER_EMAIL` to be set in your `config.mk`.

## Metrics (Prometheus / Grafana)

Install the Prometheus + Grafana stack:
```sh
make setup-metrics
```

Get the Grafana admin password:
```sh
make grafana-password
```

Get the Grafana URL:
```sh
make url-grafana
```

Requires `GRAFANA_PASSWORD` to be set in your `config.mk`.

## Useful Commands

| Target | Description |
|---|---|
| `make connect-gke` | Refresh `kubectl` credentials for the cluster |
| `make urls` | Print GCP console URLs for the cluster and workloads |
| `make disks` | List PVCs (persistent disks) associated with the cluster |
| `make ssd-storageclass` | Apply the SSD storage class to the cluster |
