# Dual-region GKE - shared defaults for both regions and the networking targets.
# Create a config.mk in the project root to override these defaults.

DEPLOYMENT_NAME ?= mydeployment
GCP_PROJECT ?= xyz
# Both clusters join this VPC. A GCP VPC is global, so no peering is needed between the regions.
GCP_NETWORK ?= default

# ── Node pools (shared) ─────────────────────────────────────────────────────
# Regional clusters: GCP_NUM_NODES, MIN_SIZE and MAX_SIZE count per zone (3 zones per region).
# Standard (non-spot) nodes, so brokers are not preempted during a demo.
# Own names, mapped with := in region0/ and region1/, so single-cluster values in the root config.mk do not leak in.
DUAL_REGION_MACHINE_TYPE ?= n1-standard-16
DUAL_REGION_USE_SPOT ?= false
DUAL_REGION_NUM_NODES ?= 2
DUAL_REGION_MIN_SIZE ?= 1
DUAL_REGION_MAX_SIZE ?= 4

# kube-dns (not Cloud DNS), because the dns-chain CoreDNS forwards to the kube-dns service (makefiles/google-dual-region-networking.mk)
GCP_CLUSTER_DNS ?= kubedns

# ── Region 0 ────────────────────────────────────────────────────────────────
ifndef CLUSTER_0
CLUSTER_0 := $(DEPLOYMENT_NAME)-region0
endif
GCP_REGION_0 ?= us-central1
# Namespaces must differ between the regions (DNS chaining forwards by namespace).
# They double as the zone names of the zone-aware Orchestration Cluster.
CAMUNDA_NAMESPACE_0 ?= $(GCP_REGION_0)
# Pod and service ranges must not overlap between the clusters
GCP_CLUSTER_IPV4_CIDR_0 ?= 10.100.0.0/14
GCP_SERVICES_IPV4_CIDR_0 ?= 10.104.0.0/20

# ── Region 1 ────────────────────────────────────────────────────────────────
ifndef CLUSTER_1
CLUSTER_1 := $(DEPLOYMENT_NAME)-region1
endif
GCP_REGION_1 ?= us-east4
CAMUNDA_NAMESPACE_1 ?= $(GCP_REGION_1)
GCP_CLUSTER_IPV4_CIDR_1 ?= 10.108.0.0/14
GCP_SERVICES_IPV4_CIDR_1 ?= 10.112.0.0/20
