# Theses are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

DEPLOYMENT_NAME ?= mydeployment

# Camunda installation
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda

CAMUNDA_CHART ?= camunda/camunda-platform
CAMUNDA_HELM_CHART_VERSION ?= 15.4.3
# Informational only for chart 15: image versions come from the chart defaults (15.4.3 ships 8.10.5 to 8.10.10).
CAMUNDA_VERSION ?= 8.10.x

CAMUNDA_HELM_VALUES ?= \
  $(root)/camunda-values.yaml.d/ingress-nginx-host.yaml \
  $(root)/camunda-values.yaml.d/enable-metrics.yaml \
  $(root)/camunda-values.yaml.d/connectors-enabled.yaml \
  $(root)/camunda-values.yaml.d/orchestration-elasticsearch.yaml \
  $(root)/camunda-values.yaml.d/orchestration-topology.yaml \
  ./my-camunda-values.yaml

DEFAULT_PASSWORD ?= changeme

CAMUNDA_CLUSTER_SIZE ?= 1
CAMUNDA_REPLICATION_FACTOR ?= 1
CAMUNDA_PARTITION_COUNT ?= 1

# Networking
CAMUNDA_INGRESS_NAME ?= camunda-camunda-platform-http
CAMUNDA_INGRESS_GRPC_NAME ?= camunda-camunda-platform-grpc

HOST_NAME ?= example.camunda.com