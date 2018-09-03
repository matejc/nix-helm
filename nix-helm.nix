{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, kubectl ? "${pkgs.kubernetes}/bin/kubectl"
, helm ? "${pkgs.kubernetes-helm}/bin/helm"
, yaml2nixNix ? ./yaml2nix.nix
, varsNix ? ./vars.nix
, valuesPath ? ./values
, resourcesPath ? ./resources }:

with lib;
with import yaml2nixNix { inherit pkgs lib; };

let
  actions = ["create" "read" "update" "delete"];
in

rec {
  vars = import varsNix { inherit pkgs lib; };

  inherit yaml2nixScript nix2yamlScript;

  importValues = {environment, name}: import (valuesPath + "/${name}-${environment}.nix") { inherit environment name vars pkgs lib; };

  importResource = {environment, name}: import (resourcesPath + "/${name}-${environment}.nix") { inherit environment name vars pkgs lib; };

  retry = pkgs.writeScript "retry" ''
    #!${pkgs.stdenv.shell}

    max_attempts="$1"; shift
    cmd="$@"
    attempt_num=1

    until $cmd
    do
        if (( attempt_num == max_attempts ))
        then
            echo "Attempt $attempt_num failed and there are no more attempts left!"
            exit 1
        else
            echo "Attempt $attempt_num failed! Trying again in $attempt_num seconds..."
            sleep $(( attempt_num++ ))
        fi
    done
  '';

  mkHelm = {environment, name, chart, namespace, context, values ? (importValues {inherit environment name;})}:
    mkEntry {
      inherit environment name;
      type = "helm";
      create = ''
        ${helm} install --namespace "${namespace}" --kube-context "${context}" --values "${builtins.toFile "${name}.yaml" (toYAML {nixes = values;})}" --name "${name}-${environment}" "${chart}"
      '';
      read = ''
        ${helm} ls "${name}-${environment}" --kube-context "${context}"
      '';
      update = ''
        ${helm} upgrade --recreate-pods --namespace "${namespace}" --kube-context "${context}" --values "${builtins.toFile "${name}-${environment}.yaml" (toYAML {nixes = values;})}" "${name}-${environment}" "${chart}"
      '';
      delete = ''
        ${helm} delete "${name}-${environment}" --purge --kube-context "${context}"
      '';
    };

  mkKube = {environment, name, namespace, context, resources ? (importResource {inherit environment name;}), retryTimes ? 5}:
    let
      r = map (resource: recursiveUpdate resource { metadata.labels.nix-helm-name = "${name}-${environment}"; }) resources;
    in
    mkEntry {
      inherit environment name;
      type = "kube";
      create = ''
        ${retry} ${toString retryTimes} ${kubectl} create -f ${builtins.toFile "${environment}-${name}.yaml" (toYAML {nixes = r;})} --context "${context}" --namespace "${namespace}"
      '';
      # in future rename all -> all-resources
      read = ''
        resources="$(printf "$(./kubectl api-resources --verbs=list -o name)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
        ${kubectl} get $resources --ignore-not-found --context "${context}" --namespace "${namespace}" --show-kind -l nix-helm-name="${name}-${environment}"
      '';
      update = ''
        ${kubectl} apply -f ${builtins.toFile "${name}-${environment}.yaml" (toYAML {nixes = r;})} --context "${context}" --namespace "${namespace}"
      '';
      # in future rename all -> all-resources
      delete = ''
        resources="$(printf "$(./kubectl api-resources --verbs=list -o name)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
        ${kubectl} delete $resources --ignore-not-found --context "${context}" --namespace "${namespace}" --show-kind -l nix-helm-name="${name}-${environment}"
      '';
    };

  mkEntry = {environment, name, type, create, read, update, delete}:
    {
      inherit environment name type create read update delete;
    };

  mkCommand = {environment, name, create, read, update, delete}:
    mkEntry {
      inherit environment name create read update delete;
      type = "command";
    };

  mkScriptText = environment: action: entry: ''
    #!${pkgs.stdenv.shell}
    echo -e "\n''${COLORBLUE}Running(${entry.type}): ${environment}/${action}/${entry.name}''${COLORCLEAR}"
    ${entry.${action}}
    if [[ "$?" == "0" ]]
    then
      echo -e "''${COLORGREEN}Success(${entry.type}): ${environment}/${action}/${entry.name}''${COLORCLEAR}\n"
    else
      echo -e "''${COLORRED}Failure(${entry.type}): exit with $? for ${environment}/${action}/${entry.name}''${COLORCLEAR}\n"
    fi
 '';

  mkScripts = {environment, entries}:
    flatten (
      map (action: (map (entry: pkgs.writeScriptBin "${action}-${entry.name}-${environment}" (
        mkScriptText environment action entry
      )) entries)) actions
    );

  scriptsEnv = {environment, entries}: pkgs.buildEnv {
    name = "nix-helm-scripts-${environment}";
    paths = mkScripts {inherit environment entries;};
  };

  shellRcFile = {environment, entries}: pkgs.writeText "nix-helm-shell-${environment}.sh" ''

  join_by() { local IFS="$1"; shift; echo "$*"; }

  _entries() {
    local cur opts filtered
    COMPREPLY=()
    cur="''${COMP_WORDS[COMP_CWORD]}"
    prev="''${COMP_WORDS[COMP_CWORD-1]}"
    opts="all ${concatMapStringsSep " " (e: e.name) entries}"

    if [ "$prev" == "all" ]
    then
      COMPREPLY=()
      return 0
    fi

    filtered="$(join_by '|' ''${COMP_WORDS[@]:1})"
    COMPREPLY=( $(compgen -W "''${opts}" -X "@($filtered)" -- ''${cur}) )
    return 0
  }

  export COLORRED='\033[0;31m'
  export COLORGREEN='\033[0;32m'
  export COLORBLUE='\033[0;34m'
  export COLORCLEAR='\033[0m' # No Color

  _run() {
    action="$1"
    entries="''${@:2}"

    case $action in
      ${concatStringsSep "|" actions})
        ;;
      *)
        echo "Not valid action: $action"
        return 1
        ;;
    esac

    for entry in "$entries"
    do
      case $entry in
        all)
          entries=( ${concatMapStringsSep " " (e: e.name) entries} )
          ;;
        ${concatMapStringsSep "|" (e: e.name) entries})
          ;;
        *)
          echo "Not a valid entry: \"$entry\""
          return 1
          ;;
      esac
    done

    echo "[$action] ''${entries[@]}"

    for entry in ''${entries[@]}
    do
      "${scriptsEnv {inherit environment entries;}}/bin/$action-$entry-${environment}"
    done
  }

  ${concatMapStringsSep "\n" (a: ''
  ${a}() {
    _run "${a}" "$@"
  }
  complete -F _entries ${a} 2>/dev/null
  '') actions}

  export PS1="nix-helm-${environment}> "
  export PATH=""
  '';

  mkNixHelmEnvironment = {environment ? "default", entries}:
  let
    entries' = map (entry:
        let
          entry' = list: (filterAttrs (key: v: any (n: key == n) list) entry) // { inherit environment; };
        in
          if entry.type == "command" then mkCommand (entry' ["name" "create" "read" "update" "delete"])
          else if entry.type == "kube" then mkKube (entry' ["name" "context" "namespace" "resources"])
          else if entry.type == "helm" then mkHelm (entry' ["name" "context" "chart" "namespace" "values"])
          else throw "Unsupported ${entry.type}"
      ) entries;
    shellrc = shellRcFile {inherit environment; entries = entries'; };
  in pkgs.writeScriptBin "nix-helm-${environment}" ''
    #!${pkgs.stdenv.shell}

    if [[ -n "$@" ]]
    then
      source ${shellrc}
      _run $1 ''${@:2}
    else
      ${pkgs.bashInteractive}/bin/bash --rcfile ${shellrc}
    fi

  '';

  toBase64 = value:
    builtins.readFile
      (pkgs.runCommand "to-base64" {
          buildInputs = [ pkgs.coreutils ];
        } "echo -n '${value}' | base64 -w0 > $out");
}
