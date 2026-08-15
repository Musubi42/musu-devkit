# Sondes fournisseur de CE projet. Sourcé par scripts/verify-secrets.sh.
#
# ⚠️ NE PAS EXÉCUTER DIRECTEMENT : hérite de son appelant `sget <NOM>` (lit une
# valeur dans le texte déchiffré, gardé en mémoire), `ok`, `bad`, `warn`, `note`.
#
# C'est le SEUL fichier de la mécanique de secrets qui change d'un dépôt à
# l'autre. Tout le reste — scripts/, Taskfile, .envrc, .sops.yaml — est
# générique. Ce qui se recopie vingt fois doit être petit.
#
# ⚠️ POURQUOI CE FICHIER ÉCHOUE TANT QU'IL EST VIDE
#
# Sans sonde, verify-secrets.sh ne vérifie que la PRÉSENCE des clés. Il
# afficherait « tout est vert » sur un jeu de clés entièrement mortes — soit
# exactement la situation d'un projet dormant qu'on rouvre, celle où l'on va
# perdre quarante minutes à déboguer du code applicatif innocent.
# Un contrôle qui ne peut pas échouer n'est pas un contrôle.
#
# RÈGLES D'UNE SONDE
#   · la lecture authentifiée la moins chère du fournisseur ;
#   · aucune mutation. Une sonde qui envoie un email n'est pas une sonde ;
#   · verdict par code de retour, pas par contenu — les corps de réponse
#     changent, les codes HTTP beaucoup moins ;
#   · `note` porte l'URL de la console. C'est le champ qui transforme
#     « bloqué quarante minutes » en « cliquer, régénérer, pousser » ;
#   · jamais la valeur dans une sortie.
#
# Table des points de vérification par fournisseur : doc 03 §10.
#
# ⚠️ L'EXEMPLE ÉVITE `curl -u`, ET CE N'EST PAS UN DÉTAIL DE STYLE.
#
# La règle gitleaks `curl-auth-user` signale tout `-u "..."` dans un appel
# curl. Elle avait donc raison sur la forme et tort sur le fond : elle
# marquait ce fichier — un COMMENTAIRE, avec une variable et aucune valeur —
# comme contenant un secret, dans chaque projet nouvellement amorcé.
#
# Un socle dont les propres fichiers déclenchent son propre scanner apprend
# dès le premier jour à ignorer le scanner. C'est plus coûteux qu'un exemple
# moins canonique. L'exemple utilise donc un fournisseur à jeton porteur.
#
# (Stripe, lui, s'authentifie bien par `-u "$key:"`. Si vous écrivez cette
# sonde-là, `task guards:scan` la signalera : c'est attendu, et c'est ce que
# `shhh ignore` sert à consigner — explicitement, une fois, en connaissance
# de cause.)
#
# Exemple, à adapter puis à retirer :
#
#   _probe_cloudflare() {
#     local key code
#     key="$(sget CLOUDFLARE_API_TOKEN)"
#     [ -n "$key" ] || { bad "CLOUDFLARE_API_TOKEN absent"; return; }
#     code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
#               -H "Authorization: Bearer $key" \
#               https://api.cloudflare.com/client/v4/user/tokens/verify)"
#     case "$code" in
#       200) ok "Cloudflare — jeton vivant" ;;
#       401) bad "Cloudflare — jeton MORT (401)"
#            note "console : https://dash.cloudflare.com/profile/api-tokens" ;;
#       *)   warn "Cloudflare — HTTP $code inattendu" ;;
#     esac
#   }
#   _probe_cloudflare

bad "aucune sonde écrite — verify-secrets.sh ne peut pas dire si les clés sont VIVANTES"
note "remplir secrets.probes.sh, puis retirer cette ligne"
