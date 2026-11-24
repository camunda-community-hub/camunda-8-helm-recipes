# ════════════════════════════════════════════════════════════════════════════
# GKE DUAL-REGION NETWORKING
# ════════════════════════════════════════════════════════════════════════════
#
# Connects two GKE clusters in different regions of the same VPC so a Camunda Orchestration Cluster can be
# stretched across them (https://docs.camunda.io/docs/self-managed/concepts/multi-region/dual-region/).
#
# Two layers, same technique as the earlier camunda-8-helm-profiles GKE dual-region profile:
#   1. Routing: a GCP VPC is global, and VPC-native (alias IP) clusters get routable pod IPs, so pods in
#      both regions reach each other without peering. Only a firewall rule for the pod ranges is needed.
#   2. DNS chaining: each cluster exposes kube-dns on an internal load balancer with global access. A small
#      CoreDNS (dns-chain, fixed ClusterIP DNS_CHAIN_IP_x) forwards <remote namespace>.svc.cluster.local to the
#      other cluster's load balancer and everything else to the local kube-dns. Pods that resolve remote names
#      (the Zeebe brokers) use it through dnsPolicy: None + dnsConfig. Namespaces have to differ between clusters.
#      kube-dns stubDomains (what the old profile used) no longer work for names under cluster.local on GKE:
#      the managed CoreDNS based kube-dns answers NXDOMAIN before the stub domain forward is reached.
#
# Cross-cluster traffic goes to pod IPs (headless services). ClusterIPs are not routable from the other
# cluster, so use headless services (Zeebe, elasticsearch-es-masters) or public URLs across regions.
#
# Variables (defaults in recipes/google/gke-dual-region/config.mk):
#   GCP_PROJECT, GCP_NETWORK, DEPLOYMENT_NAME
#   CLUSTER_0, GCP_REGION_0, CAMUNDA_NAMESPACE_0, GCP_CLUSTER_IPV4_CIDR_0
#   CLUSTER_1, GCP_REGION_1, CAMUNDA_NAMESPACE_1, GCP_CLUSTER_IPV4_CIDR_1

KUBE_CONTEXT_0 ?= gke_$(GCP_PROJECT)_$(GCP_REGION_0)_$(CLUSTER_0)
KUBE_CONTEXT_1 ?= gke_$(GCP_PROJECT)_$(GCP_REGION_1)_$(CLUSTER_1)
GCP_NETWORK ?= default
DUAL_REGION_FIREWALL_RULE ?= $(DEPLOYMENT_NAME)-dual-region-pods
DNS_TEST_IMAGE ?= busybox:1.37
COREDNS_IMAGE ?= registry.k8s.io/coredns/coredns:v1.12.1
# Fixed ClusterIPs of the dns-chain service, inside GCP_SERVICES_IPV4_CIDR_0 / _1
DNS_CHAIN_IP_0 ?= 10.104.0.53
DNS_CHAIN_IP_1 ?= 10.112.0.53

.PHONY: dual-region-networking
dual-region-networking: add-contexts firewall-dual-region configure-dns
	@echo "✅ Dual-region networking configured. Verify with: make test-dns"

# ── Kube contexts ───────────────────────────────────────────────────────────

.PHONY: add-contexts
add-contexts:
	gcloud container clusters get-credentials $(CLUSTER_0) --region $(GCP_REGION_0) --project $(GCP_PROJECT)
	gcloud container clusters get-credentials $(CLUSTER_1) --region $(GCP_REGION_1) --project $(GCP_PROJECT)
	@echo "Region 0 context: $(KUBE_CONTEXT_0)"
	@echo "Region 1 context: $(KUBE_CONTEXT_1)"

# ── Firewall: allow pod-to-pod traffic between the two clusters ────────────
# The default VPC rules only cover the node subnets, not the pod ranges of the clusters.

