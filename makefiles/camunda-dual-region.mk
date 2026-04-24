# ════════════════════════════════════════════════════════════════════════════
# CAMUNDA DUAL-REGION OPERATIONAL TARGETS
# ════════════════════════════════════════════════════════════════════════════
#
# Cross-region operational utilities for dual-region Camunda deployments.
# Cluster creation and Camunda deployment are handled per-region via the
# region0/ and region1/ Makefiles.
#
# Prerequisites:
#   - Both clusters running with Camunda deployed
#   - kubectl contexts set for both clusters (make add-contexts)
#   - CLUSTER_0, CLUSTER_1, CAMUNDA_NAMESPACE_0, CAMUNDA_NAMESPACE_1 defined
#
# Usage:
#   make topology              # Check Zeebe cluster topology
#   make pods-region0/1        # View pods in each region
#   make simulate-partition    # Simulate cross-region network failure
#   make restore-partition     # Restore cross-region connectivity

# ── Context switching ─────────────────────────────────────────────────────

.PHONY: use-region0
use-region0:
	kubectl config use-context $(CLUSTER_0)

.PHONY: use-region1
use-region1:
	kubectl config use-context $(CLUSTER_1)

# ── Verification ──────────────────────────────────────────────────────────

.PHONY: pods-region0
pods-region0:
	kubectl --context $(CLUSTER_0) get pods -n $(CAMUNDA_NAMESPACE_0)

.PHONY: pods-region1
pods-region1:
	kubectl --context $(CLUSTER_1) get pods -n $(CAMUNDA_NAMESPACE_1)

.PHONY: topology
topology:
	@echo "Checking Zeebe topology via region 0..."
	kubectl --context $(CLUSTER_0) -n $(CAMUNDA_NAMESPACE_0) \
	  port-forward svc/$(CAMUNDA_RELEASE_NAME)-zeebe-gateway 8888:8080 &
	@sleep 3
	@curl -sf -u demo:demo http://localhost:8888/v2/topology | jq . || \
	  echo "⚠️  Could not reach Zeebe gateway."
	@kill %1 2>/dev/null || true

# ── Failure Simulation ────────────────────────────────────────────────────
# Simulates a network partition by removing VPC peering routes.
# Brokers stay running but cannot communicate across regions.
# Zeebe loses quorum → processing stops.
# Restore with: make restore-partition

