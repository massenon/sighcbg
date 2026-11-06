# PROMPT — Dérivation du prototype SIGH-CNT pour la CLINIQUE BAGUIDI « L'AS DE CŒUR »

> À coller tel quel dans une nouvelle session Claude Code ouverte sur `C:\Projects\clinique_baguidi`.
> Le dossier `prototype_html/` y est une copie conforme du prototype SIGH-CNT (NASSIERA TOO), dépendances comprises — ne jamais retravailler l'original de `clinique_nassieratoo`.

---

Tu travailles dans `C:\Projects\clinique_baguidi\prototype_html\`, copie du prototype SIGH-CNT.
Objectif : en faire le prototype de la **CLINIQUE BAGUIDI « L'AS DE CŒUR »** (Parakou) **sans redévelopper** — nettoyage des seeders, désactivation des modules non exploités, charte graphique BAGUIDI. Sigle **VALIDÉ par la Direction (02/09/2026) : SIGH-CBG**.

## 0. Lire AVANT toute décision — hiérarchie des sources

1. **`../Instructions.txt` — LA SOURCE PRIORITAIRE.** En cas de divergence avec tout autre document, c'est lui qui fait foi (décision de la Direction du 02/09/2026). Identité, comptes de test, périmètre, charte. `../logo.png` = logo officiel.
2. `prototype_html/CLAUDE.md` (hérité de CNT) — les mécanismes qui portent tout ce travail : `modulesActifs`, fiches `rbac`, safelist Tailwind, `_version`, seeders au socle vs à l'écran, pièges du build.
3. `../Rapport_de_Cadrage_et_Analyse_des_Besoins_Clinique_GBAGUIDI.pdf` et `../ANALYSE DIAGNOSTIQUE DE LA CHAINE D'APPROVISIONNEMENT BAGUIDI.pdf` — contexte secondaire (l'existant, le circuit d'approvisionnement réel), jamais contraignant contre Instructions.txt. PDF scannés : les rendre en images via `node build/_pdf2png.js` puis les lire visuellement (méthode documentée au CLAUDE.md).
4. `../docs/` — photos WhatsApp des documents réels collectés (13/07/2026) : les lire une à une ; ce qu'elles documentent devient référentiel tracé, comme chez CNT.

**NE PAS LIRE `../Cahier_des_Charges_Fonctionnel_et_Technique_Clinique_BAGUIDI_V2.md` : il est OBSOLÈTE** (décision de la Direction du 02/09/2026) et ne fait foi sur rien — ni périmètre, ni acteurs, ni règles. Ne pas s'en servir non plus pour « confirmer » un point d'Instructions.txt.

## 1. Règles absolues (héritées, non négociables)

- **Aucune donnée officielle ne s'invente** : IFU, RCCM, autorisation, tarifs, numéros, seuils. Toute valeur manquante reste vide et l'écran le dit (« à compléter par la Direction »).
- **Les marquages `aValider` se posent librement et ne se retirent que sur décision écrite.**
- **Jamais de retrait d'entrée du manifeste `nav.js` pour fermer un écran** : le canal est `modulesActifs` (écrans ET modules).
- `git init` + commit initial de la copie AVANT toute modification, puis un commit par vague, messages en français.
- Chaque vague passe les verrous : `npm run lint` → `npm run build` (**safelist AVANT la CSS** — piège n°1) → `npm run check` → `npm run test` → `npm run audit-rbac` (0 promesse, 0 lecture non dite) → `npm run inventaire-rbac`.
- Toute modification de forme des données **incrémente `_version`** dans `store.js` et met à jour `LIBELLES` (corbeille).
- Édition de fichiers : jamais de scripts Python (CRLF) ni de `node -e` (backticks/échappements mangés) — scripts Node écrits via l'outil d'édition.

## 2. Identité et en-têtes (source unique : `C.BRAND` dans `core.js` → `cfg-entetes`, états imprimés, connexion, topbar)

| Champ | Valeur |
|---|---|
| Dénomination | CLINIQUE BAGUIDI « L'AS DE CŒUR » |
| Sous-titre | CENTRE DE MÉDECINE DU TRAVAIL – MÉDECINE GÉNÉRALE |
| Adresse | Quartier Zongo II, 02 BP 105, Parakou, République du Bénin |
| Téléphones | 95 74 69 56 / 95 95 99 14 / 97 09 34 99 |
| E-mail | cliniquebaguidi@yahoo.fr |
| IFU | 3201001996110 (du 26 novembre 2010) |
| RCCM | **NON FOURNI** → vide, « à compléter par la Direction » |
| N° d'autorisation d'ouverture | **NON FOURNI** → vide, « à compléter » |
| Devise / slogan | « Votre bien-être est notre raison d'être. » |
| Logo | `../logo.png` → **vendoré** dans `assets/img/` (aucune requête réseau) |

