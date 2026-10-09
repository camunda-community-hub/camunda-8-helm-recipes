# Ordered teardown of the whole environment (Camunda, Keycloak, Elasticsearch, PostgreSQL, operators, metrics,
# Traefik, DNS, cert-manager), plus a check for anything left behind.
# Order matters: custom resources go before their operators, otherwise operator finalizers can hang deletion.
#
#   make teardown-apps    Camunda, Keycloak, Elasticsearch, PostgreSQL and their operators, then the namespace
#   make teardown-infra   metrics, Traefik, DNS records and cert-manager
#   make teardown         both, then check-orphans
#   make check-orphans    list PVCs, PVs, load balancers and CRDs that are still around

.PHONY: teardown-apps
teardown-apps:
	-$(MAKE) uninstall-camunda
	-$(MAKE) clean-ingress-routes delete-certificate
	-$(MAKE) -C $(root)/recipes/keycloak clean-keycloak
	-$(MAKE) -C $(root)/recipes/elasticsearch clean-elasticsearch
	-$(MAKE) -C $(root)/recipes/postgres clean-postgres
	-$(MAKE) -C $(root)/recipes/keycloak clean-keycloak-operator
	-$(MAKE) -C $(root)/recipes/elasticsearch clean-eck-operator
	-$(MAKE) -C $(root)/recipes/postgres clean-cnpg-operator
	-kubectl delete namespace $(CAMUNDA_NAMESPACE) --wait=true --timeout=300s

.PHONY: teardown-infra
teardown-infra:
	-$(MAKE) -C $(root)/recipes/metrics clean
	-$(MAKE) delete-gcp-dns
	-$(MAKE) clean-gateway-traefik
	-$(MAKE) clean-cert-manager

.PHONY: teardown
teardown: teardown-apps teardown-infra check-orphans

.PHONY: check-orphans
check-orphans:
	@echo "== PVCs (expect none) =="; kubectl get pvc -A --no-headers 2>/dev/null || true
	@echo "== PVs (expect none; a Released PV means a cloud disk may still exist) =="; kubectl get pv --no-headers 2>/dev/null || true
	@echo "== LoadBalancer services (each one is a billed public IP) =="; kubectl get svc -A --no-headers 2>/dev/null | grep LoadBalancer || echo "none"
	@echo "== Leftover CRDs =="; kubectl get crd -o name 2>/dev/null | grep -E 'cert-manager|traefik|k8s.keycloak|elastic|cnpg|monitoring.coreos' || echo "none"
	@echo "== Namespaces =="; kubectl get ns --no-headers
