{ helmish }:
helmish.mkHelm {
  name = "name";
  chart = ./.;
  namespace = "test";
  context = "arn:aws:eks:us-east-1:926093910549:cluster/lace-prod-us-east-1";
  kubeconfig = "$HOME/.kube/config";

  templates."test.yaml" = {
    apiVersion = "acid.zalan.do/v1";
    kind = "postgresql";
    metadata.name = "test";
    spec = {
      databases.cardano = "cardano";
      numberOfInstances = 2;
      postgresql.version = "14";
      teamId = "test";
      users.cardano = [
        "superuser"
        "createdb"
      ];
      volume.size = "4Gi";
    };
  };

  values = {
    fullnameOverride = "";
    image = {
      pullPolicy = "IfNotPresent";
      repository = "nginx";
      tag = "";
    };
    nameOverride = "";
    replicaCount = 1;
    service = {
      port = 80;
      type = "ClusterIP";
    };
    serviceAccount = {
      annotations = { };
      create = true;
      name = "";
    };
  };
}

