# Keycloak via the Keycloak operator. Camunda chart 15 (8.10) no longer bundles Keycloak.
# Defaults live in recipes/keycloak/config.mk. Needs the pg-keycloak cluster from recipes/postgres.
#
# The operator and the Keycloak server it manages are released together and are expected to match,
# so KEYCLOAK_VERSION pins both the operator manifests and the camunda/keycloak image tag.

KEYCLOAK_K8S_RESOURCES_URL = https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/$(KEYCLOAK_VERSION)/kubernetes

# The operator exits at startup if a CRD it watches is missing (26.7 added the oidcclients and samlclients kinds)
.PHONY: keycloak-operator
keycloak-operator:
	kubectl create namespace $(CAMUNDA_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply --server-side -f $(KEYCLOAK_K8S_RESOURCES_URL)/keycloaks.k8s.keycloak.org-v1.yml
	kubectl apply --server-side -f $(KEYCLOAK_K8S_RESOURCES_URL)/keycloakrealmimports.k8s.keycloak.org-v1.yml
	kubectl apply --server-side -f $(KEYCLOAK_K8S_RESOURCES_URL)/keycloakoidcclients.k8s.keycloak.org-v1.yml
	kubectl apply --server-side -f $(KEYCLOAK_K8S_RESOURCES_URL)/keycloaksamlclients.k8s.keycloak.org-v1.yml
	kubectl apply -n $(CAMUNDA_NAMESPACE) --server-side -f $(KEYCLOAK_K8S_RESOURCES_URL)/kubernetes.yml
	kubectl wait --for=condition=available --timeout=300s deployment/keycloak-operator -n $(CAMUNDA_NAMESPACE)

# Bootstrap admin from KEYCLOAK_ADMIN_USERNAME and DEFAULT_PASSWORD instead of an operator generated password.
# The Keycloak resource points at this secret with spec.bootstrapAdmin.user.secret.
.PHONY: keycloak-admin-secret
keycloak-admin-secret:
	kubectl create namespace $(CAMUNDA_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret generic keycloak-bootstrap-admin -n $(CAMUNDA_NAMESPACE) \
	  --from-literal=username=$(KEYCLOAK_ADMIN_USERNAME) --from-literal=password='$(DEFAULT_PASSWORD)' \
	  --dry-run=client -o yaml | kubectl apply -f -

# KEYCLOAK_MODE: domain (public URL https://KEYCLOAK_HOST/auth) or local (no domain, port-forward)
# KEYCLOAK_INGRESS: nginx (create an Ingress for /auth) or none (for example Traefik routes it elsewhere)
.PHONY: keycloak
keycloak: keycloak-operator keycloak-admin-secret
	sed "s|<KEYCLOAK_VERSION>|$(KEYCLOAK_VERSION)|g; \
	     s|<KEYCLOAK_HOST>|$(KEYCLOAK_HOST)|g; \
	     s|<KEYCLOAK_CPU_REQUEST>|$(KEYCLOAK_CPU_REQUEST)|g; \
	     s|<KEYCLOAK_CPU_LIMIT>|$(KEYCLOAK_CPU_LIMIT)|g; \
	     s|<KEYCLOAK_MEMORY>|$(KEYCLOAK_MEMORY)|g; \
	     s|<POSTGRES_KEYCLOAK_DB>|$(POSTGRES_KEYCLOAK_DB)|g;" \
	  $(root)/recipes/keycloak/include/keycloak-instance-$(KEYCLOAK_MODE).tpl.yaml | kubectl apply -n $(CAMUNDA_NAMESPACE) -f -
ifeq ($(KEYCLOAK_INGRESS),nginx)
	sed "s|<KEYCLOAK_HOST>|$(KEYCLOAK_HOST)|g; s|<TLS_SECRET_NAME>|$(TLS_SECRET_NAME)|g;" \
	  $(root)/recipes/keycloak/include/keycloak-ingress-nginx.tpl.yaml | kubectl apply -n $(CAMUNDA_NAMESPACE) -f -
endif
	kubectl wait --for=condition=Ready --timeout=600s keycloak/keycloak -n $(CAMUNDA_NAMESPACE)

.PHONY: keycloak-status
keycloak-status:
	kubectl get keycloak,pods,svc -l app=keycloak -n $(CAMUNDA_NAMESPACE)

# Deletes the Keycloak instance and its ingress. The operator and the pg-keycloak database are left in place.
.PHONY: clean-keycloak
clean-keycloak:
	-kubectl delete ingress keycloak-ingress -n $(CAMUNDA_NAMESPACE)
	-kubectl delete keycloak keycloak -n $(CAMUNDA_NAMESPACE)

# Removes the Keycloak operator and CRDs (this deletes every Keycloak resource in the Kubernetes cluster).
.PHONY: clean-keycloak-operator
clean-keycloak-operator:
	-kubectl delete -n $(CAMUNDA_NAMESPACE) -f $(KEYCLOAK_K8S_RESOURCES_URL)/kubernetes.yml
	-kubectl delete -f $(KEYCLOAK_K8S_RESOURCES_URL)/keycloaksamlclients.k8s.keycloak.org-v1.yml
	-kubectl delete -f $(KEYCLOAK_K8S_RESOURCES_URL)/keycloakoidcclients.k8s.keycloak.org-v1.yml
	-kubectl delete -f $(KEYCLOAK_K8S_RESOURCES_URL)/keycloakrealmimports.k8s.keycloak.org-v1.yml
	-kubectl delete -f $(KEYCLOAK_K8S_RESOURCES_URL)/keycloaks.k8s.keycloak.org-v1.yml
