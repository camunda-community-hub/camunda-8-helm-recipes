# These are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

DEPLOYMENT_NAME ?= mydeployment

# Traefik
TRAEFIK_NAMESPACE ?= traefik
TRAEFIK_RELEASE_NAME ?= traefik
TRAEFIK_CHART ?= traefik/traefik
TRAEFIK_CHART_VERSION ?= 34.5.0
