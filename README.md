[![Community Extension](https://img.shields.io/badge/Community%20Extension-An%20open%20source%20community%20maintained%20project-FF4700)](https://github.com/camunda-community-hub/community)
[![Lifecycle; Incubating](https://img.shields.io/badge/Lifecycle-Proof%20of%20Concept-blueviolet)](https://github.com/Camunda-Community-Hub/community/blob/main/extension-lifecycle.md#proof-of-concept-)[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
![Compatible with: Camunda Platform 8](https://img.shields.io/badge/Compatible%20with-Camunda%20Platform%208-0072Ce)

# Camunda 8 Helm Recipes

This is a Community Project that helps to install Camunda and other supporting technologies into Kubernetes using the [Camunda Helm Charts](https://github.com/camunda/camunda-platform-helm).
Allways refer to the [official installation procedures](https://docs.camunda.io/docs/self-managed/deployment/helm/)
first and use the recipes provided here as additional examples.

This repository contains Helm chart values that are compatible with Camunda 8.9 and higher,
i.e. Camunda Helm Chart 14 and higher.
Example configurations for older versions can be found in the old repository of
[Camunda 8 Helm Profiles](https://github.com/camunda-community-hub/camunda-8-helm-profiles).

Those who are already familiar with DevOps and Kubernetes may find it easier, and more flexible, to use the [Camunda Helm Charts](https://github.com/camunda/camunda-platform-helm) along with your own methods and tools. 

For those looking for more guidance, this project provides `Makefiles`, along with custom scripts and `camunda-values.yaml` files to help with: 

- Creating Kubernetes Clusters from scratch in several popular cloud providers, including Google Cloud Platform, Azure, AWS, and Kind. 

- Installing Camunda into existing Kubernetes Clusters by providing sample `camunda-values.yaml` pre-configured for specific use cases. 

- Automating common tasks, such as installing Ingress controllers, configuring temporary TLS certificates, installing Prometheus and Grafana for metrics, etc.  

## How is it Organized?

The [makefiles](./makefiles) directory contains Makefile targets to support common tasks across multiple cloud providers.

The [camunda-values.yaml.d](./camunda-values.yaml.d) directory contains reusable Helm values files that can be composed together to create different Camunda Platform 8 configurations. Each file provides a specific configuration aspect that can be mixed and matched across different profiles, aka, `recipes`, which are described next.

The [recipes](./recipes) directory combines `Makefiles` and `camunda-values.yaml` files to support specific use cases.

### Dual-Region (AWS EKS)

[`recipes/aws/eks-dual-region/`](./recipes/aws/eks-dual-region/) provisions two AWS EKS clusters with VPC peering and CoreDNS chaining for a dual-region Camunda 8.9 deployment. [`recipes/camunda/dual-region-rdbms-postgres/`](./recipes/camunda/dual-region-rdbms-postgres/) deploys Camunda across both clusters using Aurora PostgreSQL as the secondary store (no Elasticsearch required). See the recipe [README](./recipes/aws/eks-dual-region/README.md) and [operations playbook](./recipes/aws/eks-dual-region/docs/eks-dual-region-playbook.md) for details.

## How does it work?

Each recipe contains a `Makefile` which makes use of `make` targets from files found inside [makefiles](./makefiles) directory. `make` targets use command line tools and bash scripts to accomplish the work of each profile. For example, [makefiles/camunda.mk](./makefiles/camunda.mk) defines a `make` target `make camunda`, which will install Camunda via Helm charts. 

Each recipe also makes use of one or more `camunda-values.yaml` files found inside the [camunda-values.yaml.d](./camunda-values.yaml.d) directory. These files provide configuration settings for the Camunda Helm charts. Each recipe may also include its own `my-camunda-values.yaml` file to provide additional configuration settings specific to that recipe.

# Prerequisites

1. Clone the [Camunda 8 Helm Recipes git repository](https://github.com/camunda-community-hub/camunda-8-helm-recipes).

2. Verify GNU `make` is installed.

       make --version

Each recipe may have additional prerequisites. See the `README.md` file inside each recipe for more details.

## Contributing

When making changes to a recipe — such as modifying `my-camunda-values.yaml`, `config.mk`, or any of the shared values files in `camunda-values.yaml.d` — validate your changes by running the recipe's test target before submitting a pull request.

Each Camunda recipe includes a `make test` target that generates `camunda-values.yaml` using the recipe's default configuration and compares it against the `sample-camunda-values.yaml` file, which serves as the expected output.

To test a single recipe:

```bash
make -C recipes/camunda/basic-ingress-nginx-tls test
```

To test all Camunda recipes at once:

```bash
make -C recipes/camunda test
```

If a test fails, a diff will be printed showing what changed. If the change is intentional, update `sample-camunda-values.yaml` in the affected recipe to reflect the new expected output:

```bash
make -C recipes/camunda/basic-ingress-nginx-tls camunda-values.yaml
cp recipes/camunda/basic-ingress-nginx-tls/camunda-values.yaml \
   recipes/camunda/basic-ingress-nginx-tls/sample-camunda-values.yaml
```
