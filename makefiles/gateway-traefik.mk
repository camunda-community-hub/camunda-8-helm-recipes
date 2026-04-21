# ---------------------------------------------------------------------------
# Traefik Gateway Controller — provision and manage Traefik Proxy
# ---------------------------------------------------------------------------

TRAEFIK_NAMESPACE ?= traefik
TRAEFIK_RELEASE_NAME ?= traefik
TRAEFIK_CHART ?= traefik/traefik
TRAEFIK_CHART_VERSION ?= 34.5.0

.PHONY: gateway-traefik
gateway-traefik:
	helm repo add traefik https://traefik.github.io/charts
	helm repo update traefik
	helm search repo traefik/traefik
	helm upgrade --install $(TRAEFIK_RELEASE_NAME) $(TRAEFIK_CHART) \
	  --namespace $(TRAEFIK_NAMESPACE) --create-namespace --wait \
	  --version $(TRAEFIK_CHART_VERSION)

.PHONY: clean-gateway-traefik
clean-gateway-traefik:
	-helm --namespace $(TRAEFIK_NAMESPACE) uninstall $(TRAEFIK_RELEASE_NAME)
	-kubectl delete namespace $(TRAEFIK_NAMESPACE)

.PHONY: traefik-ip-from-service
traefik-ip-from-service:
	$(eval IP := $(shell kubectl get service -w $(TRAEFIK_RELEASE_NAME) -o 'go-template={{with .status.loadBalancer.ingress}}{{range .}}{{.ip}}{{"\n"}}{{end}}{{.err}}{{end}}' -n $(TRAEFIK_NAMESPACE) 2>/dev/null | head -n1))
	@echo "Traefik uses IP address: $(IP)"

.PHONY: traefik-hostname-from-service
traefik-hostname-from-service:
	$(eval IP := $(shell kubectl get service -w $(TRAEFIK_RELEASE_NAME) -o 'go-template={{with .status.loadBalancer.ingress}}{{range .}}{{.hostname}}{{"\n"}}{{end}}{{.err}}{{end}}' -n $(TRAEFIK_NAMESPACE) 2>/dev/null | head -n1))
	@echo "Traefik uses hostname: $(IP)"

.PHONY: traefik-logs
traefik-logs:
	kubectl logs -n $(TRAEFIK_NAMESPACE) -l app.kubernetes.io/name=traefik --tail=100

.PHONY: traefik-dashboard
traefik-dashboard:
	kubectl port-forward -n $(TRAEFIK_NAMESPACE) svc/$(TRAEFIK_RELEASE_NAME)-dashboard 9000:9000

# ---------------------------------------------------------------------------
# IngressRoute management
# ---------------------------------------------------------------------------

ingress-routes.yaml: ./include/ingress-routes.tpl.yaml
	@echo "Generating ingress-routes.yaml from template ..."
	sed "s|<YOUR_HOSTNAME>|$(HOST_NAME)|g; \
	     s|<CAMUNDA_NAMESPACE>|$(CAMUNDA_NAMESPACE)|g; \
	     s|<TLS_SECRET_NAME>|$(TLS_SECRET_NAME)|g; \
	     s|<CAMUNDA_RELEASE_NAME>|$(CAMUNDA_RELEASE_NAME)|g" \
	     $< > $@
	@echo "✅ ingress-routes.yaml generated"

.PHONY: apply-ingress-routes
apply-ingress-routes: ingress-routes.yaml
	kubectl apply -f ingress-routes.yaml -n $(CAMUNDA_NAMESPACE)

.PHONY: clean-ingress-routes
clean-ingress-routes:
	-kubectl delete -f ingress-routes.yaml -n $(CAMUNDA_NAMESPACE) 2>/dev/null || true
	-rm -f ingress-routes.yaml
