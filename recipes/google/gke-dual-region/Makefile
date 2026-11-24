# Dual-region networking between the two GKE clusters created by region0/ and region1/.
# Run after both clusters exist.

ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../../..
else
    root ?= $(shell pwd)/../../..
endif

-include $(root)/config.mk
include ./config.mk

.PHONY: all
all: dual-region-networking

.PHONY: clean
clean: clean-dns-test clean-prometheus-lb clean-dns clean-firewall-dual-region

include $(root)/makefiles/google-dual-region-networking.mk
