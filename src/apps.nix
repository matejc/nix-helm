{ pkgs, lib }:
let
  inherit (lib) getExe readFile;
  pythonScript = ./json2nix.py;

in
rec {
  json2nix = pkgs.writeShellScriptBin "json2nix" ''
    ${getExe pkgs.python3} ${pythonScript} $@
  '';

  json2nix-flatten = pkgs.writeShellScriptBin "json2nix-flatten" ''
    ${getExe pkgs.python3} ${pythonScript} --flatten $@
  '';

  yaml2nix = pkgs.writeShellScriptBin "yaml2nix" ''
    ${getExe pkgs.yaml2json} < $1 > /tmp/yaml2nix.tmp
    ${getExe json2nix} /tmp/yaml2nix.tmp
    rm /tmp/yaml2nix.tmp
  '';

  yaml2nix-flatten = pkgs.writeShellScriptBin "yaml2nix-flatten" ''
    ${getExe pkgs.yaml2json} < $1 > /tmp/yaml2nix.tmp
    ${getExe json2nix-flatten} /tmp/yaml2nix.tmp
    rm /tmp/yaml2nix.tmp
  '';

}
