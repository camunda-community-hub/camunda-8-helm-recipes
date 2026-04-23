# Camunda 8.9 Dual-Region EKS Recipe - Default Configuration
# Create a config.mk file in the root directory of this project to override variables for your specific environment

# ── AWS Regions and Clusters ────────────────────────────────────────────────
# Region 0 (primary)
AWS_REGION_0 ?= us-west-1
AWS_ZONES_0 ?= 'us-west-1a', 'us-west-1c'
ifndef CLUSTER_0
CLUSTER_0 := $(DEPLOYMENT_NAME)-region0
endif
CAMUNDA_NAMESPACE_0 ?= camunda-region0

# VPC CIDRs — MUST be non-overlapping for VPC peering
VPC_CIDR_0 ?= 10.195.0.0/16
