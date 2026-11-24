---
description: Tear down a dual-region Camunda GKE environment built with /create-gke-dual-region. Offers to save what would be lost, removes Camunda and its dependencies so disks and load balancers are released, deletes both clusters, then checks for leftovers that still cost money.
---

You are helping tear down a dual-region Camunda environment on GKE. This is **irreversible**: both clusters and everything stored in them (process models in Hub, Operate/Optimize data, Grafana history) are deleted.

The root of the repo is the git root: `git rev-parse --show-toplevel`. `<gke>` is `<root>/recipes/google/gke-dual-region` and `<cam>` is `<root>/recipes/camunda/dual-region-es-oidc`. All values come from the root `config.mk` (see `/create-gke-dual-region`, Step 0).

Run the steps one at a time, never in parallel: most of them switch the kube context.

---

## Step 0: Confirm

1. Read `GCP_PROJECT`, `CLUSTER_0`, `CLUSTER_1`, `KUBE_CONTEXT_0/1`, `HOST_NAME_0/1` and `DUAL_REGION_GCP_DNS_ZONE` from the root `config.mk` and show them.
2. Check `gcloud auth list --filter=status:ACTIVE`. If not authenticated, tell the user to run `! gcloud auth login`.
3. Show what exists: `gcloud container clusters list --project <GCP_PROJECT>`.
4. Ask: "This permanently deletes `<CLUSTER_0>` and `<CLUSTER_1>` and all data in them. Type YES to continue." Proceed only after YES. Do not ask again later.

## Step 1: Offer to save what would be lost

Ask once whether the user wants any of these first. Skip the ones they decline.

- **Deployed process models.** Use the Orchestration Cluster REST API through `HOST_NAME_0`: list `POST /v2/process-definitions/search`, then save each `GET /v2/process-definitions/<key>/xml` to a local folder the user names. Hub projects that were never deployed are not covered: tell the user to export them from Hub.
- **TLS certificates**, to avoid Let's Encrypt's limit of 5 certificates per week for the same names when rebuilding with the same hostnames: `TLS_SECRET_NAME` (default `tls-secret`) in both Camunda namespaces and `grafana-tls` in `default` on region 0. They hold private keys: save them outside the repo with mode 600, never print them.
- **Custom Grafana dashboards or Optimize reports** built during the demo: export them in the UI.

## Step 2: Remove workloads that hold disks and load balancers

Deleting a GKE cluster does not reliably delete the persistent disks of PVCs, so release them first. Region 1 first, then region 0:

```
make -C <cam>/region1 clean-metrics
make -C <cam>/region1 clean
make -C <cam>/region1 clean-dependencies
kubectl --context <KUBE_CONTEXT_1> delete namespace <CAMUNDA_NAMESPACE_1> --wait=true

make -C <cam>/region0 clean-metrics
make -C <cam>/region0 clean
make -C <cam>/region0 clean-dependencies
kubectl --context <KUBE_CONTEXT_0> delete namespace <CAMUNDA_NAMESPACE_0> --wait=true
```

`clean` uninstalls Camunda and deletes its PVCs. `clean-dependencies` removes Elasticsearch (and its PVCs), Keycloak, PostgreSQL, cert-manager and Traefik (and its load balancer). Deleting the namespace removes anything left, including remaining PVCs.

Check: `kubectl --context <ctx> get pvc -A` and `kubectl --context <ctx> get svc -A | grep LoadBalancer` show nothing from these recipes. Some errors from already-deleted resources are normal (the targets ignore them).

## Step 3: DNS records

Ask whether to keep the A records. They cost next to nothing, but they point at load balancer IPs that are released now and may later be given to someone else, so deleting them is the safer default:

```
make -C <cam>/region0 clean-dns
make -C <cam>/region1 clean-dns
```

## Step 4: Cross-region networking

```
make -C <gke> clean
```

Removes the DNS test pods, the Prometheus and kube-dns internal load balancers, the dns-chain CoreDNS and the firewall rule `<CLUSTER_0>-dual-region-pods` (the rule is named after `DEPLOYMENT_NAME`, which defaults to `CLUSTER_0` there).

## Step 5: Clusters

```
make -C <gke>/region0 clean
make -C <gke>/region1 clean
```

Deletion is asynchronous (`--async`). Wait until `gcloud container clusters list --project <GCP_PROJECT>` no longer shows them (about 5 to 10 minutes; check every minute or so with a bounded loop).

Then remove the stale contexts: `kubectl config delete-context <KUBE_CONTEXT_0>` and the same for `<KUBE_CONTEXT_1>`.

## Step 6: Check for leftovers that still cost money

```
gcloud compute disks list --project <GCP_PROJECT> --filter="-users:*" --format="table(name,zone.basename(),sizeGb,type.basename())"
gcloud compute forwarding-rules list --project <GCP_PROJECT> --format="table(name,region.basename(),IPAddress,description)"
gcloud compute addresses list --project <GCP_PROJECT> --filter="status=RESERVED"
gcloud compute firewall-rules list --project <GCP_PROJECT> --filter="name~<CLUSTER_0>|name~<CLUSTER_1>"
```

The disk filter lists unattached disks. The project is probably shared, so show the results and only offer to delete items that clearly belong to these clusters: names with `pvc-` created at about the time of the environment, or descriptions that mention `<CLUSTER_0>`, `<CLUSTER_1>`, the Camunda namespaces or `kube-dns-lb` / `prometheus-internal-lb`. Ask before deleting anything.

## Step 7: Report

Summarize what was deleted, anything kept (DNS records, saved files and where), and anything left over that the user has to decide on.
