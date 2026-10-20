# Theses are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

GRAFANA_PASSWORD ?= changeme

# Camunda SaaS Cluster Metrics endpoint, used by the saas-scrape target.
# Set these in the root config.mk (the password must never be committed).
# SAAS_METRICS_HOST is the host only, e.g. jfk-1.monitoring.camunda.io (no https://, no path).
SAAS_METRICS_HOST ?=
SAAS_CLUSTER_ID ?=
SAAS_METRICS_USERNAME ?=
SAAS_METRICS_PASSWORD ?=