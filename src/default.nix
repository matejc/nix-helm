{ pkgs
, lib
}:
let
  kubectl = lib.getExe pkgs.kubectl;
  helm = lib.getExe (pkgs.wrapHelm pkgs.kubernetes-helm {
    plugins = with pkgs.kubernetes-helmPlugins; [ helm-diff ];
  });

  partitionAttrs = fn: values:
    lib.foldlAttrs
      (acc: name: value:
        if fn name value then {
          inherit (acc) wrong;
          right = acc.right // { ${name} = value; };
        } else {
          inherit (acc) right;
          wrong = acc.wrong // { "${name}" = value; };
        })
      { right = { }; wrong = { }; }
      values;

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
    };

  mkOutput =
    { chart
    , name
    , templates ? { }
    , values ? null
    }:
    let

      fileNameToEnvVar = builtins.replaceStrings [ "." "-" ] [ "_" "_" ];
      templates' = lib.mapAttrs' (n: v: { name = n; value = if builtins.isPath v then v else builtins.toJSON v; }) templates;

      templatesPartitions = (partitionAttrs (_: builtins.isPath) (lib.mapAttrs' (n: v: { name = fileNameToEnvVar n; value = v; }) templates'));
      templatesNames = lib.mapAttrs' (n: _: { name = "${fileNameToEnvVar n}Name"; value = n; }) templates';

      fileTemplates = templatesPartitions.right;
      attrTemplates = templatesPartitions.wrong;

    in
    derivation ({
      inherit name;
      inherit (pkgs) system;
      builder = "${pkgs.busybox}/bin/sh";
      args = [ ./nix-helm.builder.sh ];
      __ignoreNulls = true;
      preferLocalBuild = true;
      allowSubstitutes = false;

      PATH = lib.makeBinPath [ pkgs.busybox pkgs.gojsontoyaml ];

      chartPath = chart;
      #chart = if chart == null then null else builtins.toJSON chart;
      values = if values == null then null else builtins.toJSON values;

      passAsFile = [ "values" ] ++ builtins.attrNames attrTemplates;
      attrTemplates = builtins.attrNames attrTemplates;
      fileTemplates = builtins.attrNames fileTemplates;
    } // fileTemplates // attrTemplates // templatesNames);


  nixHelm = {
    inherit mkHelm mkOutput;
  };
in
nixHelm
