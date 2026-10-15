# Camunda 8 with External Postgres and OIDC

Sample of how to configure Camunda 8.10 (Helm chart 15) with Postgres for RDBMS storage and Keycloak for OIDC authentication.

https://docs.camunda.io/docs/next/self-managed/deployment/helm/configure/database/rdbms/

https://docs.camunda.io/docs/next/self-managed/concepts/databases/relational-db/rdbms-support-policy/#bundled-drivers

## Features

This recipe provides:
- **Orchestration Cluster**: Configured to use external PostgreSQL database as secondary storage
- **Keycloak**: Run by the Keycloak operator on a CloudNativePG database; used as the OIDC identity provider
- **Identity**: Management identity service backed by external PostgreSQL
- **OIDC authentication**: Enabled for the Orchestration cluster and Connectors
- **Ingress**: nginx ingress controller with TLS

## Prerequisites

Chart 15 does not bundle Keycloak or its database. Install them first with their own recipes:

```bash
make -C ../../postgres   # CloudNativePG operator + pg-identity, pg-keycloak, pg-hub (only pg-keycloak is used here)
make -C ../../keycloak   # Keycloak operator + Keycloak, served under /auth through an nginx Ingress
```

Also needed:
- An existing Kubernetes cluster using Kind, Google, AWS or Azure, etc, with an nginx ingress controller (see [`recipes/ingress-nginx`](../../ingress-nginx))
- A PostgreSQL database accessible from the cluster (see the `aws/eks-and-aurora-postgres` recipe for an example) with databases provisioned for Camunda and Identity (see `make setup-all-dbs`)
- A DNS hostname resolving to your cluster's ingress controller IP
- `kubectl` configured to connect to your cluster
- `helm` version 4 (Helm 3 works but is end of life in 2027) and `yq`
- GNU `make`

## Configuration

Set the following in a root-level `config.mk` (not committed) to override the recipe defaults:

| Variable | Description | Default |
|----------|-------------|---------|
| `HOST_NAME` | Hostname for ingress and external URLs | `example.camunda.com` |
| `POSTGRES_HOST` | External PostgreSQL host | `mypostgresql.camunda.com` |
| `POSTGRES_MASTER_USERNAME` | PostgreSQL master username | `postgres` |
| `POSTGRES_MASTER_PASSWORD` | PostgreSQL master password | `CHANGEME` |
| `POSTGRES_CAMUNDA_DB` / `POSTGRES_CAMUNDA_USERNAME` | Camunda DB name and user | `camunda` / `camunda` |
| `POSTGRES_IDENTITY_DB` / `POSTGRES_IDENTITY_USERNAME` | Identity DB name and user | `identity` / `identity` |
| `DEFAULT_PASSWORD` | Password used for Camunda component credentials | `changeme` |

## Helm values file

Run `make camunda-values.yaml` to generate a `camunda-values.yaml` file.

## Install

Create credentials secret, then install:

```bash
make
```

## Verify Installation

Check that all pods are running:

```bash
make pods
```

Once ingress is healthy, access the services at your configured hostname:

- Keycloak: `https://<HOST_NAME>/auth`
- Identity: `https://<HOST_NAME>/management`
- Operate UI: `https://<HOST_NAME>/orchestration/operate`
- Tasklist UI: `https://<HOST_NAME>/orchestration/tasklist`

## Uninstall

```bash
make clean
```

This will remove the Camunda installation and clean up all resources.

## Use Cases

This recipe is useful for understanding how to configure Camunda 8.10 with:
- External RDBMS (PostgreSQL) as secondary storage instead of Elasticsearch
- Keycloak (operator-managed) as an OIDC provider for Orchestration and Connectors
- External PostgreSQL for Identity and Camunda's RDBMS storage

## Limitations

⚠️ **Important**: This is provided for reference and learning, however it is **not suitable for production** use because:

- **TLS certificate**: the ingress expects a `tls-secret`, for example from `make request-certificate`, see [`recipes/letsencrypt`](../../letsencrypt)
- **No high availability**: Single instances of all components

## Customization

To customize this recipe:

1. Edit [`my-camunda-values.yaml`](my-camunda-values.yaml) for additional overrides
2. Modify `config.mk` at the root project to override default settings found in `config.mk`
3. Create additional value files in `../camunda-values.yaml.d/` for reusable configurations

## Troubleshooting

### Pods not starting
- Check resource availability: `kubectl describe nodes`
- Check pod events: `kubectl describe pod <pod-name> -n camunda`

### Keycloak not reachable
- Verify Keycloak pod is running: `kubectl get pods -n camunda`
- Check ingress is configured correctly: `kubectl get ingress -n camunda`

### Cannot access services
- Verify your DNS hostname resolves to the ingress controller IP
- Check ingress status: `kubectl get ingress -n camunda`
- Check service status: `kubectl get svc -n camunda`
