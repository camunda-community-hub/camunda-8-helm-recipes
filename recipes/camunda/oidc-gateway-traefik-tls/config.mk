# These are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

DEPLOYMENT_NAME ?= mydeployment

# PostgreSQL (CloudNativePG, recipes/postgres): one cluster per component
POSTGRES_IDENTITY_HOST ?= pg-identity-rw
POSTGRES_IDENTITY_DB ?= identity
POSTGRES_IDENTITY_USERNAME ?= identity
POSTGRES_MODELER_HOST ?= pg-hub-rw
POSTGRES_MODELER_DB ?= hub
POSTGRES_MODELER_USERNAME ?= hub

# Camunda installation
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda

CAMUNDA_CHART ?= camunda/camunda-platform
CAMUNDA_HELM_CHART_VERSION ?= 15.1.0
CAMUNDA_VERSION ?= 8.10.0

# Prerequisites (chart 15 does not bundle them):
#   recipes/postgres   CloudNativePG: pg-identity, pg-keycloak, pg-hub
#   recipes/keycloak   Keycloak operator (KEYCLOAK_INGRESS=none, Traefik routes /auth)
#   OpenSearch         external cluster, see OPENSEARCH_* below
CAMUNDA_HELM_VALUES ?= \
  $(root)/camunda-values.yaml.d/enable-metrics.yaml \
  $(root)/camunda-values.yaml.d/oidc.yaml \
  $(root)/camunda-values.yaml.d/identity-enabled.yaml \
  $(root)/camunda-values.yaml.d/hub-enabled.yaml \
  $(root)/camunda-values.yaml.d/orchestration-opensearch.yaml \
  $(root)/camunda-values.yaml.d/orchestration-oidc.yaml \
  $(root)/camunda-values.yaml.d/optimize-opensearch.yaml \
  $(root)/camunda-values.yaml.d/orchestration-topology.yaml \
  ./my-camunda-values.yaml

DEFAULT_PASSWORD ?= demo

CAMUNDA_CLUSTER_SIZE ?= 1
CAMUNDA_REPLICATION_FACTOR ?= 1
CAMUNDA_PARTITION_COUNT ?= 1

# OpenSearch
OPENSEARCH_PROTOCOL ?= http
OPENSEARCH_HOST ?= opensearch-cluster-master.shared-services.svc.cluster.local
OPENSEARCH_PORT ?= 9200
OPENSEARCH_URL ?= $(OPENSEARCH_PROTOCOL)://$(OPENSEARCH_HOST):$(OPENSEARCH_PORT)
OPENSEARCH_USERNAME ?= admin
OPENSEARCH_PASSWORD ?= admin

# Networking — single domain, same convention as the nginx recipes
# All components share HOST_NAME with context-path routing;
# Traefik IngressRoute CRDs handle TLS termination and path-based dispatch.
HOST_NAME ?= example.com

# Used by `make update-route53-dns` (AWS) to find the Traefik load balancer
LB_SERVICE ?= $(TRAEFIK_RELEASE_NAME)
LB_NAMESPACE ?= $(TRAEFIK_NAMESPACE)
TLS_SECRET_NAME ?= tls-secret

IDENTITY_EXT_URL ?= https://$(HOST_NAME)
KEYCLOAK_EXT_URL ?= https://$(HOST_NAME)
ORCHESTRATION_EXT_URL ?= https://$(HOST_NAME)
OPTIMIZE_EXT_URL ?= https://$(HOST_NAME)
WEB_MODELER_EXT_URL ?= https://$(HOST_NAME)

REPLY_EMAIL ?= noreply@$(HOST_NAME)

# Keycloak (operator-managed, recipes/keycloak). The operator creates the admin user temp-admin.
# Traefik routes /auth, so the Keycloak recipe must not create an nginx Ingress.
KEYCLOAK_ADMIN_USERNAME ?= temp-admin
KEYCLOAK_REALM ?= camunda-platform
KEYCLOAK_INGRESS ?= none
