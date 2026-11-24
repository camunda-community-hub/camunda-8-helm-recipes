CAMUNDA_RECIPES := \
  basic-ingress-nginx-tls \
  oidc-gateway-traefik-tls \
  oidc-gateway-traefik-tls-es \
  dual-region-es-oidc/region0 \
  dual-region-es-oidc/region1 \
  rdbms-postgres \
  rdbms-postgres-oidc \
  ../kind/hub

.PHONY: test
test:
	@for recipe in $(CAMUNDA_RECIPES); do \
	  echo "--- Testing $$recipe ---"; \
	  $(MAKE) -C $$recipe test || exit 1; \
	done
	@echo "All recipe tests passed."
