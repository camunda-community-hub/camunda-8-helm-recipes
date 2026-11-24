# Shared targets of region0/ and region1/. Included after the region has mapped its _0 / _1 variables.

BROKERS_PER_REGION := $(shell expr $(DUAL_REGION_CLUSTER_SIZE) / 2)
REPLICAS_PER_REGION := $(shell expr $(DUAL_REGION_REPLICATION_FACTOR) / 2)
CAMUNDA_PARTITION_COUNT := $(DUAL_REGION_PARTITION_COUNT)
ZONE := $(CAMUNDA_NAMESPACE)

# Region 0 hosts Keycloak, Management Identity, Hub and Optimize
KEYCLOAK_EXT_URL := https://$(HOST_NAME_0)
IDENTITY_EXT_URL := https://$(HOST_NAME_0)
OPTIMIZE_EXT_URL := https://$(HOST_NAME_0)
WEB_MODELER_EXT_URL := https://$(HOST_NAME_0)
REPLY_EMAIL := noreply@$(HOST_NAME_0)
# Each region serves its own Operate, Tasklist and APIs
ORCHESTRATION_EXT_URL := https://$(HOST_NAME)

# Region Makefiles may define their own targets before including this file, so pin the default goal
.DEFAULT_GOAL := all

.PHONY: all
all: use-context camunda-values.yaml create-camunda-credentials camunda apply-ingress-routes

.PHONY: clean
clean: use-context clean-ingress-routes uninstall-camunda

.PHONY: use-context
use-context:
ifneq ($(KUBE_CONTEXT),)
	kubectl config use-context $(KUBE_CONTEXT)
endif

# Third party dependencies for this region (recipes/camunda-dependencies). HOST_NAME and the namespace are passed on
# the command line so they win over single-region values in the root config.mk. DEPENDENCIES_ARGS is set per region.
.PHONY: dependencies
dependencies:
	$(MAKE) -C $(root)/recipes/camunda-dependencies KUBE_CONTEXT=$(KUBE_CONTEXT) \
	  CAMUNDA_NAMESPACE=$(CAMUNDA_NAMESPACE) HOST_NAME=$(HOST_NAME) INGRESS_CLASS=$(INGRESS_CLASS) \
	  KEYCLOAK_INGRESS=$(KEYCLOAK_INGRESS) $(DEPENDENCIES_ARGS)

# Removes this region's third party dependencies in reverse order (custom resources and their PVCs before the operators)
.PHONY: clean-dependencies
clean-dependencies:
	-$(MAKE) -C $(root)/recipes/camunda-dependencies clean KUBE_CONTEXT=$(KUBE_CONTEXT) \
	  CAMUNDA_NAMESPACE=$(CAMUNDA_NAMESPACE) HOST_NAME=$(HOST_NAME) INGRESS_CLASS=$(INGRESS_CLASS) \
	  KEYCLOAK_INGRESS=$(KEYCLOAK_INGRESS) $(DEPENDENCIES_ARGS)

# Removes the DNS A records of HOST_NAME and grpc.HOST_NAME
.PHONY: clean-dns
clean-dns:
	$(MAKE) delete-gcp-dns GCP_DNS_ZONE=$(DUAL_REGION_GCP_DNS_ZONE)

# Points HOST_NAME and grpc.HOST_NAME at this region's Traefik load balancer (GCP Cloud DNS zone DUAL_REGION_GCP_DNS_ZONE)
.PHONY: dns
dns: use-context
	$(MAKE) update-gcp-dns GCP_DNS_ZONE=$(DUAL_REGION_GCP_DNS_ZONE)

# Let's Encrypt certificate for HOST_NAME and grpc.HOST_NAME. Needs the DNS records first.
.PHONY: certificate
certificate: use-context request-certificate
	kubectl wait --for=condition=Ready certificate/camunda-tls -n $(CAMUNDA_NAMESPACE) --timeout=300s

# Cluster topology (brokers per zone, partitions, health) from the management API of this region's first broker.
# Needs jq locally.
# The management API is served under the orchestration context path. Local port 19600 avoids a local Zeebe on 9600.
MANAGEMENT_LOCAL_PORT ?= 19600
.PHONY: topology
topology: use-context
	@kubectl -n $(CAMUNDA_NAMESPACE) port-forward pod/$(CAMUNDA_RELEASE_NAME)-zeebe-$(ZONE)-0 $(MANAGEMENT_LOCAL_PORT):9600 >/dev/null 2>&1 & \
	 pf=$$!; sleep 4; \
	 curl -sf http://127.0.0.1:$(MANAGEMENT_LOCAL_PORT)/orchestration/actuator/cluster | jq '{brokers: [.brokers[] | {id, partitions: [.partitions[] | "\(.id):\(.state)"]}], pendingChange}' \
	   || echo "Could not reach the management API"; \
	 kill $$pf 2>/dev/null || true

# Prometheus + Grafana for this region (recipes/metrics), with this region's metrics-values.tpl.yaml on top.
# Region 0 hosts Grafana and receives region 1's metrics. Region 1 sets REMOTE_WRITE_URL.
REMOTE_WRITE_URL ?=

.PHONY: metrics-values.yaml
metrics-values.yaml:
	sed -e "s|<YOUR_HOSTNAME>|$(HOST_NAME)|g" \
	    -e "s|<ZONE>|$(ZONE)|g" \
	    -e "s|<REMOTE_WRITE_URL>|$(REMOTE_WRITE_URL)|g" \
	    ./metrics-values.tpl.yaml > $@

.PHONY: metrics
metrics: use-context metrics-values.yaml
	$(MAKE) -C $(root)/recipes/metrics metrics METRICS_VALUES=$(CURDIR)/metrics-values.yaml GRAFANA_LOAD_BALANCER=false

.PHONY: update-metrics
update-metrics: use-context metrics-values.yaml
	$(MAKE) -C $(root)/recipes/metrics update-metrics METRICS_VALUES=$(CURDIR)/metrics-values.yaml

.PHONY: clean-metrics
clean-metrics: use-context
	-$(MAKE) -C $(root)/recipes/metrics clean-grafana-ingress-route clean-metrics
	-rm -f metrics-values.yaml

include $(root)/makefiles/camunda.mk
include $(root)/makefiles/gateway-traefik.mk
include $(root)/makefiles/dns.mk
include $(root)/makefiles/letsencrypt.mk
include $(root)/makefiles/keycloak.mk
include $(root)/makefiles/test.mk
