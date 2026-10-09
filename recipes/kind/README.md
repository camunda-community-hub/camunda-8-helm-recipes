# Helm recipes for Camunda 8 on Kind

It's possible to use `kind` to experiment with kubernetes on your local developer laptop, but please keep in mind that Kubernetes is not really intended to be run on a single machine. That being said, this can be handy for learning and experimenting with Kubernetes.

Create a Camunda 8 self-managed Kubernetes Cluster in 3 Steps:

# Prerequisites 

Setup command line tools and software for Kind:

1. Make sure to install container manager such as Docker Desktop (https://www.docker.com/products/docker-desktop/)

2. Make sure that `kind` is installed (https://kind.sigs.k8s.io/)

Again, keep in mind that `kind` is an emulated kubernetes cluster meant only for development!

# Usage

Use the `Makefile` inside the `kind` directory to create a k8s cluster.

```shell
cd recipes/kind
make kube
```

This will create a new `kind` cluster in Docker Desktop

Then use other recipes, such as the [Simple Orchestration recipe](../camunda/orchestration-simple), to install Camunda into kind

To install Camunda 8.10 with Camunda Hub (Identity, Keycloak, PostgreSQL, ingress and TLS) on Kind in one step, see the [Hub recipe](hub/README.md).
