# shhh — redaction des secrets avant qu'ils n'atteignent le modèle.
#
# ⚠️ POURQUOI ON LE PACKAGE ICI PLUTÔT QUE DE SUIVRE SON INSTALLEUR
#
# shhh se distribue par `curl … | sh` ou `go install`. Les deux posent un
# binaire dont personne ne sait, six mois plus tard, quelle version tourne sur
# quelle machine — exactement ce que le parc a décidé d'éviter en mettant un
# flake sur chaque projet (dev-conventions : « flake Nix dès l'init »).
#
# Épingler la version ici a un coût assumé : une mise à jour de shhh demande un
# changement de `version` ET de `hash`/`vendorHash`. C'est le prix d'un
# environnement reproductible, et c'est le même prix que pour toute autre
# dépendance du flake.
{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "shhh";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "Musubi42";
    repo = "shhh";
    rev = "v${version}";
    hash = "sha256-1MTQDmEi4O0s5/B2tRrsyjlHeFg4+MPx+5Ny15KShEA=";
  };

  vendorHash = "sha256-Aq3hHWVuzu0kQVTP3OD+TnaZ3VNJJG7fQ5PjTi0eLTE=";

  subPackages = [ "cmd/shhh" ];

  # Les tests demandent des fixtures et un binaire gitleaks présents dans
  # l'arbre de développement ; ils ne valident pas le paquet.
  doCheck = false;

  meta = {
    description = "Remplace chaque secret par un placeholder typé avant que la sortie d'un outil n'atteigne le modèle";
    homepage = "https://github.com/Musubi42/shhh";
    license = lib.licenses.mit;
    mainProgram = "shhh";
  };
}
