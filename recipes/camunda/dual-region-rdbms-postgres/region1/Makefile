ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../../../..
else
    root ?= $(shell pwd)/../../../..
endif

-include $(root)/config.mk
include $(root)/recipes/aws/eks-dual-region/config.mk
include $(root)/recipes/aws/eks-dual-region/region1/config.mk
include ../config.mk
include config.mk

AWS_REGION      := $(AWS_REGION_1)
AWS_ZONES       := $(AWS_ZONES_1)
DEPLOYMENT_NAME := $(CLUSTER_1)

.PHONY: all
all: camunda-values.yaml create-camunda-credentials camunda

.PHONY: clean
clean: clean-camunda

include $(root)/makefiles/camunda.mk
include $(root)/makefiles/aws-aurora.mk
