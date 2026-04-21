# Theses are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

DEPLOYMENT_NAME ?= mydeployment

# Postgresql
# If you are using the aurora postgres recipe this will be dynamically discovered
POSTGRES_HOST ?= mypostgresql.camunda.com
POSTGRES_CAMUNDA_HOST ?= $(POSTGRES_HOST)
POSTGRES_CAMUNDA_DB ?= camunda
POSTGRES_CAMUNDA_USERNAME ?= camunda
POSTGRES_MASTER_PASSWORD ?= changeme

# Camunda installation
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda
CAMUNDA_CHART ?= camunda/camunda-platform

CAMUNDA_HELM_CHART_VERSION ?= 14.0.0
CAMUNDA_VERSION ?= 8.9.0

CAMUNDA_HELM_VALUES ?= \
  $(root)/camunda-values.yaml.d/orchestration-rdbms-postgres.yaml \
  ./my-camunda-values.yaml

DEFAULT_PASSWORD ?= changeme

CAMUNDA_CLUSTER_SIZE ?= 1
CAMUNDA_REPLICATION_FACTOR ?= 1
CAMUNDA_PARTITION_COUNT ?= 1
