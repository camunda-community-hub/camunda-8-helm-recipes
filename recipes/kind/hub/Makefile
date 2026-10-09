# Determine the root directory
ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../../..
else
    root ?= $(shell pwd)/../../..
endif

# Create a config.mk file in the root directory of this project to override defaults included below
-include $(root)/config.mk

# Theses are the default values used by this recipe
include ./config.mk

LOCAL_HOSTS ?= $(HOST_NAME) grpc.$(HOST_NAME) identity.$(HOST_NAME)

.PHONY: all
all: preflight kube ingress-nginx tls kind-keycloak camunda-values.yaml create-camunda-credentials camunda keycloak-realm-tuning wait-camunda urls

.PHONY: kube
kube: kube-kind

# Self signed certificate covering $(HOST_NAME), grpc.$(HOST_NAME) and identity.$(HOST_NAME)
.PHONY: tls
tls: kind-namespace create-custom-certs create-tls-secrets

.PHONY: preflight
preflight:
	@helm version --short | grep -q '^v4' || (echo "ERROR: Helm 4 is required (chart 15)"; exit 1)
	@for h in $(LOCAL_HOSTS); do \
	  grep -qE "(^|[[:space:]])$$h([[:space:]]|$$)" /etc/hosts || { \
	    echo "ERROR: $$h is missing from /etc/hosts. Run:"; \
	    echo "  echo \"127.0.0.1 $(LOCAL_HOSTS)\" | sudo tee -a /etc/hosts"; exit 1; }; \
	done
	@echo "preflight ok"

.PHONY: wait-camunda
wait-camunda:
	kubectl wait --for=condition=Ready pod --all -n $(CAMUNDA_NAMESPACE) --timeout=900s
	kubectl get pods -n $(CAMUNDA_NAMESPACE)

.PHONY: urls
urls:
	@echo ""
	@echo "Hub:           https://$(HOST_NAME)/modeler"
	@echo "Orchestration: https://$(HOST_NAME)/orchestration"
	@echo "Identity:      https://identity.$(HOST_NAME)"
	@echo "Keycloak:      https://$(HOST_NAME)/auth  ($(KEYCLOAK_ADMIN_USERNAME) / $(DEFAULT_PASSWORD))"
	@echo "Login:         demo / $(DEFAULT_PASSWORD)"
	@echo "After a reinstall, clear cookies for $(HOST_NAME) and identity.$(HOST_NAME) (or use a private window)."

# Removes only Camunda, Postgres and Keycloak; keep the Kind cluster
.PHONY: clean-camunda-stack
clean-camunda-stack: clean-camunda

# Deletes the whole Kind cluster
.PHONY: clean
clean: clean-kube-kind

include $(root)/makefiles/kind.mk
include $(root)/makefiles/camunda.mk
include $(root)/makefiles/keycloak.mk
include $(root)/makefiles/tls-self-signed-cert.mk
include $(root)/makefiles/test.mk
