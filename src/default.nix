{ pkgs
, lib
}:
let
  kubectl = lib.getExe pkgs.kubectl;
  helm = lib.getExe pkgs.kubernetes-helm;
  utils = import ./utils.nix { inherit pkgs lib; };

  mkHelm = { name, chart, namespace, context, kubeconfig, values, templates ? { } }:
    let
      output = mkOutput { inherit name values chart templates; };
      mkHelmCommand = operation: args: pkgs.writeShellScriptBin "${operation}-${namespace}-${name}.sh" ''
        ${helm} ${operation} ${name} --namespace "${namespace}" --kubeconfig "${kubeconfig}" --kube-context "${context}" ${args}
      '';
    in
    {
      inherit name output values;
      install = mkHelmCommand "install" ''--values "${output}/values.yaml" "${output}"'';
      status = mkHelmCommand "status" "";
      upgrade = mkHelmCommand "upgrade" ''--values "${output}/values.yaml" "${output}"'';
      uninstall = mkHelmCommand "uninstall" "";
    };

  #  mkOutput = { name, values ? null, chart, templates ? {} }:
  #    utils.toYamlFile { name = "${name}.yaml"; attrs = values; passthru = { inherit name; }; };

  mkOutput = { name, values ? null, chart, templates ? { } }:
    let
      valuesYaml = utils.toYamlFile { name = "${name}-values.yaml"; attrs = values; passthru = { inherit name; }; };
      templatesCmdMapper = path: value:
        let
          file =
            if lib.isAttrs value then
              utils.toYamlFile { name = "nix-helm-template-${path}.yaml"; attrs = value; }
            else value;
        in
        "ln -s ${file} $out/templates/${path}";
      templatesCmd = lib.concatStringsSep "\n" (lib.mapAttrsToList templatesCmdMapper templates);
    in
    pkgs.runCommand "nix-helm-outputs-${name}" { } ''
      cp -R ${chart} $out
      chmod -R u+w $out
      ln -sf ${valuesYaml} $out/values.yaml

      mkdir -p $out/templates
      ${templatesCmd}
    '';

  #  mkKube = { name, namespace, context, resources, retryTimes ? 5 }:
  #    let
  #      r = map (resource: lib.recursiveUpdate resource { metadata.labels.nix-helm-name = name; }) resources;
  #      output = mkOutput { inherit name; resources = r; };
  #    in
  #    {
  #      inherit name output;
  #      type = "kube";
  #      create = ''
  #        ${utils.retryScript} ${toString retryTimes} ${kubectl} create -f ${output} --context "${context}" --namespace "${namespace}"
  #      '';
  #      read = ''
  #        resources="$(echo -n "$(${kubectl} api-resources --verbs=get -o name | ${pkgs.gnugrep}/bin/grep -v componentstatus)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
  #        ${kubectl} get $resources --ignore-not-found --context "${context}" --namespace "${namespace}" -l nix-helm-name="${name}"
  #      '';
  #      update = ''
  #        ${kubectl} apply -f ${output} --context "${context}" --namespace "${namespace}"
  #      '';
  #      delete = ''
  #        resources="$(echo -n "$(${kubectl} api-resources --verbs=delete -o name)" | ${pkgs.coreutils}/bin/tr '\n' ',')"
  #        ${kubectl} delete $resources --ignore-not-found --context "${context}" --namespace "${namespace}" -l nix-helm-name="${name}"
  #      '';
  #    };

  #  mkEntry = { name, type, values ? { }, create, read, update, delete, output ? null }:
  #    {
  #      inherit name type output values;
  #      create = pkgs.writeShellScriptBin "create.sh" create;
  #      read = pkgs.writeShellScriptBin "read.sh" read;
  #      update = pkgs.writeShellScriptBin "update.sh" update;
  #      delete = pkgs.writeShellScriptBin "delete.sh" delete;
  #
  #    };

  mkKube = abort "TODO: Implement this";

  nixHelm = {
    inherit mkKube mkHelm;
  } // utils;
in
nixHelm
