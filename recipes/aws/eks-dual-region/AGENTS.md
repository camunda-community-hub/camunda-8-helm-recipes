# AGENTS.md — AWS EKS Dual-Region Recipe

Context for AI agents answering install, architecture, and troubleshooting questions about this recipe.

---

## What This Recipe Does

Provisions two AWS EKS clusters with VPC peering and CoreDNS chaining, then deploys Camunda 8.9 across them as a dual-region stretch cluster. Uses Aurora PostgreSQL as the secondary store — **no Elasticsearch**.

Two separate recipe directories work together:

| Directory | Responsibility |
|---|---|
| `recipes/aws/eks-dual-region/` | AWS infrastructure: EKS clusters, VPC peering, DNS chaining |
| `recipes/camunda/dual-region-rdbms-postgres/` | Camunda Helm deployment to both clusters |

---

## Directory Structure

```
recipes/aws/eks-dual-region/
├── Makefile                          # VPC peering + DNS chaining (run after clusters exist)
├── config.mk                         # Shared defaults: DEPLOYMENT_NAME, machine type, cluster size
├── README.md                         # Quick-start install instructions
├── docs/
│   ├── eks-dual-region-playbook.md   # Architecture, failure scenarios, operational procedures
│   └── images/
│       └── camunda-aws-dual-region-v3.drawio.png  # Architecture diagram
├── AGENTS.md                         # This file
├── images/
│   └── camunda-aws-dual-region-v3.drawio.png  # Architecture diagram
├── region0/
│   ├── Makefile                      # Creates EKS cluster 0 (run independently)
│   └── config.mk                     # AWS_REGION_0, AWS_ZONES_0, VPC_CIDR_0, CLUSTER_0
└── region1/
    ├── Makefile                      # Creates EKS cluster 1 (run independently)
    └── config.mk                     # AWS_REGION_1, AWS_ZONES_1, VPC_CIDR_1, CLUSTER_1

recipes/camunda/dual-region-rdbms-postgres/
├── config.mk                         # Shared Camunda config: chart version, cluster sizing, DB
├── my-camunda-values.yaml            # Shared Helm overrides (merged into all regions)
├── region0/
│   ├── Makefile                      # Deploys Camunda to cluster 0
│   ├── config.mk                     # REGION_ID=0, CAMUNDA_NAMESPACE, KUBE_CONTEXT
│   └── my-camunda-values.yaml        # Region 0 Helm overrides (applied last)
└── region1/
    ├── Makefile                      # Deploys Camunda to cluster 1
    ├── config.mk                     # REGION_ID=1, CAMUNDA_NAMESPACE, KUBE_CONTEXT
    └── my-camunda-values.yaml        # Region 1 Helm overrides (applied last)

makefiles/
├── aws-dual-region-networking.mk # VPC peering, security groups, DNS chaining targets
└── camunda-dual-region.mk            # Cross-region operational targets (topology, partition sim)

recipes/aws/include/
└── internal-dns-lb.yml               # Kubernetes Service: exposes kube-dns via internal NLB
```

---

## Architecture

See `docs/eks-dual-region-playbook.md` and `docs/images/camunda-aws-dual-region-v3.drawio.png` for the full diagram.

### Summary

```
Region 0 (Primary — serves client traffic)     Region 1 (Secondary — Raft participant)
┌──────────────────────────────────┐           ┌──────────────────────────────────┐
│  EKS Cluster 0                   │           │  EKS Cluster 1                   │
│  Namespace: camunda-region0      │           │  Namespace: camunda-region1      │
│                                  │◄─────────►│                                  │
│  orchestration pod:              │  VPC peer │  orchestration pod:              │
│    Zeebe Broker 0 (node 0)       │  + CoreDNS│    Zeebe Broker 0 (node 1)       │
│    Zeebe Broker 1 (node 2)       │  chaining │    Zeebe Broker 1 (node 3)       │
│    Zeebe Gateway                 │           │    Zeebe Gateway                 │
│    Operate  ┐ bundled, accessed  │           │    Operate  ┐ bundled (not       │
│    Tasklist ┘ via gateway:8080   │           │    Tasklist ┘ user-facing)       │
│  Aurora PostgreSQL (shared)      │           │  Aurora PostgreSQL (shared)      │
│                                  │           │                                  │
│  Namespace: kube-system          │           │  Namespace: kube-system          │
│    CoreDNS → forwards r1 queries │           │    CoreDNS → forwards r0 queries │
│    kube-dns-lb (internal NLB)    │           │    kube-dns-lb (internal NLB)    │
└──────────────────────────────────┘           └──────────────────────────────────┘
```

