# Jeu de démonstration SIGH-CBG : proposition (06/11/2026)

> **SUPPLANTÉ PAR LA VERSION 2 (08/11/2026), en fin de fichier.** Les sections 1 à 13 ci-dessus sont conservées pour mémoire.
>
> **Ancienne mention (06/11/2026, nuit)** : M1 à M10 sont ACTIFS (PRD P0-11). Les principes 6 et le §3 « un module fermé a ses collections vides » ne tiennent plus : le jeu doit aussi peupler patients, consultations, hospitalisations, analyses et maternité, et chaque spécialité d'un praticien rattaché. Volumes à rehausser après réponse à Q35.
>
> **Statut : PROPOSITION à valider par la Direction de la Clinique Baguidi.** Décision déjà rendue : un jeu créé pour Baguidi, pas de registres vides (Q4). Tout ce qui suit est fictif sauf ce qui est marqué « réel » ; rien n'y est présenté comme une donnée officielle de la clinique. Le dépôt étant public, aucune donnée de patient réel, aucune donnée personnelle hors les noms des huit agents (déjà publics dans `baguidi-sources`, demandés par la Direction).

## 1. Principes

1. **Le jeu montre ce qu'il sert à montrer** : chaque écran ouvert a des lignes à afficher, chaque alerte a une cause, et il reste un flux courant (brouillons à valider, une échéance dépassée, des stocks sous seuil, des créances à relancer). C'est la doctrine « journée des postes » du logiciel d'origine.
2. **RG-10 construit, pas contrôlé après coup** : toute écriture naît en pièce équilibrée (le semis de la maquette Baguidi, 260 lignes déséquilibrées, n'est PAS repris).
3. **Rien d'officiel ne s'invente** : les tarifs restent les valeurs d'attente héritées, marqués `tarifProvisoire` avec le motif « hérités du logiciel d'origine, grille Baguidi à fournir » (Q30) ; les salaires portent `salaireProvisoire` ; les barèmes NS 131/132 sont marqués « hérités, à confirmer » (Q31). Aucune mention « arrêté par la Direction » de Nassiera Too n'est reprise.
4. **Aucun patronyme de Nassiera Too** dans les données fictives : les noms de patients, clients et tiers sont tirés de listes propres (patronymes du Borgou et noms neutres), quartiers de Parakou (Zongo, Banikanni, Albarika, Ladjifarani, Guéma, Dépôt, Titirou, Kpébié).
5. **Déterminisme** : tout est tiré d'une graine fixe, fenêtre du **01/08/2026 au 06/11/2026**, pour que les tests et les captures se rejouent.
6. **Un module fermé a ses collections VIDES** (fichiers `[]` conservés : le chargeur du poste l'exige). Aucune consultation, hospitalisation, analyse ni dossier de maternité.

## 2. Référentiels (le socle)

| Référentiel | Contenu proposé | Origine |
|---|---|---|
| Identité | Baguidi (déjà en place, lot 1) | réel |
| Plan comptable | SYSCOHADA révisé complet, 1 332 comptes à 4 chiffres, 31 comptes des schémas nommés | décision Baguidi du 07/09/2026 (maquette) |
| Barème AIB | 5 % généralisé (arrêté 07/09/2026), 1 % et 3 % non arrêtés, comptes 4478/4492/891 | décision Baguidi (maquette) |
| Calendrier fiscal | hérité (Q29 : « pour le moment »), CNSS portée au **15** du mois suivant (fiche fiscale du 06/11/2026) | hérité + correction |
| Régime TVA | paramètre `mecef-config` laissé sur sa valeur actuelle tant que Q21 n'est pas confirmée par écrit | en attente |
| Tarifs, actes, analyses, certificats | hérités, TOUS re-marqués provisoires (principe 3) | hérités |
| Centres de coûts et groupes | les six de la maquette Baguidi (« Échographie » au lieu d'« Imagerie médicale », codes NS 145), plus la Direction transverse | maquette Baguidi |
| Assureurs | les 13 compagnies (référentiel de place, réel) ; conventions et souscripteurs FICTIFS | référentiel réel, liens fictifs |
| Familles d'articles | les 7 familles | hérité |
| Spécialités | les 14 de l'écran de connexion | réel |

## 3. Personnes et comptes (réels, fournis par la Direction)

9 comptes, TOUS ACTIFS (décision du 06/11/2026) :

| Compte | Agent | Rôle | Service |
|---|---|---|---|
| admin@baguidi-clinique.bj | Administrateur système | admin | Administration |
| m-001 | **BAGUIDI Rafiou** (orthographe RCCM) | direction | Direction |
| m-006 | SOKOU Peace | direction | Direction |
| m-002 | SANOUSSI Adamon | comptable | Comptabilité |
| m-007 | ZIME Nadège | comptable | Comptabilité |
| m-003 | MABOUDOU Nawal | rh | Ressources humaines |
| m-008 | TOUNGOUH A. Zoulkifouli | rh | Ressources humaines |
| m-004 | IDOHOU Abraham | medecin | Médecine générale |
| m-005 | AKONDE Octave | infirmier | Soins infirmiers |

Rôles actifs : admin, direction, comptable, rh, medecin, infirmier, **stock** (désarchivé, CRUD complet M6 avec le comptable ; titulaire en attente, Q33 : d'ici là la fiche de rôle existe sans compte rattaché et l'écran le dit). Salaires : grille d'attente plausible pour Parakou, chaque fiche marquée `salaireProvisoire` (proposition : direction 250 000, médecin 220 000, comptable 150 000, RH 130 000, infirmier 90 000, en FCFA mensuels, à remplacer par la grille réelle).

## 4. Tiers fictifs

- **6 entreprises clientes** de médecine du travail (le cœur du métier de Baguidi), avec convention de visites (embauche, périodique, reprise) : Société Cotonnière du Borgou, Huilerie de Parakou, Transports Okpara, Brasserie des Collines, BTP Alafia, Imprimerie Gurma. Chacune : effectif 15 à 120, contact, échéance de facturation mensuelle. Toutes marquées « entreprise fictive de démonstration ».
- **~60 clients/patients fictifs** au répertoire (CRUD Patients gardé pour M9 et les ventes) : 25 salariés rattachés aux entreprises, 10 assurés (cartes NSIA, SUNU, ASCOMA : 8 valides, 2 expirées pour montrer RG-09), 25 clients de passage. Codes `CBG/1/26` à `CBG/60/26`.
- **5 fournisseurs** : UBPHAR Bénin (grossiste pharmaceutique), CAME (centrale d'achat, nom réel d'usage courant, fiche marquée à vérifier), Labo Équip Parakou, Papeterie du Marché central, Station Niger Énergie.

## 5. Stocks (M6, complet)

- **120 produits** répartis sur les 7 familles, avec pour chacun : stock gros, stock détail, pharmacie d'urgence pour ~20 produits d'urgence, seuil d'alerte fixé (c'est la clinique qui fixe les seuils : valeurs plausibles, 8 produits SOUS seuil pour alimenter les alertes), CUMP et prix de vente = prix d'achat (RG-02).
- **180 lots FEFO** : péremptions étalées, 6 lots périmant sous 60 jours, 2 périmés (pour l'écran des alertes et les pertes).
- **~900 mouvements** sur la fenêtre : entrées fournisseur, 15 transferts gros vers détail (multi-lignes), sorties sur bons de besoins servis, 2 pertes déclarées, 1 inventaire clos en septembre + 1 feuille de comptage en cours sur le magasin détail.

## 6. Achats (M7)

12 expressions de besoins (3 soumises en attente d'arbitrage de la Direction, 1 rejetée avec motif, 8 validées avec quantité accordée ≠ demandée sur 5), 8 commandes (RG-04 : validées Direction), 6 livraisons avec PV de réception (1 avec réserves), 6 factures fournisseurs dont **2 impayées** (la dette alimente le BFR).

## 7. Caisse minimale et report des recettes (M8 + P0-8)

- **Reports journaliers** : 1 caisse source « Logiciel de caisse patient » (hypothèse Q14 : une seule, à corriger si plusieurs), **65 journées ouvrées reportées** du 04/08 au 05/11/2026, plus **la journée d'hier NON reportée** (le tableau de bord comptable doit montrer la liste des journées manquantes). Natures proposées (hypothèse Q16, comptes du plan révisé) : Visites de médecine du travail · Consultations · Actes et soins · Certificats · Analyses · Échographie · Pharmacie (logiciel patient) · Hospitalisation et mise en observation. Montants journaliers 80 000 à 450 000 FCFA, part à crédit 20 à 40 % sur les journées avec entreprises ou assureurs. 3 reports en brouillon à valider, 1 report avec écart saisi et motivé (démonstration du contrôle).
- **Ventes au comptoir SIGH** : 40 ventes de pharmacie sans dossier (client libre), sorties de stock rattachées au numéro d'opération, 2 refus RG-03 rejoués dans les tests.
- État de caisse journalier qui se recoupe : opérations + ventes − dépenses.

## 8. Assurances et créances (M9)

Créances nées des parts à crédit des reports : ~18 créances sur les 6 entreprises et 3 compagnies, dont 5 réglées, 9 en cours, **4 en retard de plus de 60 jours** (relances à montrer, alerte de recouvrement active). Les écrans qui exigent le détail patient par patient affichent leur avertissement (P0-6).

## 9. RH et paie (M10, M11)

- Dossiers des 8 agents (réels, champs personnels VIDES : CNSS, naissance, à remplir en production), contrats, 3 congés (1 en cours), planning et présences d'août à novembre, 2 heures supplémentaires, 1 avance en cours de retenue.
- **Paie : 3 mois** : août et septembre VALIDÉS par la Direction (séparation des tâches), octobre en BROUILLON à valider. Bascules NS 131/132 ouvertes ; grilles héritées marquées « héritées, à confirmer » ; aucune évaluation NS 131 saisie (aucune sanction fictive sur un agent réel : on ne fait pas dire une sanction à un nom réel).
- Badges : modèles au verso Baguidi, AUCUN badge émis (l'émission est un geste de la Direction).

## 10. Comptabilité (M12)

- Exercice 2026 ouvert, **sans bilan d'ouverture** (aucun document Baguidi : l'écran le dit, rien n'est inventé).
- ~450 lignes d'écritures en pièces équilibrées, toutes dérivées des faits du jeu : reports de recettes, dépenses, paie, achats. **30 dépenses multi-lignes** (4 sans justificatif, comptées et signalées), journaux VTE/ACH/CAI/BQE/SAL/OD.
- Échéances fiscales sur le calendrier hérité (CNSS au 15) : payées jusqu'en septembre, **1 échéance dépassée** (l'alarme a quelque chose à montrer), 2 à venir.
- Baseline et liasse : VIDES et dites (« aucun exercice déposé fourni par la clinique »).

## 11. Administration, sécurité, GED (M13, M14, GED)

10 courriers (5 arrivés, 5 départs), 4 réunions avec compte rendu, plan annuel 2026 esquissé, 6 documents GED (notes internes fictives). **Répertoire des ambulances : les seuls numéros de la clinique** ; les structures extérieures ont une fiche vide qui le dit (doctrine : aucun numéro d'urgence ne s'invente). Journal d'audit alimenté par les gestes du semis, sessions de démonstration, 1 tentative de connexion refusée sur rôle archivé.

## 12. Volumes et garde-fous

| Collection | Volume | | Collection | Volume |
|---|---|---|---|---|
| produits / lots | 120 / 180 | | reports journaliers | 65 (+1 manquante) |
| mouvements | ~900 | | ventes comptoir | 40 |
| clients fictifs | 60 | | créances | 18 |
| entreprises / fournisseurs | 6 / 5 | | écritures (lignes) | ~450 |
| besoins / commandes | 12 / 8 | | dépenses | 30 |
| bulletins | 24 (3 mois × 8) | | courriers / réunions | 10 / 4 |

Garde-fous : le contrôle d'identité (0 occurrence Nassiera Too, patronymes des 44 agents NT inclus) tourne sur le jeu engendré ; un test vérifie que chaque pièce comptable s'équilibre ; un test vérifie qu'aucune collection d'un module fermé n'est peuplée.

## 13. Ce que la proposition attend de la Direction

| # | Question | Défaut appliqué en attendant |
|---|---|---|
| Q14 | combien de caisses sources ? | une seule |
| Q15 | la pharmacie vend-elle aussi dans le logiciel patient ? | non : la nature « Pharmacie » du report reste à zéro sur la plupart des journées |
| Q16 | natures et comptes 70x | les 8 natures du §7 |
| Q33 | titulaire du rôle stock | rôle prêt, sans compte |
| | noms des 6 entreprises fictives | ceux du §4, remplaçables |
| | grille des salaires | valeurs d'attente du §3 |

---

# Version 2 (08/11/2026) : jeu de démonstration corrigé

> **VALIDÉE par la Direction le 08/11/2026** : décisions J1 à J14 telles que proposées (propositions en gras), volumes inclus. J14 (passage de `sighcbg` en privé) reste une action de la Direction sur GitHub.

Corrige la version 1 selon les décisions rendues depuis : M1 à M10 actifs avec tout, SIGH-CBG remplace le logiciel de caisse patient (plus de report des recettes), banque de sang activée, quatorze spécialités, sigle CBG, exploitant BAGUIDI Rafiou.

## Décisions à prendre (ma proposition en gras)

| # | Décision | Proposition | Alternative |
|---|---|---|---|
| J1 | Étendue du jeu | **Tous les modules actifs sont peuplés et cohérents entre eux** (un patient traverse accueil, consultation, analyse, facture, encaissement, écriture) | seulement stock, achats, RH, paie, compta |
| J2 | Fenêtre de temps | **01/08/2026 au 07/11/2026** | trois mois glissants |
| J3 | Personnes réelles | **Les 9 comptes de la maquette, « BAGUIDI Rafiou » (orthographe du RCCM)**, fiches personnel complètes sauf champs personnels vides (CNSS, naissance) | ajouter d'autres agents quand la Direction les fournit |
| J4 | Mots de passe | **Aucun mot de passe dans le dépôt** : les 9 comptes arrivent en état « mot de passe à définir », l'administrateur les active à l'installation (changement imposé à la première connexion) | mot de passe provisoire commun documenté (déconseillé : dépôt public) |
| J5 | Praticiens des spécialités | **Dix à douze vacataires FICTIFS** (cardiologue, endocrinologue, neurologue, pédiatre, ophtalmologue, urologue, rhumatologue, orthophoniste, kinésithérapeute, gynécologue, chirurgien, échographiste) rangés dans les prestataires de M10, marqués « fictif de démonstration », sans compte | rattacher les spécialités aux seuls agents réels (faux : un seul médecin) |
| J6 | Entreprises clientes (médecine du travail) | **6 entreprises fictives** avec convention de visites (noms du v1, remplaçables) | attendre vos vraies conventions |
| J7 | Tarifs | **Valeurs d'attente héritées, toutes re-marquées provisoires** ; pour les actes propres à la médecine du travail (visite d'embauche, périodique, de reprise, fiche d'aptitude) des tarifs d'attente marqués provisoires aussi (valeurs à corriger par vous) | laisser ces actes sans prix (bloque la facturation) |
| J8 | Assureurs | **Les 13 compagnies du marché conservées** comme référentiel ; conventions et souscripteurs fictifs | liste Baguidi à fournir |
| J9 | Plan comptable | **SYSCOHADA révisé complet (1 332 comptes)** pris du classeur Baguidi (`plan-comptable-syscohada-revise.csv`), AIB 5 %, calendrier fiscal hérité avec CNSS au 15 | plan réduit de 112 comptes |
| J10 | Comptabilité | **Exercice 2026 sans bilan d'ouverture ni liasse** (dits à l'écran) ; écritures produites par les moteurs, équilibrées par construction ; une échéance dépassée ; une journée de caisse non arrêtée | inventer une ouverture (refusé : rien d'officiel ne s'invente) |
| J11 | Fixtures de test | **Pseudonymisation** : les fixtures et vecteurs issus de Nassiera Too (noms d'agents) reçoivent la MÊME table de pseudonymes des deux côtés, donc la parité des tests tient, et plus aucun nom réel de l'autre clinique n'y figure ; le jeu LIVRÉ est entièrement Baguidi | conserver les noms d'origine dans les tests (visibles dans un dépôt public) |
| J12 | Générateur | **Un générateur en Dart** (`apps/poste/tool`), graine fixe, qui appelle les moteurs de `packages/domaine` (facture, encaissement, avoir, écriture) : les invariants (RG-03, RG-10) tiennent par construction | générateur Node écrit à part (recopie des règles, divergera) |
| J13 | Découpage du travail | **Quatre sous-lots, un agent chacun** : (1) référentiels et personnes, (2) RH et paie, (3) stock, achats, facturation, caisse, comptabilité, (4) clinique M1 à M5 | un seul lot (trop gros pour un agent) |
| J14 | Dépôt | **Passer `sighcbg` en privé avant de pousser le code** : il contient le code de l'éditeur, les noms des 9 agents réels et le périmètre contractuel | rester public |

## Volumes proposés

| Domaine | Volume |
|---|---|
| Patients | 120 (80 salariés des 6 entreprises, 15 assurés, 25 de passage) ; 2 cartes d'assurance expirées |
| Consultations | 200 : 110 visites de médecine du travail (45 embauche, 55 périodiques, 10 reprise), 60 médecine générale, 30 de spécialité ; 40 dossiers de consultation complets |
| Analyses et imagerie | 80 demandes (60 rendues), 25 demandes d'imagerie (cinq modalités) |
| Hospitalisation et bloc | 8 admissions (6 mises en observation, 2 hospitalisations), 5 interventions avec compte rendu |
| Maternité | 6 CPN, 3 accouchements, 3 naissances |
| Banque de sang | 15 donneurs, 20 poches, 4 transfusions |
| Facturation et caisse | ~350 factures encaissées par les moteurs, 3 avoirs, un arrêté de caisse par jour ouvré sauf un |
| Assurances et créances | 18 créances (6 entreprises, 3 compagnies), 4 en retard de plus de 60 jours |
| Stock et achats | 120 produits, 30 réactifs et consommables, 180 lots FEFO, ~900 mouvements, 12 besoins, 8 commandes, 6 livraisons, 6 factures fournisseurs (2 impayées) |
| RH et paie | 9 agents, 24 bulletins (août et septembre validés, octobre en brouillon), aucune évaluation NS 131 saisie |
| Comptabilité | ~450 lignes d'écritures équilibrées, 30 dépenses multi-lignes |

## Garde-fous

`controle-identite` à zéro sur le jeu livré ; chaque pièce comptable équilibrée ; aucune collection de module actif vide sans que l'écran le dise ; aucun numéro de téléphone ou d'urgence inventé ; aucun mot de passe ni donnée personnelle sensible dans le dépôt.
