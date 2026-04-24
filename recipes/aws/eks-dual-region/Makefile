# Dual-Region EKS Networking Overlay
#
# Adds VPC peering and DNS chaining between two existing EKS clusters.
# Clusters must already exist before running targets here.
#
# Workflow:
#   1. make -C recipes/aws/eks-dual-region/region0   # create cluster in region 0
#   2. make -C recipes/aws/eks-dual-region/region1   # create cluster in region 1
#   3. make -C recipes/aws/eks-dual-region           # wire up networking
#
# Run 'make help' for available targets.

ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../../..
else
    root ?= $(shell pwd)/../../..
endif

-include $(root)/config.mk
include ./config.mk
include $(root)/recipes/aws/eks-dual-region/region0/config.mk
include $(root)/recipes/aws/eks-dual-region/region1/config.mk

.PHONY: all
all: add-contexts configure-vpc-peering configure-dns
	@echo ""
	@echo "✅ Dual-region networking ready."
	@echo "   Run 'make test-dns' to verify cross-region DNS resolution."

.PHONY: clean
clean: clean-vpc-peering
	@echo "✅ VPC peering removed. Clusters still running."
	@echo "   To delete clusters run: make -C region0 clean && make -C region1 clean"

.PHONY: help
help:
	@echo ""
	@echo "Dual-Region EKS Networking Overlay"
	@echo "═══════════════════════════════════"
	@echo ""
	@echo "  Clusters  : $(CLUSTER_0) ($(AWS_REGION_0))  $(CLUSTER_1) ($(AWS_REGION_1))"
	@echo "  CIDRs     : $(VPC_CIDR_0)  $(VPC_CIDR_1)"
	@echo ""
	@echo "  ── Workflow ────────────────────────────────────────────────"
	@echo "  1. make -C region0             Create cluster in $(AWS_REGION_0)"
	@echo "  2. make -C region1             Create cluster in $(AWS_REGION_1)"
	@echo "  3. make                        VPC peering + DNS chaining"
	@echo "  4. make test-dns               Verify cross-region DNS"
	@echo ""
	@echo "  ── VPC Peering ─────────────────────────────────────────────"
	@echo "  configure-vpc-peering          Full VPC peering setup"
	@echo "  vpc-peering-status             Show current peering status"
	@echo "  clean-vpc-peering              Delete VPC peering"
	@echo ""
	@echo "  ── DNS Chaining ────────────────────────────────────────────"
	@echo "  configure-dns                  Full DNS setup (LB + CoreDNS)"
	@echo "  test-dns                       Test cross-region DNS resolution"
	@echo "  clean-dns-test                 Remove DNS test resources"
	@echo ""
	@echo "  ── Contexts ────────────────────────────────────────────────"
	@echo "  add-contexts                   Add both clusters to kubeconfig"
	@echo "  verify-contexts                Check kubectl contexts are set"
	@echo ""

include $(root)/makefiles/aws-eks.mk
include $(root)/makefiles/aws-dual-region-networking.mk
