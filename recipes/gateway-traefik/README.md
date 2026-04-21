# Provision Traefik Gateway

Sets up a Traefik Proxy ingress controller using the official Helm chart.

This recipe is analogous to the [ingress-nginx](../ingress-nginx) recipe but installs Traefik instead. It provisions Traefik with its CRDs (`IngressRoute`, `IngressRouteTCP`, `Middleware`) which are then used by the [oidc-gateway-traefik-tls](../camunda/oidc-gateway-traefik-tls) recipe to route traffic to Camunda services.

After provisioning the gateway controller, you can optionally set up a cert-manager and cert-issuer for TLS support using Let's Encrypt.

## Prerequisites

- A Kubernetes cluster provisioned and accessible
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [helm](https://helm.sh/docs/intro/install/) version 3.7.0 or later

## Install

```sh
make
```

## Verify

Check that Traefik pods are running:

```sh
kubectl get pods -n traefik
```

Get the external IP/hostname:

```sh
make traefik-ip-from-service
```

Access the Traefik dashboard (port-forward):

```sh
make traefik-dashboard
```

Then open http://localhost:9000/dashboard/

## Uninstall

```sh
make clean
```

## Customization

Override variables in the project root `config.mk`:

```makefile
TRAEFIK_NAMESPACE = my-traefik
TRAEFIK_CHART_VERSION = 34.5.0
```
