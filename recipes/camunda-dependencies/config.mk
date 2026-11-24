# These are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

# Which third party dependencies to install. Set any of them to false to skip it.
WITH_TRAEFIK ?= true
WITH_CERT_MANAGER ?= true
WITH_POSTGRES ?= true
WITH_KEYCLOAK ?= true
WITH_ELASTICSEARCH ?= true
WITH_METRICS ?= false

# Optional kubectl context to switch to before installing. Empty uses the current context.
KUBE_CONTEXT ?=

# Namespace for PostgreSQL, Keycloak and Elasticsearch (same as Camunda)
CAMUNDA_NAMESPACE ?= camunda

# Let's Encrypt ClusterIssuer solves HTTP-01 challenges through this ingress class
INGRESS_CLASS ?= traefik

# Traefik routes /auth to Keycloak, so the Keycloak recipe must not create an nginx Ingress
KEYCLOAK_INGRESS ?= none
