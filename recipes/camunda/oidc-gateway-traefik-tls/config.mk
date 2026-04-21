# These are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

DEPLOYMENT_NAME ?= mydeployment

# PostgreSQL (external)
POSTGRES_HOST ?= 127.0.0.1
POSTGRES_KEYCLOAK_HOST ?= $(POSTGRES_HOST)
POSTGRES_KEYCLOAK_DB ?= keycloak
POSTGRES_KEYCLOAK_USERNAME ?= keycloak_user
POSTGRES_MODELER_HOST ?= $(POSTGRES_HOST)
POSTGRES_MODELER_DB ?= modeler
POSTGRES_MODELER_USERNAME ?= modeler_user

# Camunda installation
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda

CAMUNDA_CHART ?= camunda/camunda-platform
CAMUNDA_HELM_CHART_VERSION ?= 14.0.0-alpha5
CAMUNDA_VERSION ?= 8.9.0-alpha5

CAMUNDA_HELM_VALUES ?= \
  $(root)/camunda-values.yaml.d/enable-opensearch.yaml \
  $(root)/camunda-values.yaml.d/enable-metrics.yaml \
  $(root)/camunda-values.yaml.d/oidc.yaml \
  $(root)/camunda-values.yaml.d/identity-keycloak-external-postgres.yaml \
  $(root)/camunda-values.yaml.d/modeler-enabled.yaml \
  $(root)/camunda-values.yaml.d/modeler-external-postgres.yaml \
  $(root)/camunda-values.yaml.d/orchestration-opensearch.yaml \
  $(root)/camunda-values.yaml.d/optimize-opensearch.yaml \
  $(root)/camunda-values.yaml.d/console-enabled.yaml \
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
TLS_SECRET_NAME ?= tls-secret

IDENTITY_EXT_URL ?= https://$(HOST_NAME)
KEYCLOAK_EXT_URL ?= https://$(HOST_NAME)
ORCHESTRATION_EXT_URL ?= https://$(HOST_NAME)
OPTIMIZE_EXT_URL ?= https://$(HOST_NAME)
CONSOLE_EXT_URL ?= https://$(HOST_NAME)
WEB_MODELER_EXT_URL ?= https://$(HOST_NAME)

REPLY_EMAIL ?= noreply@$(HOST_NAME)

# Keycloak
KEYCLOAK_ADMIN_USERNAME ?= admin
KEYCLOAK_REALM ?= camunda-platform