### Key Design Decisions

**No Elasticsearch.** The RDBMS exporter writes process/task data to Aurora PostgreSQL. Operate and Tasklist read from PostgreSQL instead of Elasticsearch. This simplifies the dual-region setup significantly — no Elasticsearch stretch cluster required.

**Operate and Tasklist are bundled.** In Camunda 8.9, Operate and Tasklist are part of the `orchestration` Helm component. They run inside the same pod as the Zeebe broker/gateway and are accessed via the `camunda-zeebe-gateway` service on port 8080. There are no separate `camunda-operate` or `camunda-tasklist` Kubernetes services.

**Client traffic goes to region 0 only.** Region 1 is not a user-facing entry point under normal operation. Its Zeebe brokers participate in Raft consensus and may hold partition leadership for some partitions, but users access Operate/Tasklist/REST API through region 0's gateway.

**"Active-active" refers to the Raft layer.** Both regions' brokers can hold partition leadership (unlike old active-passive where region 1 was follower-only). A command submitted to region 0's gateway may be routed internally to a partition leader in region 1 — this is transparent to the client.

**Quorum requires both regions.** With 4 brokers total (2 per region) and replicationFactor=4, losing one region loses quorum. Processing stops until failover is executed or connectivity is restored.

---

## Networking: VPC Peering + DNS Chaining

Cross-region connectivity is a two-layer problem.

**Layer 1 — VPC Peering (IP routing)**
`make configure-vpc-peering` (in `aws-dual-region-networking.mk`) creates a VPC peering connection and adds routes to every route table in each VPC so pod CIDRs are mutually reachable.

**Layer 2 — CoreDNS chaining (service DNS)**
`make configure-dns` does two things:
1. Applies `recipes/aws/include/internal-dns-lb.yml` to each cluster — creates a `kube-dns-lb` Service (internal AWS NLB, TCP port 53 only) in `kube-system` that exposes `kube-dns` at a stable private IP reachable via the peering link.
2. Patches the CoreDNS ConfigMap in each cluster to add a stub zone forwarding queries for the remote namespace (e.g., `camunda-region1.svc.cluster.local`) to the other cluster's NLB IP using `force_tcp`.

> AWS NLBs do not support mixed TCP/UDP on the same port. TCP-only is used with `force_tcp` in CoreDNS to match.

---

## Zeebe Cluster Topology

| Property | Value |
|---|---|
| clusterSize | 4 total (2 per region) |
| replicationFactor | 4 (every partition on every broker) |
| partitionCount | 4 |
| Node ID formula | `podIndex * regions + regionId` |

| Pod | Region | Node ID |
|---|---|---|
| `camunda-zeebe-0` | Region 0 | 0 |
| `camunda-zeebe-1` | Region 0 | 2 |
| `camunda-zeebe-0` | Region 1 | 1 |
| `camunda-zeebe-1` | Region 1 | 3 |

---

## Configuration Variables

### Infrastructure (`recipes/aws/eks-dual-region/`)

