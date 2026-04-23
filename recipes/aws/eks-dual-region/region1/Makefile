ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../../../..
else
    root ?= $(shell pwd)/../../../..
endif

-include $(root)/config.mk
include ../config.mk
include config.mk

# Map region-specific vars to the standard vars expected by aws-eks.mk
AWS_REGION    := $(AWS_REGION_1)
AWS_ZONES     := $(AWS_ZONES_1)
DEPLOYMENT_NAME := $(CLUSTER_1)
VPC_CIDR      := $(VPC_CIDR_1)

.PHONY: all
all: kube add-context-region1

.PHONY: clean
clean: clean-kube

# EBS CSI addon and OIDC are declared in cluster.tpl.yaml and handled by eksctl
# during cluster creation — skip the separate post-install targets
.PHONY: install-ebs-csi-controller-addon
install-ebs-csi-controller-addon:
	@echo "Skipping: EBS CSI addon is managed via cluster.yaml addons block"

.PHONY: oidc-provider
oidc-provider:
	@echo "Skipping: OIDC is managed via cluster.yaml (iam.withOIDC: true)"

include $(root)/makefiles/aws-eks.mk
include $(root)/makefiles/aws-dual-region-networking.mk
