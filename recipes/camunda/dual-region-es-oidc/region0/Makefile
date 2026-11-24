# Region 0 of the dual-region Camunda recipe: a combined release with the region 0 zone of the
# Orchestration Cluster, plus Management Identity, Camunda Hub and Optimize (single region, not stretched).

ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../../../..
else
    root ?= $(shell pwd)/../../../..
endif

-include $(root)/config.mk
include ../config.mk

# Map the region 0 variables. := so a single-region root config.mk cannot override them.
CAMUNDA_NAMESPACE := $(CAMUNDA_NAMESPACE_0)
KUBE_CONTEXT := $(KUBE_CONTEXT_0)
HOST_NAME := $(HOST_NAME_0)
DNS_CHAIN_IP := $(DNS_CHAIN_IP_0)

CAMUNDA_HELM_VALUES := \
  $(root)/camunda-values.yaml.d/oidc.yaml \
  $(root)/camunda-values.yaml.d/identity-enabled.yaml \
  $(root)/camunda-values.yaml.d/hub-enabled.yaml \
  $(root)/camunda-values.yaml.d/orchestration-elasticsearch.yaml \
  $(root)/camunda-values.yaml.d/orchestration-oidc.yaml \
  $(root)/camunda-values.yaml.d/optimize-elasticsearch.yaml \
  $(root)/camunda-values.yaml.d/orchestration-dual-region-es.yaml \
  $(root)/camunda-values.yaml.d/orchestration-dns-chain.yaml \
  $(root)/camunda-values.yaml.d/orchestration-secret-store-file.yaml \
  $(root)/camunda-values.yaml.d/enable-metrics.yaml \
  ./my-camunda-values.yaml

# Public Grafana at https://HOST_NAME/grafana: a Let's Encrypt certificate in the metrics namespace (default) and a
# Traefik IngressRoute. Run after `make metrics`.
.PHONY: grafana-route
grafana-route: use-context
	$(MAKE) request-certificate CAMUNDA_NAMESPACE=default TLS_SECRET_NAME=grafana-tls
	kubectl wait --for=condition=Ready certificate/camunda-tls -n default --timeout=300s
	$(MAKE) -C $(root)/recipes/metrics grafana-ingress-route HOST_NAME=$(HOST_NAME) GRAFANA_TLS_SECRET_NAME=grafana-tls
	@echo "Grafana: https://$(HOST_NAME)/grafana"

# Lets users log in to region 1's Operate and Tasklist: Management Identity registers the orchestration client
# with region 0's redirect URL only, so add region 1's. Run after Camunda is up in region 0.
.PHONY: allow-region1-login
allow-region1-login: use-context
	$(MAKE) keycloak-add-redirect-uri KEYCLOAK_CLIENT=orchestration KEYCLOAK_REDIRECT_URI=https://$(HOST_NAME_1)/*

include ../region-common.mk