| Variable | Default | Description |
|---|---|---|
| `DEPLOYMENT_NAME` | `my-camunda` | Prefix for cluster names |
| `AWS_MACHINE_TYPE` | `m5.2xlarge` | EC2 instance type |
| `CLUSTER_VERSION` | `1.35` | EKS Kubernetes version |
| `DESIRED_SIZE` | `4` | Node group desired size |
| `AWS_REGION_0` | `us-west-1` | Region 0 AWS region |
| `VPC_CIDR_0` | `10.195.0.0/16` | Region 0 VPC CIDR (must not overlap with CIDR_1) |
| `CLUSTER_0` | `$(DEPLOYMENT_NAME)-region0` | Cluster 0 name (frozen at include time) |
| `AWS_REGION_1` | `us-east-2` | Region 1 AWS region |
| `VPC_CIDR_1` | `10.196.0.0/16` | Region 1 VPC CIDR (must not overlap with CIDR_0) |
| `CLUSTER_1` | `$(DEPLOYMENT_NAME)-region1` | Cluster 1 name (frozen at include time) |

Override without editing committed files by creating a `config.mk` at the repo root.

### Camunda (`recipes/camunda/dual-region-rdbms-postgres/`)

| Variable | Description |
|---|---|
| `REGION_ID` | 0 or 1 — set per-region in `region0/config.mk` / `region1/config.mk` |
| `CAMUNDA_NAMESPACE` | Kubernetes namespace — MUST differ between regions |
| `KUBE_CONTEXT` | kubectl context name — maps to `CLUSTER_0` or `CLUSTER_1` |
| `CAMUNDA_RELEASE_NAME` | Helm release name |
| `CAMUNDA_HELM_VERSION` | Camunda Helm chart version |
| `POSTGRES_HOST` | Aurora cluster endpoint hostname |
| `CAMUNDA_CLUSTER_SIZE` | Total Zeebe brokers across both regions (default: 4) |
| `CAMUNDA_REPLICATION_FACTOR` | Must equal clusterSize for dual-region (default: 4) |
| `CAMUNDA_PARTITION_COUNT` | Number of partitions (default: 4) |
| `ZEEBE_INITIAL_CONTACT_POINTS` | Comma-separated broker addresses across both regions |

---

## Make Targets

### Infrastructure (run from `recipes/aws/eks-dual-region/`)

| Target | Description |
|---|---|
| `make -C region0` | Create EKS cluster 0 (~15-20 min) |
| `make -C region1` | Create EKS cluster 1 (~15-20 min, run in parallel with region0) |
| `make` | Run `configure-vpc-peering` then `configure-dns` |
| `make configure-vpc-peering` | Create VPC peering, accept connection, add routes both directions |
| `make configure-dns` | Deploy internal NLB + patch CoreDNS in both clusters |
| `make test-dns` | Verify cross-region DNS resolution |
| `make add-contexts` | Add both clusters to kubeconfig |
| `make verify-contexts` | Check kubectl contexts are configured |
| `make vpc-peering-status` | Show current peering connection state |
| `make clean-vpc-peering` | Delete VPC peering connection |
| `make clean` | Remove VPC peering (clusters remain) |
| `make -C region0 clean` | Delete EKS cluster 0 |
| `make -C region1 clean` | Delete EKS cluster 1 |

### Camunda Deployment (run from `recipes/camunda/dual-region-rdbms-postgres/`)

| Target | Description |
|---|---|
| `make -C region0` | Deploy Camunda to cluster 0 |
| `make -C region1` | Deploy Camunda to cluster 1 |
| `make -C region0 clean` | Uninstall Camunda from cluster 0 |
| `make -C region1 clean` | Uninstall Camunda from cluster 1 |

### Cross-Region Operations (defined in `makefiles/camunda-dual-region.mk`)

| Target | Description |
|---|---|
| `make topology` | Check Zeebe cluster topology via region 0 gateway |
| `make pods-region0` | List pods in region 0 namespace |
| `make pods-region1` | List pods in region 1 namespace |
| `make use-region0` | Switch kubectl context to cluster 0 |
| `make use-region1` | Switch kubectl context to cluster 1 |
| `make simulate-partition` | Remove VPC routes to simulate network partition |
| `make restore-partition` | Restore VPC routes and recover connectivity |

---

## Install Order

