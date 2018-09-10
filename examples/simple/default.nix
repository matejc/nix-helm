{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib }:
let
  /* init nixHelm */
  nixHelm = import ../../src {
    kubectl = ./kubectl;  # optional path to the custom kubectl
    chartsPath = ./charts;  # path to local helm charts
    valuesPath = ./values;  # path to the chart values files, by default in nix files
    resourcesPath = ./resources;  # path to the kubernetes resources, by default in nix files
  };

  context = "minikube";
  namespace = "apps";

  entries = [
    /* type kube:
      is serching for resources in ./resources/apps-namespace-simple.nix

      can also accept:
      resources - must be a list of attrsets
      namespace - kubernetes namespace
      context - kubernetes context
    */
    {type = "kube"; name = "apps-namespace";}

    /* type helm:
      is serching for values in ./values/statics-simple.nix
      and chart in ./charts/statics

      can also accept:
      chart - filesystem path or online chart (ex: "stable/nginx-ingress")
      values - must be a list of attrsets
      namespace - kubernetes namespace
      context - kubernetes context
    */
    {type = "helm"; name = "statics";}
  ];
in
  /* only entries field is required */
  nixHelm.mkEnvironment { inherit entries namespace context; environment = "simple"; }
