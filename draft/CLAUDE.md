# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

**SIGH-CBG** (sigle validé par la Direction le 02/09/2026) — dérivation du prototype SIGH-CNT
(CLINIQUE NASSIERA TOO, Natitingou) pour la **CLINIQUE BAGUIDI « L'AS DE CŒUR »** (Quartier Zongo II,
02 BP 105, Parakou — IFU 3201001996110 du 26/11/2010 — cliniquebaguidi@yahoo.fr — 95 74 69 56 /
95 95 99 14 / 97 09 34 99). Devise : « Votre bien-être est notre raison d'être. »

**LA DÉRIVATION EST LIVRÉE (02/09/2026)** — six vagues committées : identité et en-tête 3 zones,
périmètre par `modulesActifs`, seeders (8 agents/comptes exacts, purge du jeu clinique), RBAC
(rh désarchivé, 15 rôles archivés, validations à la Direction), charte graphique (Rouge Cœur /
Bleu Santé / Anthracite, polices vendorées, décors connexion/verrou/ruban/topbar), verrous et tests.
Verrous au vert : 283 pages / 0 erreur JS / 0 lien cassé, 16 scénarios / 129 vérifications,
audit RBAC 0 promesse / 0 lecture non dite, inventaire régénéré (`newdocs/INVENTAIRE-RBAC.md`).

Périmètre BAGUIDI : **stocks et inventaire pharmacie (M6), achats et expressions de besoins — dont les
besoins du laboratoire et des services (M7), RH (M10), paie (M11), comptabilité SYSCOHADA (M12),
administration (M13), sécurité (M14), pilotage, tableaux de bord (dont le croisé), configuration, GED,
rapports**. Modules cliniques (M1–M5, M8, M9, MECeF), barème NS 131, PRIMES NS 132, statistiques cliniques et
**dispensation au patient** (officines interne/externe et registre des délivrances — le stock, lui,
reste entier) **désactivés via `modulesActifs`** — jamais retirés du manifeste, réactivables sur
décision écrite.

## État du dépôt

- `prototype_html/` — le prototype SIGH-CBG (283 pages). **Son `CLAUDE.md` interne est LA doctrine
  détaillée** (mécanismes, pièges du build, RBAC, seeders, chaînes de référence) — le lire avant d'y
  travailler.
- `Instructions.txt` — **LA SOURCE PRIORITAIRE** (décision de la Direction du 02/09/2026) : identité,
  8 comptes de test, périmètre, charte. En cas de divergence avec tout autre document, il fait foi.
  `logo.png` — logo officiel (vendoré dans `prototype_html/assets/img/logo.png`).
- `PROMPT-DERIVATION.md` — la feuille de route de la dérivation (exécutée).
- `Cahier_des_Charges_Fonctionnel_et_Technique_Clinique_BAGUIDI_V2.md` — **OBSOLÈTE (décision du
  02/09/2026) : ne pas le lire, il ne fait foi sur rien.**
- `Rapport_de_Cadrage_...pdf`, `ANALYSE DIAGNOSTIQUE DE LA CHAINE D'APPROVISIONNEMENT BAGUIDI.pdf`,
  `Plan_Sprints_Agile_...pdf` — contexte secondaire, jamais contraignant contre Instructions.txt.
  PDF scannés sans couche texte : `node prototype_html/build/_pdf2png.js` puis lecture visuelle.
- `docs/` — photos des documents réels (13/07/2026). Les notes manuscrites de la réunion de cadrage
  sont à IGNORER (consigne du 02/09/2026) ; les captures Excel montrent le classeur comptable réel
  BAGUIDI (« Journal de Janvier 2026 » : ACHT, VENTE, SALAIRE, Caisse Dépenses, OD, Prestation,
  Point AIB, IMO) — source possible pour remplacer la baseline héritée, sur décision écrite.
- `newdocs/INVENTAIRE-RBAC.md` — ce que chaque rôle voit réellement, régénéré à chaque lot.

