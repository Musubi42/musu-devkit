# aegis — filet de sécurité positive sur le travail non committé.
#
# ⚠️ CE QUI EST ÉPINGLÉ ICI N'EST PAS CE QUI EST SUR LE DISQUE.
#
# Au 2026-08-15, le dépôt public Codeberg est en retard sur la copie locale :
#   · local  HEAD  7934447  « aegis ui — la salle de contrôle » (ADR 0012)
#   · public refonte/engine-v1  9f3d379  2026-07-03
#   · public main               cc608e3  2026-07-01
#
# On épingle `refonte/engine-v1` et non `main`, parce que c'est la branche où
# le README annonce la refonte engine v1 livrée et le scénario canonique
# `gauntlet/S1` vert. `main` est antérieur à cette refonte.
#
# Conséquence à connaître : un `nix run` de ce devkit sur une autre machine
# n'installera PAS la version qui tourne sur le Mac. Tant que le travail local
# n'est pas poussé et qu'aucun tag n'existe, c'est le mieux qui soit
# reproductible — et un devkit non reproductible ne vaut rien. Mettre à jour
# cette révision est une décision d'opérateur, dans le dépôt aegis.
{ lib, buildGoModule, fetchzip }:

buildGoModule rec {
  pname = "aegis";
  version = "0-unstable-2026-07-03";
  rev = "9f3d379e7e7b47f8325c7817ca05f29af636de6f";

  src = fetchzip {
    url = "https://codeberg.org/Musubi42/Aegis/archive/${rev}.tar.gz";
    hash = "sha256-BMegpdWeHRjp94COqFy0Yq7sOxYd4vM1Votb4ucUJsw=";
  };

  vendorHash = "sha256-+lF44HjDJuVThoOqvmx8yA3U9MBR+p4PsHO0SDcreXM=";

  # Le gauntlet exige un dépôt git réel et un binaire construit ; il ne tourne
  # pas dans le bac à sable de nix. Il se lance à la main : `make gauntlet`.
  doCheck = false;

  meta = {
    description = "Garde-fou git à sécurité positive : snapshot avant chaque action d'agent, revert sélectif";
    homepage = "https://codeberg.org/Musubi42/Aegis";
    mainProgram = "aegis";
  };
}