- **En-tête imprimé à 3 zones** (structure en tableau 3 colonnes, `print.js`) : gauche = logo circulaire (~2–2,5 cm) avec le slogan en cursive **rouge** juste dessous ; centre = nom en rouge/noir très lisible + sous-titre ; droite = adresse, téléphones, IFU, e-mail. Sous l'en-tête, **double ligne fine (rouge et bleue)** séparant l'en-tête du corps de la pièce.
- Spécialités (référentiel de présentation) : Médecine du travail, Santé publique, Gynécologie, Chirurgie, Urologie, Rhumatologie, Ophtalmologie, Orthophonie, Endocrinologie, Pédiatrie, Neurologie, Cardiologie, Kinésithérapie, Imagerie (Radiologie-Échographie).
- **Grep final obligatoire** : plus aucune chaîne « NASSIERA », « Natitingou », « Votre santé, notre raison de vivre », IFU 3201642748214 ou RCCM RB/NAT/2016-B-268 dans l'UI ni les états. Le préfixe du code dossier `CNT/...` devient `CBG/...` (paramètre unique — la règle vit à UN endroit, piège documenté) et la numérotation des pièces `<SIGLE> n°/n°/CNT/<direction>/<année>` devient `/CBG/`. Attention aux faux positifs du grep : « CNT » apparaît aussi dans des identifiants techniques (`sigh-cnt:` des clés localStorage — les renommer en `sigh-cbg:` fait partie du travail, avec `_version` incrémentée).

## 3. Périmètre : `modulesActifs` (mécanisme vague 50 de CNT), jamais le manifeste

**ACTIFS** : M6 (stocks, inventaire pharmacie), M7 (achats, expressions/analyse des besoins — **y compris les demandes de besoins du laboratoire et des services**, qui sont des besoins M7 et non du labo clinique), M10 (RH — fiches du personnel), M11 (paie & primes), M12 (comptabilité SYSCOHADA), M13 (administration), PIL (pilotage), DASH (tableaux de bord, **dont le croisé dynamique**), CFG, GED, RAP.

**DÉSACTIVÉS** : M1, M2, M3, M4, M5 (le laboratoire clinique — ses besoins passent par M7), M8 (caisse/facturation), M9 (assurances), MECEF. Cette liste découle d'Instructions.txt, qui fait foi ; elle ne se rediscute que sur une nouvelle décision écrite de la Direction.

Doctrine héritée à respecter :
- une désactivation retire du méga-menu, de la recherche et des adresses, pour **tous** les rôles admin compris, sans rien supprimer — la réactivation rend tout en l'état ;
- **la désactivation ne doit JAMAIS casser un module actif** : sonder explicitement que stocks, achats, RH, paie, compta et tableaux de bord fonctionnent avec le clinique fermé (un KPI qui lit une collection clinique affiche un zéro honnête ou se masque, il ne casse pas) ;
- CFG + DASH sont le noyau non désactivable ;
- un tableau de bord dont le poste n'existe pas chez BAGUIDI **l'annonce** (doctrine des dash pharmacie/RH archivés chez CNT), il n'affiche pas des indicateurs vides.

**Barème d'évaluation NS 131 : DÉSACTIVÉ.** Écrans d'évaluation fermés par le canal des écrans de `modulesActifs`, bascule `baremeModifiable` fermée, barème seedé vidé. La paie M11 doit calculer **sans** rubrique de sanction — les lignes conditionnelles à `null` sont déjà filtrées, le vérifier par une sonde.

**Le critère de réussite change de chaîne.** Chez CNT c'était patient→consultation→facture ; chez BAGUIDI les parcours transactionnels de référence sont :
1. expression de besoin (service ou laboratoire) → validation Direction → bon de commande → réception/PV → mouvement de stock → CUMP/FEFO → écriture comptable ;
2. fiche RH → planning → prime → bulletin de paie → écriture comptable.
Adapter les scénarios de `build/test-fonctionnel.js` : ceux qui traversent un module désactivé sont remplacés par des sondes « module fermé proprement + modules actifs intacts », et les deux chaînes ci-dessus sont sondées de bout en bout.

## 4. Seeders (`data*.js`, `store.seed()`, `data-seed.js`)

