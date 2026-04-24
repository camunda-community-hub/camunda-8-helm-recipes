# Dual-Region EKS - Shared Configuration
# Create a config.mk in the project root to override these defaults.

DEPLOYMENT_NAME ?= my-camunda

# ── EKS cluster settings (shared across both regions) ───────────────────────
AWS_MACHINE_TYPE ?= m5.2xlarge
CLUSTER_VERSION  ?= 1.35
VOLUME_SIZE      ?= 100
DESIRED_SIZE     ?= 4
MIN_SIZE         ?= 1
MAX_SIZE         ?= 6
