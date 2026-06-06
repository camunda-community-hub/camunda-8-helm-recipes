BENCHMARK_NAMESPACE ?= $(CAMUNDA_NAMESPACE)

.PHONY: benchmark # create the payload ConfigMap and deploy the benchmark tool
benchmark:
	-kubectl delete configmap benchmark-payload -n $(BENCHMARK_NAMESPACE) 2>/dev/null || true
	kubectl create configmap benchmark-payload \
	  --from-file=payload.json=./include/payload.json \
	  -n $(BENCHMARK_NAMESPACE)
	kubectl apply -f ./include/benchmark.yaml -n $(BENCHMARK_NAMESPACE)

.PHONY: clean-benchmark # remove the benchmark deployment and payload ConfigMap
clean-benchmark:
	-kubectl delete -f ./include/benchmark.yaml -n $(BENCHMARK_NAMESPACE)
	-kubectl delete configmap benchmark-payload -n $(BENCHMARK_NAMESPACE)

.PHONY: logs-benchmark # stream logs from the running benchmark pod
logs-benchmark:
	kubectl logs -f -l app=benchmark -n $(BENCHMARK_NAMESPACE)

