# Theses are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

DEPLOYMENT_NAME ?= mydeployment

# Camunda installation
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda

CAMUNDA_CHART ?= camunda/camunda-platform
CAMUNDA_HELM_CHART_VERSION ?= 14.0.0
CAMUNDA_VERSION ?= 8.9.0

CAMUNDA_HELM_VALUES ?= \
  $(root)/camunda-values.yaml.d/enable-ingress-nginx.yaml \
  $(root)/camunda-values.yaml.d/identity-keycloak-external-postgres.yaml \
  $(root)/camunda-values.yaml.d/connectors-oidc.yaml \
  $(root)/camunda-values.yaml.d/orchestration-rdbms-postgres.yaml \
  $(root)/camunda-values.yaml.d/orchestration-oidc.yaml \
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

# Postgresql
POSTGRES_HOST ?= mypostgresql.camunda.com
POSTGRES_CAMUNDA_HOST ?= $(POSTGRES_HOST)

POSTGRES_MASTER_USERNAME ?= postgres
POSTGRES_MASTER_PASSWORD ?= CHANGEME

POSTGRES_KEYCLOAK_DB ?= bitnami_keycloak
POSTGRES_KEYCLOAK_USERNAME ?= bn_keycloak

POSTGRES_IDENTITY_DB ?= identity
POSTGRES_IDENTITY_USERNAME ?= identity

POSTGRES_MODELER_DB ?= modeler
POSTGRES_MODELER_USERNAME ?= modeler

POSTGRES_CAMUNDA_DB ?= camunda
POSTGRES_CAMUNDA_USERNAME ?= camunda

POSTGRES_CAMUNDA_DB ?= camunda
POSTGRES_CAMUNDA_USERNAME ?= camunda

# Camunda installation
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda
CAMUNDA_CHART ?= camunda/camunda-platform

CAMUNDA_HELM_CHART_VERSION ?= 14.0.0
CAMUNDA_VERSION ?= 8.9.0
