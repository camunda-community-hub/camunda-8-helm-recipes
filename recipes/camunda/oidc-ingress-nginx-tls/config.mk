# Theses are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

DEPLOYMENT_NAME ?= mydeployment

POSTGRES_MASTER_USERNAME ?= postgres
POSTGRES_MASTER_PASSWORD ?= CHANGEME

POSTGRES_KEYCLOAK_DB ?= bitnami_keycloak
POSTGRES_KEYCLOAK_USERNAME ?= bn_keycloak

POSTGRES_IDENTITY_DB ?= identity
POSTGRES_IDENTITY_USERNAME ?= identity

POSTGRES_MODELER_DB ?= modeler
POSTGRES_MODELER_USERNAME ?= modeler

# Camunda installation
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda

CAMUNDA_CHART ?= camunda/camunda-platform
CAMUNDA_HELM_CHART_VERSION ?= 14.0.0-alpha5
CAMUNDA_VERSION ?= 8.9.0-alpha5

CAMUNDA_HELM_VALUES ?= \
  $(root)/camunda-values.yaml.d/enable-elasticsearch.yaml \
  $(root)/camunda-values.yaml.d/enable-ingress-nginx.yaml \
  $(root)/camunda-values.yaml.d/enable-metrics.yaml \
  $(root)/camunda-values.yaml.d/connectors-enabled.yaml \
  $(root)/camunda-values.yaml.d/oidc.yaml \
  $(root)/camunda-values.yaml.d/identity-keycloak-internal-postgres.yaml \
  $(root)/camunda-values.yaml.d/modeler-enabled.yaml \
  $(root)/camunda-values.yaml.d/modeler-internal-postgres.yaml \
  $(root)/camunda-values.yaml.d/orchestration-elasticsearch.yaml \
  $(root)/camunda-values.yaml.d/enable-multitenancy.yaml \
  ./my-camunda-values.yaml

DEFAULT_PASSWORD ?= changeme

CAMUNDA_CLUSTER_SIZE ?= 1
CAMUNDA_REPLICATION_FACTOR ?= 1
CAMUNDA_PARTITION_COUNT ?= 1

# Networking
CAMUNDA_INGRESS_NAME ?= camunda-camunda-platform-http
CAMUNDA_INGRESS_GRPC_NAME ?= camunda-camunda-platform-grpc

HOST_NAME ?= example.camunda.com
IDENTITY_EXT_URL ?= https://example.camunda.com
ORCHESTRATION_EXT_URL ?= https://example.camunda.com
WEB_MODELER_EXT_URL ?= https://example.camunda.com

# Keycloak
KEYCLOAK_EXT_URL ?= https://example.camunda.com
KEYCLOAK_ADMIN_USERNAME ?= admin
KEYCLOAK_REALM ?= camunda-platform
