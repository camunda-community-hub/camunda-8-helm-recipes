---
name: install-camunda-kind
description: Install, verify, or tear down the full Camunda 8.10 alpha stack (Hub, Identity, Keycloak, Connectors, minimal single-broker Zeebe, Postgres history backend, no Optimize) on a local Kind cluster with ingress and self-signed TLS at https://camunda.local. Use when the user asks to install, reinstall, test, or remove Camunda 8.10 / Camunda Hub locally on Kind.
---

# Install Camunda 8.10 (Hub) on Kind

Operating procedure only. The recipe is `recipes/kind/hub/`; its `README.md` describes what is installed, the
URLs and the known alpha limitations. For how the project is organized or how to change a recipe, use the
`camunda-helm-recipes-conventions` skill.

Chart `camunda/camunda-platform` `15.0.0-alpha5` (app 8.10). Login `demo` / `demo`.

Status: `make all` was run end to end on a real Kind cluster (2026-10-01): exit 0, all 7 pods 1/1 Running,
all routes redirect as expected. Also covered by `helm template` and the golden test
(`make -C recipes/kind/hub test`).

## Do not do these yourself
- Edit `/etc/hosts` (needs `sudo`). Check `grep camunda.local /etc/hosts`. If `camunda.local`,
  `grpc.camunda.local` or `identity.camunda.local` is missing, ask the user to run:
  `echo "127.0.0.1 camunda.local grpc.camunda.local identity.camunda.local" | sudo tee -a /etc/hosts`
  (`make preflight` prints the same line and fails until it is done).
- Type credentials into browser pages; verify with `curl` and logs instead.
- Stop other clusters, containers or port-forwards without asking.

## 1. Preflight
- `helm version` must start with `v4`. Tools: `kind kubectl helm yq jq openssl docker make`.
- Host ports 80 and 443 must be bindable. `lsof` is NOT enough: Docker Desktop's built-in Kubernetes reserves
  them for any LoadBalancer service (e.g. an `ingress-nginx-controller` in the `docker-desktop` context) without a
  visible listener, and Kind then fails with `Bind for 0.0.0.0:80 failed: port is already allocated`. Probe with
  `docker run --rm -d -p 80:80 busybox:1.36 sleep 3` (and 443). If it fails, find the holder
  (`kubectl --context docker-desktop get svc -A | grep LoadBalancer`, other Kind clusters, `docker ps`), say what it is
  and ask before changing it (switch the service to ClusterIP, uninstall it, or turn off Docker Desktop Kubernetes).
- `helm repo add camunda https://helm.camunda.io && helm repo update camunda`, then confirm
  `helm search repo camunda/camunda-platform --devel` lists `15.0.0-alpha5`.

## 2. Install
```bash
cd recipes/kind/hub
make all     # run in the background and read the log; takes several minutes
```
Steps: `preflight`, `kube` (Kind cluster named `DEPLOYMENT_NAME`, default `camunda-hub`; a root `config.mk` may override it, so
the kube context is `kind-<DEPLOYMENT_NAME>`), `ingress-nginx` (hostPort), `tls`,
`kind-keycloak` (PostgreSQL + Keycloak), `camunda-values.yaml`, `create-camunda-credentials`, `camunda`,
`keycloak-realm-tuning`, `wait-camunda`, `urls`.

`Error 1 (ignored)` for `camunda-credentials` not found is expected on a fresh install. A real failure shows
`***` without `(ignored)`. For an existing cluster without ingress, `make check-ingress` explains and
`make ingress-nginx` installs it (ask the user first).

## 3. Verify (never rely on a single signal)
- `kubectl get pods -n camunda`: every pod `1/1 Running`, 0 restarts.
- Routes: `for u in https://camunda.local/modeler/ https://camunda.local/orchestration/ https://identity.camunda.local/ https://camunda.local/; do curl -sk -o /dev/null -w '%{http_code} -> %{redirect_url}\n' $u; done`
  Expect 302s to the Hub login, the Keycloak login, the Identity login, and `/` to the Identity host.
- Connectors may log many `Connection refused` errors to `camunda-zeebe-gateway` during startup while Zeebe is not
  ready; that is normal if the last minute of logs is clean and the pod has 0 restarts.
- Realm `camunda-platform` exists and user `demo` is enabled (`kcadm.sh` in the Keycloak pod).
- Tell the user to clear cookies for `camunda.local` and `identity.camunda.local` (or use a private window);
  stale sessions make Management Identity return HTTP 500.

## 4. Teardown
```bash
make -C recipes/kind/hub clean                 # deletes the whole Kind cluster
make -C recipes/kind/hub clean-camunda-stack   # keeps the cluster; removes Camunda, Postgres, Keycloak
```

## Operating gotchas
- Hub reads its config at startup: after changing Hub values run
  `kubectl rollout restart deploy/camunda-web-modeler-restapi -n camunda`.
- Never run `make update-camunda` against a live cluster whose secrets differ from `DEFAULT_PASSWORD`; it
  recreates `camunda-credentials` and breaks Keycloak and database logins. Use `helm upgrade` directly.
- `DEFAULT_PASSWORD` is used for the Postgres roles, the Keycloak admin and `camunda-credentials`; change it
  only before the first install.
