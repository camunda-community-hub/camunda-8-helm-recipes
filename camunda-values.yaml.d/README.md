# Shared Camunda Values Directory

This directory contains reusable Helm chart values files that can be composed together to create different Camunda Platform 8 configurations. Each file provides a specific configuration aspect that can be mixed and matched across different profiles.

This repository contains chart values that are compatible with Camunda 8.9 and higher,
i.e. Camunda Helm Chart 14 and higher.
Example configurations for older versions can be found in the old repository of
[Camunda 8 Helm Profiles](https://github.com/camunda-community-hub/camunda-8-helm-profiles).

## Purpose

The `camunda-values.yaml.d` directory serves as a shared library of configuration components that:

- **Promote reusability**: Common configurations are defined once and reused across multiple profiles
- **Enable composition**: Different profiles can combine multiple values files to achieve their desired configuration
- **Simplify maintenance**: Updates to shared configurations automatically benefit all profiles that use them
- **Provide modularity**: Each file focuses on a specific aspect (size, persistence, features, etc.)

## Usage Example

The [`minimal-composed`](../minimal-composed) profile demonstrates how to compose multiple values files:

```makefile
chartValues ?= \
       "../camunda-values.yaml.d/cluster-size-mini.yaml" \
    -f "../camunda-values.yaml.d/persistence-in-memory.yaml" \
    -f "../camunda-values.yaml.d/elasticsearch-disabled.yaml" \
    -f "../camunda-values.yaml.d/identity-disabled.yaml" \
    -f "../camunda-values.yaml.d/connectors-disabled.yaml" \
    -f "../camunda-values.yaml.d/pod-anti-affinity-disabled.yaml" \
    -f "../camunda-values.yaml.d/prometheus-service-monitor.yaml" \
    -f "camunda-values.yaml"
```

This configuration creates a minimal, in-memory Camunda setup by combining:
- Mini cluster sizing
- In-memory persistence
- Disabled optional components
- Prometheus monitoring

## Creating New Profiles

To create a new profile using these shared values:

1. Create a new directory for your profile (e.g., `../my-profile/`)
2. Create a `config.mk` file that references the desired values files from this directory
3. Add any profile-specific overrides in a local `camunda-values.yaml` file
4. Use relative paths: `"../camunda-values.yaml.d/filename.yaml"`

Example `config.mk` structure:
```makefile
chartValues ?= \
       "../camunda-values.yaml.d/cluster-size-mini.yaml" \
    -f "../camunda-values.yaml.d/your-choice.yaml" \
    -f "camunda-values.yaml"
```

## File Naming Conventions

Files follow these naming patterns:
- **Component-specific**: `{component}-{setting}.yaml` (e.g., `elasticsearch-disabled.yaml`)
- **Feature-based**: `{feature}.yaml` (e.g., `ingress.yaml`, `dual-region.yaml`)
- **Size-related**: `cluster-size-{size}.yaml` (e.g., `cluster-size-mini.yaml`)

## Best Practices

1. **Order matters**: List values files from most general to most specific
2. **Local overrides**: Always include a local `camunda-values.yaml` file last for profile-specific customizations
3. **Modularity**: Keep each file focused on a single concern
4. **Documentation**: Include comments in YAML files explaining the purpose and impact
5. **Testing**: Test combinations to ensure they work together without conflicts
6. **Array merging limitation**: ⚠️ **Important**: Helm cannot merge arrays like `zeebe.env` - the last file with an array will completely override previous arrays. If multiple files need to set environment variables, consolidate them into a single file or use the final `camunda-values.yaml` file for all array-based configurations.

## Contributing

When adding new shared values files:

1. **Use descriptive names** that clearly indicate the file's purpose
2. **Add comments** explaining what the configuration does and when to use it
3. **Consider compatibility** with existing files
4. **Update this README** to document the new file
5. **Test with existing profiles** to ensure no breaking changes

## Related Documentation

- [Main Helm Profiles README](../README.md)
- [Minimal Composed Profile](../minimal-composed/README.md)
- [Camunda Platform Helm Chart Documentation](https://docs.camunda.io/docs/self-managed/platform-deployment/helm-kubernetes/)
