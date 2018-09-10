{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, kubectl ? "${pkgs.kubernetes}/bin/kubectl"
, helm ? "${pkgs.kubernetes-helm}/bin/helm"
, chartsPath ? ./charts
, valuesPath ? ./values
, resourcesPath ? ./resources }:

let
  actions = ["create" "read" "update" "delete"];
  utils = import ./utils.nix { inherit pkgs lib; };
  importValues = {environment, name}: import (valuesPath + "/${name}-${environment}.nix") { inherit environment name utils pkgs lib; };
  importResource = {environment, name}: import (resourcesPath + "/${name}-${environment}.nix") { inherit environment name utils pkgs lib; };
  retryScript = pkgs.writeScript "retry.sh" ''
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

  mkHelm = {environment, name, chart ? (chartsPath + "/${name}"), namespace, context, values ? (importValues {inherit environment name;})}:
  let
    output = mkOutput { inherit environment name values; };
  in
    mkEntry {
      inherit environment name output;
      type = "helm";
      create = ''
        ${helm} install --namespace "${namespace}" --kube-context "${context}" --values "${output.file}" --name "${name}-${environment}" "${chart}"
      '';
      read = ''
        ${helm} status "${name}-${environment}" --kube-context "${context}"
      '';
      update = ''
        ${helm} upgrade --recreate-pods --namespace "${namespace}" --kube-context "${context}" --values "${output.file}" "${name}-${environment}" "${chart}"
      '';
      delete = ''
        ${helm} delete "${name}-${environment}" --purge --kube-context "${context}"
      '';
    };

  mkOutput = {environment, name, values ? null, resources ? null}:
  let
    outputType = if values == null then "resources" else "values";
    file = pkgs.writeText "${name}-${environment}.yaml" (utils.toYAML {nixes = if values == null then resources else values;});
  in
    pkgs.stdenv.mkDerivation {
      name = "${outputType}-${name}-${environment}.yaml";
      passthru = { inherit file environment name; };
      phases = "phase";
      phase = ''
        mkdir -p $out/etc/nix-helm/${outputType}
        cp ${file} $out/etc/nix-helm/${outputType}/${name}-${environment}.yaml
      '';
    };

  mkKube = {environment, name, namespace, context, resources ? (importResource {inherit environment name;}), retryTimes ? 5}:
    let
      r = map (resource: lib.recursiveUpdate resource { metadata.labels.nix-helm-name = "${name}-${environment}"; }) resources;
      output = mkOutput { inherit environment name; resources = r; };
    in
    mkEntry {
      inherit environment name output;
      type = "kube";
      create = ''
        ${retryScript} ${toString retryTimes} ${kubectl} create -f ${output.file} --context "${context}" --namespace "${namespace}"
      '';
      # in future rename all -> all-resources
      read = ''
        resources="$(printf "$(./kubectl api-resources --verbs=list -o name)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
        ${kubectl} get $resources --ignore-not-found --context "${context}" --namespace "${namespace}" --show-kind -l nix-helm-name="${name}-${environment}"
      '';
      update = ''
        ${kubectl} apply -f ${output.file} --context "${context}" --namespace "${namespace}"
      '';
      # in future rename all -> all-resources
      delete = ''
        resources="$(printf "$(./kubectl api-resources --verbs=list -o name)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
        ${kubectl} delete $resources --ignore-not-found --context "${context}" --namespace "${namespace}" --show-kind -l nix-helm-name="${name}-${environment}"
      '';
    };

  mkEntry = {environment, name, type, create, read, update, delete, output ? null}:
    {
      inherit environment name type create read update delete output;
    };

  mkCommand = {environment, name, create, read, update, delete, output}:
    mkEntry {
      inherit environment name create read update delete output;
      type = "command";
    };

    mkScriptText = {environment, action, entry}: ''
      #!${pkgs.stdenv.shell}
      echo -e "\n''${COLORBLUE}Running(${entry.type}): ${environment}/${action}/${entry.name} ...''${COLORCLEAR}"
      ${entry.${action}}
      if [[ "$?" == "0" ]]
      then
        echo -e "''${COLORGREEN}Success(${entry.type}): ${environment}/${action}/${entry.name}''${COLORCLEAR}\n"
      else
        echo -e "''${COLORRED}Failure(${entry.type}): exit with $? for ${environment}/${action}/${entry.name}''${COLORCLEAR}\n"
      fi
   '';

    mkScripts = {environment, entries}:
      lib.flatten (
        map (action: (map (entry: pkgs.writeScriptBin "${action}-${entry.name}-${environment}" (
          mkScriptText {inherit environment action entry;}
        )) entries)) actions
      );

    mkScriptsEnv = {environment, entries}: pkgs.buildEnv {
      name = "nix-helm-scripts-${environment}";
      paths = mkScripts {inherit environment entries;};
    };

    mkShellRcFile = {environment, entries}: pkgs.writeText "nix-helm-shell-${environment}.sh" ''

    join_by() { local IFS="$1"; shift; echo "$*"; }

    _entries() {
      local cur opts filtered
      COMPREPLY=()
      cur="''${COMP_WORDS[COMP_CWORD]}"
      prev="''${COMP_WORDS[COMP_CWORD-1]}"
      opts="all ${lib.concatMapStringsSep " " (e: e.name) entries}"

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
    export COLORCYAN='\033[0;36m'
    export COLORGREEN='\033[0;32m'
    export COLORBLUE='\033[0;34m'
    export COLORCLEAR='\033[0m' # No Color

    _run() {
      action="$1"
      entries="''${@:2}"

      case $action in
        ${lib.concatStringsSep "|" actions})
          ;;
        *)
          echo -e "''${COLORRED}Not valid action: $action''${COLORCLEAR}"
          return 1
          ;;
      esac

      for entry in "$entries"
      do
        case $entry in
          all)
            if [[ "$action" = "delete" ]]
            then
              entries=( ${lib.concatMapStringsSep " " (e: e.name) (lib.reverseList entries)} )
            else
              entries=( ${lib.concatMapStringsSep " " (e: e.name) entries} )
            fi
            ;;
          ${lib.concatMapStringsSep "|" (e: e.name) entries})
            ;;
          *)
            echo -e "''${COLORRED}Not a valid entry: \"$entry\"''${COLORCLEAR}"
            return 1
            ;;
        esac
      done

      echo -e "''${COLORBLUE}[$action] ''${entries[@]}''${COLORCLEAR}"

      for entry in ''${entries[@]}
      do
        "${mkScriptsEnv {inherit environment entries;}}/bin/$action-$entry-${environment}"
      done
    }

    ${lib.concatMapStringsSep "\n" (a: ''
    ${a}() {
      _run "${a}" "$@"
    }
    complete -F _entries ${a} 2>/dev/null
    '') actions}

    export PS1="nix-helm-${environment}''${COLORCYAN}>''${COLORCLEAR} "
    export PATH=""
  '';

  mkEnvironment = {environment ? "default", entries, namespace ? null, context ? null}:
  let
    entries' = map (entry:
        let
          defaults =
            (lib.optionalAttrs (namespace != null) {inherit namespace;}) //
            (lib.optionalAttrs (context != null) {inherit context;});
          entry' = list: defaults // (lib.filterAttrs (key: v: lib.any (n: key == n) list) entry) // { inherit environment; };
        in
          if entry.type == "command" then mkCommand (entry' ["name" "create" "read" "update" "delete"])
          else if entry.type == "kube" then mkKube (entry' ["name" "context" "namespace" "resources" "retryTimes"])
          else if entry.type == "helm" then mkHelm (entry' ["name" "context" "chart" "namespace" "values"])
          else throw "Unsupported ${entry.type}"
      ) entries;
    shellrc = mkShellRcFile {inherit environment; entries = entries'; };
    command = pkgs.writeScriptBin "nix-helm-${environment}" ''
      #!${pkgs.stdenv.shell}
      if [[ -n "$@" ]]
      then
        source ${shellrc}
        _run $1 ''${@:2}
      else
        ${pkgs.bashInteractive}/bin/bash --rcfile ${shellrc}
      fi
    '';
  in
    pkgs.buildEnv {
      name = "nix-helm-${environment}-env";
      paths = [ command ] ++ (lib.filter (v: v != null) (map (e: e.output) entries'));
    };

  nixHelm = {
    inherit mkCommand mkKube mkHelm mkEnvironment;
  } // utils;
in
  nixHelm
