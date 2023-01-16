{
  description = "A very basic flake";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgsAll = nixpkgs.legacyPackages;
      helmish = { ${system} = mkHelmish pkgsAll.${system}; };

      mkHelmish = pkgs: pkgs.callPackage ./src { };
      examples = helmish: {
        sample = import ./examples/nginx { inherit helmish; };
      };
    in
    {

      packages.${system} = helmish.${system};

      deployments.${system} = examples helmish.${system};

    };
}
