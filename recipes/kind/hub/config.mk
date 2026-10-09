# Theses are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

# Kind cluster (kube context: kind-$(DEPLOYMENT_NAME))
DEPLOYMENT_NAME ?= camunda-hub

# Camunda 8.10 (Helm chart 15) installation
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda

CAMUNDA_CHART ?= camunda/camunda-platform
CAMUNDA_HELM_CHART_VERSION ?= 15.0.0-alpha5
CAMUNDA_VERSION ?= 8.10.0-alpha5

# Minimal topology for feature testing, not load
CAMUNDA_CLUSTER_SIZE ?= 1
CAMUNDA_REPLICATION_FACTOR ?= 1
CAMUNDA_PARTITION_COUNT ?= 1

# Used for every local credential (Keycloak admin, database roles, first user "demo").
# The database and Keycloak manifests are created with the same value.
DEFAULT_PASSWORD ?= demo

# Networking: add these names to /etc/hosts pointing at 127.0.0.1
HOST_NAME ?= camunda.local
IDENTITY_EXT_URL ?= https://identity.camunda.local
ORCHESTRATION_EXT_URL ?= https://camunda.local
WEB_MODELER_EXT_URL ?= https://camunda.local
CONSOLE_EXT_URL ?= https://camunda.local

# Self signed TLS (recipes/tls-self-signed-certs). CA_KEY_PASS makes it non-interactive.
CERT_NAME ?= camunda
TLS_SECRET_NAME ?= tls-secret
TRUST_STORE_PASS ?= camunda
CA_KEY_PASS ?= camunda

# Keycloak (deployed in cluster by `make kind-keycloak`; chart 15 does not bundle one)
KEYCLOAK_EXT_URL ?= https://camunda.local
KEYCLOAK_ADMIN_USERNAME ?= admin
KEYCLOAK_REALM ?= camunda-platform

# PostgreSQL (deployed in cluster by `make kind-postgres`)
POSTGRES_HOST ?= postgres
POSTGRES_MODELER_HOST ?= postgres
POSTGRES_CAMUNDA_HOST ?= postgres

POSTGRES_MASTER_PASSWORD ?= $(DEFAULT_PASSWORD)

POSTGRES_KEYCLOAK_DB ?= keycloak
POSTGRES_KEYCLOAK_USERNAME ?= keycloak

POSTGRES_IDENTITY_DB ?= identity
POSTGRES_IDENTITY_USERNAME ?= identity

POSTGRES_MODELER_DB ?= modeler
POSTGRES_MODELER_USERNAME ?= modeler

POSTGRES_CAMUNDA_DB ?= camunda
POSTGRES_CAMUNDA_USERNAME ?= camunda

CAMUNDA_HELM_VALUES ?= \
  $(root)/camunda-values.yaml.d/ingress-nginx-host.yaml \
  $(root)/camunda-values.yaml.d/identity-own-hostname.yaml \
  $(root)/camunda-values.yaml.d/oidc-external-keycloak.yaml \
  $(root)/camunda-values.yaml.d/connectors-enabled.yaml \
  $(root)/camunda-values.yaml.d/orchestration-rdbms-postgres.yaml \
  $(root)/camunda-values.yaml.d/hub-enabled.yaml \
  ./my-camunda-values.yaml
