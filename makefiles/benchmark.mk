BENCHMARK_NAMESPACE ?= $(CAMUNDA_NAMESPACE)

.PHONY: benchmark # create the payload ConfigMap and deploy the benchmark tool
benchmark:
	-kubectl delete configmap benchmark-payload -n $(BENCHMARK_NAMESPACE) 2>/dev/null || true
	kubectl create configmap benchmark-payload \
	  --from-file=payload.json=./payload.json \
	  -n $(BENCHMARK_NAMESPACE)
	kubectl apply -f ./benchmark.yaml -n $(BENCHMARK_NAMESPACE)

.PHONY: clean-benchmark # remove the benchmark deployment and payload ConfigMap
clean-benchmark:
	-kubectl delete -f ./benchmark.yaml -n $(BENCHMARK_NAMESPACE)
	-kubectl delete configmap benchmark-payload -n $(BENCHMARK_NAMESPACE)

.PHONY: logs-benchmark # stream logs from the running benchmark pod
logs-benchmark:
	kubectl logs -f -l app=benchmark -n $(BENCHMARK_NAMESPACE)

.PHONY: await-zeebe # wait for Zeebe gateway to be available before starting benchmark
await-zeebe:
	@echo "Waiting for Zeebe gateway..."
	kubectl wait --for=condition=available \
	  deployment/$(CAMUNDA_RELEASE_NAME)-zeebe-gateway \
	  --timeout=300s -n $(BENCHMARK_NAMESPACE)
