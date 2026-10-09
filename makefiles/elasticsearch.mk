# Elasticsearch via the ECK operator. Camunda chart 15 (8.10) no longer bundles Elasticsearch.
# Variables (defaults live in recipes/elasticsearch/config.mk):
#   CAMUNDA_NAMESPACE, ECK_VERSION, ECK_NAMESPACE, ES_VERSION, ES_NODE_COUNT,
#   ES_CPU_REQUEST, ES_CPU_LIMIT, ES_MEMORY, ES_STORAGE_SIZE

.PHONY: eck-operator
eck-operator:
	kubectl apply --server-side -f https://download.elastic.co/downloads/eck/$(ECK_VERSION)/crds.yaml
	kubectl create namespace $(ECK_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n $(ECK_NAMESPACE) --server-side -f https://download.elastic.co/downloads/eck/$(ECK_VERSION)/operator.yaml
	kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 --timeout=300s statefulset/elastic-operator -n $(ECK_NAMESPACE)

.PHONY: elasticsearch
elasticsearch: eck-operator
	kubectl create namespace $(CAMUNDA_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	sed "s|<ES_VERSION>|$(ES_VERSION)|g; \
	     s|<ES_NODE_COUNT>|$(ES_NODE_COUNT)|g; \
	     s|<ES_CPU_REQUEST>|$(ES_CPU_REQUEST)|g; \
	     s|<ES_CPU_LIMIT>|$(ES_CPU_LIMIT)|g; \
	     s|<ES_MEMORY>|$(ES_MEMORY)|g; \
	     s|<ES_STORAGE_SIZE>|$(ES_STORAGE_SIZE)|g;" \
	  $(root)/recipes/elasticsearch/include/elasticsearch-cluster.tpl.yaml | kubectl apply -n $(CAMUNDA_NAMESPACE) -f -
	kubectl wait --for=jsonpath='{.status.phase}'=Ready --timeout=900s elasticsearch/elasticsearch -n $(CAMUNDA_NAMESPACE)

.PHONY: elasticsearch-status
elasticsearch-status:
	kubectl get elasticsearch,pods,pvc -l elasticsearch.k8s.elastic.co/cluster-name=elasticsearch -n $(CAMUNDA_NAMESPACE)

.PHONY: elasticsearch-password
elasticsearch-password:
	@echo "Elasticsearch user: elastic"
	@echo "Elasticsearch password: $$(kubectl get secret elasticsearch-es-elastic-user -n $(CAMUNDA_NAMESPACE) -o go-template='{{.data.elastic | base64decode}}')"

.PHONY: port-elasticsearch
port-elasticsearch:
	kubectl port-forward svc/elasticsearch-es-http 9200:9200 -n $(CAMUNDA_NAMESPACE)

# Deletes the Elasticsearch cluster and its data. The ECK operator is left in place.
.PHONY: clean-elasticsearch
clean-elasticsearch:
	-kubectl delete elasticsearch elasticsearch -n $(CAMUNDA_NAMESPACE)
	-kubectl delete pvc -l elasticsearch.k8s.elastic.co/cluster-name=elasticsearch -n $(CAMUNDA_NAMESPACE)

# Removes the ECK operator and CRDs. Only do this when no Elasticsearch clusters remain in the Kubernetes cluster.
.PHONY: clean-eck-operator
clean-eck-operator:
	-kubectl delete -n $(ECK_NAMESPACE) -f https://download.elastic.co/downloads/eck/$(ECK_VERSION)/operator.yaml
	-kubectl delete -f https://download.elastic.co/downloads/eck/$(ECK_VERSION)/crds.yaml