.PHONY: simulate-partition
simulate-partition:
	@echo "🔥 Simulating network partition between regions..."
	@echo ""
	@VPC_ID_0=$$(aws eks describe-cluster --region $(AWS_REGION_0) --name $(CLUSTER_0) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_ID_1=$$(aws eks describe-cluster --region $(AWS_REGION_1) --name $(CLUSTER_1) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_CIDR_0=$$(aws ec2 describe-vpcs --region $(AWS_REGION_0) \
	  --vpc-ids $$VPC_ID_0 --query 'Vpcs[0].CidrBlock' --output text); \
	VPC_CIDR_1=$$(aws ec2 describe-vpcs --region $(AWS_REGION_1) \
	  --vpc-ids $$VPC_ID_1 --query 'Vpcs[0].CidrBlock' --output text); \
	PEERING_ID=$$(aws ec2 describe-vpc-peering-connections --region $(AWS_REGION_0) \
	  --filters "Name=requester-vpc-info.vpc-id,Values=$$VPC_ID_0" \
	            "Name=accepter-vpc-info.vpc-id,Values=$$VPC_ID_1" \
	            "Name=status-code,Values=active" \
	  --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' --output text); \
	if [ "$$PEERING_ID" = "None" ] || [ -z "$$PEERING_ID" ]; then \
	  echo "❌ No active peering found."; exit 1; \
	fi; \
	echo "  Peering: $$PEERING_ID"; \
	echo ""; \
	echo "  --- Removing routes in Region 0 ($$VPC_CIDR_1 via $$PEERING_ID) ---"; \
	for RT in $$(aws ec2 describe-route-tables --region $(AWS_REGION_0) \
	    --filters "Name=vpc-id,Values=$$VPC_ID_0" \
	    --query 'RouteTables[*].RouteTableId' --output text); do \
	  aws ec2 delete-route --region $(AWS_REGION_0) \
	    --route-table-id $$RT \
	    --destination-cidr-block $$VPC_CIDR_1 2>/dev/null && \
	    echo "    $$RT: ✅ route removed" || echo "    $$RT: ⚠️  no route found"; \
	done; \
	echo ""; \
	echo "  --- Removing routes in Region 1 ($$VPC_CIDR_0 via $$PEERING_ID) ---"; \
	for RT in $$(aws ec2 describe-route-tables --region $(AWS_REGION_1) \
	    --filters "Name=vpc-id,Values=$$VPC_ID_1" \
	    --query 'RouteTables[*].RouteTableId' --output text); do \
	  aws ec2 delete-route --region $(AWS_REGION_1) \
	    --route-table-id $$RT \
	    --destination-cidr-block $$VPC_CIDR_0 2>/dev/null && \
	    echo "    $$RT: ✅ route removed" || echo "    $$RT: ⚠️  no route found"; \
	done; \
	echo ""; \
	echo "🔥 Network partition active. Regions cannot communicate."; \
	echo "   Zeebe will lose quorum and stop processing."; \
	echo "   To restore: make restore-partition"

.PHONY: restore-partition
restore-partition:
	@echo "🔧 Restoring network connectivity between regions..."
	@echo ""
	@VPC_ID_0=$$(aws eks describe-cluster --region $(AWS_REGION_0) --name $(CLUSTER_0) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_ID_1=$$(aws eks describe-cluster --region $(AWS_REGION_1) --name $(CLUSTER_1) \
	  --query 'cluster.resourcesVpcConfig.vpcId' --output text); \
	VPC_CIDR_0=$$(aws ec2 describe-vpcs --region $(AWS_REGION_0) \
	  --vpc-ids $$VPC_ID_0 --query 'Vpcs[0].CidrBlock' --output text); \
	VPC_CIDR_1=$$(aws ec2 describe-vpcs --region $(AWS_REGION_1) \
	  --vpc-ids $$VPC_ID_1 --query 'Vpcs[0].CidrBlock' --output text); \
	PEERING_ID=$$(aws ec2 describe-vpc-peering-connections --region $(AWS_REGION_0) \
	  --filters "Name=requester-vpc-info.vpc-id,Values=$$VPC_ID_0" \
	            "Name=accepter-vpc-info.vpc-id,Values=$$VPC_ID_1" \
	            "Name=status-code,Values=active" \
	  --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' --output text); \
	if [ "$$PEERING_ID" = "None" ] || [ -z "$$PEERING_ID" ]; then \
	  echo "❌ No active peering found. May need full reconfiguration: make configure-vpc-peering"; exit 1; \
	fi; \
	echo "  Peering: $$PEERING_ID"; \
	echo ""; \
	echo "  --- Restoring routes in Region 0 ($$VPC_CIDR_1 → $$PEERING_ID) ---"; \
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
	echo "  --- Restoring routes in Region 1 ($$VPC_CIDR_0 → $$PEERING_ID) ---"; \
	for RT in $$(aws ec2 describe-route-tables --region $(AWS_REGION_1) \
	    --filters "Name=vpc-id,Values=$$VPC_ID_1" \
	    --query 'RouteTables[*].RouteTableId' --output text); do \
	  aws ec2 create-route --region $(AWS_REGION_1) \
	    --route-table-id $$RT \
	    --destination-cidr-block $$VPC_CIDR_0 \
	    --vpc-peering-connection-id $$PEERING_ID > /dev/null 2>&1 && \
	    echo "    $$RT: ✅ route added" || echo "    $$RT: ⚠️  route exists"; \
	done; \
	echo ""; \
	echo "✅ Network connectivity restored."; \
	echo "   Zeebe should automatically recover quorum."; \
	echo "   Verify with: make topology"
