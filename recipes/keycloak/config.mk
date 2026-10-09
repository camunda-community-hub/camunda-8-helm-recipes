# These are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

# Keycloak is installed into the same namespace as Camunda
CAMUNDA_NAMESPACE ?= camunda

# Keycloak operator and server version (https://github.com/keycloak/keycloak-k8s-resources/tags).
# Also the tag of the camunda/keycloak image: quay-optimized-$(KEYCLOAK_VERSION).
# Use the latest version in the Camunda supported environments matrix
# https://docs.camunda.io/docs/reference/supported-environments/
KEYCLOAK_VERSION ?= 26.8.0

# domain: reachable at https://KEYCLOAK_HOST/auth (production like)
# local:  no domain, reachable in the cluster as http://keycloak-service:18080/auth
KEYCLOAK_MODE ?= domain

# nginx: create an Ingress for /auth (needs ingress-nginx and the TLS secret).
# none:  no Ingress, for example when Traefik routes /auth through its IngressRoute.
KEYCLOAK_INGRESS ?= nginx

# Same host as Camunda (single domain, Keycloak under /auth)
HOST_NAME ?= example.com
KEYCLOAK_HOST ?= $(HOST_NAME)
TLS_SECRET_NAME ?= tls-secret

KEYCLOAK_CPU_REQUEST ?= 250m
KEYCLOAK_CPU_LIMIT ?= 500m
KEYCLOAK_MEMORY ?= 1Gi

# Database name, from the PostgreSQL recipe (pg-keycloak)
POSTGRES_KEYCLOAK_DB ?= keycloak

# Used by `make keycloak-realm-tuning`
KEYCLOAK_REALM ?= camunda-platform

# Bootstrap admin user. The password is DEFAULT_PASSWORD (set it in the root config.mk).
# Keycloak only reads it when it first starts on an empty database.
KEYCLOAK_ADMIN_USERNAME ?= temp-admin
DEFAULT_PASSWORD ?= changeme
