# Keycloak admin helpers for the operator-managed Keycloak (see recipes/keycloak).
# The secret keycloak-bootstrap-admin is created by `make keycloak-admin-secret` (user KEYCLOAK_ADMIN_USERNAME, password DEFAULT_PASSWORD).

.PHONY: keycloak-password
keycloak-password:
	@echo "Keycloak admin user: $$(kubectl get secret keycloak-bootstrap-admin -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.username | base64decode}}')"
	@echo "Keycloak admin password: $$(kubectl get secret keycloak-bootstrap-admin -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.password | base64decode}}')"

# Adds a redirect URI (and its origin as a web origin) to an OIDC client in KEYCLOAK_REALM, keeping the existing ones.
# Example: make keycloak-add-redirect-uri KEYCLOAK_CLIENT=orchestration KEYCLOAK_REDIRECT_URI='https://other.example.com/*'
# Management Identity may reset the client when it restarts, so re-run it after an Identity restart. Needs jq locally.
KEYCLOAK_CLIENT ?= orchestration
KEYCLOAK_REDIRECT_URI ?=
KCADM = kubectl exec -i -n $(CAMUNDA_NAMESPACE) keycloak-0 -- /opt/keycloak/bin/kcadm.sh
.PHONY: keycloak-add-redirect-uri
keycloak-add-redirect-uri:
	@if [ -z "$(KEYCLOAK_REDIRECT_URI)" ]; then echo "Set KEYCLOAK_REDIRECT_URI"; exit 1; fi
	@admin=$$(kubectl get secret keycloak-bootstrap-admin -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.username | base64decode}}'); \
	 pass=$$(kubectl get secret keycloak-bootstrap-admin -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.password | base64decode}}'); \
	 $(KCADM) config credentials --server http://localhost:18080/auth --realm master --user "$$admin" --password "$$pass" >/dev/null; \
	 client=$$($(KCADM) get clients -r $(KEYCLOAK_REALM) -q clientId=$(KEYCLOAK_CLIENT) --fields id,redirectUris,webOrigins); \
	 id=$$(echo "$$client" | jq -r '.[0].id'); \
	 if [ -z "$$id" ] || [ "$$id" = "null" ]; then echo "Client $(KEYCLOAK_CLIENT) not found in realm $(KEYCLOAK_REALM)"; exit 1; fi; \
	 origin=$$(echo "$(KEYCLOAK_REDIRECT_URI)" | sed -E 's|^(https?://[^/]+).*|\1|'); \
	 echo "$$client" | jq --arg uri "$(KEYCLOAK_REDIRECT_URI)" --arg origin "$$origin" \
	   '{redirectUris: ((.[0].redirectUris // []) + [$$uri] | unique), webOrigins: ((.[0].webOrigins // []) + [$$origin] | unique)}' | \
	   $(KCADM) update clients/$$id -r $(KEYCLOAK_REALM) -f -; \
	 echo "Client $(KEYCLOAK_CLIENT): added redirect URI $(KEYCLOAK_REDIRECT_URI) and web origin $$origin"

# Optional, for self-signed TLS only. Identity cannot renew expired tokens against a public issuer URL
# with a self-signed certificate from inside the cluster, so Management Identity returns HTTP 500 about
# 5 minutes after login. Long token and session lifespans avoid renewal. With a publicly trusted
# certificate (for example Let's Encrypt) this is not needed.
# The realm is created by Identity at startup, so this waits for it.
# Not yet verified against the operator-managed camunda/keycloak image (adapted from the Kind hub recipe).
.PHONY: keycloak-realm-tuning
keycloak-realm-tuning:
	@echo "waiting for realm $(KEYCLOAK_REALM) ..."
	@admin=$$(kubectl get secret keycloak-bootstrap-admin -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.username | base64decode}}'); \
	 pass=$$(kubectl get secret keycloak-bootstrap-admin -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.password | base64decode}}'); \
	 for i in $$(seq 1 60); do \
	  if kubectl exec -n $(CAMUNDA_NAMESPACE) keycloak-0 -- sh -c \
	    "/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:18080/auth --realm master --user $$admin --password $$pass >/dev/null 2>&1 && \
	     /opt/keycloak/bin/kcadm.sh update realms/$(KEYCLOAK_REALM) -s accessTokenLifespan=28800 -s ssoSessionIdleTimeout=28800 -s ssoSessionMaxLifespan=43200" >/dev/null 2>&1; then \
	    echo "realm $(KEYCLOAK_REALM): token lifespan 8h, session 12h"; exit 0; fi; sleep 10; done; \
	 echo "ERROR: realm $(KEYCLOAK_REALM) not available"; exit 1
