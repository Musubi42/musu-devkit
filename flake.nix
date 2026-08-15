{
  description = "musu-devkit — un projet neuf naît déjà gardé";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # ⚠️ LES DEUX CHEMINS D'AMORÇAGE, ET POURQUOI IL EN FAUT DEUX
      #
      #   nix flake init -t <devkit>      → le substrat, reproductible, scriptable
      #   nix run <devkit>                → l'interactif, qui écrit par-dessus
      #
      # L'interactif seul ne se rejoue pas : on ne peut ni reproduire une amorce
      # ni la tester. Le template seul est aride — il faut relire six fichiers
      # pour savoir quoi renommer. En couches, l'interactif n'est qu'un
      # générateur d'arguments pour la couche basse, et c'est cette couche-là
      # que le gauntlet exerce.

      templates = {
        default = self.templates.socle;
        socle = {
          path = ./templates/socle;
          description = "Socle gardé : flake + direnv + sops/age + sondes + shhh + aegis";
          welcomeText = ''
            Socle posé. Trois choses avant de coder :

              1. direnv allow
              2. task guards:install     # câble shhh et aegis sur ce projet
              3. task doctor             # dit ce qui manque, et rien d'autre

            Les secrets ne sont chargés par aucun shell : ils s'injectent par
            commande (`task dev`). Voir GARDE-FOUS.md.
          '';
        };
      };

      packages = forAllSystems (pkgs: rec {
        # Les deux garde-fous, épinglés. Ils ne sont pas des dépendances du
        # code produit : ce sont des outils de poste, que le devkit rend
        # disponibles pour que `task guards:install` ne dépende pas de ce que
        # la machine a bien voulu installer.
        shhh = pkgs.callPackage ./pkgs/shhh.nix { };
        aegis = pkgs.callPackage ./pkgs/aegis.nix { };

        # L'amorce interactive.
        musu-init = pkgs.writeShellApplication {
          name = "musu-init";
          runtimeInputs = with pkgs; [ coreutils gnused gnugrep findutils ];
          text = builtins.readFile ./lib/musu-init.sh;
        };

        default = musu-init;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.system}.musu-init}/bin/musu-init";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            self.packages.${pkgs.system}.shhh
            self.packages.${pkgs.system}.aegis
          ] ++ (with pkgs; [ go-task sops age jq shellcheck ]);
        };
      });
    };
}
