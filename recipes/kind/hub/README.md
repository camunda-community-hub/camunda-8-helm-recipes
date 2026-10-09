# Camunda 8.10 with Camunda Hub on Kind

> [!CAUTION]
> **LOCAL DEVELOPMENT AND TESTING ONLY.** Uses self signed certificates, a single in-cluster PostgreSQL and
> Keycloak, and the password `demo` for everything. Camunda 8.10 and Helm chart 15 are **alpha**.

Installs a complete Camunda 8.10 alpha stack on a local [Kind](../README.md) cluster with one command:

| Component | Notes |
|---|---|
| Orchestration (Zeebe, Operate, Tasklist) | 1 broker, 1 partition, replication factor 1 (minimal, not for load) |
| Camunda Hub | replaces Web Modeler and Console in 8.10 |
| Management Identity + Keycloak | OIDC; Keycloak is deployed by this recipe (chart 15 no longer bundles one) |
| Connectors | OIDC |
| PostgreSQL | history backend (RDBMS secondary storage), Hub, Identity and Keycloak databases |
| ingress-nginx | hostPort on the Kind node, self signed TLS |
| Optimize | not installed |

## Prerequisites

- Docker Desktop (or another container runtime), `kind`, `kubectl`, `yq`, `jq`, `openssl`, `make`
- **Helm 4** (Helm chart 15 requires it): `helm version`
- Host ports **80 and 443** free. Kind maps them to the node, so stop anything else that uses them: another Kind
  cluster, a local web server, or **Docker Desktop's built-in Kubernetes**, whose LoadBalancer services (such as an
  ingress-nginx controller) reserve 80/443 invisibly to `lsof`. If `make kube` fails with
  `port is already allocated`, remove that service or turn off Docker Desktop Kubernetes.
- Add the hostnames to `/etc/hosts` (needs `sudo`, so do this yourself):

  ```shell
  echo "127.0.0.1 camunda.local grpc.camunda.local identity.camunda.local" | sudo tee -a /etc/hosts
  ```

## Usage

```shell
cd recipes/kind/hub
make all
```

`make all` runs: `preflight` (Helm 4 and `/etc/hosts` entries) → `kube` (Kind cluster) → `ingress-nginx` →
`tls` (self signed cert and `tls-secret`/`grpc-tls-secret`) → `kind-keycloak` (PostgreSQL + Keycloak) →
`camunda-values.yaml` → `create-camunda-credentials` → `camunda` → `keycloak-realm-tuning` →
`wait-camunda` → `urls`. It takes several minutes.

Then open (accept the browser's self signed certificate warning):

- Hub: https://camunda.local/modeler
- Orchestration (Operate, Tasklist): https://camunda.local/orchestration
- Identity: https://identity.camunda.local
- Keycloak admin: https://camunda.local/auth (`admin` / `demo`)

Log in as **`demo` / `demo`**.

After a reinstall, clear cookies for `camunda.local` and `identity.camunda.local` (or use a private window);
Management Identity returns HTTP 500 instead of the login page when the browser still holds a session from a
previous install.

### Clean up

```shell
make clean              # delete the whole Kind cluster
make clean-camunda-stack  # remove only Camunda, PostgreSQL and Keycloak, keep the cluster
```

### Test

```shell
make test               # regenerate camunda-values.yaml and diff against sample-camunda-values.yaml
```

## How it is composed

`camunda-values.yaml` is built from these shared files in [`camunda-values.yaml.d/`](../../../camunda-values.yaml.d)
(chart 15 only; they supersede their chart 14 counterparts), then `my-camunda-values.yaml`:

| File | Purpose |
|---|---|
| `ingress-nginx-host.yaml` | ingress with TLS; hostname is `global.host` in chart 15 |
| `identity-own-hostname.yaml` | Identity on `identity.<host>` plus a redirect for Hub's Identity link |
| `oidc-external-keycloak.yaml` | OIDC against an external Keycloak, Identity on external PostgreSQL |
| `connectors-enabled.yaml` | Connectors |
| `orchestration-rdbms-postgres.yaml` | PostgreSQL as secondary storage |
| `hub-enabled.yaml` | Camunda Hub with its PostgreSQL database |

The cluster, ingress, PostgreSQL and Keycloak steps are in [`makefiles/kind.mk`](../../../makefiles/kind.mk) with their
manifests in [`../include/`](../include). TLS reuses [`makefiles/tls-self-signed-cert.mk`](../../../makefiles/tls-self-signed-cert.mk)
(set `CA_KEY_PASS` to skip the interactive passphrase prompt).

## Known limitations of the 8.10 alpha

- **Management Identity cannot run under a sub-path.** Its UI requests assets and `/api` from the site root and
  scopes cookies to the sub-path, so it is served on its own hostname.
- **Identity cannot renew expired tokens inside the cluster** (the public issuer URL is self signed and not resolvable
  there), so Management Identity failed about 5 minutes after login. `keycloak-realm-tuning` sets 8 hour token
  and 12 hour session lifespans as a workaround.
- Hub reads its configuration at startup. After changing Hub related values run
  `kubectl rollout restart deploy/camunda-web-modeler-restapi -n camunda`.
- Zeebe logs a "License Key has wrong format" warning without a license; it is harmless.
