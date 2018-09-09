{ name, vars ? import ../vars.nix, ... }@argv:
/* array of Kubernetes resources */
[{
    apiVersion = "v1";
    kind = "Namespace";
    metadata = {
      labels = {
          name = "apps";
      };
      name = "apps";
    };
}]
