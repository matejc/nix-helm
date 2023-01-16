{ pkgs
, lib
}:
let
  kubectl = "${pkgs.kubernetes}/bin/kubectl";
  helm = "${pkgs.kubernetes-helm}/bin/helm";
  utils = import ./utils.nix { inherit pkgs lib; };

  mkHelm = { environment, name, chart, namespace, context, values }:
    let
      output = mkOutput { inherit environment name values; };
    in
    mkEntry {
      inherit environment name output values;
      type = "helm";
      create = ''
        ${helm} install --namespace "${namespace}" --kube-context "${context}" --values "${output}" "${name}-${environment}" "${chart}"
      '';
      read = ''
        ${helm} status "${name}-${environment}" --kube-context "${context}"
      '';
      update = ''
        ${helm} upgrade --recreate-pods --namespace "${namespace}" --kube-context "${context}" --values "${output}" "${name}-${environment}" "${chart}"
      '';
      delete = ''
        ${helm} delete "${name}-${environment}" --purge --kube-context "${context}"
      '';
    };

  mkOutput = { environment, name, values ? null }:
    utils.toYamlFile { name = "${name}-${environment}.yaml"; attrs = values; passthru = { inherit environment name; }; };

  mkKube = { environment, name, namespace, context, resources, retryTimes ? 5 }:
    let
      r = map (resource: lib.recursiveUpdate resource { metadata.labels.nix-helm-name = "${name}-${environment}"; }) resources;
      output = mkOutput { inherit environment name; resources = r; };
    in
    mkEntry {
      inherit environment name output;
      type = "kube";
      create = ''
        ${utils.retryScript} ${toString retryTimes} ${kubectl} create -f ${output} --context "${context}" --namespace "${namespace}"
      '';
      read = ''
        resources="$(echo -n "$(${kubectl} api-resources --verbs=get -o name | ${pkgs.gnugrep}/bin/grep -v componentstatus)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
        ${kubectl} get $resources --ignore-not-found --context "${context}" --namespace "${namespace}" -l nix-helm-name="${name}-${environment}"
      '';
      update = ''
        ${kubectl} apply -f ${output} --context "${context}" --namespace "${namespace}"
      '';
      delete = ''
        resources="$(echo -n "$(${kubectl} api-resources --verbs=delete -o name)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
        ${kubectl} delete $resources --ignore-not-found --context "${context}" --namespace "${namespace}" -l nix-helm-name="${name}-${environment}"
      '';
    };

  mkEntry = { environment, name, type, values ? { }, create, read, update, delete, output ? null }:
    let
      shellApp = name: content: {
        type = "app";
        program = lib.getExe (pkgs.writeShellScriptBin name content);
      };
    in
    {
      inherit environment name type output values;
      create = pkgs.writeShellScriptBin "create.sh" create;
      read = shellApp "read.sh" read;
      update = shellApp "update.sh" update;
      delete = shellApp "delete.sh" delete;

    };


  nixHelm = {
    inherit mkKube mkHelm;
  } // utils;
in
nixHelm
