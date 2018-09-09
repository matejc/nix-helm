{ name, vars ? import ../vars.nix, ... }@argv: [{
  files = vars.statics.files;
  service.type = "NodePort";
}]
