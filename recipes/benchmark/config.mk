# Kubernetes namespace where Camunda is installed
BENCHMARK_NAMESPACE ?= camunda

# Helm release name of the existing Camunda installation
# Used to construct the Zeebe gateway service name: <release>-zeebe-gateway
CAMUNDA_RELEASE_NAME ?= camunda

# OIDC authentication (required for benchmark-oidc target)
# Override these in the root config.mk - do not commit secrets
BENCHMARK_CLIENT_ID ?= benchmark
BENCHMARK_TOKEN_URL ?= http://camunda-keycloak/auth/realms/camunda-platform/protocol/openid-connect/token
BENCHMARK_TOKEN_AUDIENCE ?= zeebe-api
BENCHMARK_CLIENT_SECRET ?= changeme
