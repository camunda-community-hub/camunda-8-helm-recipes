# Creates the region 1 GKE cluster of the dual-region setup.

ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../../../..
else
    root ?= $(shell pwd)/../../../..
endif

-include $(root)/config.mk
include ../config.mk

# Map the region 1 variables to the ones google-gke.mk expects
DEPLOYMENT_NAME := $(CLUSTER_1)
GCP_REGION := $(GCP_REGION_1)
GCP_CLUSTER_IPV4_CIDR := $(GCP_CLUSTER_IPV4_CIDR_1)
GCP_SERVICES_IPV4_CIDR := $(GCP_SERVICES_IPV4_CIDR_1)
GCP_MACHINE_TYPE := $(DUAL_REGION_MACHINE_TYPE)
GCP_USE_SPOT := $(DUAL_REGION_USE_SPOT)
GCP_NUM_NODES := $(DUAL_REGION_NUM_NODES)
MIN_SIZE := $(DUAL_REGION_MIN_SIZE)
MAX_SIZE := $(DUAL_REGION_MAX_SIZE)

.PHONY: all
all: kube default-ssd-storageclass

.PHONY: clean
clean: clean-kube

include $(root)/makefiles/google-common.mk
include $(root)/makefiles/google-gke.mk
