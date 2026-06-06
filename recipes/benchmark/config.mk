# Kubernetes namespace where Camunda is installed
BENCHMARK_NAMESPACE ?= camunda

# Helm release name of the existing Camunda installation
# Used to construct the Zeebe gateway service name: <release>-zeebe-gateway
CAMUNDA_RELEASE_NAME ?= camunda
