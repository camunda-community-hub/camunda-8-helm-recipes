# These are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

# The Secret is created in the same namespace as Camunda
CAMUNDA_NAMESPACE ?= camunda

# Secrets are defined as SECRET_<NAME> variables, see README.md. Put the values in the root config.mk (gitignored),
# never in this committed file.
