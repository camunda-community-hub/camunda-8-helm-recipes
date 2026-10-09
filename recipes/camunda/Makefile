CAMUNDA_RECIPES := \
  basic-ingress-nginx-tls \
  oidc-ingress-nginx-tls \
  oidc-gateway-traefik-tls \
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