.PHONY: firewall-dual-region
firewall-dual-region:
	@if gcloud compute firewall-rules describe $(DUAL_REGION_FIREWALL_RULE) --project $(GCP_PROJECT) >/dev/null 2>&1; then \
	  echo "Firewall rule $(DUAL_REGION_FIREWALL_RULE) already exists"; \
	else \
	  gcloud compute firewall-rules create $(DUAL_REGION_FIREWALL_RULE) \
	    --project $(GCP_PROJECT) \
	    --network $(GCP_NETWORK) \
	    --direction INGRESS \
	    --source-ranges $(GCP_CLUSTER_IPV4_CIDR_0),$(GCP_CLUSTER_IPV4_CIDR_1) \
	    --allow tcp,udp,icmp \
	    --description "Pod to pod traffic between the dual-region GKE clusters $(CLUSTER_0) and $(CLUSTER_1)"; \
	fi

.PHONY: clean-firewall-dual-region
clean-firewall-dual-region:
	-gcloud compute firewall-rules delete $(DUAL_REGION_FIREWALL_RULE) --project $(GCP_PROJECT) --quiet

# ── DNS chaining ────────────────────────────────────────────────────────────

.PHONY: configure-dns
configure-dns: deploy-dns-lb deploy-dns-chain

.PHONY: deploy-dns-lb
deploy-dns-lb:
	kubectl --context $(KUBE_CONTEXT_0) apply -f $(root)/recipes/google/include/internal-dns-lb.yaml
	kubectl --context $(KUBE_CONTEXT_1) apply -f $(root)/recipes/google/include/internal-dns-lb.yaml

