# Mesurer le quota du relais avant de s'engager (Q32, Q33)

**Décision de la Direction du 15/11/2026** : le quota du relais (on a parlé de 5 Gio) n'est **pas** un fait établi. Il se **mesure sur l'hébergement réel** avant tout engagement, et **rien n'est codé en dur** : aucune constante de 5 Gio n'existe dans le code. Tant que le volume des fichiers numérisés n'est pas mesuré, la **destination des fichiers par défaut est « Aucune »** (Q33, réglage `horssite.destinationFichiers`).

## L'outil

```bash
node tools/baguidi/mesurer-quota-relais.mjs --magasin <fichier ou dossier du magasin> --fichiers <dossier des scans> [--quota-gio <n>] [--json]
```

- `--copies-magasin` (7), `--copies-fichiers` (14) et `--bloc` (1 048 576) reprennent les réglages semés ; on peut les surcharger pour simuler.
- Le besoin est donné en **fourchette** : borne basse (une copie de chaque), borne haute (toutes les copies gardées, aucun bloc partagé — la réalité est entre les deux, selon le rythme de changement des scans).
- Le surcoût du chiffrement (28 octets par bloc) est compté.
- **`--quota-gio` est une mesure, pas une valeur du code** : à relever auprès de l'hébergeur (cPanel, « Utilisation du disque », ou `quota -s` en ligne de commande). Sans lui, l'outil dit « quota à relever ».

## Procédure

1. Sur la poste mère : mesurer le magasin et le dossier des scans.
2. Sur l'hébergement : relever l'espace disponible réel (pas celui de l'offre commerciale).
3. Lancer l'outil avec `--quota-gio`. Verdict possible : *tient*, *tient seulement si les copies partagent leurs blocs*, *ne tient pas*.
4. Seulement alors la Direction choisit la destination des fichiers (relais web ou dossier distant monté) aux Paramètres, « Sauvegarde hors site ». Les plancher et plafond de copies (2 et 60) bornent déjà le réglage.

SFTP : **reporté** (Q34), non décrit, non inventé (voir ADR-0008).
