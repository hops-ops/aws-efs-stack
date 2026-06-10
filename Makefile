SHELL := /bin/bash

PACKAGE ?= aws-efs-stack
XRD_DIR := apis/efsstoragestacks
COMPOSITION := $(XRD_DIR)/composition.yaml
DEFINITION := $(XRD_DIR)/definition.yaml
CONFIGURATION := $(XRD_DIR)/configuration.yaml
EXAMPLE_DEFAULT := examples/efsstoragestacks/standard.yaml
RENDER_TESTS := $(wildcard tests/test-*)
E2E_TESTS := $(wildcard tests/e2etest-*)

# Examples list - mirrors GitHub Actions workflow
# Format: example_path::observed_resources_path (observed_resources_path is optional)
EXAMPLES := \
    examples/efsstoragestacks/minimal.yaml:: \
    examples/efsstoragestacks/standard.yaml:: \
    examples/efsstoragestacks/standard.yaml::examples/test/mocks/observed-resources/standard/steps/1/ \
    examples/efsstoragestacks/standard.yaml::examples/test/mocks/observed-resources/standard/steps/2/ \
    examples/efsstoragestacks/import.yaml:: \
    examples/efsstoragestacks/addon-existing.yaml:: \
    examples/efsstoragestacks/storageclass-disabled.yaml::

clean:
	rm -rf _output
	rm -rf .up
	rm -f $(CONFIGURATION)

build:
	up project build

generate-configuration:
	@set -euo pipefail; \
	hops validate generate-configuration --path . --api-path "$(XRD_DIR)"

render\:all:
	@tmpdir=$$(mktemp -d); \
	pids=""; \
	for entry in $(EXAMPLES); do \
		example=$${entry%%::*}; \
		observed=$${entry#*::}; \
		outfile="$$tmpdir/$$(echo $$entry | tr '/:' '__')"; \
		( \
			if [ -n "$$observed" ]; then \
				echo "=== Rendering $$example with observed-resources $$observed ==="; \
				up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example --observed-resources=$$observed; \
			else \
				echo "=== Rendering $$example ==="; \
				up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example; \
			fi; \
			echo "" \
		) > "$$outfile" 2>&1 & \
		pids="$$pids $$!:$$outfile"; \
	done; \
	failed=0; \
	for pair in $$pids; do \
		pid=$${pair%%:*}; \
		outfile=$${pair#*:}; \
		if ! wait $$pid; then failed=1; fi; \
		cat "$$outfile"; \
	done; \
	rm -rf "$$tmpdir"; \
	exit $$failed

validate\:all: generate-configuration
	@tmpdir=$$(mktemp -d); \
	pids=""; \
	for entry in $(EXAMPLES); do \
		example=$${entry%%::*}; \
		observed=$${entry#*::}; \
		outfile="$$tmpdir/$$(echo $$entry | tr '/:' '__')"; \
		( \
			set -euo pipefail; \
			if [ -n "$$observed" ]; then \
				echo "=== Validating $$example with observed-resources $$observed ==="; \
				up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example \
					--observed-resources=$$observed --include-full-xr --quiet | \
					crossplane beta validate $(CONFIGURATION),$(XRD_DIR) --error-on-missing-schemas -; \
			else \
				echo "=== Validating $$example ==="; \
				up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example \
					--include-full-xr --quiet | \
					crossplane beta validate $(CONFIGURATION),$(XRD_DIR) --error-on-missing-schemas -; \
			fi; \
			echo "" \
		) > "$$outfile" 2>&1 & \
		pids="$$pids $$!:$$outfile"; \
	done; \
	failed=0; \
	for pair in $$pids; do \
		pid=$${pair%%:*}; \
		outfile=$${pair#*:}; \
		if ! wait $$pid; then failed=1; fi; \
		cat "$$outfile"; \
	done; \
	rm -rf "$$tmpdir"; \
	exit $$failed

.PHONY: render validate generate-configuration
render:
	$(MAKE) render:all
validate: generate-configuration
	$(MAKE) validate:all

render\:%:
	@example="examples/efsstoragestacks/$$*.yaml"; \
	if [ -f "$$example" ]; then \
		echo "=== Rendering $$example ==="; \
		up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example; \
	else \
		echo "Example $$example not found"; \
		exit 1; \
	fi

validate\:%: generate-configuration
	@example="examples/efsstoragestacks/$$*.yaml"; \
	if [ -f "$$example" ]; then \
		set -euo pipefail; \
		echo "=== Validating $$example ==="; \
		up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example \
			--include-full-xr --quiet | \
			crossplane beta validate $(CONFIGURATION),$(XRD_DIR) --error-on-missing-schemas -; \
	else \
		echo "Example $$example not found"; \
		exit 1; \
	fi

test:
	up test run $(RENDER_TESTS)

e2e:
	up test run $(E2E_TESTS) --e2e

publish:
	@if [ -z "$(tag)" ]; then echo "Error: tag is not set. Usage: make publish tag=<version>"; exit 1; fi
	up project build --push --tag $(tag)

generate-definitions:
	up xrd generate $(EXAMPLE_DEFAULT)

generate-function:
	up function generate --language=go-templating render $(COMPOSITION)
