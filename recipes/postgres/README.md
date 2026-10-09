# Provision PostgreSQL with the CloudNativePG operator

Camunda 8.10 (Helm chart 15) no longer bundles PostgreSQL. This recipe installs the
[CloudNativePG](https://cloudnative-pg.io/) operator and one PostgreSQL cluster per component, following the
[Camunda reference architecture](https://docs.camunda.io/docs/self-managed/deployment/helm/configure/operator-based-infrastructure/#postgresql-deployment).

Run it before the Keycloak recipe and before installing a Camunda recipe that uses Management Identity or Camunda Hub.

## What you get
| Cluster | Used by | Service | Secret (keys `username`, `password`) |
|---|---|---|---|
| `pg-identity` | Management Identity | `pg-identity-rw:5432` | `pg-identity-secret` |
| `pg-keycloak` | Keycloak | `pg-keycloak-rw:5432` | `pg-keycloak-secret` |
| `pg-hub` | Camunda Hub | `pg-hub-rw:5432` | `pg-hub-secret` |
| `pg-camunda` (optional) | Orchestration Cluster when using RDBMS secondary storage | `pg-camunda-rw:5432` | `pg-camunda-secret` |

Each cluster also has a `<cluster>-superuser-secret`. Choose clusters with `PG_CLUSTERS`.
The operator runs in the `cnpg-system` namespace, the clusters in `CAMUNDA_NAMESPACE` (default `camunda`).

## Prerequisites
- A Kubernetes cluster provisioned and accessible.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) and [yq](https://github.com/mikefarah/yq) installed.
- At least `PG_INSTANCES` Kubernetes nodes (instances use required anti-affinity).

## Install
```sh
make
```

Override settings in the root `config.mk`, for example for a single-node Kind cluster:
```make
PG_INSTANCES ?= 1
DEFAULT_PASSWORD ?= something-better-than-changeme
```
Passwords are only stored in Kubernetes secrets, never in files. Changing `PG_PASSWORD` after the first install
updates the secrets but not the role passwords already inside the databases.

## Useful targets
| Target | What it does |
|---|---|
| `make postgres-status` | Show the clusters and pods |
| `make postgres-password PG_CLUSTER=pg-identity` | Print the owner credentials of a cluster |

## Uninstall
```sh
make clean               # deletes the PostgreSQL clusters, their data and secrets (keeps the operator)
make clean-cnpg-operator # removes the operator and CRDs, only if no other clusters use it
```

## Notes
- Two instances and the dedicated WAL volume are one-way settings: the operator refuses to remove `walStorage`
  or shrink `storage`. Decide before the first install.
- `PG_IMAGE` should be the latest PostgreSQL version in the
  [Camunda supported environments matrix](https://docs.camunda.io/docs/reference/supported-environments/).
