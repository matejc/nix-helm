# nix-helm

Kubernetes and Helm deployment management tool bound with Nix


# Motivation

Helm has charts which are basically apps and then subcharts that are a bit limited in terms if you would like to describe whole cluster(s),
even so.. if you create multiple charts you can not put configuration in one config file and just ran it, so it is time for abstraction layer.
Abstraction layer that can describe `environments` (can be also called `projects` I guess), and deploy every Helm chart and Kubernetes resource in one go.

This is not to be used in production environment, it was made because I wanted a simple solution to deploy resources and still have a repository of resources (Helm charts) on my disposal.


# Features

- Environments are a group of entries
  - CRUD functionality for each entry (create, read, update, delete)
- Each environment can be used to deploy or modify apps across multiple namespaces and contexts
  - Each entry has its own Kubernetes context and namespace
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
$ ./result/bin/nix-helm-simple
```


## File structure

```
simple
├── charts
│   └── statics/
├── resources
│   └── apps-namespace-simple.nix
├── values
│   └── statics-simple.nix
├── default.nix
└── vars.nix
```

- charts/
  - local Helm charts
- resources/
  - Kubernetes resource files in Nix not YAML, by default
  - named as `<entry name>-<environment name>.nix`
- values/
  - Helm chart values files, just that they by default are in Nix not YAML
  - named as `<entry name>-<environment name>.nix`
- default.nix
  - entry point, this is where you build an environment(s)
- vars.nix
  - global variables, where your top level variables reside
  - this file is meant to be imported in every `resources` and `values` files
  - it is for domain names, user names, secret resource names, ... this file should be kept secret and normally not included in version control repository


## nix-helm-environment command

```
nix-helm-<environmentName> <create|read|update|delete> <all|entryName1> [entryName1 entryName2 ...]
```

... or shell:

```
./result/bin/nix-helm-default
nix-helm-default> update [Press Tab Tab]
```

## Other tools

To convert YAML files to Nix, lets build yaml2nix script:

```
nix-build ./src -A yaml2nixScript
```

To use it:

```
$ ./result/bin/yaml2nix ./something.yaml
```

or just pipe through it:

```
cat ./something.yaml | result/bin/yaml2nix
```

Result will be printed in stdout and wrapped as list of resources, just like `resources` and `values` files require.
The script supports multi document YAML files.


# TODO

- proper cli tool
- module system - inspired by [kubenix](https://github.com/xtruder/kubenix)
