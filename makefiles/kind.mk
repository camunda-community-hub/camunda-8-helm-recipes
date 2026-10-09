.PHONY: kube-kind
kube-kind:
	kind create cluster \
	  --config=$(root)/recipes/kind/include/config.yaml \
	  --name $(DEPLOYMENT_NAME)
	
#	kubectl apply -f $(root)/kind/include/ssd-storageclass-kind.yaml

.PHONY: clean-kube-kind
clean-kube-kind: use-kube
	kind delete cluster --name $(DEPLOYMENT_NAME)

.PHONY: use-kube
use-kube:
	kubectl config use-context kind-$(DEPLOYMENT_NAME)

.PHONY: kube-status
kube-status:
	kubectl get nodes -o wide
	kubectl cluster-info 

# Kind has no LoadBalancer: run the controller on the ingress-ready node with hostPort.
# recipes/kind/include/config.yaml maps host ports 80/443 to that node.
.PHONY: ingress-nginx
ingress-nginx:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update ingress-nginx
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace \
	  --set controller.hostPort.enabled=true \
	  --set controller.service.type=NodePort \
	  --set-string controller.nodeSelector.ingress-ready=true \
	  --set controller.tolerations[0].key=node-role.kubernetes.io/control-plane \
	  --set controller.tolerations[0].operator=Exists \
	  --set controller.tolerations[0].effect=NoSchedule \
	  --wait

.PHONY: kind-namespace
kind-namespace:
	kubectl create namespace $(CAMUNDA_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

# Single in-cluster PostgreSQL for local development (Camunda, Hub, Identity and Keycloak databases).
.PHONY: kind-postgres
kind-postgres: kind-namespace
	sed "s|<DEFAULT_PASSWORD>|$(DEFAULT_PASSWORD)|g; \
	     s|<POSTGRES_MASTER_PASSWORD>|$(POSTGRES_MASTER_PASSWORD)|g; \
	     s|<POSTGRES_CAMUNDA_DB>|$(POSTGRES_CAMUNDA_DB)|g; \
	     s|<POSTGRES_CAMUNDA_USERNAME>|$(POSTGRES_CAMUNDA_USERNAME)|g; \
	     s|<POSTGRES_MODELER_DB>|$(POSTGRES_MODELER_DB)|g; \
	     s|<POSTGRES_MODELER_USERNAME>|$(POSTGRES_MODELER_USERNAME)|g; \
	     s|<POSTGRES_KEYCLOAK_DB>|$(POSTGRES_KEYCLOAK_DB)|g; \
	     s|<POSTGRES_KEYCLOAK_USERNAME>|$(POSTGRES_KEYCLOAK_USERNAME)|g; \
	     s|<POSTGRES_IDENTITY_DB>|$(POSTGRES_IDENTITY_DB)|g; \
	     s|<POSTGRES_IDENTITY_USERNAME>|$(POSTGRES_IDENTITY_USERNAME)|g;" \
	  $(root)/recipes/kind/include/postgres.tpl.yaml | kubectl apply -n $(CAMUNDA_NAMESPACE) -f -
	kubectl rollout status statefulset/postgres -n $(CAMUNDA_NAMESPACE) --timeout=180s

# Single Keycloak for local development (chart 15 has no bundled Keycloak). Needs kind-postgres and the TLS secret.
.PHONY: kind-keycloak
kind-keycloak: kind-postgres
	sed "s|<DEFAULT_PASSWORD>|$(DEFAULT_PASSWORD)|g; \
	     s|<HOST_NAME>|$(HOST_NAME)|g; \
	     s|<TLS_SECRET_NAME>|$(TLS_SECRET_NAME)|g; \
	     s|<KEYCLOAK_ADMIN_USERNAME>|$(KEYCLOAK_ADMIN_USERNAME)|g; \
	     s|<POSTGRES_KEYCLOAK_DB>|$(POSTGRES_KEYCLOAK_DB)|g; \
	     s|<POSTGRES_KEYCLOAK_USERNAME>|$(POSTGRES_KEYCLOAK_USERNAME)|g;" \
	  $(root)/recipes/kind/include/keycloak.tpl.yaml | kubectl apply -n $(CAMUNDA_NAMESPACE) -f -
	kubectl rollout status deployment/camunda-keycloak -n $(CAMUNDA_NAMESPACE) --timeout=300s

.PHONY: check-ingress
check-ingress:
	@kubectl get ingressclass nginx >/dev/null 2>&1 && \
	  [ "$$(kubectl get deploy -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" -ge 1 ] 2>/dev/null || { \
	    echo "ERROR: ingress-nginx is not installed/ready in the current context. Run: make ingress-nginx"; exit 1; }
