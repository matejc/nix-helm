{ pkgs
, lib
}:
let
  kubectl = lib.getExe pkgs.kubectl;
  helm = lib.getExe (pkgs.wrapHelm pkgs.kubernetes-helm {
    plugins = with pkgs.kubernetes-helmPlugins; [ helm-diff ];
  });

  toYamlFile = name: content: pkgs.runCommand "yaml-to-json"
    {
      buildInputs = [ pkgs.gojsontoyaml ];
      json = builtins.toJSON content;
      passAsFile = [ "json" ];
    } "cat $jsonPath | gojsontoyaml > $out";

  mkHelm = { name, chart, namespace, context, kubeconfig, values, templates ? { } }:
    let
      output = mkOutput { inherit name values chart templates; };
      mkHelmCommand = operation: args: pkgs.writeShellScriptBin "${lib.replaceChars [" "] ["-"] operation}-${namespace}-${name}.sh" ''
        ${helm} ${operation} ${name} --namespace "${namespace}" --kubeconfig "${kubeconfig}" --kube-context "${context}" ${args}
      '';

      plan = mkHelmCommand "diff upgrade" ''--values "${output}/values.yaml" "${output}"'';
    in
    {
      inherit name output values plan;
      install = mkHelmCommand "install" ''--values "${output}/values.yaml" "${output}"'';
      status = mkHelmCommand "status" "";
      uninstall = mkHelmCommand "uninstall" "";
      upgrade = pkgs.writeShellScriptBin "upgrade-${namespace}-${name}.sh" ''
        ${lib.getExe plan}

        echo "Do you wish to apply these changes?"
        select yn in "Yes" "No"; do
            case $yn in
                Yes ) ${lib.getExe (mkHelmCommand "upgrade" ''--values "${output}/values.yaml" "${output}"'')}; break;;
                No ) exit;;
            esac
        done
      '';
      k9s = pkgs.writeShellScriptBin "k9s-${namespace}.sh" ''
        ${lib.getExe pkgs.k9s} --kubeconfig "${kubeconfig}" --namespace "${namespace}" $@
      '';
    };

  mkOutput = { name, values ? null, chart, templates ? { } }:
    let
      valuesYaml = toYamlFile "${name}-values.yaml" values;
      templatesCmdMapper = path: value:
        let
          file =
            if lib.isAttrs value then
              toYamlFile "nix-helm-template-${path}.yaml" value
            else value;
        in
        "cp ${file} $out/templates/${path}";
      templatesCmd = lib.concatStringsSep "\n" (lib.mapAttrsToList templatesCmdMapper templates);
    in
    pkgs.runCommand "nix-helm-outputs-${name}" { } ''
      cp -R ${chart} $out
      chmod -R u+w $out
      cp ${valuesYaml} $out/values.yaml

      mkdir -p $out/templates
      ${templatesCmd}
    '';

  nixHelm = {
    inherit mkHelm toYamlFile;
  };
in
nixHelm
