# musu-devkit

> Un projet neuf naît déjà gardé.

Une commande pose un projet équipé : flake, direnv, secrets chiffrés injectés
par commande, sondes de vivacité — et les deux garde-fous du poste, `shhh` et
`aegis`, câblés dès la première minute plutôt qu'ajoutés après le premier
incident.

```sh
nix run github:Musubi42/musu-devkit              # interactif
nix flake init -t github:Musubi42/musu-devkit    # substrat brut
```

---

## Pourquoi deux chemins

`nix flake init -t` copie le template tel quel : reproductible, scriptable, et
il laisse une douzaine de placeholders qu'on oublie toujours en partie. Un
amorceur interactif est agréable et **ne se rejoue pas** — impossible de
reproduire une amorce, donc impossible de la tester.

D'où la superposition : `musu-init` n'est qu'un **générateur d'arguments** pour
la substitution, et il accepte tous ses choix en ligne de commande. Le mode
interactif ne fait que les remplir. Le gauntlet appelle la forme non
interactive — **ce qui est testé est donc ce qui tourne**.

Le template livre un marqueur `.musu-template` : tant qu'il est là, `task
doctor` refuse de dire que le socle est configuré. `musu-init` le supprime ;
après un `nix flake init -t`, il reste, et il liste ce qu'il faut remplacer.

## Ce que ça pose

| | |
|---|---|
| `flake.nix` + `.envrc` | devShell, aucun secret dans l'environnement par défaut |
| `.sops.yaml` + `secrets/` | chiffrement age, une clé par machine |
| `scripts/with-secrets.sh` | déchiffre en mémoire, `exec` la commande — jamais un shell entier |
| `scripts/verify-secrets.sh` | couverture, hygiène, et **vivacité** via les sondes |
| `secrets.probes.sh` | le **seul** fichier propre au projet ; échoue tant qu'il est vide |
| `scripts/guards.sh` | câble et interroge `shhh` et `aegis` |
| `scripts/front-guard.sh` | valeurs exactes **+** `shhh scan` sur le bundle produit |
| `scripts/doctor.sh` | l'état complet, sans jamais déchiffrer une valeur |
| `GARDE-FOUS.md` | la doctrine, parce que les commandes s'oublient |

## La doctrine, en une ligne

**Sécurité positive** : il faut un signal pour assouplir, jamais pour protéger.
Et aucun filet ne parie sur la reconnaissance de la menace — `aegis` refuse
d'énumérer les commandes dangereuses, `front-guard` cherche les valeurs qu'on
possède plutôt que des motifs de clés. Détail dans
[`templates/socle/GARDE-FOUS.md`](templates/socle/GARDE-FOUS.md).

## Le gauntlet

```sh
./gauntlet/run.sh
```

Sept scénarios, 31 assertions. **Chacun est un défaut qui a existé**, pas une
hypothèse — trois d'entre eux sont des faux verts écrits de bonne foi et
trouvés seulement en instanciant un deuxième projet ou en lisant un code de
sortie :

- un `doctor` qui cherchait des placeholders écrits en dur… que l'amorceur
  substituait aussi, corrompant le contrôle ;
- un `aegis status` qui répondait « protégé » pour un dossier jamais enregistré,
  parce qu'il liste tous les projets et sort toujours en 0 ;
- un garde-fou de bundle vérifié en rejouant la fuite avec une **vraie** clé.

Le gauntlet n'installe aucun hook et n'écrit que dans un bac temporaire.

## Versions épinglées

`shhh` et `aegis` sont construits depuis leurs sources, à une révision fixe. Un
garde-fou dont on ne connaît pas la version est un garde-fou dont on ne connaît
pas la couverture.

| | version | source |
|---|---|---|
| shhh | v0.3.0 | github.com/Musubi42/shhh |
| aegis | `refonte/engine-v1` @ `9f3d379` (2026-07-03) | codeberg.org/Musubi42/Aegis |

⚠️ **aegis est épinglé en retard sur la copie locale.** Le dépôt public n'a pas
de tag, et le travail récent (ADR 0012, l'UI) n'y est pas poussé. On épingle
`refonte/engine-v1` plutôt que `main` parce que c'est la branche où la refonte
engine v1 est livrée et le gauntlet S1 vert. Avancer cette révision est une
décision à prendre dans le dépôt aegis, pas ici.

## Limites

- Éprouvé sur **un seul poste** (macOS, Apple Silicon). Le socle déclare
  quatre systèmes ; aucun n'a été exercé sauf `aarch64-darwin`.
- `guards install` n'est **pas** couvert par le gauntlet : il écrit dans
  `~/.config/aegis` et dans les réglages de Claude Code, ce qu'un test ne doit
  pas faire. Ce chemin-là reste vérifié à la main.
- Le rôle `ci` existe dans `role.sh` et n'a jamais tourné.
- Aucune rotation de recipient age n'a été exercée.
