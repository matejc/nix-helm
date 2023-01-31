{
  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
      nixpkgsFor = forAllSystems (system: nixpkgs.legacyPackages.${system});

      mkHelmish = system: nixpkgsFor.${system}.callPackage ./src { };
      examples = helmish: {
        sample = import ./examples/nginx { inherit helmish; };
      };
    in
    {

      builders = forAllSystems (system: mkHelmish system);
      deployments = forAllSystems (system: examples self.builders.${system});

      apps = forAllSystems (system:
        builtins.mapAttrs (_: v: { type = "app"; program = nixpkgs.lib.getExe v; }) (nixpkgsFor.${system}.callPackage ./src/apps.nix { })
      );

    };
}
