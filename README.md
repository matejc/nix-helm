# nix-helm

Kubernetes and Helm management tool bound with Nix


# Features

- Environments are a group of entries
  - CRUD functionality for each entry (create, read, update, delete)
- Each environment can be used to deploy or modify apps across multiple namespaces and contexts
  - Each entry has its own context and namespace Kubernetes contexts
- Clean uninstall of charts and Kubernetes resources

- Entries
  - are Kubernetes resources, Helm charts and custom commands (just those 3 for now)
  - Kubernetes
    - Automatic installation retry, for when previous entry creates custom resource definitions
  - Helm
    - Charts can be loaded from local filesystem or from online chart repository
  - Commands
    - any kind of functionality that can CRUD


# Requirements

- Nix
- kubectl 1.11+ (lower versions will not be compatible, because it does not have `kubectl api-resources`)
  - currently in [nixpkgs](https://github.com/NixOS/nixpkgs/) there is no compatible version, [just download the latest static binary](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-using-curl)


# Usage

```
$ cd examples/simple/
$ nix-build .
./result/bin/nix-helm-default
```


# nix-helm-environment command

```
nix-helm-<environmentName> <create|read|update|delete> <all|entryName1> [entryName1 entryName2 ...]
```

... or shell:

```
./result/bin/nix-helm-default
nix-helm-default> update [Press Tab Tab]
```


# TODO

- proper cli tool
- module system - inspired by [kubenix](https://github.com/xtruder/kubenix)
