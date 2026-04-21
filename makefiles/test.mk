.PHONY: test
test: camunda-values.yaml
	@echo "Testing $(CURDIR)..."
	@if diff -q ./camunda-values.yaml ./sample-camunda-values.yaml > /dev/null 2>&1; then \
	  echo "PASS: camunda-values.yaml matches sample-camunda-values.yaml"; \
	else \
	  echo "FAIL: camunda-values.yaml does not match sample-camunda-values.yaml"; \
	  diff ./camunda-values.yaml ./sample-camunda-values.yaml; \
	  $(MAKE) delete-camunda-values; \
	  exit 1; \
	fi
	@$(MAKE) delete-camunda-values
