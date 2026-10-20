ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../..
else
    root ?= $(shell pwd)/../..
endif

-include $(root)/config.mk
include ./config.mk

.PHONY: all
all: benchmark-query

.PHONY: clean
clean: clean-benchmark-query

include $(root)/makefiles/benchmark-query.mk
