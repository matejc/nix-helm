{ pkgs
, lib
}:
let
  kubectl = "${pkgs.kubernetes}/bin/kubectl";
  helm = "${pkgs.kubernetes-helm}/bin/helm";
  utils = import ./utils.nix { inherit pkgs lib; };

  mkHelm = { name, chart, namespace, context, values }:
    let
      output = mkOutput { inherit name values; };
      mkHelmCommand = operation: args: pkgs.writeShellScriptBin "${operation}-${namespace}-${name}.sh" ''
        ${helm} ${operation} ${name} --namespace "${namespace}" --kube-context "${context}" ${args}
      '';
    in
    {
      inherit name output values;
      install = mkHelmCommand "install" ''--values "${output}" "${chart}"'';
      status = mkHelmCommand "status" "";
      upgrade = mkHelmCommand "upgrade" ''--values "${output}" "${chart}"'';
      uninstall = mkHelmCommand "uninstall" "";
    };

  mkOutput = { name, values ? null }:
    utils.toYamlFile { name = "${name}.yaml"; attrs = values; passthru = { inherit name; }; };

  mkKube = { name, namespace, context, resources, retryTimes ? 5 }:
    let
      r = map (resource: lib.recursiveUpdate resource { metadata.labels.nix-helm-name = name; }) resources;
      output = mkOutput { inherit name; resources = r; };
    in
    {
      inherit name output;
      type = "kube";
      create = ''
        ${utils.retryScript} ${toString retryTimes} ${kubectl} create -f ${output} --context "${context}" --namespace "${namespace}"
      '';
      read = ''
        resources="$(echo -n "$(${kubectl} api-resources --verbs=get -o name | ${pkgs.gnugrep}/bin/grep -v componentstatus)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
        ${kubectl} get $resources --ignore-not-found --context "${context}" --namespace "${namespace}" -l nix-helm-name="${name}"
      '';
      update = ''
        ${kubectl} apply -f ${output} --context "${context}" --namespace "${namespace}"
      '';
      delete = ''
        resources="$(echo -n "$(${kubectl} api-resources --verbs=delete -o name)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
        ${kubectl} delete $resources --ignore-not-found --context "${context}" --namespace "${namespace}" -l nix-helm-name="${name}"
      '';
    };

  mkEntry = { name, type, values ? { }, create, read, update, delete, output ? null }:
    {
      inherit name type output values;
      create = pkgs.writeShellScriptBin "create.sh" create;
      read = pkgs.writeShellScriptBin "read.sh" read;
      update = pkgs.writeShellScriptBin "update.sh" update;
      delete = pkgs.writeShellScriptBin "delete.sh" delete;

    };


  nixHelm = {
    inherit mkKube mkHelm;
  } // utils;
in
nixHelm
