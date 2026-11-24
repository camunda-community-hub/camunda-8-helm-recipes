# Region 1 of the dual-region Camunda recipe: an orchestration release with the region 1 zone of the
# Orchestration Cluster. Authenticates against Keycloak and Management Identity in region 0 over their public URLs.

ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../../../..
else
    root ?= $(shell pwd)/../../../..
endif

-include $(root)/config.mk
include ../config.mk

# Map the region 1 variables. := so a single-region root config.mk cannot override them.
CAMUNDA_NAMESPACE := $(CAMUNDA_NAMESPACE_1)
KUBE_CONTEXT := $(KUBE_CONTEXT_1)
HOST_NAME := $(HOST_NAME_1)
DNS_CHAIN_IP := $(DNS_CHAIN_IP_1)

CAMUNDA_HELM_VALUES := \
  $(root)/camunda-values.yaml.d/oidc.yaml \
  $(root)/camunda-values.yaml.d/orchestration-elasticsearch.yaml \
  $(root)/camunda-values.yaml.d/orchestration-oidc.yaml \
  $(root)/camunda-values.yaml.d/orchestration-dual-region-es.yaml \
  $(root)/camunda-values.yaml.d/orchestration-dns-chain.yaml \
  $(root)/camunda-values.yaml.d/orchestration-secret-store-file.yaml \
  $(root)/camunda-values.yaml.d/enable-metrics.yaml \
  ./my-camunda-values.yaml

# Region 1's Prometheus remote-writes to region 0's, through its internal load balancer (on GKE:
# `make -C recipes/google/gke-dual-region prometheus-lb`). Looked up only when metrics-values.yaml is generated.
REMOTE_WRITE_URL = http://$(shell kubectl --context $(KUBE_CONTEXT_0) -n default get svc prometheus-internal-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):9090/api/v1/write

# Region 1 only needs Traefik, cert-manager and its own Elasticsearch. PostgreSQL and Keycloak run in region 0.
DEPENDENCIES_ARGS := WITH_POSTGRES=false WITH_KEYCLOAK=false

# Only the Orchestration Cluster routes (no Identity, Keycloak, Hub or Optimize in this region)
INGRESS_ROUTES_TEMPLATE := $(root)/recipes/gateway-traefik/include/ingress-routes-orchestration.tpl.yaml

include ../region-common.mk
