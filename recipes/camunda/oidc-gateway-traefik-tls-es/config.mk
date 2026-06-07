# These are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

DEPLOYMENT_NAME ?= mydeployment


# Camunda installation
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda

CAMUNDA_CHART ?= camunda/camunda-platform
CAMUNDA_HELM_CHART_VERSION ?= 14.4.0
CAMUNDA_VERSION ?= 8.9.0

# To enable BPM Copilot to use Google Vertex AI, replace `modeler-enabled.yaml` below
#  and use `modeler-enabled-copilot-vertexai.yaml` instead. 
CAMUNDA_HELM_VALUES ?= \
  $(root)/camunda-values.yaml.d/enable-elasticsearch.yaml \
  $(root)/camunda-values.yaml.d/enable-metrics.yaml \
  $(root)/camunda-values.yaml.d/oidc.yaml \
  $(root)/camunda-values.yaml.d/identity-keycloak-internal-postgres.yaml \
  $(root)/camunda-values.yaml.d/modeler-enabled.yaml \
  $(root)/camunda-values.yaml.d/modeler-internal-postgres.yaml \
  $(root)/camunda-values.yaml.d/orchestration-elasticsearch.yaml \
  $(root)/camunda-values.yaml.d/orchestration-oidc.yaml \
  $(root)/camunda-values.yaml.d/optimize-elasticsearch.yaml \
  $(root)/camunda-values.yaml.d/console-enabled.yaml \
  $(root)/camunda-values.yaml.d/enable-multitenancy.yaml \
  ./my-camunda-values.yaml

DEFAULT_PASSWORD ?= changeme

CAMUNDA_CLUSTER_SIZE ?= 1
CAMUNDA_REPLICATION_FACTOR ?= 1
CAMUNDA_PARTITION_COUNT ?= 1

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
