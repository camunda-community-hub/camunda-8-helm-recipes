# Determine the root directory
ifeq ($(OS),Windows_NT)
    root ?= $(CURDIR)/../..
else
    root ?= $(shell pwd)/../..
endif

# Create a config.mk file in the root directory of this project to override defaults included below
-include $(root)/config.mk

# Theses are the default values used by this recipe
include ./config.mk

.PHONY: all
all: create-custom-certs list-sans create-keystore
	
.PHONY: clean
clean: delete-custom-certs

.PHONY: setup-ingress-nginx
setup-ingress-nginx: ingress-nginx cert-manager letsencrypt-prod

include $(root)/makefiles/tls-self-signed-cert.mk
include $(root)/makefiles/tls-keystore.mk