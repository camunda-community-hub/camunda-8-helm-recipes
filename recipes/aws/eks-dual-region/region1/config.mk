# Camunda 8.9 Dual-Region EKS Recipe - Default Configuration
# Create a config.mk file in the root directory of this project to override variables for your specific environment

# ── AWS Regions and Clusters ────────────────────────────────────────────────
# Region 1 (secondary)
AWS_REGION_1 ?= us-east-2
AWS_ZONES_1 ?= 'us-east-2a', 'us-east-2b'
ifndef CLUSTER_1
CLUSTER_1 := $(DEPLOYMENT_NAME)-region1
endif
CAMUNDA_NAMESPACE_1 ?= camunda-region1

# VPC CIDRs — MUST be non-overlapping for VPC peering
VPC_CIDR_1 ?= 10.196.0.0/16