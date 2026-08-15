{
  description = "MON-PROJET";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # ⚠️ LES GARDE-FOUS VIENNENT DU DEVKIT, PAS DE LA MACHINE.
    #
    # shhh et aegis sont des outils de poste : la tentation est de les
    # installer une fois « globalement » et de ne plus y penser. C'est
    # précisément ce qui produit, six mois plus tard, une machine où le hook
    # tourne dans une version que personne ne peut nommer — et un garde-fou
    # dont on ne connaît pas la version est un garde-fou dont on ne connaît pas
    # la couverture.
    #
    # Les épingler ici les rend versionnés avec le projet, et un `nix flake
    # update` devient une décision datée dans le lock plutôt qu'une dérive.
    musu-devkit.url = "github:Musubi42/musu-devkit";
  };

  outputs = { self, nixpkgs, musu-devkit }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            go-task
            sops
            age
            jq
            curl
            # Décommenter selon les briques du projet :
            # nodejs_24 pnpm_10 postgresql_16 python3 go
          ] ++ [
            musu-devkit.packages.${pkgs.system}.shhh
            musu-devkit.packages.${pkgs.system}.aegis
          ];

          # ⚠️ AUCUN SECRET DANS CE shellHook.
          #
          # Tout ce qui est exporté ici entre dans l'environnement de chaque
          # processus lancé depuis le dossier — éditeur, serveur de langage,
          # agent — et direnv en garde une copie dans DIRENV_DIFF qu'un `unset`
          # ne retire pas. Le devShell pose des outils ; les clés s'injectent
          # par commande (`scripts/with-secrets.sh`).
          shellHook = ''
            export MUSU_ROLE="$(./scripts/role.sh 2>/dev/null || echo dev)"
            echo "MON-PROJET · rôle : $MUSU_ROLE · task --list"
            ./scripts/guards.sh status --quiet || true
          '';
        };
      });
    };
}
