# ════════════════════════════════════════════════════════════════════════════
# AWS EKS DUAL-REGION TARGETS
# ════════════════════════════════════════════════════════════════════════════
#
# Dual-region networking overlay for two EKS clusters.
# Cluster creation is handled per-region via region0/ and region1/ Makefiles.
#
# Prerequisites:
#   - CLUSTER_0, CLUSTER_1, AWS_REGION_0, AWS_REGION_1 defined in config.mk
#   - VPC_CIDR_0, VPC_CIDR_1 must be non-overlapping
#   - Both clusters must be running before configuring networking
#
# Usage:
#   make -C region0 all           # Create EKS cluster in region 0
#   make -C region1 all           # Create EKS cluster in region 1
#   make configure-vpc-peering    # Full VPC peering setup
#   make configure-dns            # DNS chaining between clusters
#   make test-dns                 # Verify cross-region DNS

# ── VPC Peering ────────────────────────────────────────────────────────────

.PHONY: configure-vpc-peering
configure-vpc-peering: create-vpc-peering accept-vpc-peering configure-vpc-routes configure-vpc-security-groups
	@echo "✅ VPC peering fully configured between $(AWS_REGION_0) and $(AWS_REGION_1)"

.PHONY: create-vpc-peering
create-vpc-peering:
	@echo "🔗 Setting up VPC peering..."
	@VPC_ID_0=$$(aws eks describe-cluster --region $(AWS_REGION_0) --name $(CLUSTER_0) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null); \
	VPC_CIDR_0=$$(aws ec2 describe-vpcs --region $(AWS_REGION_0) \
	  --vpc-ids $$VPC_ID_0 --query 'Vpcs[0].CidrBlock' --output text); \
	VPC_ID_1=$$(aws eks describe-cluster --region $(AWS_REGION_1) --name $(CLUSTER_1) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null); \
	VPC_CIDR_1=$$(aws ec2 describe-vpcs --region $(AWS_REGION_1) \
	  --vpc-ids $$VPC_ID_1 --query 'Vpcs[0].CidrBlock' --output text); \
	echo "  Region 0: VPC=$$VPC_ID_0 CIDR=$$VPC_CIDR_0"; \
	echo "  Region 1: VPC=$$VPC_ID_1 CIDR=$$VPC_CIDR_1"; \
	if [ -z "$$VPC_ID_0" ] || echo "$$VPC_ID_0" | grep -q "None\|error"; then \
	  echo "❌ Could not find VPC for cluster $(CLUSTER_0) in $(AWS_REGION_0)"; exit 1; \
	fi; \
	if [ -z "$$VPC_ID_1" ] || echo "$$VPC_ID_1" | grep -q "None\|error"; then \
	  echo "❌ Could not find VPC for cluster $(CLUSTER_1) in $(AWS_REGION_1)"; exit 1; \
	fi; \
	if [ "$$VPC_CIDR_0" = "$$VPC_CIDR_1" ]; then \
	  echo "❌ ERROR: Both VPCs have the same CIDR ($$VPC_CIDR_0). VPC peering requires non-overlapping CIDRs."; \
	  exit 1; \
	fi; \
	EXISTING=$$(aws ec2 describe-vpc-peering-connections --region $(AWS_REGION_0) \
	  --filters "Name=requester-vpc-info.vpc-id,Values=$$VPC_ID_0" \
	            "Name=accepter-vpc-info.vpc-id,Values=$$VPC_ID_1" \
	            "Name=status-code,Values=active,pending-acceptance,provisioning" \
	  --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' --output text); \
	if [ "$$EXISTING" != "None" ] && [ -n "$$EXISTING" ]; then \
	  echo "  ⚠️  Peering already exists: $$EXISTING. Skipping."; \
	else \
	  echo "  Creating VPC peering connection..."; \
	  PEERING_ID=$$(aws ec2 create-vpc-peering-connection --region $(AWS_REGION_0) \
	    --vpc-id $$VPC_ID_0 \
	    --peer-vpc-id $$VPC_ID_1 \
	    --peer-region $(AWS_REGION_1) \
	    --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text); \
	  echo "  ✅ Peering created: $$PEERING_ID"; \
	fi

.PHONY: accept-vpc-peering
accept-vpc-peering:
	@echo "=== Accepting VPC peering ==="
	@VPC_ID_0=$$(aws eks describe-cluster --region $(AWS_REGION_0) --name $(CLUSTER_0) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_ID_1=$$(aws eks describe-cluster --region $(AWS_REGION_1) --name $(CLUSTER_1) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	PEERING_ID=$$(aws ec2 describe-vpc-peering-connections --region $(AWS_REGION_0) \
	  --filters "Name=requester-vpc-info.vpc-id,Values=$$VPC_ID_0" \
	            "Name=accepter-vpc-info.vpc-id,Values=$$VPC_ID_1" \
	  --query 'VpcPeeringConnections[?Status.Code!=`deleted` && Status.Code!=`rejected`] | [0].VpcPeeringConnectionId' --output text); \
	if [ "$$PEERING_ID" = "None" ] || [ -z "$$PEERING_ID" ]; then \
	  echo "❌ No peering connection found. Run 'make create-vpc-peering' first."; exit 1; \
	fi; \
	echo "  Peering ID: $$PEERING_ID"; \
	STATUS=$$(aws ec2 describe-vpc-peering-connections --region $(AWS_REGION_0) \
	  --vpc-peering-connection-ids $$PEERING_ID \
	  --query 'VpcPeeringConnections[0].Status.Code' --output text); \
	if [ "$$STATUS" = "active" ]; then \
	  echo "  ⚠️  Already active. Skipping."; \
	else \
	  echo "  Accepting in $(AWS_REGION_1)..."; \
	  aws ec2 accept-vpc-peering-connection --region $(AWS_REGION_1) \
	    --vpc-peering-connection-id $$PEERING_ID > /dev/null; \
	  echo "  ⏳ Waiting for active status..."; \
	  for i in $$(seq 1 30); do \
	    S=$$(aws ec2 describe-vpc-peering-connections --region $(AWS_REGION_0) \
	      --vpc-peering-connection-ids $$PEERING_ID \
	      --query 'VpcPeeringConnections[0].Status.Code' --output text); \
	    if [ "$$S" = "active" ]; then echo "  ✅ Peering active"; break; fi; \
	    sleep 2; \
	  done; \
	fi

.PHONY: configure-vpc-routes
configure-vpc-routes:
	@echo "=== Configuring route tables ==="
	@VPC_ID_0=$$(aws eks describe-cluster --region $(AWS_REGION_0) --name $(CLUSTER_0) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_CIDR_0=$$(aws ec2 describe-vpcs --region $(AWS_REGION_0) \
	  --vpc-ids $$VPC_ID_0 --query 'Vpcs[0].CidrBlock' --output text); \
	VPC_ID_1=$$(aws eks describe-cluster --region $(AWS_REGION_1) --name $(CLUSTER_1) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_CIDR_1=$$(aws ec2 describe-vpcs --region $(AWS_REGION_1) \
	  --vpc-ids $$VPC_ID_1 --query 'Vpcs[0].CidrBlock' --output text); \
	PEERING_ID=$$(aws ec2 describe-vpc-peering-connections --region $(AWS_REGION_0) \
	  --filters "Name=requester-vpc-info.vpc-id,Values=$$VPC_ID_0" \
	            "Name=accepter-vpc-info.vpc-id,Values=$$VPC_ID_1" \
	            "Name=status-code,Values=active" \
	  --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' --output text); \
	echo "  Peering: $$PEERING_ID"; \
	echo ""; \
	echo "  --- Region 0: route $$VPC_CIDR_1 → $$PEERING_ID ---"; \
	for RT in $$(aws ec2 describe-route-tables --region $(AWS_REGION_0) \
	    --filters "Name=vpc-id,Values=$$VPC_ID_0" \
	    --query 'RouteTables[*].RouteTableId' --output text); do \
	  aws ec2 create-route --region $(AWS_REGION_0) \
	    --route-table-id $$RT \
	    --destination-cidr-block $$VPC_CIDR_1 \
	    --vpc-peering-connection-id $$PEERING_ID > /dev/null 2>&1 && \
	  echo "    $$RT: ✅ route added" || echo "    $$RT: ⚠️  route exists"; \
	done; \
	echo ""; \
	echo "  --- Region 1: route $$VPC_CIDR_0 → $$PEERING_ID ---"; \
	for RT in $$(aws ec2 describe-route-tables --region $(AWS_REGION_1) \
	    --filters "Name=vpc-id,Values=$$VPC_ID_1" \
	    --query 'RouteTables[*].RouteTableId' --output text); do \
	  aws ec2 create-route --region $(AWS_REGION_1) \
	    --route-table-id $$RT \
	    --destination-cidr-block $$VPC_CIDR_0 \
	    --vpc-peering-connection-id $$PEERING_ID > /dev/null 2>&1 && \
	  echo "    $$RT: ✅ route added" || echo "    $$RT: ⚠️  route exists"; \
	done

.PHONY: configure-vpc-security-groups
configure-vpc-security-groups:
	@echo "=== Configuring security groups ==="
	@VPC_ID_0=$$(aws eks describe-cluster --region $(AWS_REGION_0) --name $(CLUSTER_0) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_CIDR_0=$$(aws ec2 describe-vpcs --region $(AWS_REGION_0) \
	  --vpc-ids $$VPC_ID_0 --query 'Vpcs[0].CidrBlock' --output text); \
	VPC_ID_1=$$(aws eks describe-cluster --region $(AWS_REGION_1) --name $(CLUSTER_1) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_CIDR_1=$$(aws ec2 describe-vpcs --region $(AWS_REGION_1) \
	  --vpc-ids $$VPC_ID_1 --query 'Vpcs[0].CidrBlock' --output text); \
	echo "  --- Region 0: allow inbound from $$VPC_CIDR_1 ---"; \
	for SG in $$(aws ec2 describe-security-groups --region $(AWS_REGION_0) \
	    --filters "Name=vpc-id,Values=$$VPC_ID_0" \
	    --query "SecurityGroups[?contains(GroupName,'ClusterSharedNode') || contains(GroupName,'eks-cluster-sg')].GroupId" --output text); do \
	  echo "    SG $$SG:"; \
	  for PORT in 53 26500-26502 5432 8080; do \
	    aws ec2 authorize-security-group-ingress --region $(AWS_REGION_0) \
	      --group-id $$SG --protocol tcp --port $$PORT --cidr $$VPC_CIDR_1 2>/dev/null && \
	      echo "      ✅ TCP $$PORT" || echo "      ⚠️  TCP $$PORT (exists)"; \
	  done; \
	  aws ec2 authorize-security-group-ingress --region $(AWS_REGION_0) \
	    --group-id $$SG --protocol udp --port 53 --cidr $$VPC_CIDR_1 2>/dev/null && \
	    echo "      ✅ UDP 53" || echo "      ⚠️  UDP 53 (exists)"; \
	done; \
	echo ""; \
	echo "  --- Region 1: allow inbound from $$VPC_CIDR_0 ---"; \
	for SG in $$(aws ec2 describe-security-groups --region $(AWS_REGION_1) \
	    --filters "Name=vpc-id,Values=$$VPC_ID_1" \
	    --query "SecurityGroups[?contains(GroupName,'ClusterSharedNode') || contains(GroupName,'eks-cluster-sg')].GroupId" --output text); do \
	  echo "    SG $$SG:"; \
	  for PORT in 53 26500-26502 5432 8080; do \
	    aws ec2 authorize-security-group-ingress --region $(AWS_REGION_1) \
	      --group-id $$SG --protocol tcp --port $$PORT --cidr $$VPC_CIDR_0 2>/dev/null && \
	      echo "      ✅ TCP $$PORT" || echo "      ⚠️  TCP $$PORT (exists)"; \
	  done; \
	  aws ec2 authorize-security-group-ingress --region $(AWS_REGION_1) \
	    --group-id $$SG --protocol udp --port 53 --cidr $$VPC_CIDR_0 2>/dev/null && \
	    echo "      ✅ UDP 53" || echo "      ⚠️  UDP 53 (exists)"; \
	done

.PHONY: vpc-peering-status
vpc-peering-status:
	@VPC_ID_0=$$(aws eks describe-cluster --region $(AWS_REGION_0) --name $(CLUSTER_0) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_ID_1=$$(aws eks describe-cluster --region $(AWS_REGION_1) --name $(CLUSTER_1) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	aws ec2 describe-vpc-peering-connections --region $(AWS_REGION_0) \
	  --filters "Name=requester-vpc-info.vpc-id,Values=$$VPC_ID_0" \
	            "Name=accepter-vpc-info.vpc-id,Values=$$VPC_ID_1" \
	  --query 'VpcPeeringConnections[*].{ID:VpcPeeringConnectionId,Status:Status.Code}' --output table

.PHONY: clean-vpc-peering
clean-vpc-peering:
	@echo "🗑️  Deleting VPC peering..."
	-@VPC_ID_0=$$(aws eks describe-cluster --region $(AWS_REGION_0) --name $(CLUSTER_0) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null); \
	VPC_ID_1=$$(aws eks describe-cluster --region $(AWS_REGION_1) --name $(CLUSTER_1) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null); \
	if [ -n "$$VPC_ID_0" ] && [ -n "$$VPC_ID_1" ]; then \
	  PEERING_ID=$$(aws ec2 describe-vpc-peering-connections --region $(AWS_REGION_0) \
	    --filters "Name=requester-vpc-info.vpc-id,Values=$$VPC_ID_0" \
	              "Name=accepter-vpc-info.vpc-id,Values=$$VPC_ID_1" \
	              "Name=status-code,Values=active,pending-acceptance" \
	    --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' --output text); \
	  if [ "$$PEERING_ID" != "None" ] && [ -n "$$PEERING_ID" ]; then \
	    aws ec2 delete-vpc-peering-connection --region $(AWS_REGION_0) \
	      --vpc-peering-connection-id $$PEERING_ID; \
	    echo "  ✅ Deleted peering $$PEERING_ID"; \
	  else \
	    echo "  No active peering found."; \
	  fi; \
	fi

# ── Kubeconfig Context Management ──────────────────────────────────────────

.PHONY: add-contexts
add-contexts: add-context-region0 add-context-region1
	@echo "✅ Both kubectl contexts configured"

.PHONY: add-context-region0
add-context-region0:
	@echo "🔧 Adding kubectl context for $(CLUSTER_0) in $(AWS_REGION_0)..."
	aws eks --region $(AWS_REGION_0) update-kubeconfig --name $(CLUSTER_0) --alias $(CLUSTER_0)
	@echo "  ✅ Context $(CLUSTER_0) added"

.PHONY: add-context-region1
add-context-region1:
	@echo "🔧 Adding kubectl context for $(CLUSTER_1) in $(AWS_REGION_1)..."
	aws eks --region $(AWS_REGION_1) update-kubeconfig --name $(CLUSTER_1) --alias $(CLUSTER_1)
	@echo "  ✅ Context $(CLUSTER_1) added"

.PHONY: verify-contexts
verify-contexts:
	@echo "🔍 Verifying kubectl contexts..."
	@kubectl config get-contexts $(CLUSTER_0) > /dev/null 2>&1 && \
		echo "  ✅ $(CLUSTER_0): OK" || echo "  ❌ $(CLUSTER_0): NOT FOUND. Run: make add-contexts"
	@kubectl config get-contexts $(CLUSTER_1) > /dev/null 2>&1 && \
		echo "  ✅ $(CLUSTER_1): OK" || echo "  ❌ $(CLUSTER_1): NOT FOUND. Run: make add-contexts"

# ── DNS Chaining ───────────────────────────────────────────────────────────

.PHONY: configure-dns
configure-dns: verify-contexts deploy-dns-lb wait-for-dns-lb apply-coredns-config

.PHONY: deploy-dns-lb
deploy-dns-lb:
	@echo "🌐 Deploying internal DNS load balancers..."
	kubectl --context $(CLUSTER_0) apply -f $(root)/recipes/aws/include/internal-dns-lb.yml
	kubectl --context $(CLUSTER_1) apply -f $(root)/recipes/aws/include/internal-dns-lb.yml

.PHONY: wait-for-dns-lb
wait-for-dns-lb:
	@echo "⏳ Waiting for DNS LB in region 0..."
	sleep 60
	@for i in $$(seq 1 60); do \
	  ADDR=$$(kubectl --context $(CLUSTER_0) get svc kube-dns-lb -n kube-system \
	    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	  if [ -n "$$ADDR" ]; then echo "  ✅ Region 0 DNS LB: $$ADDR"; break; fi; \
	  if [ $$i -eq 60 ]; then echo "  ❌ Timeout"; exit 1; fi; \
	  echo "  Waiting... ($$i/60)"; sleep 5; \
	done
	@echo "⏳ Waiting for DNS LB in region 1..."
	@for i in $$(seq 1 60); do \
	  ADDR=$$(kubectl --context $(CLUSTER_1) get svc kube-dns-lb -n kube-system \
	    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	  if [ -n "$$ADDR" ]; then echo "  ✅ Region 1 DNS LB: $$ADDR"; break; fi; \
	  if [ $$i -eq 60 ]; then echo "  ❌ Timeout"; exit 1; fi; \
	  echo "  Waiting... ($$i/60)"; sleep 5; \
	done

.PHONY: apply-coredns-config
apply-coredns-config:
	@echo "🔗 Applying CoreDNS cross-region forwarding..."
	@DNS_LB_0_HOST=$$(kubectl --context $(CLUSTER_0) get svc kube-dns-lb -n kube-system \
	  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	DNS_LB_0_IP=$$(kubectl --context $(CLUSTER_0) get svc kube-dns-lb -n kube-system \
	  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	DNS_LB_1_HOST=$$(kubectl --context $(CLUSTER_1) get svc kube-dns-lb -n kube-system \
	  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	DNS_LB_1_IP=$$(kubectl --context $(CLUSTER_1) get svc kube-dns-lb -n kube-system \
	  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	if [ -n "$$DNS_LB_0_IP" ]; then DNS_LB_0=$$DNS_LB_0_IP; \
	elif [ -n "$$DNS_LB_0_HOST" ]; then DNS_LB_0=$$(nslookup "$$DNS_LB_0_HOST" 2>/dev/null | awk '/^Address:/ && !/#/ {print $$2; exit}'); \
	fi; \
	if [ -n "$$DNS_LB_1_IP" ]; then DNS_LB_1=$$DNS_LB_1_IP; \
	elif [ -n "$$DNS_LB_1_HOST" ]; then DNS_LB_1=$$(nslookup "$$DNS_LB_1_HOST" 2>/dev/null | awk '/^Address:/ && !/#/ {print $$2; exit}'); \
	fi; \
	echo "Region 0 DNS LB IP: $$DNS_LB_0"; \
	echo "Region 1 DNS LB IP: $$DNS_LB_1"; \
	if [ -z "$$DNS_LB_0" ] || [ -z "$$DNS_LB_1" ]; then \
	  echo "❌ ERROR: Could not resolve DNS LB IPs."; \
	  echo "   Ensure NLBs are provisioned (make wait-for-dns-lb) and 'host' command works."; \
	  exit 1; \
	fi; \
	echo ""; \
	echo "=== Patching CoreDNS in Cluster 0 ($(CLUSTER_0)) ==="; \
	echo "  Forwarding $(CAMUNDA_NAMESPACE_1).svc.cluster.local → $$DNS_LB_1"; \
	kubectl --context $(CLUSTER_0) -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' \
	  | sed '/^$(CAMUNDA_NAMESPACE_1)\.svc\.cluster\.local/,/^}/d' > /tmp/corefile0-base.txt; \
	printf '\n$(CAMUNDA_NAMESPACE_1).svc.cluster.local:53 {\n    errors\n    cache 30\n    forward . %s {\n        force_tcp\n    }\n}\n' "$$DNS_LB_1" >> /tmp/corefile0-base.txt; \
	kubectl --context $(CLUSTER_0) -n kube-system create configmap coredns \
	  --from-file=Corefile=/tmp/corefile0-base.txt --dry-run=client -o yaml | \
	  kubectl --context $(CLUSTER_0) -n kube-system apply -f -; \
	echo "  ✅ CoreDNS patched in cluster 0"; \
	echo ""; \
	echo "=== Patching CoreDNS in Cluster 1 ($(CLUSTER_1)) ==="; \
	echo "  Forwarding $(CAMUNDA_NAMESPACE_0).svc.cluster.local → $$DNS_LB_0"; \
	kubectl --context $(CLUSTER_1) -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' \
	  | sed '/^$(CAMUNDA_NAMESPACE_0)\.svc\.cluster\.local/,/^}/d' > /tmp/corefile1-base.txt; \
	printf '\n$(CAMUNDA_NAMESPACE_0).svc.cluster.local:53 {\n    errors\n    cache 30\n    forward . %s {\n        force_tcp\n    }\n}\n' "$$DNS_LB_0" >> /tmp/corefile1-base.txt; \
	kubectl --context $(CLUSTER_1) -n kube-system create configmap coredns \
	  --from-file=Corefile=/tmp/corefile1-base.txt --dry-run=client -o yaml | \
	  kubectl --context $(CLUSTER_1) -n kube-system apply -f -; \
	echo "  ✅ CoreDNS patched in cluster 1"; \
	echo ""; \
	echo "⏳ Restarting CoreDNS..."; \
	kubectl --context $(CLUSTER_0) -n kube-system rollout restart deployment/coredns; \
	kubectl --context $(CLUSTER_1) -n kube-system rollout restart deployment/coredns; \
	sleep 10; \
	echo "✅ CoreDNS configuration applied to both clusters"

.PHONY: test-dns
test-dns:
	@echo "🧪 Testing DNS chaining between clusters..."
	-kubectl --context $(CLUSTER_0) create namespace $(CAMUNDA_NAMESPACE_0) 2>/dev/null
	-kubectl --context $(CLUSTER_1) create namespace $(CAMUNDA_NAMESPACE_1) 2>/dev/null
	kubectl --context $(CLUSTER_0) -n $(CAMUNDA_NAMESPACE_0) run dns-test --image=busybox:1.36 --restart=Never -- sleep 3600 2>/dev/null || true
	kubectl --context $(CLUSTER_0) -n $(CAMUNDA_NAMESPACE_0) expose pod dns-test --port=80 --name=dns-test 2>/dev/null || true
	kubectl --context $(CLUSTER_1) -n $(CAMUNDA_NAMESPACE_1) run dns-test --image=busybox:1.36 --restart=Never -- sleep 3600 2>/dev/null || true
	kubectl --context $(CLUSTER_1) -n $(CAMUNDA_NAMESPACE_1) expose pod dns-test --port=80 --name=dns-test 2>/dev/null || true
	@echo "⏳ Waiting for pods..."
	kubectl --context $(CLUSTER_0) -n $(CAMUNDA_NAMESPACE_0) wait --for=condition=Ready pod/dns-test --timeout=60s
	kubectl --context $(CLUSTER_1) -n $(CAMUNDA_NAMESPACE_1) wait --for=condition=Ready pod/dns-test --timeout=60s
	@echo ""
	@echo "Region 0 → Region 1:"
	@kubectl --context $(CLUSTER_0) -n $(CAMUNDA_NAMESPACE_0) exec dns-test -- \
	  nslookup dns-test.$(CAMUNDA_NAMESPACE_1).svc.cluster.local && echo "  ✅ DNS OK" || echo "  ❌ DNS FAILED"
	@echo ""
	@echo "Region 1 → Region 0:"
	@kubectl --context $(CLUSTER_1) -n $(CAMUNDA_NAMESPACE_1) exec dns-test -- \
	  nslookup dns-test.$(CAMUNDA_NAMESPACE_0).svc.cluster.local && echo "  ✅ DNS OK" || echo "  ❌ DNS FAILED"

.PHONY: clean-dns-test
clean-dns-test:
	-kubectl --context $(CLUSTER_0) -n $(CAMUNDA_NAMESPACE_0) delete svc dns-test --grace-period=0
	-kubectl --context $(CLUSTER_0) -n $(CAMUNDA_NAMESPACE_0) delete pod dns-test --grace-period=0
	-kubectl --context $(CLUSTER_1) -n $(CAMUNDA_NAMESPACE_1) delete svc dns-test --grace-period=0
	-kubectl --context $(CLUSTER_1) -n $(CAMUNDA_NAMESPACE_1) delete pod dns-test --grace-period=0

.PHONY: preview # show what the full dual-region setup would provision — no side effects
preview:
	@echo ""
	@echo "══════════════════════════════════════════════════════════════════"
	@echo "  Dual-Region EKS Preview"
	@echo "  Steps: make -C region0 all / make -C region1 all → configure-vpc-peering → configure-dns"
	@echo "══════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  ── Region 0 EKS Cluster (make -C region0 all) ──────────────────"
	@echo "     Name            : $(CLUSTER_0)"
	@echo "     Region          : $(AWS_REGION_0)"
	@echo "     Availability Zones: $(AWS_ZONES_0)"
	@echo "     Kubernetes      : $(CLUSTER_VERSION)"
	@echo "     VPC CIDR        : $(VPC_CIDR_0)"
	@echo "     kubectl context : $(CLUSTER_0)"
	@echo ""
	@echo "  ── Region 1 EKS Cluster (make -C region1 all) ──────────────────"
	@echo "     Name            : $(CLUSTER_1)"
	@echo "     Region          : $(AWS_REGION_1)"
	@echo "     Availability Zones: $(AWS_ZONES_1)"
	@echo "     Kubernetes      : $(CLUSTER_VERSION)"
	@echo "     VPC CIDR        : $(VPC_CIDR_1)"
	@echo "     kubectl context : $(CLUSTER_1)"
	@echo ""
	@echo "  ── Shared Node Group Config ─────────────────────────────────────"
	@echo "     Instance type   : $(AWS_MACHINE_TYPE)"
	@echo "     Desired / Min / Max nodes: $(DESIRED_SIZE) / $(MIN_SIZE) / $(MAX_SIZE)"
	@echo "     Root volume     : $(VOLUME_SIZE) GB"
	@echo ""
	@echo "  ── Built into cluster.yaml (both clusters) ──────────────────────"
	@echo "     OIDC provider   : enabled via eksctl (iam.withOIDC: true)"
	@echo "     EKS Addon       : aws-ebs-csi-driver (wellKnownPolicies.ebsCSIController)"
	@echo "     StorageClass    : ssd (ebs.csi.aws.com) → set as default; gp2 → unset"
	@echo ""
	@echo "  ── VPC Peering (make configure-vpc-peering) ─────────────────────"
	@echo "     Peering         : $(VPC_CIDR_0) ($(AWS_REGION_0)) ↔ $(VPC_CIDR_1) ($(AWS_REGION_1))"
	@echo "     Route tables    : cross-region routes added in both VPCs"
	@echo "     Security groups : inbound rules opened on ClusterSharedNode/eks-cluster-sg SGs"
	@echo "       TCP ports     : 53, 26500-26502 (Zeebe), 5432 (Postgres), 8080"
	@echo "       UDP ports     : 53 (DNS)"
	@echo ""
	@echo "  ── DNS Chaining (make configure-dns) ────────────────────────────"
	@echo "     kube-dns-lb     : internal NLB (TCP/53) deployed in kube-system on each cluster"
	@echo "     CoreDNS region 0: forwards $(CAMUNDA_NAMESPACE_1).svc.cluster.local → region 1 NLB"
	@echo "     CoreDNS region 1: forwards $(CAMUNDA_NAMESPACE_0).svc.cluster.local → region 0 NLB"
	@echo ""
	@echo "  ── Camunda Namespaces ───────────────────────────────────────────"
	@echo "     Region 0        : $(CAMUNDA_NAMESPACE_0)"
	@echo "     Region 1        : $(CAMUNDA_NAMESPACE_1)"
	@echo ""
	@echo "  ── Camunda 8 Platform (run per-region after cluster setup) ──────"
	@echo "     Helm chart      : $(CAMUNDA_CHART) v$(CAMUNDA_HELM_CHART_VERSION)"
	@echo "     Camunda version : $(CAMUNDA_VERSION)"
	@echo "     Zeebe cluster   : $(CAMUNDA_CLUSTER_SIZE) brokers total, $(BROKERS_PER_REGION) per region"
	@echo "     Replication     : $(CAMUNDA_REPLICATION_FACTOR)x  |  Partitions: $(CAMUNDA_PARTITION_COUNT)"
	@echo ""
	@echo "══════════════════════════════════════════════════════════════════"
	@echo ""