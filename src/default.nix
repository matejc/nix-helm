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
      output = mkOutput { inherit name values chart templates namespace kubeconfig context; };
    in
    {
      inherit name output values;
    };

  mkOutput =
    { chart
    , name
    , templates ? { }
    , values ? null
    , namespace
    , kubeconfig
    , context
    }:
    let

      fileNameToEnvVar = builtins.replaceStrings [ "." "-" ] [ "_" "_" ];
      templates' = lib.mapAttrs' (n: v: { name = n; value = if builtins.isPath v then v else builtins.toJSON v; }) templates;

      templatesPartitions = (partitionAttrs (_: builtins.isPath) (lib.mapAttrs' (n: v: { name = fileNameToEnvVar n; value = v; }) templates'));
      templatesNames = lib.mapAttrs' (n: _: { name = "${fileNameToEnvVar n}Name"; value = n; }) templates';

      fileTemplates = templatesPartitions.right;
      attrTemplates = templatesPartitions.wrong;

      # Helm Boilerplate
      helmArgs = ''\
        --namespace "${namespace}" \
        --kubeconfig "${kubeconfig}" \
        --kube-context "${context}" \
      '';

      helmArgsWithValues = helmArgs + ''
        --values "${placeholder "out"}/values.yaml" \
        "${placeholder "out"}"
      '';

      bashConfirmationDialog = name: successCmd: cancelMsg: ''
        echo -e "\n\n\e[1mDo you wish to apply these changes to '\e[34m${name}\e[0m\e[1m'?\e[0m"
        echo -e "  Only 'yes' will be accepted to approve.\n"
        read -p $'\e[1m  Enter a value: \e[0m' choice
        case "$choice" in
          yes )
            echo
            ${helm} ${successCmd}
          ;;
          * ) echo -e '\n${cancelMsg}'; exit 1;;
        esac
      '';

      # Helm Commands
      __commandApply = ''
        #! ${pkgs.bash}/bin/sh
        ${placeholder "out"}/bin/plan.sh
        ${bashConfirmationDialog name "upgrade --install ${name} ${helmArgsWithValues}" "Apply canceled"}
      '';

      __commandDestroy = ''
        #! ${pkgs.bash}/bin/sh
        ${bashConfirmationDialog name "uninstall ${name} ${helmArgs}" "Destroy canceled"}
      '';

      __commandPlan = ''
        #! ${pkgs.bash}/bin/sh
        ${helm} diff upgrade ${name} --install  ${helmArgsWithValues}
      '';

      __commandStatus = ''
        #! ${pkgs.bash}/bin/sh
        ${helm} status ${name} ${helmArgs}
      '';

    in
    derivation ({
      inherit __commandApply __commandDestroy __commandPlan __commandStatus;
      inherit name;
      inherit (pkgs) system;
      builder = "${pkgs.bash}/bin/sh";
      args = [ ./nix-helm.builder.sh ];
      __ignoreNulls = true;
      preferLocalBuild = true;
      allowSubstitutes = false;

      PATH = lib.makeBinPath [ pkgs.coreutils pkgs.gojsontoyaml ];

      chartPath = chart;
      #chart = if chart == null then null else builtins.toJSON chart;
      values = if values == null then null else builtins.toJSON values;

      passAsFile = [ "__commandApply" "__commandDestroy" "__commandPlan" "__commandStatus" "values" ] ++ builtins.attrNames attrTemplates;
      attrTemplates = builtins.attrNames attrTemplates;
      fileTemplates = builtins.attrNames fileTemplates;
    } // fileTemplates // attrTemplates // templatesNames);


  nixHelm = {
    inherit mkHelm mkOutput;
  };
in
nixHelm
