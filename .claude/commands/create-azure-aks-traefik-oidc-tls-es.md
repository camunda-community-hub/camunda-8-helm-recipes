---
description: Create a full Azure AKS environment running Camunda 8 with Traefik gateway, Keycloak OIDC, and Let's Encrypt TLS. Validates all config before provisioning, then runs the complete 7-step sequence.
---

You are helping provision a full Azure AKS environment for Camunda 8 with Traefik gateway, Keycloak OIDC auth, and Let's Encrypt TLS. Follow these steps in order. Run the Bash tool so the user can see output.

The root of the repo is at the git root — find it with `git rev-parse --show-toplevel`.

---

## Step 0 — Validate config

This must fully pass before anything else runs. Read `<root>/config.mk`.

### 0a. Gather config interactively

Whether `<root>/config.mk` exists or not, run through this interactive flow to build or validate the config. Collect answers one question at a time — do not ask multiple questions in the same message.

**Detect context first** (run these before asking anything):
- Run `git config user.name` → use the first name to suggest `firstname01` for `DEPLOYMENT_NAME`
- Run `git config user.email` → suggest as `CERT_MANAGER_EMAIL`
- If git email is empty, check `gcloud config get-value account`
- Generate two random passwords now (run `openssl rand -hex 16` twice) so you have them ready to offer — hex produces clean alphanumeric strings with no padding or special characters

**Then ask the user, one at a time:**

1. **DEPLOYMENT_NAME** — "What would you like to name this deployment? (suggested: `<firstname>01`)"
   - Must be lowercase alphanumeric, unique per Azure subscription
   - If the user just presses Enter or says "yes"/"ok", use the suggested value

2. **CERT_MANAGER_EMAIL** — "What email should Let's Encrypt use for certificate notifications? (suggested: `<detected-email>`)"
   - If the user accepts, use the detected email

3. **Passwords** — "I'll generate secure random passwords for `DEFAULT_PASSWORD` and `GRAFANA_PASSWORD`. Generated: `<pwd1>` and `<pwd2>`. Use these? (or type your own)"
   - If the user accepts, use the generated values
   - If they provide their own, use that for both (or ask if they want different ones)

4. **CAMUNDA_CLUSTER_SIZE** — "How many Zeebe brokers? (suggested: `3` for production, `1` for testing)"
   - Default to `3` if the user accepts

Do not ask about any other variables — use the defaults listed in 0b for everything else.

### 0b. Defaults for unasked variables

Use these for all variables not gathered interactively:

| Variable | Default |
|---|---|
| `AZURE_REGION` | `eastus` |
| `AZURE_MACHINE_TYPE` | `Standard_D8s_v3` |
| `AZURE_NODE_COUNT` | `3` |
| `MIN_SIZE` | `3` |
| `MAX_SIZE` | `15` |
| `HOST_NAME` | `${DEPLOYMENT_NAME}.aks.c8sm.com` |
| `IDENTITY_EXT_URL` | `https://${DEPLOYMENT_NAME}.aks.c8sm.com` |
| `KEYCLOAK_EXT_URL` | `https://${DEPLOYMENT_NAME}.aks.c8sm.com` |
| `ORCHESTRATION_EXT_URL` | `https://${DEPLOYMENT_NAME}.aks.c8sm.com` |
| `OPTIMIZE_EXT_URL` | `https://${DEPLOYMENT_NAME}.aks.c8sm.com` |
| `CONSOLE_EXT_URL` | `https://${DEPLOYMENT_NAME}.aks.c8sm.com` |
| `WEB_MODELER_EXT_URL` | `https://${DEPLOYMENT_NAME}.aks.c8sm.com` |
| `INGRESS_CLASS` | `traefik` |
| `TLS_SECRET_NAME` | `tls-secret` |
| `GCP_DNS_ZONE` | `aks` |

### 0c. Show config preview and offer to write

After gathering answers, show a complete preview of the config file that will be written:

```
──────────────────────────────────────────
  config.mk preview
──────────────────────────────────────────
DEPLOYMENT_NAME      = <value>
AZURE_REGION         = <value>
AZURE_MACHINE_TYPE   = <value>
AZURE_NODE_COUNT     = <value>
MIN_SIZE             = <value>
MAX_SIZE             = <value>
HOST_NAME            = <value>
CERT_MANAGER_EMAIL   = <value>
INGRESS_CLASS        = <value>
TLS_SECRET_NAME      = <value>
GCP_DNS_ZONE         = <value>
DEFAULT_PASSWORD      = <value>
GRAFANA_PASSWORD     = <value>
CAMUNDA_CLUSTER_SIZE = <value>
──────────────────────────────────────────
```

Then ask: **"Shall I write this to `<root>/config.mk`?"**

