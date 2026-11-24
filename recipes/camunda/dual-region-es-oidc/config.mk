# Shared defaults for both regions of the dual-region Camunda recipe.
# Create a config.mk file in the root directory of this project to override variables for your specific environment.
# region0/ and region1/ map the _0 / _1 values to the standard variables with :=, so the root config.mk cannot
# accidentally override them with single-region values (for example HOST_NAME or CAMUNDA_CLUSTER_SIZE).

# ── Regions ─────────────────────────────────────────────────────────────────
# Namespaces must differ between the regions (cross-cluster DNS forwards by namespace). They double as the
# zone names of the zone-aware Orchestration Cluster. For GKE, use the same values as recipes/google/gke-dual-region.
CAMUNDA_NAMESPACE_0 ?= region0
CAMUNDA_NAMESPACE_1 ?= region1
# kubectl contexts of the two clusters. Empty uses the current context (enough for `make camunda-values.yaml`).
KUBE_CONTEXT_0 ?=
KUBE_CONTEXT_1 ?=
# Fixed ClusterIP of the dns-chain CoreDNS the brokers resolve through (orchestration-dns-chain.yaml).
# Must match DNS_CHAIN_IP_0 / _1 of the networking recipe (recipes/google/gke-dual-region).
DNS_CHAIN_IP_0 ?= 10.104.0.53
DNS_CHAIN_IP_1 ?= 10.112.0.53
# Public hostnames. Region 0 also serves Hub, Management Identity, Keycloak (/auth) and Optimize.
HOST_NAME_0 ?= region0.example.com
HOST_NAME_1 ?= region1.example.com

# ── Camunda installation ────────────────────────────────────────────────────
CAMUNDA_RELEASE_NAME ?= camunda
CAMUNDA_CHART ?= camunda/camunda-platform
CAMUNDA_HELM_CHART_VERSION ?= 15.4.3
# Informational only for chart 15: image versions come from the chart defaults (15.4.3 ships 8.10.5 to 8.10.10).
CAMUNDA_VERSION ?= 8.10.x

# ── Orchestration Cluster topology ──────────────────────────────────────────
# Dual region needs an even cluster size of at least 4 and replication factor 4 (2 replicas per region).
# The docs recommend 8 brokers (4 per region). Separate names, so a single-region CAMUNDA_CLUSTER_SIZE in the
# root config.mk does not leak in.
DUAL_REGION_CLUSTER_SIZE ?= 8
DUAL_REGION_PARTITION_COUNT ?= 8
DUAL_REGION_REPLICATION_FACTOR ?= 4

DEFAULT_PASSWORD ?= changeme

# ── Keycloak (operator-managed, recipes/keycloak, region 0 only) ────────────
KEYCLOAK_ADMIN_USERNAME ?= temp-admin
KEYCLOAK_REALM ?= camunda-platform
KEYCLOAK_INGRESS ?= none

# ── PostgreSQL (CloudNativePG, recipes/postgres, region 0 only) ─────────────
POSTGRES_IDENTITY_HOST ?= pg-identity-rw
POSTGRES_IDENTITY_DB ?= identity
POSTGRES_IDENTITY_USERNAME ?= identity
POSTGRES_MODELER_HOST ?= pg-hub-rw
POSTGRES_MODELER_DB ?= hub
POSTGRES_MODELER_USERNAME ?= hub

# ── Networking ──────────────────────────────────────────────────────────────
# GCP Cloud DNS zone (name, not domain) that holds HOST_NAME_0 and HOST_NAME_1, used by `make dns`
DUAL_REGION_GCP_DNS_ZONE ?= $(GCP_DNS_ZONE)
TLS_SECRET_NAME ?= tls-secret
LB_SERVICE ?= $(TRAEFIK_RELEASE_NAME)
LB_NAMESPACE ?= $(TRAEFIK_NAMESPACE)
INGRESS_CLASS ?= traefik