## Commandes (depuis `prototype_html/`)

`npm run verify` = lint + build (**safelist AVANT la CSS — piège n°1**) + check (283 pages) + test
(16 scénarios BAGUIDI). Puis `npm run audit-rbac` (attendu : 0 promesse, 0 lecture non dite) et
`npm run inventaire-rbac`.

## Règles à ne jamais contourner

- **Aucune donnée officielle ne s'invente** (autorisation d'ouverture, forme juridique, salaires,
  IFU des agents, seuils — non fournis à ce jour) : champ vide + « à compléter par la Direction ».
  L'écran `adm-validations` tient la liste vivante. Fournis à ce jour : IFU 3201001996110 du
  26/11/2010 et **RCCM RB/PKO/17 A 4240 du 19/03/2009** (07/09/2026).
- **Marquages `aValider`** : se posent librement, ne se retirent que sur décision écrite.
- Fermer un écran = `modulesActifs`, **jamais** un retrait du manifeste `nav.js`.
- Un rôle sans fiche `rbac` a TOUS les droits — chaque rôle actif a sa fiche ; une surcharge ACCORDE
  autant qu'elle restreint ; DASH/PIL ne se déclarent jamais au niveau module.
- Toute modification de forme des données incrémente `_version` (`store.js`, constante `VERSION`,
  courante : **64** — elle sert à la fois à la semence et au contrôle de `load()`, ne jamais la
  dédoubler) et met à jour `LIBELLES`.
- **L'IFU se porte sur la fiche du tiers** (agents et prestataires), avec son statut daté et signé et
  son `regimeRemuneration` : un salaire supporte l'ITS, des honoraires supportent l'AIB. Le bulletin
  porte la ligne d'AIB dans les deux cas — à zéro et motivée pour un salarié.
- **Toute surface qui présente des écrans ou des rôles passe par `can()` / `N.tree()` / `roleArchive`,
  jamais par le manifeste brut** — l'écran d'aide et le sélecteur de profil l'avaient oublié
  (corrigé le 03/09/2026).
- Édition de texte français sous Windows : scripts Node écrits via l'outil d'édition — jamais
  `node -e` ni Python (CRLF).
- Un rôle/référentiel s'**archive** (RG-14), ne se supprime jamais.
- **Le plan comptable est le SYSCOHADA RÉVISÉ** (1 332 comptes, codes à quatre chiffres) ; une
  écriture se passe sur un compte **imputable**, et les schémas d'écriture nomment leurs comptes
  via `D.COMPTES_SIGH`.
- **AIB** : le barème est une donnée administrable. 5 % arrêté depuis le 07/09/2026 (IFU désactivé
  ou absent) ; les taux de 1 % et 3 % attendent que la Direction arrête leur condition à l'écran —
  d'ici là ils ne s'appliquent pas. Le statut de l'IFU se vérifie et se date avant toute retenue.
- **Pas de primes** (07/09/2026) : grille vide, écran fermé, bulletins sans prime — une grille vide
  vaut zéro, jamais un repli sur la note de la clinique d'origine. Réactivable sur décision écrite.
- **Un prix se fige sur le mouvement** au moment de l'enregistrement ; l'historique des prix est une
  trace en lecture seule, jamais une source de valorisation. Un article sans prix ne sort pas.

## Charte graphique

Rouge Cœur `#D32F2F` (actions — boutons pleins), Bleu Santé `#1565C0` (titres/badges — la palette
`navy` du design system est remappée dessus), Noir Anthracite `#212121` (texte, topbar, barres
sombres), Blanc/Gris médical (fonds). Sémantique d'état vert/orange/rouge inchangée — le rouge
d'erreur reste le rouge vif, le bouton danger est un contour (nuance documentée). Titres Montserrat,
courant Inter, slogan SEUL en Dancing Script — polices et logo vendorés, aucune requête réseau.
En-tête imprimé à 3 zones avec double ligne fine rouge et bleue (reprise sous la topbar).
