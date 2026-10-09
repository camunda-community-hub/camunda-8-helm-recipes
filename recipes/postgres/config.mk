# These are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

# PostgreSQL clusters are installed into the same namespace as Camunda
CAMUNDA_NAMESPACE ?= camunda

# CloudNativePG operator (https://github.com/cloudnative-pg/cloudnative-pg/releases)
CNPG_VERSION ?= 1.30.0
CNPG_NAMESPACE ?= cnpg-system

# Which clusters to create. Remove the ones you do not need.
#   pg-identity  Management Identity
#   pg-keycloak  Keycloak
#   pg-hub       Camunda Hub
#   pg-camunda   Orchestration Cluster secondary storage (only when using RDBMS instead of Elasticsearch)
PG_CLUSTERS ?= pg-identity pg-keycloak pg-hub

# Use the latest PostgreSQL version in the Camunda supported environments matrix
# https://docs.camunda.io/docs/reference/supported-environments/
PG_IMAGE ?= ghcr.io/cloudnative-pg/postgresql:18.4

# Two instances keep Kubernetes nodes drainable (see the Camunda docs on high availability and node
# maintenance). Use 1 on single-node clusters such as Kind. Instances use required pod anti-affinity, so
# PG_INSTANCES must not exceed the number of Kubernetes nodes.
PG_INSTANCES ?= 2
# The sizes can only grow later, and the WAL volume cannot be removed once added
PG_STORAGE_SIZE ?= 15Gi
PG_WAL_STORAGE_SIZE ?= 5Gi

# Database and owner names. Camunda values fragments reference the same variables.
POSTGRES_IDENTITY_DB ?= identity
POSTGRES_IDENTITY_USERNAME ?= identity
POSTGRES_KEYCLOAK_DB ?= keycloak
POSTGRES_KEYCLOAK_USERNAME ?= keycloak
POSTGRES_MODELER_DB ?= hub
POSTGRES_MODELER_USERNAME ?= hub
POSTGRES_CAMUNDA_DB ?= camunda
POSTGRES_CAMUNDA_USERNAME ?= camunda

# Passwords are stored only in Kubernetes secrets, never in files. Defaults to DEFAULT_PASSWORD.
DEFAULT_PASSWORD ?= changeme
PG_PASSWORD ?= $(DEFAULT_PASSWORD)
