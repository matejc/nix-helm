{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib }:
let
  /* init nixHelm */
  nixHelm = import ../../src {
    kubectl = ./kubectl;  # optional path to the custom kubectl
    valuesPath = ./values;  # path to the chart values files, by default in nix files
    resourcesPath = ./resources;  # path to the kubernetes resources, by default in nix files
  };

  context = "minikube";
  namespace = "apps";

  entries = [
    /* type kube, is serching for resources in ./resources/apps-namespace-simple.nix */
    {type = "kube"; name = "apps-namespace"; inherit namespace context;}

    /* type helm, is serching for values in ./values/statics-simple.nix */
    {type = "helm"; name = "statics"; chart = "./charts/statics"; inherit namespace context;}
  ];
in
  nixHelm.mkEnvironment { inherit entries; environment = "simple"; }
  
