.PHONY: create-keycloak-admin-user
create-keycloak-admin-user:
	@echo "🔐 creating temporary keycloak admin user ... "

	kubectl exec -it camunda-keycloak-0 --namespace $(CAMUNDA_NAMESPACE) -- \
    env KC_CACHE=local \
    env KC_BOOTSTRAP_ADMIN_PASSWORD=$(KEYCLOAK_TEMP_ADMIN_PASSWORD) \
	/opt/bitnami/keycloak/bin/kc.sh bootstrap-admin user \
	          --db postgres \
	          --no-prompt \
              --username $(KEYCLOAK_TEMP_ADMIN_USERNAME) \
              --password:env KC_BOOTSTRAP_ADMIN_PASSWORD \
              --db-url jdbc:postgresql://$(POSTGRES_HOST):5432/$(POSTGRES_KEYCLOAK_DB) \
              --db-username $(POSTGRES_KEYCLOAK_USERNAME) \
              --db-password $(POSTGRES_KEYCLOAK_PASSWORD) \
              --verbose
	@echo "✅ Created temporary admin account: $(KEYCLOAK_TEMP_ADMIN_USERNAME)"

.PHONY: keycloak-password
keycloak-password:
	$(eval kcPassword := $(shell kubectl get secret --namespace $(CAMUNDA_NAMESPACE) "camunda-credentials" -o jsonpath="{.data.identity-keycloak-admin-password}" | base64 --decode))
	@echo KeyCloak Admin password: $(kcPassword)



# Identity cannot renew expired tokens against the public (self-signed) issuer URL from inside the
# cluster, so Management Identity returns HTTP 500 about 5 minutes after login. For local development,
# long token/session lifespans avoid renewal. Works with the Keycloak from `make kind-keycloak`.
# The realm is created by Identity at startup, so this waits for it.
.PHONY: keycloak-realm-tuning
keycloak-realm-tuning:
	@echo "waiting for realm $(KEYCLOAK_REALM) ..."
	@for i in $$(seq 1 60); do \
	  if kubectl exec -n $(CAMUNDA_NAMESPACE) deploy/camunda-keycloak -- sh -c \
	    '/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/auth --realm master --user $(KEYCLOAK_ADMIN_USERNAME) --password $(DEFAULT_PASSWORD) >/dev/null 2>&1 && \
	     /opt/keycloak/bin/kcadm.sh update realms/$(KEYCLOAK_REALM) -s accessTokenLifespan=28800 -s ssoSessionIdleTimeout=28800 -s ssoSessionMaxLifespan=43200' >/dev/null 2>&1; then \
	    echo "realm $(KEYCLOAK_REALM): token lifespan 8h, session 12h"; exit 0; fi; sleep 10; done; \
	  echo "ERROR: realm $(KEYCLOAK_REALM) not available"; exit 1