# Internal load balancer for region 0's Prometheus, so region 1's Prometheus can remote-write to it.
# Run after the metrics stack is installed in region 0.
.PHONY: prometheus-lb
prometheus-lb:
	kubectl --context $(KUBE_CONTEXT_0) apply -f $(root)/recipes/google/include/prometheus-internal-lb.yaml
	@for i in $$(seq 1 60); do \
	  ip=$$(kubectl --context $(KUBE_CONTEXT_0) -n default get svc prometheus-internal-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	  if [ -n "$$ip" ]; then echo "Region 0 Prometheus remote write: http://$$ip:9090/api/v1/write"; break; fi; sleep 10; done

.PHONY: clean-prometheus-lb
clean-prometheus-lb:
	-kubectl --context $(KUBE_CONTEXT_0) delete -f $(root)/recipes/google/include/prometheus-internal-lb.yaml

# Reads the internal IP of kube-dns-lb, waiting until GCP has assigned it
DNS_LB_IP = $$(for i in $$(seq 1 60); do \
	  ip=$$(kubectl --context $(1) -n kube-system get svc kube-dns-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	  if [ -n "$$ip" ]; then echo $$ip; break; fi; sleep 10; done)

# Renders and applies the dns-chain CoreDNS in one cluster.
# $(1) context, $(2) DNS_CHAIN_IP, $(3) remote namespace, $(4) shell expression with the remote kube-dns-lb IP
define APPLY_DNS_CHAIN
	LOCAL_DNS=$$(kubectl --context $(1) -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}'); \
	sed "s|<REMOTE_NAMESPACE>|$(3)|g; s|<REMOTE_DNS_LB_IP>|$(4)|g; s|<LOCAL_KUBE_DNS_IP>|$$LOCAL_DNS|g; \
	     s|<DNS_CHAIN_IP>|$(2)|g; s|<COREDNS_IMAGE>|$(COREDNS_IMAGE)|g" \
	  $(root)/recipes/google/include/dns-chain.tpl.yaml | kubectl --context $(1) apply -f -
endef

.PHONY: deploy-dns-chain
deploy-dns-chain:
	@echo "Waiting for the internal DNS load balancer IPs..."
	@IP0=$(call DNS_LB_IP,$(KUBE_CONTEXT_0)); IP1=$(call DNS_LB_IP,$(KUBE_CONTEXT_1)); \
	if [ -z "$$IP0" ] || [ -z "$$IP1" ]; then echo "❌ kube-dns-lb has no IP (region0='$$IP0' region1='$$IP1')"; exit 1; fi; \
	echo "Region 0 kube-dns-lb: $$IP0"; echo "Region 1 kube-dns-lb: $$IP1"; \
	$(call APPLY_DNS_CHAIN,$(KUBE_CONTEXT_0),$(DNS_CHAIN_IP_0),$(CAMUNDA_NAMESPACE_1),$$IP1); \
	$(call APPLY_DNS_CHAIN,$(KUBE_CONTEXT_1),$(DNS_CHAIN_IP_1),$(CAMUNDA_NAMESPACE_0),$$IP0)
	kubectl --context $(KUBE_CONTEXT_0) -n kube-system rollout restart deployment dns-chain
	kubectl --context $(KUBE_CONTEXT_1) -n kube-system rollout restart deployment dns-chain
	kubectl --context $(KUBE_CONTEXT_0) -n kube-system rollout status deployment dns-chain --timeout=300s
	kubectl --context $(KUBE_CONTEXT_1) -n kube-system rollout status deployment dns-chain --timeout=300s

.PHONY: clean-dns
clean-dns:
	-kubectl --context $(KUBE_CONTEXT_0) -n kube-system delete deployment,service,configmap dns-chain
	-kubectl --context $(KUBE_CONTEXT_1) -n kube-system delete deployment,service,configmap dns-chain
	-kubectl --context $(KUBE_CONTEXT_0) -n kube-system delete svc kube-dns-lb
	-kubectl --context $(KUBE_CONTEXT_1) -n kube-system delete svc kube-dns-lb

# ── Verification ────────────────────────────────────────────────────────────
# Deploys a small web server behind a headless service in each Camunda namespace, then resolves and calls it
# from the other cluster. Passing proves cross-cluster DNS, pod routing and the firewall rule.

define DNS_TEST_MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: dns-test
  labels: {app: dns-test}
spec:
  containers:
    - name: web
      image: $(DNS_TEST_IMAGE)
      command: ["sh", "-c", "echo ok > /tmp/index.html && httpd -f -p 8080 -h /tmp"]
      ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata:
  name: dns-test
spec:
  clusterIP: None
  selector: {app: dns-test}
  ports: [{port: 8080}]
endef
export DNS_TEST_MANIFEST

# Pod spec override that resolves through dns-chain. $(1) dns-chain IP, $(2) local namespace
DNS_CHAIN_OVERRIDES = {"spec":{"dnsPolicy":"None","dnsConfig":{"nameservers":["$(1)"],"searches":["$(2).svc.cluster.local","svc.cluster.local","cluster.local"],"options":[{"name":"ndots","value":"5"}]}}}

.PHONY: test-dns
test-dns:
	kubectl --context $(KUBE_CONTEXT_0) create namespace $(CAMUNDA_NAMESPACE_0) --dry-run=client -o yaml | kubectl --context $(KUBE_CONTEXT_0) apply -f -
	kubectl --context $(KUBE_CONTEXT_1) create namespace $(CAMUNDA_NAMESPACE_1) --dry-run=client -o yaml | kubectl --context $(KUBE_CONTEXT_1) apply -f -
	echo "$$DNS_TEST_MANIFEST" | kubectl --context $(KUBE_CONTEXT_0) -n $(CAMUNDA_NAMESPACE_0) apply -f -
	echo "$$DNS_TEST_MANIFEST" | kubectl --context $(KUBE_CONTEXT_1) -n $(CAMUNDA_NAMESPACE_1) apply -f -
	kubectl --context $(KUBE_CONTEXT_0) -n $(CAMUNDA_NAMESPACE_0) wait --for=condition=Ready pod/dns-test --timeout=120s
	kubectl --context $(KUBE_CONTEXT_1) -n $(CAMUNDA_NAMESPACE_1) wait --for=condition=Ready pod/dns-test --timeout=120s
	@echo "── Region 0 → region 1 (through dns-chain $(DNS_CHAIN_IP_0), like the brokers) ──"
	kubectl --context $(KUBE_CONTEXT_0) -n $(CAMUNDA_NAMESPACE_0) run dns-test-client --rm -i --restart=Never --image=$(DNS_TEST_IMAGE) \
	  --overrides='$(call DNS_CHAIN_OVERRIDES,$(DNS_CHAIN_IP_0),$(CAMUNDA_NAMESPACE_0))' -- \
	  sh -c "nslookup dns-test.$(CAMUNDA_NAMESPACE_1).svc.cluster.local && wget -qO- -T 5 http://dns-test.$(CAMUNDA_NAMESPACE_1).svc.cluster.local:8080 && wget -qO- -T 5 http://dns-test.$(CAMUNDA_NAMESPACE_0).svc.cluster.local:8080"
	@echo "── Region 1 → region 0 (through dns-chain $(DNS_CHAIN_IP_1)) ──"
	kubectl --context $(KUBE_CONTEXT_1) -n $(CAMUNDA_NAMESPACE_1) run dns-test-client --rm -i --restart=Never --image=$(DNS_TEST_IMAGE) \
	  --overrides='$(call DNS_CHAIN_OVERRIDES,$(DNS_CHAIN_IP_1),$(CAMUNDA_NAMESPACE_1))' -- \
	  sh -c "nslookup dns-test.$(CAMUNDA_NAMESPACE_0).svc.cluster.local && wget -qO- -T 5 http://dns-test.$(CAMUNDA_NAMESPACE_0).svc.cluster.local:8080 && wget -qO- -T 5 http://dns-test.$(CAMUNDA_NAMESPACE_1).svc.cluster.local:8080"
	@echo "✅ Cross-region DNS and pod routing work in both directions"

.PHONY: clean-dns-test
clean-dns-test:
	-echo "$$DNS_TEST_MANIFEST" | kubectl --context $(KUBE_CONTEXT_0) -n $(CAMUNDA_NAMESPACE_0) delete -f -
	-echo "$$DNS_TEST_MANIFEST" | kubectl --context $(KUBE_CONTEXT_1) -n $(CAMUNDA_NAMESPACE_1) delete -f -

# ── Elasticsearch passwords across regions ──────────────────────────────────
# Each ECK cluster generates its own elastic password. The brokers in both regions export to both
# Elasticsearch clusters, so both namespaces need both passwords. Same approach as the Camunda EKS
# dual-region reference (sync_elasticsearch_passwords.sh). Run after Elasticsearch is Ready in both
# regions and before installing Camunda. If Camunda already runs, restart the brokers afterwards.

.PHONY: sync-elasticsearch-passwords
sync-elasticsearch-passwords:
	@P0=$$(kubectl --context $(KUBE_CONTEXT_0) -n $(CAMUNDA_NAMESPACE_0) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d); \
	P1=$$(kubectl --context $(KUBE_CONTEXT_1) -n $(CAMUNDA_NAMESPACE_1) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d); \
	if [ -z "$$P0" ] || [ -z "$$P1" ]; then echo "❌ elasticsearch-es-elastic-user missing in one of the regions"; exit 1; fi; \
	for ctx_ns in "$(KUBE_CONTEXT_0) $(CAMUNDA_NAMESPACE_0)" "$(KUBE_CONTEXT_1) $(CAMUNDA_NAMESPACE_1)"; do \
	  set -- $$ctx_ns; \
	  kubectl --context $$1 -n $$2 create secret generic elasticsearch-es-password-region-0 --from-literal=elastic="$$P0" --dry-run=client -o yaml | kubectl --context $$1 apply -f -; \
	  kubectl --context $$1 -n $$2 create secret generic elasticsearch-es-password-region-1 --from-literal=elastic="$$P1" --dry-run=client -o yaml | kubectl --context $$1 apply -f -; \
	done
	@echo "✅ elasticsearch-es-password-region-0 and -region-1 exist in $(CAMUNDA_NAMESPACE_0) and $(CAMUNDA_NAMESPACE_1)"

.PHONY: dual-region-status
dual-region-status:
	@echo "Region 0: $(CLUSTER_0) ($(GCP_REGION_0)) namespace $(CAMUNDA_NAMESPACE_0) context $(KUBE_CONTEXT_0)"
	@echo "Region 1: $(CLUSTER_1) ($(GCP_REGION_1)) namespace $(CAMUNDA_NAMESPACE_1) context $(KUBE_CONTEXT_1)"
	-kubectl --context $(KUBE_CONTEXT_0) -n kube-system get svc kube-dns-lb
	-kubectl --context $(KUBE_CONTEXT_1) -n kube-system get svc kube-dns-lb
	-gcloud compute firewall-rules describe $(DUAL_REGION_FIREWALL_RULE) --project $(GCP_PROJECT) --format="value(name,sourceRanges)"
