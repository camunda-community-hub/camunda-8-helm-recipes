# Dual-Region Camunda - Shared Configuration
# Create a config.mk in the project root to override these defaults.

CAMUNDA_RELEASE_NAME ?= camunda
CAMUNDA_CHART        ?= camunda/camunda-platform

CAMUNDA_HELM_CHART_VERSION ?= 14.0.0
CAMUNDA_VERSION            ?= 8.9.0

DEFAULT_PASSWORD ?= changeme

# ── Zeebe cluster sizing (total across BOTH regions) ────────────────────────
CAMUNDA_CLUSTER_SIZE       ?= 4
CAMUNDA_REPLICATION_FACTOR ?= 4
CAMUNDA_PARTITION_COUNT    ?= 4

BROKERS_PER_REGION ?= $(shell echo $$(( $(CAMUNDA_CLUSTER_SIZE) / 2 )))

# ── Namespaces (must differ between regions for DNS chaining) ────────────────
CAMUNDA_NAMESPACE_0 ?= camunda-region0
CAMUNDA_NAMESPACE_1 ?= camunda-region1

# ── Zeebe initial contact points (all brokers in both regions) ───────────────
# Format: <release>-zeebe-<n>.<release>-zeebe.<namespace>.svc.cluster.local:26502
# Update if CAMUNDA_RELEASE_NAME, namespaces, or BROKERS_PER_REGION change.
ZEEBE_INITIAL_CONTACT_POINTS ?= \
  $(CAMUNDA_RELEASE_NAME)-zeebe-0.$(CAMUNDA_RELEASE_NAME)-zeebe.$(CAMUNDA_NAMESPACE_0).svc.cluster.local:26502,\
  $(CAMUNDA_RELEASE_NAME)-zeebe-1.$(CAMUNDA_RELEASE_NAME)-zeebe.$(CAMUNDA_NAMESPACE_0).svc.cluster.local:26502,\
  $(CAMUNDA_RELEASE_NAME)-zeebe-0.$(CAMUNDA_RELEASE_NAME)-zeebe.$(CAMUNDA_NAMESPACE_1).svc.cluster.local:26502,\
  $(CAMUNDA_RELEASE_NAME)-zeebe-1.$(CAMUNDA_RELEASE_NAME)-zeebe.$(CAMUNDA_NAMESPACE_1).svc.cluster.local:26502

# ── PostgreSQL (internal per-region instance) ────────────────────────────────
POSTGRES_HOST             ?= $(CAMUNDA_RELEASE_NAME)-identity-postgresql
POSTGRES_CAMUNDA_DB       ?= camunda
POSTGRES_CAMUNDA_USERNAME ?= camunda

# ── Helm values composition ──────────────────────────────────────────────────
# Merge order (later files override earlier; arrays are replaced, not merged):
#   1. Base RDBMS + orchestration values
#   2. Dual-region multiregion settings (regionId, clusterSize, contact points)
#   3. Region-specific overrides (./my-camunda-values.yaml, resolved relative
#      to the region subdirectory where make is invoked)
CAMUNDA_HELM_VALUES ?= \
  $(root)/camunda-values.yaml.d/orchestration-rdbms-postgres.yaml \
  $(root)/camunda-values.yaml.d/orchaestration-dual-region-postgres.yaml \
  ./my-camunda-values.yaml