- If `<root>/config.mk` already exists: warn the user — "⚠️ A `config.mk` already exists. Writing will replace it. Your existing file will be backed up to `config.mk.bak` first. Proceed?"
  - Only replace after explicit confirmation. **Always create the `.bak` first.**
- If it does not exist: write it immediately on confirmation.

Never delete or overwrite `config.mk` without explicit user confirmation and a backup.

---

## Prerequisites

After config is confirmed, verify:
- `az` session is active: `az account show`. If expired, tell the user to run `! az login`.
- `gcloud` is authenticated: `gcloud auth list --filter=status:ACTIVE`. If not, tell the user to run `! gcloud auth login`.
- `kubectl` is installed.
- `helm` is installed.

---

## Step 1 — Create AKS cluster

```
cd <root>/recipes/azure/aks && make
```

Creates the resource group and AKS cluster with autoscaler, then updates kubeconfig. Takes several minutes.

Verify nodes are ready:
```
kubectl get nodes
```

---

## Step 2 — Install metrics (Prometheus + Grafana)

```
cd <root>/recipes/metrics && make
```

---

## Step 3 — Install cert-manager and Let's Encrypt ClusterIssuer

```
cd <root>/recipes/letsencrypt && make
```

This installs cert-manager and creates the Let's Encrypt production ClusterIssuer. The `INGRESS_CLASS` must be `traefik` (validated in Step 0) so ACME HTTP-01 challenges route through Traefik, not nginx.

---

## Step 4 — Install Traefik gateway

```
cd <root>/recipes/gateway-traefik && make
```

Wait for the Traefik LoadBalancer to get an external IP:
```
kubectl get service traefik -n traefik --watch
```
Proceed only once `EXTERNAL-IP` is populated (not `<pending>`).

---

## Step 5 — Update GCP Cloud DNS

From the same directory (`recipes/gateway-traefik`):
```
make update-gcp-dns
```

Upserts two A records in GCP Cloud DNS zone `GCP_DNS_ZONE` (default: `aks`):
- `$(HOST_NAME)` → Traefik LB IP
- `grpc.$(HOST_NAME)` → Traefik LB IP

If this fails:
- **No IP yet**: wait longer for the LB to provision, then retry.
- **gcloud not authenticated**: tell the user to run `! gcloud auth login`.

---

## Step 6 — Install Camunda

```
cd <root>/recipes/camunda/oidc-gateway-traefik-tls-es && make
```

Generates `camunda-values.yaml`, creates Kubernetes credentials secret, installs via Helm, and applies Traefik IngressRoutes.

Wait for all pods to be Running/Ready:
```
kubectl get pods -n camunda --watch
```

Key pods: `camunda-zeebe-*`, `camunda-zeebe-gateway-*`, `camunda-keycloak-*`, `camunda-identity-*`. Wait until all are `Running` and `READY`.

---

## Step 7 — Request TLS certificate

From the same directory (`recipes/camunda/oidc-gateway-traefik-tls-es`):
```
make request-certificate
```

Creates a cert-manager `Certificate` resource for `$(HOST_NAME)` using the secret name `$(TLS_SECRET_NAME)`. Monitor issuance:
```
make get-cert-requests
make get-cert-orders
```

Let's Encrypt issuance typically takes 1–3 minutes. When the certificate shows `Ready: True`, the environment is fully provisioned.

---

## Config variable reference

All overridden in root `config.mk` (gitignored). Never commit secrets.

| Variable | Default | Step | Notes |
|---|---|---|---|
| `DEPLOYMENT_NAME` | `mydeployment` | 1 | Must be unique per subscription |
| `AZURE_REGION` | `eastus` | 1 | |
| `AZURE_MACHINE_TYPE` | `Standard_A8_v2` | 1 | |
| `AZURE_NODE_COUNT` | `1` | 1 | Initial node count (autoscaler adjusts) |
| `MIN_SIZE` / `MAX_SIZE` | `1` / `6` | 1 | Autoscaler bounds |
| `GRAFANA_PASSWORD` | `changeme` | 2 | Use a real password |
| `CERT_MANAGER_EMAIL` | placeholder | 3 | Must be a real email for Let's Encrypt |
| `INGRESS_CLASS` | `nginx` | 3 | **Must be `traefik`** for this setup |
| `GCP_DNS_ZONE` | `aks` | 5 | GCP Cloud DNS zone name |
| `HOST_NAME` | `example.com` | 5, 6, 7 | e.g. `dave01.aks.c8sm.com` |
| `TLS_SECRET_NAME` | `tls-secret` | 6, 7 | Must match in both Camunda and cert-manager |
| `DEFAULT_PASSWORD` | `changeme` | 6 | Camunda component credentials |
| `CAMUNDA_CLUSTER_SIZE` | `1` | 6 | Zeebe broker count |

---

## Teardown

Run `/destroy-aks` to tear down the environment.
