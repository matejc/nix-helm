{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib }:
with lib;
with pkgs;
let
  yamlFile = name: yaml: path: if path != null then path else builtins.toFile "${name}.yaml" yaml;
  jsonFile = yamlFile: runCommand "yaml-to-json"
    {
      buildInputs = [ remarshal ];
    } ''
    jsonFile="$out"
    echo -n "[" > $jsonFile

    delimiter="---"
    s=$(cat ${yamlFile})$delimiter
    while [[ $s ]]
    do
        yaml="''${s%%"$delimiter"*}"
        echo -n "$yaml" | remarshal -i - -if yaml -of json >> $jsonFile
        s=''${s#*"$delimiter"};
    done;

    sed -i ':a $!N; s/\n/,/; ta' $jsonFile
    sed -i 's|$|]|' $jsonFile
  '';

  string = value:
    "\"${value}\"";

  any = value:
    toString value;

  bool = value:
    if value then "true" else "false";

  list = value:
    "[${concatMapStringsSep " " nix2string value}]";

  attrs = value:
    if value == { }
    then
      "{ }"
    else
      "{ ${concatStringsSep "; " (mapAttrsToList (n: v: "${n} = ${nix2string v}") value)}; }";

  nix2string = v:
    if isString v then string v
    else if v == null then "null"
    else if isInt v then any v
    else if isBool v then bool v
    else if isList v then list v
    else if (builtins.typeOf v) == "path" then any v
    else if lib.isAttrs v then attrs v
    else throw "Attribute has unsupported type (${builtins.typeOf v})!";

  nixFile = jsonFile: runCommand "toNix"
    {
      buildInputs = [ nix perl nix-beautify ];
    } ''
    nixFile="$out"
    echo '${nix2string (builtins.fromJSON (builtins.readFile jsonFile))}' | perl -ne 's/(?!\ )([A-Za-z0-9\-\/]+[\.\/]+[A-Za-z0-9\-\/]+)(?=\ =\ )/"$1"/g; print;' | sed "s/;/;\n/g" | sed "s/{/{\n/g" | nix-beautify > $nixFile
  '';

  nix-beautify = stdenv.mkDerivation {
    name = "nix-beautify";
    src = fetchurl {
      url = "https://raw.githubusercontent.com/nixcloud/nix-beautify/5ea527d95aaae3a131882f9f5d5babfa28ddebd7/nix-beautify.js";
      sha256 = "05rmdql1vgn3ghx0mmh7v25s8c1rsd3541ipkn0ck1j282vzs9n2";
    };
    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      echo "#!${nodejs}/bin/node" > $out/bin/nix-beautify
      cat $src >> $out/bin/nix-beautify
      chmod +x $out/bin/nix-beautify
    '';
  };

  scriptFun = arg: ''
    #!${stdenv.shell}
    set -e
    if [[ -z "$1" ]]
    then
      inputFile="$(mktemp)"
      cat > $inputFile
      outputFile="$(${nix}/bin/nix-build ${./utils.nix} --no-out-link -A ${arg} --arg path $inputFile)"
      test -f $inputFile && rm $inputFile
    else
      outputFile="$(${nix}/bin/nix-build ${./utils.nix} --no-out-link -A ${arg} --arg path $1)"
    fi
    cat $outputFile
  '';

  scriptBin = arg: writeScriptBin arg (scriptFun arg);

  nix2yaml = config: runCommand "to-yaml"
    {
      buildInputs = [ remarshal ];
    } ''
    remarshal -i ${writeText "to-json" (builtins.toJSON config)} -if json -of yaml > $out
  '';

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
in
{
  inherit retryScript;
  yaml2nix = { name ? "default", yaml ? null, path ? null }:
    nixFile (jsonFile (yamlFile name yaml path));
  nix2yaml = { name ? "default", nix ? null, path ? null }:
    nix2yaml (if path != null then import path else nix);
  loadJSON = { path }:
    builtins.fromJSON (builtins.readFile path);
  loadYAML = { name ? "default", yaml ? null, path ? null }:
    builtins.fromJSON (builtins.readFile (jsonFile (yamlFile name yaml path)));
  toYAML = { nixes }:
    concatMapStringsSep "\n---\n" (v: builtins.readFile (nix2yaml v)) nixes;

  toYamlFile = { name, attrs, passthru ? { } }:
    pkgs.stdenv.mkDerivation {
      inherit name passthru;
      phases = "phase";
      phase = ''
        cp ${nix2yaml attrs} $out
      '';
    };
  yaml2nixScript = scriptBin "yaml2nix";
  nix2yamlScript = scriptBin "nix2yaml";
  toBase64 = value:
    builtins.readFile
      (pkgs.runCommand "to-base64"
        {
          buildInputs = [ pkgs.coreutils ];
        } "echo -n '${value}' | base64 -w0 > $out");
}
