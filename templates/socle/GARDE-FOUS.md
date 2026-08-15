# Garde-fous de ce projet

Trois filets, une seule doctrine. Ce document explique la doctrine, parce que
les trois commandes s'oublient et que le raisonnement, lui, se retient.

## La doctrine : sécurité positive

Terme ferroviaire. Un système à sécurité positive atteint l'état sûr par
**absence** d'énergie : plus de liaison entre deux wagons → le frein serre. On
n'attend pas un signal pour freiner ; l'absence de signal **est** l'ordre de
freiner.

Appliqué ici : **il faut un signal pour assouplir, jamais pour protéger.**

| Surface | Filet | Ce qui se passe par défaut |
|---|---|---|
| Fuite vers le modèle | `shhh` | la sortie d'outil est rédigée **avant** d'atteindre le modèle |
| Destruction par l'agent | `aegis` | snapshot **avant** chaque action, sans chercher à savoir si elle est dangereuse |
| Secret en clair | `sops` + `with-secrets.sh` | rien n'est chargé ; il faut une commande explicite |

## Le corollaire, qui est la vraie idée

**Aucun des trois ne parie sur la reconnaissance de la menace.**

- `aegis` refuse d'énumérer les commandes destructrices — une liste est toujours
  incomplète, et un `rm` obfusqué ou un flag qui change de sens la périment. Il
  garde une copie récente, et se moque de *ce qui* a détruit.
- `with-secrets.sh` ne cherche pas à savoir quels processus sont de confiance :
  il borne la fuite à la durée d'une commande.
- `front-guard.sh` ne cherche pas des motifs de clés, il cherche **les valeurs
  qu'on possède** dans les octets produits.

Un contrôle qui repose sur la reconnaissance échoue exactement sur le cas qu'on
n'avait pas prévu — c'est-à-dire sur celui qui arrive.

## Les commandes

```sh
task guards:status      # que protège-t-on, ici, maintenant ?
task guards:install     # câble shhh et aegis sur ce projet
task guards:scan        # secrets présents dans l'arbre de travail
task guards:audit       # ce qui a DÉJÀ atteint le modèle
task doctor             # l'état complet du socle
task secrets:verify     # les clés sont-elles VIVANTES (pas juste présentes) ?
task front:guard        # un secret a-t-il fini dans le bundle ?
task front:guard:test   # le garde-fou détecte-t-il vraiment ?
```

## Trois pièges, rencontrés et corrigés

Ils ne sont pas théoriques : chacun a produit un affichage vert sur une
situation qui ne l'était pas.

**1. Un binaire présent ne prouve pas qu'il est câblé.** `shhh` dans le `PATH`
ne dit rien du hook. `guards status` regarde le réglage, pas le binaire.

**2. « Installé quelque part » n'est pas « protège ici ».** `aegis status`
liste **tous** les projets enregistrés et sort en 0 : un `if aegis status`
répond « protégé » dès qu'aegis connaît un projet, fût-ce une démo dans `/tmp`.
On demande si *ce* chemin est dans la liste.

**3. Un contrôle qui ne peut pas échouer n'est pas un contrôle.** Sans sondes
dans `secrets.probes.sh`, `secrets:verify` ne vérifie que la présence des clés —
et afficherait « tout est vert » sur un jeu de clés entièrement mortes. Il
échoue donc tant que le fichier est vide.

Le fil commun : **une ligne verte que personne n'a vérifiée est pire que pas de
ligne du tout.** Elle ne laisse pas seulement passer le défaut, elle décourage
de le chercher.

## Ce que les filets ne couvrent pas

- `shhh` peut réécrire la sortie d'un outil, **pas votre prompt** ni la réponse
  du modèle. Coller une clé dans une question reste une fuite.
- `aegis` protège le travail **non committé** contre la destruction. Ce n'est ni
  une sauvegarde hors-machine, ni un remplaçant de `git`.
- `sops` chiffre au repos et pour le transport. Une clé déchiffrée dans un
  processus reste lisible par ce processus — c'est précisément pourquoi
  l'injection se fait par commande et non par shell.
- Aucun des trois ne protège contre une clé **déjà** commitée. Celle-là est
  brûlée : on la rotate, on ne réécrit pas l'historique.
