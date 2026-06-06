ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../..
else
    root ?= $(shell pwd)/../..
endif

-include $(root)/config.mk
include ./config.mk

.PHONY: all
all: benchmark

.PHONY: clean
clean: clean-benchmark

include $(root)/makefiles/benchmark.mk
