{ pkgs, lib }:
let
  inherit (lib) getExe readFile;
  pythonScript = ./json2nix.py;
  python = pkgs.python3.withPackages (it: [ it.pyyaml ]);

in
rec {
  yaml2nix = pkgs.writeShellScriptBin "json2nix" ''
    ${getExe python} ${pythonScript} $@
  '';

  yaml2nix-flatten = pkgs.writeShellScriptBin "json2nix-flatten" ''
    ${getExe python} ${pythonScript} --flatten $@
  '';


}
