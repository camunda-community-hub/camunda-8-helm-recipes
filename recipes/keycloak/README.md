# Provision Keycloak with the Keycloak operator

Camunda 8.10 (Helm chart 15) no longer bundles Keycloak. This recipe installs the
[Keycloak operator](https://www.keycloak.org/operator/installation) and a Keycloak instance using the
Camunda-maintained `camunda/keycloak` image, following the
[Camunda reference architecture](https://docs.camunda.io/docs/self-managed/deployment/helm/configure/operator-based-infrastructure/#keycloak-deployment).

Management Identity creates the realm, OIDC clients and first user in this Keycloak when Camunda starts.

## What you get
- The Keycloak operator and an instance named `keycloak` in `CAMUNDA_NAMESPACE` (default `camunda`)
- Service `keycloak-service:18080`, served under `/auth`
- Secret `keycloak-initial-admin` with the bootstrap admin (default `temp-admin`, password `DEFAULT_PASSWORD`), created by `make keycloak-admin-secret`
- In `domain` mode, issuer URLs are `https://<KEYCLOAK_HOST>/auth/realms/<realm>`
- With `KEYCLOAK_INGRESS=nginx` (the default), an Ingress routes `/auth` to Keycloak. Traefik recipes route `/auth`
  through their IngressRoute instead, so set `KEYCLOAK_INGRESS ?= none` for them.

## Prerequisites
- A Kubernetes cluster provisioned and accessible.
- The `pg-keycloak` database from the [postgres recipe](../postgres/README.md) (`make -C ../postgres`).
- For `domain` mode with nginx: an ingress controller and the TLS secret (`TLS_SECRET_NAME`) in the namespace.

## Install
```sh
make
```

Override settings in the root `config.mk`, for example:
```make
HOST_NAME ?= camunda.example.com
KEYCLOAK_INGRESS ?= none      # when Traefik routes /auth
KEYCLOAK_MODE ?= local        # no domain, port-forward only
```

## Useful targets
| Target | What it does |
|---|---|
| `make keycloak-status` | Show the instance and pods |
| `make keycloak-password` | Print the admin user and password |
| `make keycloak-realm-tuning` | Optional, self-signed TLS only: long token and session lifespans (not yet verified with this image) |

## Uninstall
```sh
make clean                    # deletes the Keycloak instance (keeps the operator and the database)
make clean-keycloak-operator  # removes the operator and CRDs
```

## Notes
- `KEYCLOAK_VERSION` pins both the operator manifests and the image tag (`quay-optimized-<version>`). Use the latest
  version in the [Camunda supported environments matrix](https://docs.camunda.io/docs/reference/supported-environments/).
- The first admin is a temporary one. Create a permanent admin and remove `temp-admin` for anything beyond testing.
