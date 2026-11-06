# Inventaire des audits et lectures déjà payés (06/11/2026)

> Objet : ne plus payer deux fois la même lecture. Les bruts (116 Ko d'audit du code, 1,06 Mo d'extraits de la maquette) restent dans l'espace de travail de la session et ne sont **pas** poussés : ils citent des agents réels de Nassiera Too et des tarifs de cette clinique, et le dépôt est public. Ce fichier en est la synthèse réutilisable.

## 1. Ce que chaque audit a coûté

| Audit | Agents | Jetons (sous-agents) | Appels d'outils | Durée | Résultat conservé |
|---|---|---|---|---|---|
| Faisabilité du code de base (caisse, stock, M9, bascules, données, identité) | 12 (6 lecteurs + 6 contre-vérificateurs) | **3 135 841** | 556 | 37 min | `lecture.md`, 5 rapports sur 6 (le 6e, identité, n'a laissé que son résumé) |
| Extraction de la maquette Baguidi (identité, rôles, tarifs, pièces, fiscal) | 10 (5 + 5) | **3 030 454** | 517 | 40 min | 5 fichiers `extraits/*.json` |
| Lot 1 (identité, fermetures, NS 131/132, MECeF) | 4 + 1 agent MECeF | 1 356 900 + 384 487 | 583 + 157 | 1 h 53 + 49 min | code fusionné (commits) |
| Lot 2 charte + contre-vérification | 2 | 650 755 | 228 | 1 h 01 | code fusionné (`d150b4f`) |
| Lots B et C (en-tête, réouverture) | 2, **arrêtés** | non facturés au détail (2 Mo de transcription chacun) | | | travail partiel non commité (12 et 13 fichiers modifiés dans leurs espaces) |
| **Total sous-agents** | | **≈ 8,56 millions** | 2 041+ | | |

Les deux audits de **lecture** pèsent à eux seuls **72 %** des jetons des sous-agents (6,17 millions sur 8,56).

## 2. Ce que les audits ont établi (à ne pas redécouvrir)

**Faisabilité du code de base**
- Fermer un module : une fiche `modulesActifs` sans liste d'écrans le ferme entier, avec liste elle ferme des écrans. Au poste, la matrice en force est `rbac.json` (engendré) et les fiches ne la corrigent que par différence avec la référence : ajouter des fermetures au jeu livré ne ferme rien tant que la référence n'est pas distincte (corrigé au lot 1).
- Les paies : `paiCalculer` ajoutait toujours les primes NS 132 et retranchait toujours les sanctions NS 131 (corrigé au lot 1 par des bascules lues par le moteur).
- Normalisation MECeF : fermer le module ne coupait pas la pose de `statutMecef` et `baseMecef` (corrigé au lot 1).
- Une facture ne s'émet pas sans fiche patient (la case « comptoir » existe mais le moteur exige un patient) ; « Enregistrer et encaisser » et l'écran Paiements ne passent aucune écriture ; l'écriture lit `partAssureur` quand les pièces portent `partAssurance` (débit 411 jamais passé). **Ces trois défauts restent à corriger** (lot D).
- Les catalogues (actes, produits, analyses, natures de facture) sont semés au socle : fermer M1 à M5 n'en vide aucun.
- L'application mobile ne lit ni le manifeste ni `modulesActifs` : elle ne suit pas les fermetures.
- Le jeu livré est extrait de la maquette Nassiera Too par ~60 scripts, sans script maître ; le jeu n'est pas déterministe (identifiants `Date.now` et `Math.random`). Le dépôt `sighcbg` ne contient pas la maquette : régénérer est impossible ici, le jeu de démonstration Baguidi doit donc être produit par un générateur propre au dépôt.
- 144 fichiers de test Dart lisent des vecteurs d'identité de Nassiera Too, 115 chargent le jeu.
- Une pièce Dart engendrée porte encore des données de Nassiera Too : liasse fiscale (`cpb_liasse.dart`, `cpc_liasse.dart`), classeur 2025, inventaire SAGE (`donnees_sage.dart`), notes NS 131/132 (`adm_notes_donnees.dart`), `cfb_donnees.dart`, données mobiles.

**Extraction de la maquette Baguidi**
- Identité complète, 14 spécialités, charte mesurée (`coeur #D32F2F`, `sante #1565C0`, `anthracite #212121`), polices Montserrat et Dancing Script, logo 315 x 324, en-tête imprimé à trois zones.
- Rôles : 6 actifs, 17 archivés ; le stock était tenu par le comptable ; M8, M9 et MECeF fermés dans la maquette (dépassé par les décisions du 06/11).
- **Tarifs, actes, analyses, certificats : identiques à Nassiera Too** (131 lignes sourcées « NASSIERA TOO »). Les 295 Ko d'extraction tarifaire aboutissent à cette seule conclusion.
- Plan comptable SYSCOHADA révisé complet (1 332 comptes), barème AIB, centres de coûts renommés (décisions Baguidi du 07/09).
- La maquette dérive d'une version antérieure du code de Nassiera Too (journaux BQE et AN absents, semis comptable déséquilibré).

## 3. Où va la consommation : mesures de la session

| Mesure | Valeur |
|---|---|
| Modèle actuel | Sonnet 5.5 |
| Modèles passés | Opus 5.5 (départ), Fable 5, Sonnet 5.5 |
| Contexte principal à cet instant | **584 711 jetons** sur 1 000 000 |
| Jetons relus en cache sur la session | **≈ 620 millions** |
| Jetons écrits en cache | ≈ 14,75 millions |
| Jetons de sortie de la session | ≈ 1,40 million |
| Coût estimé affiché par la session | **376 $** |

Causes, par ordre d'effet probable (estimation, la session n'expose pas la ventilation) :
1. **Taille du contexte principal.** Chaque appel de modèle relit tout le contexte. Avec un contexte moyen de plusieurs centaines de milliers de jetons, 620 millions de jetons relus correspondent à quelque 1 500 à 2 000 appels. C'est le premier poste, quel que soit le modèle.
2. **Le socle fixe.** Les instructions du dépôt (CLAUDE.md, environ 150 000 caractères) et les listes d'outils sont renvoyées à chaque appel.
3. **Les sous-agents héritent du modèle au lancement** : les deux grandes lectures (6,17 millions) ont tourné sur le modèle le plus cher de la session.
4. **Les résultats de workflow reviennent dans le contexte principal** : cinq notifications de plusieurs dizaines de milliers de caractères chacune, plus les relectures partielles.
5. **Le travail refait** : la fermeture de M1 à M5 (lot 1, environ 0,5 million de jetons d'agent) a été défaite par la décision du soir ; les lots B et C ont été lancés puis arrêtés.
6. **Les contre-vérificateurs** ont doublé le coût des deux audits de lecture (10 des 22 agents), pour très peu de corrections.

## 4. Règles pour ne plus payer deux fois

1. Une nouvelle session pour chaque grand lot : elle repart de la spec et de ce fichier, pas du contexte.
2. Plus d'audit de lecture général : la spec et cet inventaire font foi ; un agent ne lit que les fichiers nommés dans sa mission.
3. Modèle imposé explicitement sur chaque agent (le défaut hérite du plus cher).
4. Contre-vérification par agent uniquement pour l'argent et les droits ; ailleurs, sonde scriptée.
5. Résultats d'agent bornés : rapport court, chiffres, échecs ; pas de journal.
6. Les décisions bloquantes avant le lancement du lot qu'elles conditionnent.
