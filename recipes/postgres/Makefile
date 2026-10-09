# Determine the root directory
ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../..
else
    root ?= $(shell pwd)/../..
endif

# Create a config.mk file in the root directory of this project to override defaults included below
-include $(root)/config.mk

# These are the default values used by this recipe
include ./config.mk


.PHONY: all
all: postgres

.PHONY: clean
clean: clean-postgres

include $(root)/makefiles/postgres.mk
