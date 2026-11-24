# Dual-region GKE: infrastructure recipe

Creates two regional GKE clusters in one VPC and connects them so a Camunda Orchestration Cluster can be stretched
across both regions. Camunda itself is installed by [`recipes/camunda/dual-region-es-oidc`](../../camunda/dual-region-es-oidc).
For the full sequence with checks, use the `/create-gke-dual-region` and `/destroy-gke-dual-region` Claude Code commands
in `.claude/commands/`.

## How the regions are connected

- **Routing:** a GCP VPC is global and VPC-native clusters get routable pod IPs, so pods reach each other across
  regions without peering. `firewall-dual-region` adds one rule for the two pod ranges. Pod and service ranges must
  not overlap (`GCP_CLUSTER_IPV4_CIDR_x`, `GCP_SERVICES_IPV4_CIDR_x`).
- **DNS chaining:** each cluster exposes kube-dns on an internal load balancer with global access
  ([`internal-dns-lb.yaml`](../include/internal-dns-lb.yaml)). A small CoreDNS (`dns-chain`, fixed ClusterIP
  `DNS_CHAIN_IP_x`, [`dns-chain.tpl.yaml`](../include/dns-chain.tpl.yaml)) forwards `<other namespace>.svc.cluster.local`
  to the other cluster and everything else to the local kube-dns. The Zeebe brokers resolve through it
  ([`orchestration-dns-chain.yaml`](../../../camunda-values.yaml.d/orchestration-dns-chain.yaml)).
  kube-dns `stubDomains` do not work for this on GKE: the managed kube-dns answers NXDOMAIN for names under
  `cluster.local` before the forward is reached.
- ClusterIPs are not routable between clusters: use headless services or public URLs across regions.

## Prerequisites

- `gcloud` authenticated, `kubectl`, `helm`, GNU `make`
- Regional vCPU quota for both regions (6 x n1-standard-16 per region to start, up to 12 with autoscaling)

## Usage

Set at least `GCP_PROJECT`, `CLUSTER_0` and `CLUSTER_1` in the root `config.mk` (see [`config.mk`](config.mk) for
all defaults). Namespaces default to the region names and must match the Camunda recipe.

```bash
make -C region0                 # cluster + default SSD storage class (can run in parallel with region1)
make -C region1
make                            # firewall rule, DNS load balancers, dns-chain
make test-dns && make clean-dns-test
```

After Elasticsearch is installed in both regions: `make sync-elasticsearch-passwords`.
After the metrics stack is installed in region 0: `make prometheus-lb` (region 1's Prometheus remote-writes to it).

## Cleanup

```bash
make clean                      # test pods, internal load balancers, dns-chain, firewall rule
make -C region0 clean           # deletes the cluster (async)
make -C region1 clean
```

Delete the Camunda releases and their PVCs first, otherwise their disks may be left behind
(see `/destroy-gke-dual-region`).

## Limitations

- Same-project, same-VPC only.
- Uses kube-dns (`--cluster-dns=kubedns`), not Cloud DNS.