- **GARDER en jeu de test, renommé au contexte BAGUIDI** (décision écrite d'Instructions.txt : « ON GARDE ») : inventaire SAGE 184 articles, catalogue des médicaments, plan comptable SYSCOHADA (93 comptes), compte de résultat 2025 (baseline des dashboards), calendrier fiscal béninois, fournisseurs, périodicités, familles de pièces. Marquer ce qui vient de CNT comme **jeu de démonstration à remplacer par les données BAGUIDI** (`aValider`) — les photos de `../docs/` et l'analyse de la chaîne d'approvisionnement diront ce qui peut être substitué par du réel BAGUIDI dès cette passe.
- **REMPLACER** : l'organigramme CNT (44 agents) et les 14 comptes → le personnel et les **8 comptes BAGUIDI** ci-dessous, exactement, sans en inventer d'autres. NS 132/primes : garder le moteur, marquer la grille `aValider` (aucune note de service BAGUIDI fournie). Plannings/régimes : garder le mécanisme, semer sur le personnel BAGUIDI.
- **SUPPRIMER du jeu de démonstration** : patients, factures de soins, analyses, hospitalisations, maternité, `genFactures` et toutes les files cliniques — régénérer les « gestes de poste » sur les seuls modules actifs (écritures en brouillon, bons en validation Direction, échéances fiscales, inventaires en cours).

**Comptes de test (seed exact) :**

| Nom | Identifiant | Rôle |
|---|---|---|
| GBAGUIDI Rafiou | m-001@baguidi-clinique.bj | Direction (Directeur Général) |
| SANOUSSI Adamon | m-002@baguidi-clinique.bj | Comptable |
| MABOUDOU Nawal | m-003@baguidi-clinique.bj | RH |
| IDOHOU Abraham | m-004@baguidi-clinique.bj | Médecin |
| AKONDE Octave | m-005@baguidi-clinique.bj | Infirmier |
| SOKOU Peace | m-006@baguidi-clinique.bj | Direction |
| ZIME Nadège | m-007@baguidi-clinique.bj | Comptable |
| TOUNGOUH A. Zoulkifouli | m-008@baguidi-clinique.bj | RH |

## 5. RBAC

- Rôles servis : direction, comptable, RH, médecin, infirmier (+ admin système) — la liste des 8 comptes d'Instructions.txt fait foi ; un rôle de plus (gestionnaire de stock/magasinier, par exemple) ne s'ajoute que sur décision écrite de la Direction. Le rôle RH de CNT était **archivé** (transféré à la DA) : chez BAGUIDI il a deux titulaires — le **désarchiver** proprement.
- Les rôles cliniques sans titulaire ni module (biologiste, sage-femme, caissier, chirurgien, anesthésiste, aide-soignant, échographiste…) sont **archivés** (RG-14), jamais supprimés — leurs tableaux de bord l'annoncent.
- Médecin et infirmier **existent** (comptes actifs) mais leurs modules cliniques sont fermés : ils gardent leur tableau de bord (qui annonce le périmètre actuel), l'expression de besoins et ce que `modulesActifs` leur laisse.
- **Chaque rôle actif garde ou reçoit sa fiche `rbac`** — un rôle sans fiche a TOUS les droits, c'est le trou corrigé chez CNT en vague 53. Rappels : une surcharge ACCORDE autant qu'elle restreint ; un écran l'emporte sur son module ; DASH et PIL ne se déclarent jamais au niveau du module dans une fiche.
- Attendu final : `npm run audit-rbac` → **0 promesse, 0 lecture non dite** ; `npm run inventaire-rbac` régénéré et relu.

## 6. Charte graphique BAGUIDI (design system — safelist !)

Palette (remplace le navy institutionnel CNT) :
- **Rouge Cœur `#D32F2F`** — actions principales, éléments importants, accents d'icônes ;
- **Bleu Santé `#1565C0`** — titres de sections, badges, liens secondaires ;
- **Noir Anthracite `#212121`** — textes, pied de page, barres sombres ;
- **Blanc `#FFFFFF` / Gris médical `#F8F9FA`** — fonds, cartes.
- La **sémantique d'état** vert (validé) / orange (alerte) / rouge (rupture, erreur) **ne change pas** — attention : le rouge d'ACTION et le rouge d'ERREUR doivent rester distinguables à l'œil (nuancer l'un des deux si besoin, et le documenter).

Typographie (tout **vendoré localement**, aucune requête réseau) :
- Titres : **Montserrat** ou **Poppins** (semi-bold/gras) ;
- Texte courant : **Inter** (déjà vendoré) ou Open Sans ;
- Slogan **exclusivement** : **Dancing Script** ou Great Vibes (cursive) — nulle part ailleurs.

Logo sur topbar, écran de connexion, états imprimés, favicon. **Régénérer la safelist avant de compiler la CSS** (`gen-safelist` puis Tailwind) — toute classe nouvelle née de la charte doit y passer.

## 7. Documentation et livraison

- **Réécrire `prototype_html/CLAUDE.md`** pour qu'il décrive BAGUIDI et non CNT : identité, périmètre, modules actifs/désactivés, comptes, chaînes de référence — en CONSERVANT toute la doctrine technique héritée qui reste vraie (pièges du build, seeders au socle, RBAC, `_version`, typographie française des montants).
- Mettre à jour l'écran d'aide et le contact éditeur ; l'écran `cfg-modules` doit montrer l'état réel (modules BAGUIDI ouverts, clinique fermé).
- Compléter `C:\Projects\clinique_baguidi\CLAUDE.md` (racine) si une décision nouvelle de la Direction fait évoluer le périmètre.
- Livraison : verrous tous verts, commit final, et un compte rendu qui liste ce qui reste « à compléter par la Direction » (RCCM, autorisation, grille des primes, seuils d'alerte, tout `aValider` posé).

---

**Ce qui manque encore et ne doit PAS être inventé** : RCCM, n° d'autorisation d'ouverture, forme juridique exacte (SARL ?), note de service des primes BAGUIDI, seuils d'alerte de stock, RIB/banques. Tout cela reste vide et marqué — c'est la doctrine du prototype.
