# Installs the third party dependencies Camunda 8.10 (Helm chart 15) needs, by running the existing
# single-purpose recipes in order. Nothing here is cloud specific: it only needs a working kube context,
# so it works the same on GKE, AKS, EKS and Kind.
#
#   gateway-traefik   Traefik ingress controller          (WITH_TRAEFIK)
#   letsencrypt       cert-manager + ClusterIssuer         (WITH_CERT_MANAGER)
#   postgres          CloudNativePG + PostgreSQL clusters  (WITH_POSTGRES)
#   keycloak          Keycloak operator + instance         (WITH_KEYCLOAK, needs postgres)
#   elasticsearch     ECK operator + Elasticsearch         (WITH_ELASTICSEARCH)
#   metrics           Prometheus + Grafana                 (WITH_METRICS)
#
# Cloud specific steps (cluster, storage class, DNS records) stay in the cloud recipes.

# Determine the root directory
ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../..
else
    root ?= $(shell pwd)/../..
endif

# Create a config.mk file in the root directory of this project to override defaults included below
-include $(root)/config.mk

# These are the default values used by this recipe
include ./config.mk

# Pass the shared settings down to the sub-recipes, whose config.mk files use ?=
export CAMUNDA_NAMESPACE INGRESS_CLASS KEYCLOAK_INGRESS

.PHONY: all
all: use-context
ifeq ($(WITH_TRAEFIK),true)
	$(MAKE) -C $(root)/recipes/gateway-traefik gateway-traefik
endif
ifeq ($(WITH_CERT_MANAGER),true)
	-$(MAKE) -C $(root)/recipes/letsencrypt cert-manager
	$(MAKE) -C $(root)/recipes/letsencrypt letsencrypt-prod
endif
ifeq ($(WITH_POSTGRES),true)
	$(MAKE) -C $(root)/recipes/postgres
endif
ifeq ($(WITH_KEYCLOAK),true)
	$(MAKE) -C $(root)/recipes/keycloak
endif
ifeq ($(WITH_ELASTICSEARCH),true)
	$(MAKE) -C $(root)/recipes/elasticsearch
endif
ifeq ($(WITH_METRICS),true)
	$(MAKE) -C $(root)/recipes/metrics
endif
	@echo "✅ Dependencies installed in namespace $(CAMUNDA_NAMESPACE) (context: $$(kubectl config current-context))"

.PHONY: use-context
use-context:
ifneq ($(KUBE_CONTEXT),)
	kubectl config use-context $(KUBE_CONTEXT)
endif

# Removes the dependencies in reverse order. Custom resources go before their operators.
.PHONY: clean
clean: use-context
ifeq ($(WITH_METRICS),true)
	-$(MAKE) -C $(root)/recipes/metrics clean
endif
ifeq ($(WITH_ELASTICSEARCH),true)
	-$(MAKE) -C $(root)/recipes/elasticsearch clean-elasticsearch clean-eck-operator
endif
ifeq ($(WITH_KEYCLOAK),true)
	-$(MAKE) -C $(root)/recipes/keycloak clean-keycloak clean-keycloak-operator
endif
ifeq ($(WITH_POSTGRES),true)
	-$(MAKE) -C $(root)/recipes/postgres clean-postgres clean-cnpg-operator
endif
ifeq ($(WITH_CERT_MANAGER),true)
	-$(MAKE) -C $(root)/recipes/letsencrypt clean-cert-manager
endif
ifeq ($(WITH_TRAEFIK),true)
	-$(MAKE) -C $(root)/recipes/gateway-traefik clean-gateway-traefik
endif
