# These are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

# Elasticsearch is installed into the same namespace as Camunda
CAMUNDA_NAMESPACE ?= camunda

# ECK operator (https://github.com/elastic/cloud-on-k8s/releases)
ECK_VERSION ?= 3.4.1
ECK_NAMESPACE ?= elastic-system

# Elasticsearch version: use the latest one in the Camunda supported environments matrix
# https://docs.camunda.io/docs/reference/supported-environments/
ES_VERSION ?= 9.5.4

# Defaults match the Camunda reference architecture. Nodes are spread across Kubernetes nodes
# (required pod anti-affinity), so ES_NODE_COUNT must not exceed the number of Kubernetes nodes.
ES_NODE_COUNT ?= 3
ES_CPU_REQUEST ?= 1
ES_CPU_LIMIT ?= 2
# The JVM heap is set by ECK to 50% of this value
ES_MEMORY ?= 2Gi
ES_STORAGE_SIZE ?= 64Gi
