{
  description = "A very basic flake";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgsAll = nixpkgs.legacyPackages;
      helmish = { ${system} = mkHelmish pkgsAll.${system}; };

      mkHelmish = pkgs: pkgs.callPackage ./src { };
      examples = helmish:
        let
        in {
          #mkHelm = {environment, name, chart, namespace, context, values }:
          sample = helmish.mkHelm {
            environment = "environment";
            name = "name";
            chart = ./examples/nginx;
            namespace = "test";
            context = "arn:aws:eks:us-east-1:926093910549:cluster/lace-prod-us-east-1";
            values = {
              "fullnameOverride" = "";
              "image" = {
                "pullPolicy" = "IfNotPresent";
                "repository" = "nginx";
                "tag" = "";
              };
              "nameOverride" = "";
              "replicaCount" = 1;
              "service" = {
                "port" = 80;
                "type" = "ClusterIP";
              };
              "serviceAccount" = {
                "annotations" = { };
                "create" = true;
                "name" = "";
              };
            };
          };

        };
    in
    {

      packages.${system} = helmish.${system};

      deployments.${system} = examples helmish.${system};

    };
}
