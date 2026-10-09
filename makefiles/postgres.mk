# PostgreSQL via the CloudNativePG (CNPG) operator. Camunda chart 15 (8.10) no longer bundles PostgreSQL.
# Defaults live in recipes/postgres/config.mk.
#
# PG_CLUSTERS is a space separated list of: pg-identity pg-keycloak pg-hub pg-camunda
# Each cluster is a separate PostgreSQL cluster with its own database, owner and secrets,
# reachable in the cluster as <cluster>-rw:5432 (for example pg-identity-rw).

CNPG_MANIFEST_URL = https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-$(basename $(CNPG_VERSION))/releases/cnpg-$(CNPG_VERSION).yaml

.PHONY: cnpg-operator
cnpg-operator:
	kubectl apply -n $(CNPG_NAMESPACE) --server-side -f $(CNPG_MANIFEST_URL)
	kubectl rollout status deployment -n $(CNPG_NAMESPACE) cnpg-controller-manager --timeout=300s

# Secrets for every cluster: <cluster>-secret (database owner) and <cluster>-superuser-secret (postgres).
# CNPG requires the kubernetes.io/basic-auth type. Passwords come from PG_PASSWORD (default DEFAULT_PASSWORD)
# and are never written to a file.
.PHONY: postgres-secrets
postgres-secrets:
	@kubectl create namespace $(CAMUNDA_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@for c in $(PG_CLUSTERS); do \
	  case $$c in pg-identity) owner=$(POSTGRES_IDENTITY_USERNAME);; pg-keycloak) owner=$(POSTGRES_KEYCLOAK_USERNAME);; pg-hub) owner=$(POSTGRES_MODELER_USERNAME);; *) owner=$(POSTGRES_CAMUNDA_USERNAME);; esac; \
	  echo "secrets for $$c (owner $$owner)"; \
	  kubectl create secret generic $$c-secret --type=kubernetes.io/basic-auth \
	    --from-literal=username=$$owner --from-literal=password='$(PG_PASSWORD)' \
	    --dry-run=client -o yaml | kubectl apply -n $(CAMUNDA_NAMESPACE) -f - || exit 1; \
	  kubectl create secret generic $$c-superuser-secret --type=kubernetes.io/basic-auth \
	    --from-literal=username=postgres --from-literal=password='$(PG_PASSWORD)' \
	    --dry-run=client -o yaml | kubectl apply -n $(CAMUNDA_NAMESPACE) -f - || exit 1; \
	done

.PHONY: postgres
postgres: cnpg-operator postgres-secrets
	@for c in $(PG_CLUSTERS); do \
	  case $$c in pg-identity) db=$(POSTGRES_IDENTITY_DB); owner=$(POSTGRES_IDENTITY_USERNAME); desc="Management Identity";; \
	    pg-keycloak) db=$(POSTGRES_KEYCLOAK_DB); owner=$(POSTGRES_KEYCLOAK_USERNAME); desc="Keycloak";; \
	    pg-hub) db=$(POSTGRES_MODELER_DB); owner=$(POSTGRES_MODELER_USERNAME); desc="Camunda Hub";; \
	    *) db=$(POSTGRES_CAMUNDA_DB); owner=$(POSTGRES_CAMUNDA_USERNAME); desc="the Camunda Orchestration Cluster";; esac; \
	  if [ "$(PG_INSTANCES)" -gt 1 ]; then pdb=true; else pdb=false; fi; \
	  echo "deploying $$c"; \
	  sed "s|<PG_CLUSTER>|$$c|g; s|<PG_DATABASE>|$$db|g; s|<PG_OWNER>|$$owner|g; s|<PG_DESCRIPTION>|$$desc|g; \
	       s|<PG_INSTANCES>|$(PG_INSTANCES)|g; s|<PG_ENABLE_PDB>|$$pdb|g; s|<PG_IMAGE>|$(PG_IMAGE)|g; \
	       s|<PG_STORAGE_SIZE>|$(PG_STORAGE_SIZE)|g; s|<PG_WAL_STORAGE_SIZE>|$(PG_WAL_STORAGE_SIZE)|g;" \
	    $(root)/recipes/postgres/include/postgres-cluster.tpl.yaml | \
	  if [ "$$c" = "pg-keycloak" ]; then yq '.spec.postgresql.parameters.lock_timeout = "30s" | .spec.postgresql.parameters.statement_timeout = "0"'; else cat; fi | \
	  kubectl apply --server-side -n $(CAMUNDA_NAMESPACE) -f - || exit 1; \
	done
	@for c in $(PG_CLUSTERS); do \
	  kubectl wait --for=condition=Ready --timeout=600s cluster/$$c -n $(CAMUNDA_NAMESPACE) || exit 1; \
	  kubectl wait --for=jsonpath="{.status.readyInstances}=$(PG_INSTANCES)" --timeout=600s cluster/$$c -n $(CAMUNDA_NAMESPACE) || exit 1; \
	done

.PHONY: postgres-status
postgres-status:
	kubectl get clusters.postgresql.cnpg.io,pods -l cnpg.io/cluster -n $(CAMUNDA_NAMESPACE)

# Usage: make postgres-password PG_CLUSTER=pg-identity
.PHONY: postgres-password
postgres-password:
	@echo "user: $$(kubectl get secret $(PG_CLUSTER)-secret -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.username | base64decode}}')"
	@echo "password: $$(kubectl get secret $(PG_CLUSTER)-secret -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.password | base64decode}}')"

# Deletes the PostgreSQL clusters, their data and secrets. The CNPG operator is left in place.
.PHONY: clean-postgres
clean-postgres:
	@for c in $(PG_CLUSTERS); do \
	  kubectl delete cluster.postgresql.cnpg.io $$c -n $(CAMUNDA_NAMESPACE); \
	  kubectl delete secret $$c-secret $$c-superuser-secret -n $(CAMUNDA_NAMESPACE); \
	done; true

# Removes the CNPG operator and CRDs. Only do this when no PostgreSQL clusters remain in the Kubernetes cluster.
.PHONY: clean-cnpg-operator
clean-cnpg-operator:
	-kubectl delete -f $(CNPG_MANIFEST_URL)
