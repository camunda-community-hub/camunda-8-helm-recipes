# Keycloak admin helpers for the operator-managed Keycloak (see recipes/keycloak).
# The secret keycloak-bootstrap-admin is created by `make keycloak-admin-secret` (user KEYCLOAK_ADMIN_USERNAME, password DEFAULT_PASSWORD).

.PHONY: keycloak-password
keycloak-password:
	@echo "Keycloak admin user: $$(kubectl get secret keycloak-bootstrap-admin -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.username | base64decode}}')"
	@echo "Keycloak admin password: $$(kubectl get secret keycloak-bootstrap-admin -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.password | base64decode}}')"

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