1. **Configure** — edit `config.mk` files with your AWS region, zones, VPC CIDRs, deployment name
2. **Create clusters in parallel** — `make -C region0` in one terminal, `make -C region1` in another
3. **Add kubeconfig contexts** — `make add-contexts`
4. **Wire networking** — `make` (runs peering + DNS in sequence)
5. **Verify DNS** — `make test-dns`
6. **Deploy Camunda** — `make -C region0` and `make -C region1` (can run in parallel)
7. **Verify topology** — `make topology` (expect 4 brokers, all partitions healthy)

---

## Accessing the UI

Operate and Tasklist are bundled into the `orchestration` component and served via the Zeebe gateway. There are no separate `camunda-operate` or `camunda-tasklist` services.

```bash
kubectl --context <cluster-0> -n <namespace-0> \
  port-forward svc/camunda-zeebe-gateway 8080:8080

# Operate:  http://localhost:8080/operate   (default: demo/demo)
# Tasklist: http://localhost:8080/tasklist
# REST API: http://localhost:8080/v2/topology
```

---

## Helm Values Pipeline

Each region's `camunda-values.yaml` is generated by merging files listed in `CAMUNDA_HELM_VALUES` using `yq eval-all '. as $item ireduce ({}; . * $item)'`, then substituting `<PLACEHOLDER>` tokens with `sed`.

Merge order (later files override earlier):
1. Shared values from `camunda-values.yaml.d/` (RDBMS base, dual-region config)
2. Recipe-level `my-camunda-values.yaml`
3. Region-specific `region0/my-camunda-values.yaml` or `region1/my-camunda-values.yaml`

Key values file: `camunda-values.yaml.d/orchaestration-dual-region-postgres.yaml`
- Sets `global.multiregion.regions: 2` and `global.multiregion.regionId: <REGION_ID>`
- Disables Identity auth (`global.identity.auth.enabled: false`)
- Sets Zeebe cluster sizing and cross-region contact points via `CAMUNDA_CLUSTER_INITIAL-CONTACT-POINTS`
- Configures GZIP compression and adjusted SWIM probe timeouts for cross-region latency

> **Array merge gotcha:** `yq` replaces arrays entirely — it does not merge them. If two values files both define `orchestration.env`, only the last one wins.

---

## Common Issues

**Zeebe brokers can't see each other across regions**
- Check VPC peering status: `make vpc-peering-status`
- Verify routes exist in both VPCs' route tables
- Test DNS: `make test-dns`
- Check CoreDNS config: `kubectl -n kube-system get configmap coredns -o yaml`

**`camunda-values.yaml` is empty**
- All files listed in `CAMUNDA_HELM_VALUES` must exist. A missing file causes `yq` to produce empty output silently.
- Check that `region0/my-camunda-values.yaml` exists (it's not gitignored, it must be present).

**Wrong cluster context used**
- Each region Makefile sets `KUBE_CONTEXT` before including shared `.mk` files. All `kubectl` and `helm` commands pass `--context $(KUBE_CONTEXT)`.
- Run `kubectl config get-contexts` to verify context names match `CLUSTER_0` / `CLUSTER_1`.

**`camunda-operate` service not found**
- Expected in Camunda 8.9. Operate and Tasklist are bundled — use `svc/camunda-zeebe-gateway` on port 8080.

**Aurora connection timeout from pods**
- Verify the RDS security group allows inbound TCP 5432 from the EKS node security group or VPC CIDR.
- Verify Aurora is not publicly accessible (use private endpoint within VPC).
- Check the pod VPC CIDR matches the SG rule: `kubectl get pods -o wide` to see pod IPs.

**CLUSTER_1 expanding to `name-region1-region1`**
- Caused by recursive `?=` re-expanding after `DEPLOYMENT_NAME` is overridden. Fixed with `ifndef`/`:=` pattern in `region1/config.mk`. Do not change the variable assignment style.

---

## Limitations

- Identity (RBAC, multi-tenancy) not supported in dual-region
- Optimize not supported
- OpenSearch not supported
- Connectors can be deployed but require idempotent design
- Losing either region stops processing (quorum requires 3 of 4 brokers)
- Max recommended network RTT between regions: 100ms
