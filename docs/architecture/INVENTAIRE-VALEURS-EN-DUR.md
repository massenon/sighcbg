# Inventaire des valeurs encore écrites EN DUR dans le code

*SIGH-CBG, Clinique Baguidi. Branche `baguidi-lot1`, mesure du 16/11/2026.*
*Script de mesure : `tools/baguidi/inventaire-en-dur.mjs`. On peut le relancer, et il ne fait que lire le code.*

> **La demande de la Direction** : « faire l’inventaire des modules qui sont encore EN DUR dans le code ».
> **La règle du projet** : une valeur métier ne s’écrit jamais dans le code. Elle vient de l’une de ces quatre sources :
> - un référentiel que la clinique administre ;
> - un paramètre de clinique daté et versionné (`definitions.dart`) ;
> - la matrice des droits ou un geste réservé ;
> - l’identité de la clinique.

---

## 1. Synthèse

**Périmètre mesuré** : 808 fichiers, soit 225 804 lignes de code de production :
- le code `lib` du poste, du domaine, du client de synchronisation et du mobile, en Dart ;
- le relais Laravel (`apps/web/app` et `apps/web/config`), en PHP.

Les tests, les vecteurs, les fixtures, le jeu livré et les générateurs ne sont pas comptés.

**Résultat : 349 défauts réels**, comptés après le tri. Répartition par gravité : haute : **103** · moyenne : **213** · basse : **33**.
- **Haute** : la valeur touche l’argent, la fiscalité, le médical ou un droit.
- **Moyenne** : un seuil ou une liste métier.
- **Basse** : un libellé.

On compte **un site par ligne**. Plusieurs littéraux sur une même ligne, ou les fiches sœurs d’un même tableau, ne comptent qu’une fois.

À ces défauts s’ajoutent **17 fichiers de référentiels compilés** (famille R, § 2.R). Ce sont des données engendrées depuis la maquette ou des données de démonstration écrites dans `lib`. On les compte une fois chacun : ils ne sont pas administrables, mais ils sont tracés vers leur source.

**Familles** :
- A : années et dates fixes ;
- B : taux et montants ;
- C : seuils et durées ;
- D : listes de choix ;
- E : préfixes de numérotation ;
- F : noms de rôles qui décident d’un droit ;
- G : libellés d’organisation et contacts ;
- H : barèmes figés.

| Module | A | B | C | D | E | F | G | H | **Total** | dont haute |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| M12 Comptabilité | 8 | · | 3 | 7 | 10 | · | · | · | **28** | 13 |
| M1 Patients & DMI | 2 | 2 | · | 11 | 6 | · | 3 | · | **24** | 11 |
| M8 Facturation & caisse | · | · | 2 | 6 | 8 | · | · | · | **16** | 12 |
| M11 Paie & primes | 1 | 3 | · | 5 | 5 | · | · | 2 | **16** | 10 |
| M3 Hospitalisation & bloc | · | · | 1 | 5 | 9 | · | 1 | · | **16** | 8 |
| M13 Administration, qualité | 3 | 1 | 3 | 14 | 6 | · | 2 | · | **29** | 3 |
| M14 Sécurité & accès | · | · | 8 | 4 | 1 | · | · | · | **13** | 8 |
| M10 RH | · | 2 | 3 | 12 | 9 | · | 4 | 1 | **31** | 2 |
| M2 RDV, consultations, imagerie | · | · | 2 | 10 | 9 | 1 | 2 | · | **24** | 4 |
| M9 Assurances & créances | · | · | 2 | 9 | 3 | · | · | 1 | **15** | 6 |
| M7 Achats & fournisseurs | · | · | · | 3 | 8 | · | · | · | **11** | 6 |
| M4 Maternité | 2 | · | · | 5 | 10 | · | · | · | **17** | 2 |
| SYNC Synchronisation (sync_dart, poste) | 3 | · | 11 | · | · | · | · | · | **14** | 3 |
| M5 Laboratoire & sang | · | · | 2 | 6 | 4 | · | · | 1 | **13** | 3 |
| CFG Configuration & paramètres | 1 | · | 4 | 3 | 6 | 1 | · | · | **15** | 2 |
| MOBILE (règles du téléphone) | · | · | 19 | · | · | · | · | · | **19** | · |
| MECeF | · | · | · | 1 | 4 | · | · | · | **5** | 4 |
| PIL Pilotage | 1 | 2 | 1 | 1 | · | · | · | 1 | **6** | 3 |
| Import / reprise | · | · | 1 | 2 | 6 | · | · | · | **9** | 2 |
| M6 Pharmacie & stocks | · | · | 2 | 6 | 3 | · | · | · | **11** | · |
| MÈRE (console du poste mère) | · | · | 6 | · | · | · | · | · | **6** | · |
| DASH Tableaux de bord | · | · | 1 | 1 | · | · | · | · | **2** | 1 |
| Assistant | · | · | 4 | · | · | · | · | · | **4** | · |
| Socle (kit, coque) | · | · | 2 | · | · | · | · | · | **2** | · |
| RAP Rapports | · | · | · | 2 | · | · | · | · | **2** | · |
| RELAIS (Laravel) | · | · | 1 | · | · | · | · | · | **1** | · |
| **Total** | **21** | **10** | **78** | **113** | **107** | **2** | **12** | **6** | **349** | **103** |


Le tableau est classé du module le plus « en dur » au moins « en dur ». Le score de classement est le total des défauts, plus 3 points par défaut de gravité haute :

1. **M12 Comptabilité** — 28 défauts, dont 13 de gravité haute
2. **M1 Patients & DMI** — 24 défauts, dont 11 de gravité haute
3. **M8 Facturation & caisse** — 16 défauts, dont 12 de gravité haute
4. **M11 Paie & primes** — 16 défauts, dont 10 de gravité haute
5. **M3 Hospitalisation & bloc** — 16 défauts, dont 8 de gravité haute
6. **M13 Administration, qualité** — 29 défauts, dont 3 de gravité haute
7. **M14 Sécurité & accès** — 13 défauts, dont 8 de gravité haute
8. **M10 RH** — 31 défauts, dont 2 de gravité haute
9. **M2 RDV, consultations, imagerie** — 24 défauts, dont 4 de gravité haute
10. **M9 Assurances & créances** — 15 défauts, dont 6 de gravité haute
11. **M7 Achats & fournisseurs** — 11 défauts, dont 6 de gravité haute
12. **M4 Maternité** — 17 défauts, dont 2 de gravité haute
13. **SYNC Synchronisation (sync_dart, poste)** — 14 défauts, dont 3 de gravité haute
14. **M5 Laboratoire & sang** — 13 défauts, dont 3 de gravité haute
15. **CFG Configuration & paramètres** — 15 défauts, dont 2 de gravité haute
16. **MOBILE (règles du téléphone)** — 19 défauts, dont 0 de gravité haute
17. **MECeF** — 5 défauts, dont 4 de gravité haute
18. **PIL Pilotage** — 6 défauts, dont 3 de gravité haute
19. **Import / reprise** — 9 défauts, dont 2 de gravité haute
20. **M6 Pharmacie & stocks** — 11 défauts, dont 0 de gravité haute
21. **MÈRE (console du poste mère)** — 6 défauts, dont 0 de gravité haute
22. **DASH Tableaux de bord** — 2 défauts, dont 1 de gravité haute
23. **Assistant** — 4 défauts, dont 0 de gravité haute
24. **Socle (kit, coque)** — 2 défauts, dont 0 de gravité haute
25. **RAP Rapports** — 2 défauts, dont 0 de gravité haute
26. **RELAIS (Laravel)** — 1 défauts, dont 0 de gravité haute

### Les 10 défauts les plus graves

Ils ont été vérifiés un par un dans le code.

| # | Où | Ce qui est en dur | Pourquoi c’est grave | Où cela doit vivre |
|---|---|---|---|---|
| 1 | `sync_dart/lib/src/fileul.dart:165`, `mere.dart:481`, `mobile.dart:152` | `codePatient(n, 2026)` | **RG-01.** Le code patient attribué par la mère, un fileul ou un téléphone porte l’année 2026 en dur. **À partir du 1er janvier 2027, chaque nouveau dossier serait codé « …/26 »**, et un code attribué ne se corrige plus. | Année de la date d’ouverture du dossier, comme le fait déjà `C.codePatient()` |
| 2 | 10 sites de préfixe de pièce : `BEB-2026-` et `BC-2026-` (domaine et poste), `CPA-2026-`, `CRA-2026-`, `OBS-2026-`, `RU-2026-`, `AM-2026-`, `CERT-2026-`. S’y ajoute `PA-2026-` dans l’amorçage du plan annuel, non compté. | L’année 2026 écrite dans le préfixe | Au 1er janvier 2027, ces pièces continueraient la série 2026. Le circuit des achats (RG-04) et les certificats sont touchés. | Référentiel de numérotation par exercice (lot 2) |
| 3 | `mecef/ecrans.dart:1520-1524` | `FN-2026-`, `AV-2026-`, `PRO-2026-` et le « prochain numéro » calculé sur la série 2026 | La configuration MECeF affiche une série fiscale figée. Le moteur `emission.dart` prend pourtant déjà l’année de la facture : **deux vérités**. | Lire le référentiel de numérotation |
| 4 | `domaine/paie/pai_moteur.dart:24-28` | CNSS 3,6 % / 16,4 %, VPS 4 % | Ces taux servent au calcul de **chaque bulletin**. La « confirmation fiscale » recopie ces constantes sans pouvoir les changer. Un changement de taux exigerait une nouvelle version du logiciel. | Paramètre de paie daté et versionné, confirmé par le geste `fiscal_confirmer` |
| 5 | `domaine/paie/pai_moteur.dart:39` | Barème progressif de l’ITS, avec la mention « à confirmer par le service comptable » | Impôt retenu sur chaque salaire. Le barème n’a pas de date et ne peut pas être révisé. | Barème versionné par date, comme `baremeAib` |
| 6 | `domaine/comptabilite/cpa_ecritures.dart:39-41` | `cpaLiasseExerciceN = 2025`, `N1 = 2024`, date de dépôt `2026-04-30` | Ces constantes décident si un exercice est **« clos » ou « ouvert »**. Elles ne suivent pas la clôture réelle faite au module M12. | Collection `exercices` (statut, clôture, dépôt) |
| 7 | `domaine/patients/pat_fiche.dart:110-114` | `switch` sur la fonction de l’agent (`medecin`, `chirurgien`, `direction`, `sage_femme`) | Cette décision fixe **qui lit les comptes rendus d’imagerie** (RG-13), en dehors de la matrice et des gestes réservés. Le cliquet des rôles ne la voit pas parce que la comparaison porte sur la fonction. | Gestes réservés ou droits d’écran |
| 8 | `domaine/consultation/cs_moteur.dart:190` | `capacite == 'chirurgien' \|\| session.role == 'chirurgien'` | Ce test décide de l’écriture des rubriques chirurgicales. Il est déjà toléré par le cliquet comme « chantier parallèle ». | Geste `rubriques_chirurgicales` |
| 9 | `domaine/pilotage/pil_stats.dart:442-447` | ORTB recalculée avec 1 000 / 3 000 / 60 000 | Le pilotage recalcule la retenue ORTB à côté de la fiche `ORTB-PARAMETRES` que lit la paie. Si la Direction change la fiche, **le pilotage et la paie divergent**. | Lire `PaiParametresOrtb` |
| 10 | `domaine/acces/acc_verrou.dart:10`, `securite/sec_exploitation.dart:28`, `securite/verrou_secours.dart:27`, `acc_identifiants.dart:65,134`, `acc_secours.dart:80,119` | Verrouillage de session à 15 min (écrit **trois fois**), renouvellement du mot de passe à 90 j, blocage à 15 min, mot de passe temporaire valable 24 h | Ce sont des règles de sécurité sans paramètre. Les trois copies du délai de verrouillage peuvent diverger. | Paramètres de la famille `securite`. Le poste de secours a déjà le sien : `securite.delaiVerrouPosteSecours`. |

Ces défauts arrivent juste après :
- le tarif inventé d’une course d’ambulance (`adm_regles.dart:355` : 5 000 F + 500 F/km) ;
- la grille NS 132 tenue en **deux copies** (`rhbPrimesOrigine` et `paiPrimesNs132`), à côté de la collection versionnée `grillePrimes` ;
- les **neuf listes de services ou secteurs** écrites séparément (RH, paie, comptes, courrier, besoins, rendez-vous, accès, import, demandes du labo), alors que les collections `secteurs` et `referentiels.secteursActivite` existent ;
- les **modes de paiement** écrits en trois endroits (`m8/commun.dart`, `pil_direction.dart`, `tba_regles.dart`) ;
- les tranches de la **balance âgée des créances assureurs** (30 / 90 j) écrites en dur, alors que celles des patients sont déjà paramétrées.

> **Échéance** : les défauts n° 1 à 3, ainsi que les compteurs « de l’année 2026 », deviennent faux **le 1er janvier 2027**. Ils forment le lot 0 du plan (§ 4).

---

## 2. Les défauts, module par module

Lecture des colonnes :
- **Fam.** : la famille (A à H).
- **Ce qu’elle décide** : l’effet de la valeur dans le logiciel.
- **Où elle devrait vivre** : la destination proposée.

Les chemins sont abrégés : `domaine/` = `packages/domaine/lib/src/`, `poste/` = `apps/poste/lib/`. Dans chaque module, les lignes sont triées par gravité.


### M12 Comptabilité — 28 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | A | `poste/modules/m12/cpa_dashboard.dart:14` | 2026 | le mois de référence des courbes produits/charges du tableau de bord comptable (août 2026) | horloge du poste |
| haute | A | `domaine/comptabilite/cpa_ecritures.dart:39` | 2025 | l’état « clos » / « ouvert » d’un exercice comptable (2024 et 2025 réputés clos par constante) et la date de dépôt de la liasse | collection `exercices` (statut, date de clôture, dépôt) — la clôture existe déjà au module M12 |
| haute | A | `domaine/comptabilite/cpa_ecritures.dart:40` | 2024 | l’état « clos » / « ouvert » d’un exercice comptable (2024 et 2025 réputés clos par constante) et la date de dépôt de la liasse | collection `exercices` (statut, date de clôture, dépôt) — la clôture existe déjà au module M12 |
| haute | A | `domaine/comptabilite/cpa_ecritures.dart:41` | 2026-04-30 | l’état « clos » / « ouvert » d’un exercice comptable (2024 et 2025 réputés clos par constante) et la date de dépôt de la liasse | collection `exercices` (statut, date de clôture, dépôt) — la clôture existe déjà au module M12 |
| haute | A | `domaine/comptabilite/cpc_baseline.dart:144` | 2026 | la comparaison « 2025 / 2026 » et le filtre de l’année courante de l’écran baseline | exercice courant (horloge) ; 2025 reste une citation du classeur |
| haute | D | `domaine/comptabilite/cpc_echeances.dart:182` | cpcMoyensReglement : [Virement bancaire \| Chèque \| Espèces \| Mobile Mo | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | E | `domaine/comptabilite/aib.dart:599` | AIB-${l['reference']} | le préfixe de la numérotation de la pièce « AIB-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/comptabilite/cpa_depenses.dart:45` | DEP-${cpaAnnee(date)}- | le préfixe de la numérotation de la pièce « DEP-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/comptabilite/cpc_exercice.dart:762` | CL-$annee-${_pad5(cpcRangPiece(journal, 'CL', anne | le préfixe de la numérotation de la pièce « CL-$annee-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/comptabilite/cpc_exercice.dart:813` | AN-${annee + 1}-${_pad5(cpcRangPiece(journal, 'AN' | le préfixe de la numérotation de la pièce « AN-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/comptabilite/cpc_exercice.dart:934` | CL-$annee-C${_pad5(cpcRangPiece(journal, 'CL', ann | le préfixe de la numérotation de la pièce « CL-$annee-C… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/comptabilite/cpc_exercice.dart:935` | AN-${annee + 1}-C${_pad5(cpcRangPiece(journal, 'AN | le préfixe de la numérotation de la pièce « AN-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/comptabilite/cpc_exercice.dart:1140` | AN-${annee + 1}-00001 | le préfixe de la numérotation de la pièce « AN-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | A | `poste/modules/m12/cpc_baseline.dart:212` | Comparaison 2025 / 2026 | la comparaison « 2025 / 2026 » et le filtre de l’année courante de l’écran baseline | exercice courant (horloge) ; 2025 reste une citation du classeur |
| moyenne | A | `poste/modules/m12/cpc_baseline.dart:309` | Chiffre d’affaires 2025 et 2026 | la comparaison « 2025 / 2026 » et le filtre de l’année courante de l’écran baseline | exercice courant (horloge) ; 2025 reste une citation du classeur |
| moyenne | A | `poste/modules/m12/cpc_baseline.dart:312` | 2026 (prototype) | la comparaison « 2025 / 2026 » et le filtre de l’année courante de l’écran baseline | exercice courant (horloge) ; 2025 reste une citation du classeur |
| moyenne | C | `poste/modules/m12/cpc_bfr.dart:84` | 90 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | C | `domaine/comptabilite/cpc_bfr.dart:161` | 60 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | C | `domaine/comptabilite/cpc_echeances.dart:27` | 10 | les seuils « à payer » / « à déclarer » des échéances fiscales (10 / 30 j), copies des paramètres `fiscal.delaiAPayerJours` et `fiscal.delaiDeclarationJours` | lire les paramètres |
| moyenne | D | `poste/modules/m12/cpb_banques.dart:46` | options : [FCFA \| EUR \| USD] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `poste/modules/m12/cpb_immobilisations.dart:38` | motifs : [Cession \| Réforme \| Destruction \| Vol ou perte \| Don] (5) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/comptabilite/cpa_referentiels.dart:43` | cpaCategoriesDepense : [medical \| fonctionnement \| logistique \| entret | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/comptabilite/cpb_gestion.dart:80` | cpbCategoriesImmobilisation : [Matériel médical \| Matériel de laborato | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/comptabilite/cpb_gestion.dart:89` | cpbEtatsImmobilisation : [En service \| En maintenance \| Hors service \| | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/comptabilite/cpb_gestion.dart:90` | cpbNaturesBudget : [Charges de fonctionnement \| Investissements \| Char | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `poste/modules/m12/cpb_budgets.dart:177` | BG-${num.tryParse('${s['exercice']}')?.toInt() ??  | le préfixe de la numérotation de la pièce « BG-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m12/cpb_immobilisations.dart:304` | IM- | le préfixe de la numérotation de la pièce « IM- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/comptabilite/cpc_archive.dart:157` | ARC-$annee-${version.toString().padLeft(2, '0')} | le préfixe de la numérotation de la pièce « ARC-$annee-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |

### M1 Patients & DMI — 24 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | D | `domaine/patients/pat_fiche.dart:95` | patCategoriesAntecedent : [medicaux \| chirurgicaux \| gyneco_obstetrica | la PORTÉE de lecture des comptes rendus d’imagerie selon la FONCTION de l’agent (médecin, chirurgien, direction : tout ; sage-femme : son secteur) | gestes réservés ou droits d’écran de la matrice (RG-13) |
| haute | D | `domaine/patients/pat_patients.dart:21` | patAntecedents : [Hypertension artérielle \| Diabète de type 2 \| Asthme | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/patients/pat_patients.dart:34` | patAntecedentsRisque : [Drépanocytose \| Insuffisance rénale \| Épilepsi | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/patients/pat_patients.dart:41` | patAllergies : [Pénicilline \| Sulfamides \| Aspirine \| Arachide \| Iode  | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/patients/pat_pieces.dart:39` | patTypesPiece : [LAB-GSRH \| LAB-HEPB \| LAB-HEPC \| LAB-TPHA \| LAB-HIV … | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/patients/pat_releves.dart:112` | patEvolutions : [Guéri(e) \| Évadé(e) \| Décédé(e) \| Sortie contre avis  | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | E | `domaine/patients/pat_externe.dart:192` | FE-${date.year}-${_pad(nbFactures + 1, 5)} | le préfixe de la numérotation de la pièce « FE-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/patients/pat_pieces.dart:162` | FC-${date.year}-${_pad(nbFactures + 1, 5)} | le préfixe de la numérotation de la pièce « FC-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | G | `domaine/patients/pat_fiche.dart:110` | medecin | la PORTÉE de lecture des comptes rendus d’imagerie selon la FONCTION de l’agent (médecin, chirurgien, direction : tout ; sage-femme : son secteur) | gestes réservés ou droits d’écran de la matrice (RG-13) |
| haute | G | `domaine/patients/pat_fiche.dart:111` | chirurgien | la PORTÉE de lecture des comptes rendus d’imagerie selon la FONCTION de l’agent (médecin, chirurgien, direction : tout ; sage-femme : son secteur) | gestes réservés ou droits d’écran de la matrice (RG-13) |
| haute | G | `domaine/patients/pat_fiche.dart:114` | sage_femme | la PORTÉE de lecture des comptes rendus d’imagerie selon la FONCTION de l’agent (médecin, chirurgien, direction : tout ; sage-femme : son secteur) | gestes réservés ou droits d’écran de la matrice (RG-13) |
| moyenne | A | `poste/modules/m1/patients.dart:295` | Créés en 2026 | le libellé du compteur annuel | année courante |
| moyenne | A | `domaine/patients/pat_patients.dart:157` | 2026 | le compteur « dossiers créés cette année » (figé sur 2026) | horloge du poste |
| moyenne | B | `poste/modules/m1/documents.dart:417` | 6200 | le nombre de « dossiers actifs prioritaires » à numériser (6 200) affiché et soustrait comme un fait | paramètre du plan de numérisation (ou compte calculé depuis les dossiers vus en 24 mois) |
| moyenne | B | `poste/modules/m1/documents.dart:418` | 6200 | le nombre de « dossiers actifs prioritaires » à numériser (6 200) affiché et soustrait comme un fait | paramètre du plan de numérisation (ou compte calculé depuis les dossiers vus en 24 mois) |
| moyenne | D | `poste/modules/m1/externe.dart:18` | _services : [Maternité \| Médecine \| Médecine et spécialité] (3) | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `poste/modules/m1/fiche_impression.dart:333` | noms : [echographie \| radiographie \| mammographie \| scanner \| irm] (5) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/patients/pat_fiche.dart:11` | patTempsExamen : [inspection \| palpation \| percussion \| auscultation]  | la PORTÉE de lecture des comptes rendus d’imagerie selon la FONCTION de l’agent (médecin, chirurgien, direction : tout ; sage-femme : son secteur) | gestes réservés ou droits d’écran de la matrice (RG-13) |
| moyenne | D | `domaine/patients/pat_patients.dart:52` | patAssureurs : [AFR \| NSIA \| OLEA \| SANLAM \| TRANSVIE …] (13) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/patients/pat_releves.dart:103` | patMoyensTransport : [Ambulance \| Véhicule administratif \| Taxi \| Barq | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `poste/modules/m1/releves.dart:239` | CST- | le préfixe de la numérotation de la pièce « CST- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/patients/pat_patients.dart:244` | GED-${(nbFiches + 1).toString().padLeft(5, '0')} | le préfixe de la numérotation de la pièce « GED-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/patients/pat_releves.dart:125` | REF- | le préfixe de la numérotation de la pièce « REF- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/patients/pat_releves.dart:172` | CRF- | le préfixe de la numérotation de la pièce « CRF- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |

### M8 Facturation & caisse — 16 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | D | `poste/modules/m8/avoirs.dart:14` | motifsAvoir : [Erreur de facturation \| Interruption de soins \| Évacuat | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `poste/modules/m8/factures.dart:19` | _natures : [Consultation \| Hospitalisation \| Laboratoire \| Pharmacie \| | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/caisse/mecef.dart:342` | motifsAvoirMecef : [Erreur de facturation \| Prestation non réalisée \|  | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/caisse/remboursement.dart:41` | naturesOperation : [Facture avoir \| Remboursement \| Annulation] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | E | `poste/modules/m8/facturation.dart:569` | T-${(nbFactures + 1).toString().padLeft(5, '0')} | le préfixe de la numérotation de la pièce « T-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `poste/modules/m8/facturation.dart:597` | T-${(nbFactures + 1).toString().padLeft(5, '0')} | le préfixe de la numérotation de la pièce « T-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `poste/modules/m8/proforma.dart:33` | PRO- | le préfixe de la numérotation de la pièce « PRO- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/caisse/avoir.dart:59` | AV-${date.length >= 4 ? date.substring(0, 4) : dat | le préfixe de la numérotation de la pièce « AV-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/caisse/emission.dart:201` | PRO- | le préfixe de la numérotation de la pièce « PRO- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/caisse/encaissement.dart:325` | CAI-${date.substring(0, 4)}- | le préfixe de la numérotation de la pièce « CAI-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/caisse/remboursement.dart:66` | RB- | le préfixe de la numérotation de la pièce « RB- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/caisse/remboursement.dart:71` | RB-${(max + 1).toString().padLeft(5, '0')} | le préfixe de la numérotation de la pièce « RB-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | C | `poste/modules/m8/commun.dart:343` | 30 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | C | `poste/modules/m8/reliquats.dart:220` | 30 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | D | `poste/modules/m8/commun.dart:29` | modesPaiement : [especes \| tpe \| mtn \| moov \| assurance] (5) | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | D | `domaine/caisse/mecef.dart:267` | codesRejet : [E-101 \| E-204 \| E-307 \| E-412 \| E-500] (5) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |

### M11 Paie & primes — 16 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | A | `domaine/paie/pai_moteur.dart:1239` | 2026 | les douze mois de la courbe de masse salariale (finissent toujours en août 2026) | horloge du poste |
| haute | B | `domaine/paie/pai_moteur.dart:24` | 3.6 | le calcul des cotisations sociales de CHAQUE bulletin (CNSS 3,6 % / 16,4 %, VPS 4 %) ; la « confirmation fiscale » recopie ces constantes sans pouvoir les changer | paramètre de clinique versionné par date (famille `paie`), confirmé par le geste `fiscal_confirmer` |
| haute | B | `domaine/paie/pai_moteur.dart:25` | 16.4 | le calcul des cotisations sociales de CHAQUE bulletin (CNSS 3,6 % / 16,4 %, VPS 4 %) ; la « confirmation fiscale » recopie ces constantes sans pouvoir les changer | paramètre de clinique versionné par date (famille `paie`), confirmé par le geste `fiscal_confirmer` |
| haute | B | `domaine/paie/pai_moteur.dart:28` | 4 | le calcul des cotisations sociales de CHAQUE bulletin (CNSS 3,6 % / 16,4 %, VPS 4 %) ; la « confirmation fiscale » recopie ces constantes sans pouvoir les changer | paramètre de clinique versionné par date (famille `paie`), confirmé par le geste `fiscal_confirmer` |
| haute | E | `poste/modules/m11/pai_calcul.dart:69` | BP- | le préfixe de la numérotation de la pièce « BP- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `poste/modules/m11/pai_pieces.dart:64` | BP-${c.matricule}-${(c.mois + 1).toString().padLef | le préfixe de la numérotation de la pièce « BP-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/paie/pai_moteur.dart:947` | SAL-${date.substring(0, 4)}- | le préfixe de la numérotation de la pièce « SAL-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/paie/pai_moteur.dart:973` | PAIE-$periode | le préfixe de la numérotation de la pièce « PAIE-$periode » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | H | `domaine/paie/pai_moteur.dart:39` | paiBaremeIts : 12 valeurs (60000, 60001, 150000, 10, 150001, 250000…) | le barème progressif de l’ITS appliqué à chaque bulletin (« à confirmer par le service comptable ») | barème versionné par date (comme `baremeAib`), confirmé par geste |
| haute | H | `domaine/paie/pai_moteur.dart:191` | paiPrimesNs132 : 26 valeurs (600, 600, 700, 800, 800, 800…) | la liste des primes NS 132 parcourue par la paie et le montant « d’origine » de repli ; seconde copie de la grille déjà tenue par `rhbPrimesOrigine` | collection `grillePrimes` (déjà versionnée) : une seule graine |
| moyenne | D | `poste/modules/m11/pai_heures_avances.dart:113` | _motifsHs : [Renfort de garde \| Urgence \| Remplacement \| Surcroît d’ac | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `poste/modules/m11/pai_heures_avances.dart:235` | _motifsAvance : [Frais de santé \| Frais de scolarité \| Événement famil | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `poste/modules/m11/pai_prets.dart:42` | options : [pret_etudes \| avance \| pret_social] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/paie/pai_moteur.dart:209` | paiFonctions : [aide_soignant \| caissiere \| accueil \| infirmier \| sage | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/paie/pai_moteur.dart:231` | paiServices : [Médecine générale \| Maternité \| Chirurgie \| Laboratoire | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | E | `poste/modules/m11/pai_prets.dart:158` | PRT- | le préfixe de la numérotation de la pièce « PRT- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |

### M3 Hospitalisation & bloc — 16 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | D | `domaine/hospitalisation/bloc_regles.dart:51` | blocTechniques : [Anesthésie générale \| Rachianesthésie \| Péridurale \| | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/hospitalisation/bloc_regles.dart:58` | blocConclusionsCpa : [Apte à l’anesthésie \| Apte avec réserves \| Inter | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/hospitalisation/bloc_regles.dart:63` | blocDecisionsReveil : [Retour dans le service \| Surveillance prolongée | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/hospitalisation/bloc_regles.dart:70` | blocChecklistEntree : [Identité du patient confirmée  \| Intervention e | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/hospitalisation/hos_regles.dart:110` | hosActesSoins : [Injection intraveineuse \| Injection intramusculaire \| | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | E | `poste/modules/m3/bloc_cpa.dart:92` | CPA-2026- | le préfixe de la numérotation de la pièce « CPA-2026- » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `poste/modules/m3/bloc_cra.dart:88` | CRA-2026- | le préfixe de la numérotation de la pièce « CRA-2026- » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `poste/modules/m3/hos_observation.dart:142` | OBS-2026-${rang.toString().padLeft(4, '0')} | le préfixe de la numérotation de la pièce « OBS-2026-… » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | C | `poste/modules/m3/hos_plan_lits.dart:32` | 5 | le marquage « sortie prévue » d’un lit au plan des lits dès 5 jours de séjour | paramètre de clinique (famille `hospitalisation`) |
| moyenne | E | `poste/modules/m3/bloc_checklist.dart:95` | CKL- | le préfixe de la numérotation de la pièce « CKL- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m3/surv_administrations.dart:62` | ADM- | le préfixe de la numérotation de la pièce « ADM- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m3/surv_glasgow.dart:94` | GCS- | le préfixe de la numérotation de la pièce « GCS- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m3/surv_rapport.dart:112` | RAP- | le préfixe de la numérotation de la pièce « RAP- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m3/surv_transfusion.dart:80` | TRF- | le préfixe de la numérotation de la pièce « TRF- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/hospitalisation/bloc_regles.dart:211` | CRO- | le préfixe de la numérotation de la pièce « CRO- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| basse | G | `poste/modules/m3/surv_surveillance.dart:179` | Accueil | une décision ou un affichage pris sur un LIBELLÉ | le code du référentiel, jamais le libellé |

### M13 Administration, qualité — 29 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | B | `domaine/administration/adm_regles.dart:355` | 5000 | le prix d’une course d’ambulance sans tarif : 5 000 F + 500 F par kilomètre | référentiel tarifaire (acte « transport ambulance », prix au km) — aucun prix ne s’invente |
| haute | E | `poste/modules/m13/adm_registres.dart:210` | RU-2026- | le préfixe de la numérotation de la pièce « RU-2026- » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `poste/modules/m13/adm_registres.dart:317` | AM-2026- | le préfixe de la numérotation de la pièce « AM-2026- » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | A | `poste/modules/m13/adm_vues.dart:222` | Exercice 2026 | l’exercice affiché sur le Plan annuel de travail imprimé (chantier PTA en cours dans un autre arbre) | exercice du plan (champ de la fiche) — à traiter par le chantier PTA |
| moyenne | A | `poste/modules/m13/adm_vues.dart:224` | 2026 | l’exercice affiché sur le Plan annuel de travail imprimé (chantier PTA en cours dans un autre arbre) | exercice du plan (champ de la fiche) — à traiter par le chantier PTA |
| moyenne | A | `poste/modules/m13/adm_vues.dart:307` | Plan annuel de travail 2026 | l’exercice affiché sur le Plan annuel de travail imprimé (chantier PTA en cours dans un autre arbre) | exercice du plan (champ de la fiche) — à traiter par le chantier PTA |
| moyenne | C | `poste/modules/m13/qual_enquetes.dart:428` | 30 | la validité d’un lien d’enquête (30 j) | paramètre de clinique (famille `qualite`) |
| moyenne | C | `domaine/administration/adm_regles.dart:167` | 7 | le seuil « urgent » d’une échéance administrative (7 j) | paramètre de clinique |
| moyenne | C | `domaine/administration/adm_regles.dart:409` | 90 | l’âge au-delà duquel un numéro d’ambulance est signalé « non vérifié » (90 j) | paramètre de clinique |
| moyenne | D | `domaine/administration/adm_regles.dart:57` | admServicesCourrier : [Direction Médicale \| Direction Administrative \| | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `domaine/administration/adm_regles.dart:145` | admCategoriesEvenement : [Santé publique \| Formation \| Qualité \| Techn | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/administration/adm_regles.dart:344` | admMotifsIntervention : [Urgence médicale \| Transfert inter-hospitalie | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/administration/adm_regles.dart:536` | admCategoriesMateriel : [Automate de laboratoire \| Imagerie \| Bloc opé | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/administration/adm_regles.dart:545` | admLocalisationsMateriel : [Laboratoire \| Salle d’échographie \| Bloc o | une liste de services / secteurs de la clinique | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/qualite/qual_enquetes.dart:13` | qualTypesQuestion : [note \| choix \| texte] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/qualite/qual_validations.dart:62` | qualValidees : [Tarifs des actes (valeurs d’at \| Valorisation des 34 r | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `poste/modules/m13/adm_registres.dart:463` | EQ- | le préfixe de la numérotation de la pièce « EQ- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m13/qual_enquetes.dart:320` | ENQ-${(max + 1).toString().padLeft(3, '0')} | le préfixe de la numérotation de la pièce « ENQ-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/administration/adm_regles.dart:85` | ARR- | le préfixe de la numérotation de la pièce « ARR- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/administration/adm_regles.dart:176` | EVT-${(effectif + 1).toString().padLeft(4, '0')} | le préfixe de la numérotation de la pièce « EVT-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | G | `poste/modules/m13/qual_enquetes.dart:25` | http://serveur-clinique | l’adresse imprimée sur les liens et QR des enquêtes de satisfaction | paramètre de clinique (adresse publique du relais) |
| basse | D | `domaine/administration/adm_regles.dart:56` | admNaturesCourrier : [Lettre \| Courriel \| Note \| Facture \| Convocation | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| basse | D | `domaine/administration/adm_regles.dart:105` | admTypesReunion : [Réunion de direction \| Réunion de service \| Comité  | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| basse | D | `domaine/administration/adm_regles.dart:113` | admLieuxReunion : [Salle de réunion \| Bureau de la Direction \| Salle d | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| basse | D | `domaine/administration/adm_regles.dart:266` | admAvancementsPlan : [Réalisée \| En cours \| Planifiée] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| basse | D | `domaine/qualite/qual_enquetes.dart:20` | qualCanaux : [Au guichet \| À la sortie \| Par téléphone] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| basse | D | `domaine/qualite/qual_ged.dart:12` | qualGedCategories : [ordonnance \| resultat \| rapport \| facture_patient | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| basse | D | `domaine/qualite/qual_ged.dart:27` | qualGedRattachements : [Patient \| Employé \| Fournisseur \| Administrati | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| basse | G | `poste/modules/m13/adm_registres.dart:340` | Urgence | une décision ou un affichage pris sur un LIBELLÉ | le code du référentiel, jamais le libellé |

### M14 Sécurité & accès — 13 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | C | `domaine/acces/acc_identifiants.dart:65` | 90 | le renouvellement obligatoire du mot de passe tous les 90 jours | paramètre de clinique (famille `securite`) |
| haute | C | `domaine/acces/acc_identifiants.dart:134` | 15 | la durée du verrouillage d’un compte après échecs (15 min) | paramètre de clinique (famille `securite`) |
| haute | C | `domaine/acces/acc_secours.dart:80` | 15 | le blocage du code de secours après échecs (15 min) | paramètre de clinique (famille `securite`) |
| haute | C | `domaine/acces/acc_secours.dart:119` | 24 | la validité d’un mot de passe temporaire (24 h) | paramètre de clinique (famille `securite`) |
| haute | C | `domaine/acces/acc_verrou.dart:10` | 15 | le verrouillage de session après 15 min d’inactivité (CDCT §12.2) — écrit TROIS fois (acc_verrou, sec_exploitation, verrou_secours) | un seul paramètre `securite.delaiVerrou` (le poste de secours a déjà le sien) |
| haute | C | `domaine/securite/sec_exploitation.dart:28` | 15 | le verrouillage de session après 15 min d’inactivité (CDCT §12.2) — écrit TROIS fois (acc_verrou, sec_exploitation, verrou_secours) | un seul paramètre `securite.delaiVerrou` (le poste de secours a déjà le sien) |
| haute | C | `domaine/securite/verrou_secours.dart:20` | 5 | copie du défaut du paramètre `securite.delaiVerrouPosteSecours` | lire `securite.delaiVerrouPosteSecours` aux Paramètres |
| haute | C | `domaine/securite/verrou_secours.dart:27` | 15 | le verrouillage de session après 15 min d’inactivité (CDCT §12.2) — écrit TROIS fois (acc_verrou, sec_exploitation, verrou_secours) | un seul paramètre `securite.delaiVerrou` (le poste de secours a déjà le sien) |
| moyenne | D | `poste/modules/auth/acc_gabarit.dart:16` | specialitesClinique : [Médecine du travail \| Santé publique \| Gynécolo | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/acces/acc_agent.dart:89` | agentSecteurDeService : [Accueil \| Comptabilité \| Direction \| Administ | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `domaine/securite/sec_comptes.dart:25` | secServices : [Médecine générale \| Maternité \| Chirurgie \| Laboratoire | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | E | `domaine/acces/acc_support.dart:144` | SUP-$annee- | le préfixe de la numérotation de la pièce « SUP-$annee- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| basse | D | `domaine/acces/acc_support.dart:10` | accEditeur : [auteur \| telephone \| horaires \| version] (4) | les coordonnées de l’éditeur affichées au support (auteur, téléphone, horaires) | fiche « éditeur » réglable (comme l’identité de la clinique) |

### M10 RH — 31 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | B | `domaine/rh/rhb_regles.dart:82` | 5000 | l’honoraire mensuel du régime « incinération » (5 000 F, NS 132) | collection `regimesTravail` (le régime y est semé) — la constante ne doit servir que de graine |
| haute | H | `domaine/rh/rhb_regles.dart:282` | rhbPrimesOrigine : 26 valeurs (600, 600, 700, 800, 800, 800…) | la grille NS 132 d’origine (montants par fonction) : première copie | graine unique de `grillePrimes` |
| moyenne | B | `domaine/rh/rhc_regles.dart:239` | 1000 | la participation standard par agent aux événements du personnel (1 000 F) | paramètre de clinique (famille `rh`) |
| moyenne | C | `domaine/rh/pointage_badge.dart:20` | 5 | copie du défaut du paramètre `planning.delaiEntrePointagesBadge` | lire `planning.delaiEntrePointagesBadge` aux Paramètres |
| moyenne | C | `domaine/rh/rhc_regles.dart:55` | 24 | la durée de validité d’un badge (24 mois) — point déjà signalé « à arbitrer » | paramètre de clinique (famille `rh`) |
| moyenne | C | `domaine/rh/rhc_regles.dart:192` | 60 | l’alerte « badge expirant » (60 j) | paramètre de clinique |
| moyenne | D | `domaine/rh/rha_regles.dart:21` | rhaServices : [Médecine générale \| Maternité \| Chirurgie \| Laboratoire | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `domaine/rh/rha_regles.dart:35` | rhaTypesPlanning : [garde \| garde_hospi \| garde_soins \| permanence \| s | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/rh/rha_regles.dart:68` | rhaNaturesContrat : [CDI \| CDD \| Stage \| Prestation] (4) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/rh/rha_regles.dart:69` | rhaPeriodesEssai : [1 mois \| 3 mois \| 6 mois] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/rh/rha_regles.dart:70` | rhaNaturesConge : [Congé annuel \| Congé de maternité \| Congé de maladi | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/rh/rha_regles.dart:79` | rhaNaturesMission : [Mission \| Formation \| Représentation \| Convoyage] | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/rh/rha_regles.dart:80` | rhaMoyensMission : [Véhicule de service \| Transport en commun \| Ambula | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/rh/rha_regles.dart:83` | rhaMoyensMission : [projet \| a_valider \| validee \| en_cours \| terminee | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/rh/rha_regles.dart:102` | rhaSpecialitesPrestataire : [Circoncision \| Hydrotubation \| Accoucheme | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/rh/rha_regles.dart:112` | rhaTypesCouverture : [CNSS — régime général \| Mutuelle de santé \| Assu | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/rh/rhb_regles.dart:113` | rhbServices : [Médecine générale \| Maternité \| Chirurgie \| Laboratoire | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `domaine/rh/rhb_regles.dart:184` | rhbCriteres : 3 fiches ([Retard \| Sortie non autorisée \| Absence au po | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `poste/modules/m10/rha_conges.dart:33` | CG- | le préfixe de la numérotation de la pièce « CG- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m10/rha_contrats.dart:28` | CT- | le préfixe de la numérotation de la pièce « CT- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m10/rha_prestataires.dart:34` | PE- | le préfixe de la numérotation de la pièce « PE- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m10/rhb_evaluations.dart:231` | EV-${c.aujourdhui.year}- | le préfixe de la numérotation de la pièce « EV-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m10/rhc_evenements.dart:242` | EVT- | le préfixe de la numérotation de la pièce « EVT- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m10/rhc_participations.dart:264` | REC-PART- | le préfixe de la numérotation de la pièce « REC-PART- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m10/rhc_securite_entretien.dart:310` | SE- | le préfixe de la numérotation de la pièce « SE- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/rh/rha_regles.dart:549` | OM-$an- | le préfixe de la numérotation de la pièce « OM-$an- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/rh/rhc_regles.dart:146` | BDG-${(max + 1).toString().padLeft(5, '0')}-$annee | le préfixe de la numérotation de la pièce « BDG-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | G | `poste/modules/m10/rhb_circuit.dart:51` | daf | le nom de l’étape affiché au circuit des présences (« la directrice administrative », « le surveillant ») | organigramme / paramètre du libellé du validateur (comme `achats.libelleValidateur`) |
| basse | G | `poste/modules/m10/rhc_assurance_personnel.dart:149` | Consultation | une décision ou un affichage pris sur un LIBELLÉ | le code du référentiel, jamais le libellé |
| basse | G | `poste/modules/m10/rhc_assurance_personnel.dart:212` | Consultation | une décision ou un affichage pris sur un LIBELLÉ | le code du référentiel, jamais le libellé |
| basse | G | `poste/modules/m10/rhc_assurance_personnel.dart:214` | Hospitalisation | une décision ou un affichage pris sur un LIBELLÉ | le code du référentiel, jamais le libellé |

### M2 RDV, consultations, imagerie — 24 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | D | `domaine/specialites/spec_travail.dart:35` | mdtAptitudes : [Apte \| Apte avec aménagement de poste \| Inapte tempora | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| haute | E | `domaine/consultation/cs_moteur.dart:691` | ORD-$annee-${_pad(s.toutes('ordonnances').length + | le préfixe de la numérotation de la pièce « ORD-$annee-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/imagerie/img_demandes_ouverture.dart:224` | FI-${d.year}-${_pad(nbFactures + 1, 5)} | le préfixe de la numérotation de la pièce « FI-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | F | `domaine/consultation/cs_moteur.dart:190` | chirurgien | qui peut écrire les rubriques chirurgicales : comparaison sur le nom de rôle et la fonction | geste réservé `rubriques_chirurgicales` (déjà nommé par le cliquet) |
| moyenne | C | `domaine/consultation/ag_rendezvous.dart:281` | 4 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | C | `domaine/specialites/spec_travail.dart:79` | 30 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | D | `poste/modules/m2/ag_registres.dart:32` | c : 2 fiches ([Consultation \| Contrôle \| Urgence \| Domicile] (4)) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `poste/modules/m2/cr_saisie.dart:93` | options : [Bonne \| Moyenne \| Difficile] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `poste/modules/m2/cs_dossiers.dart:442` | options : 3 fiches ([À jour \| Incomplet \| Non vacciné \| Inconnu] (4)) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/consultation/ag_file.dart:36` | agPostes : [accueil \| consultation \| caisse \| prelevement \| pharmacie  | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/consultation/ag_rendezvous.dart:34` | agMotifsReport : [Indisponibilité du praticien \| Demande du patient \|  | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | D | `domaine/consultation/ag_rendezvous.dart:53` | agTypesRdv : [Consultation \| Contrôle \| Urgence \| Domicile \| Visite …] | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | D | `domaine/consultation/ag_rendezvous.dart:146` | agOrientations : [Médecine générale \| Chirurgie \| Maternité \| Laborato | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | D | `domaine/consultation/ag_rendezvous.dart:435` | agObjetsAppel : [Prise de rendez-vous \| Report de rendez-vous \| Demand | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | D | `domaine/consultation/ag_rendezvous.dart:447` | agSuitesAppel : [Rendez-vous fixé \| Information donnée \| Rappel à prog | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | E | `poste/modules/m2/cr_saisie.dart:467` | IMG- | le préfixe de la numérotation de la pièce « IMG- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/consultation/cs_moteur.dart:219` | DOS- | le préfixe de la numérotation de la pièce « DOS- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/consultation/cs_moteur.dart:887` | LAB- | le préfixe de la numérotation de la pièce « LAB- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/consultation/cs_moteur.dart:1152` | IME- | le préfixe de la numérotation de la pièce « IME- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/consultation/cs_moteur.dart:1246` | PRS- | le préfixe de la numérotation de la pièce « PRS- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/consultation/cs_moteur.dart:1339` | ADM- | le préfixe de la numérotation de la pièce « ADM- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/specialites/spec_travail.dart:63` | FA-${(max + 1).toString().padLeft(4, '0')}/$aa | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| basse | G | `poste/modules/m2/ag_registres.dart:367` | Urgence | une décision ou un affichage pris sur un LIBELLÉ | le code du référentiel, jamais le libellé |
| basse | G | `poste/modules/m2/ag_rendezvous.dart:396` | Urgence | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |

### M9 Assurances & créances — 15 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | D | `domaine/assurances/ass_regles.dart:378` | actesExclus : [Visites prénuptiales \| Avortements et fausses couches \| | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/assurances/ass_regles.dart:384` | produitsExclus : [Médicaments non prescrits \| Contraceptifs et hormone | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/assurances/ass_regles.dart:390` | accordPrealable : [Scanner \| Laser \| IRM \| Fibroscopie \| MAPA …] (15) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | E | `domaine/assurances/ass_regles.dart:720` | REL-${(max + 1).toString().padLeft(4, '0')} | le préfixe de la numérotation de la pièce « REL-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/assurances/ass_regles.dart:846` | FM-${auj.year}-${(nbExistantes + 1).toString().pad | le préfixe de la numérotation de la pièce « FM-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/assurances/ass_regles.dart:969` | BQ-${jour.substring(0, 4)}- | le préfixe de la numérotation de la pièce « BQ-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | C | `poste/modules/m9/historique.dart:60` | 180 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | C | `domaine/assurances/ass_regles.dart:65` | 30 | les tranches de la balance âgée des créances ASSUREURS (30 / 90 j) — celle des patients est déjà paramétrée | paramètres `comptabilite.balanceAgeeAssureurBorne1/2Jours` sur le modèle des bornes patients |
| moyenne | D | `poste/modules/m9/assures.dart:28` | options : [Changement d’employeur \| Changement de compagnie par l’ \| C | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/assurances/ass_regles.dart:112` | assConventions : [Signée \| En cours de renouvellement \| Suspendue] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/assurances/ass_regles.dart:303` | assCategoriesGarantie : [consultation \| analyse \| medicament \| vitamin | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/assurances/ass_regles.dart:341` | assCategoriesAssurance : [entreprise \| particulier \| personnel] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/assurances/ass_regles.dart:696` | assNiveauxRelance : [1re relance \| 2e relance \| Mise en demeure] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | H | `domaine/assurances/ass_regles.dart:356` | garanties : 13 fiches ([code \| libelle \| categorie \| taux \| plafond …] | le barème de référence d’un régime employeur (taux 80 %, plafonds) écrit en fiches | référentiel des garanties par convention (collection `garanties`, déjà en base) |
| basse | D | `domaine/assurances/ass_regles.dart:697` | assCanauxRelance : [Courrier remis en main propre \| Courrier électroni | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |

### M7 Achats & fournisseurs — 11 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | E | `poste/modules/m7/besoins_commandes.dart:420` | BC-2026- | le préfixe de la numérotation de la pièce « BC-2026- » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `poste/modules/m7/besoins_expression.dart:773` | BEB-2026- | le préfixe de la numérotation de la pièce « BEB-2026- » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `poste/modules/m7/pv_factures_fournisseurs.dart:601` | AIB-${r['reference']} | le préfixe de la numérotation de la pièce « AIB-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `poste/modules/m7/pv_factures_fournisseurs.dart:763` | AIBS-${vivante['reference']} | le préfixe de la numérotation de la pièce « AIBS-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/achats/besoins.dart:251` | BEB-2026- | le préfixe de la numérotation de la pièce « BEB-2026- » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/achats/commandes.dart:124` | BC-2026- | le préfixe de la numérotation de la pièce « BC-2026- » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | D | `domaine/achats/besoins.dart:65` | servicesDemandeurs : [Pharmacie d’urgence \| Laboratoire \| Hospitalisat | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `domaine/achats/besoins.dart:77` | categoriesBesoin : [Produits d’entretien (nettoyag \| Produits administ | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/achats/fournisseurs_m7.dart:20` | typesFournisseur : [Grossiste pharmaceutique \| Centrale d’achat \| Réac | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `domaine/achats/pv_reception.dart:87` | PV-${sigleNature(nature)}-$annee- | le préfixe de la numérotation de la pièce « PV-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/achats/reception.dart:148` | BL- | le préfixe de la numérotation de la pièce « BL- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |

### M4 Maternité — 17 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | D | `poste/modules/m4/mat_registres.dart:289` | (anonyme) : [Aucune \| Hémorragie de la délivrance \| Souffrance fœtale  | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `poste/modules/m4/mat_suivis.dart:344` | (anonyme) : [Placenta praevia \| Hématome rétro-placentaire \| Rupture u | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | A | `poste/modules/m4/mat_registres.dart:702` | 2026 | le compteur « accouchements de l’année » (figé sur 2026) | horloge du poste |
| moyenne | A | `poste/modules/m4/mat_registres.dart:705` | Sur l’année 2026 | le compteur « accouchements de l’année » (figé sur 2026) | horloge du poste |
| moyenne | D | `poste/modules/m4/mat_registres.dart:657` | lieux : [Hospitalisation \| Urgences \| Bloc opératoire \| Maternité \| Do | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `poste/modules/m4/mat_suivis.dart:609` | options : [Favorable \| Référée \| Décédée] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `poste/modules/m4/mat_suivis.dart:735` | options : [En attente \| Négatif \| Positif] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `poste/modules/m4/mat_partogramme.dart:84` | PARTO- | le préfixe de la numérotation de la pièce « PARTO- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m4/mat_registres.dart:228` | ACC- | le préfixe de la numérotation de la pièce « ACC- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m4/mat_registres.dart:416` | NAI- | le préfixe de la numérotation de la pièce « NAI- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m4/mat_registres.dart:664` | DEC- | le préfixe de la numérotation de la pièce « DEC- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m4/mat_suivis.dart:107` | CPN- | le préfixe de la numérotation de la pièce « CPN- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m4/mat_suivis.dart:296` | CPO- | le préfixe de la numérotation de la pièce « CPO- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m4/mat_suivis.dart:419` | PF- | le préfixe de la numérotation de la pièce « PF- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m4/mat_suivis.dart:545` | SONU- | le préfixe de la numérotation de la pièce « SONU- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m4/mat_suivis.dart:682` | PTME- | le préfixe de la numérotation de la pièce « PTME- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/m4/mat_suivis.dart:806` | SCM- | le préfixe de la numérotation de la pièce « SCM- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |

### SYNC Synchronisation (sync_dart, poste) — 14 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | A | `packages/sync_dart/lib/src/fileul.dart:165` | 2026 | l’ANNÉE du code patient attribué (RG-01) : en 2027 un nouveau dossier serait encore codé « /26 » | année de la date d’ouverture du dossier (horloge), comme `C.codePatient()` |
| haute | A | `packages/sync_dart/lib/src/mere.dart:481` | 2026 | l’ANNÉE du code patient attribué (RG-01) : en 2027 un nouveau dossier serait encore codé « /26 » | année de la date d’ouverture du dossier (horloge), comme `C.codePatient()` |
| haute | A | `packages/sync_dart/lib/src/mobile.dart:152` | 2026 | l’ANNÉE du code patient attribué (RG-01) : en 2027 un nouveau dossier serait encore codé « /26 » | année de la date d’ouverture du dossier (horloge), comme `C.codePatient()` |
| moyenne | C | `poste/sync/service_circuit_achats.dart:23` | 7 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| basse | C | `poste/sync/alerte_decisions_mere.dart:38` | 4 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| basse | C | `packages/sync_dart/lib/src/horssite_mere.dart:324` | 30 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| basse | C | `packages/sync_dart/lib/src/mere.dart:255` | 30 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| basse | C | `packages/sync_dart/lib/src/mere.dart:1186` | 20 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| basse | C | `packages/sync_dart/lib/src/supervision.dart:16` | 26 | un seuil de supervision du poste mère (propositions « à valider sur le matériel ») | paramètre d’exploitation de la mère |
| basse | C | `packages/sync_dart/lib/src/supervision.dart:17` | 50 | un seuil de supervision du poste mère (propositions « à valider sur le matériel ») | paramètre d’exploitation de la mère |
| basse | C | `packages/sync_dart/lib/src/supervision.dart:19` | 240 | un seuil de supervision du poste mère (propositions « à valider sur le matériel ») | paramètre d’exploitation de la mère |
| basse | C | `packages/sync_dart/lib/src/supervision.dart:20` | 500 | un seuil de supervision du poste mère (propositions « à valider sur le matériel ») | paramètre d’exploitation de la mère |
| basse | C | `packages/sync_dart/lib/src/supervision.dart:21` | 50 | un seuil de supervision du poste mère (propositions « à valider sur le matériel ») | paramètre d’exploitation de la mère |
| basse | C | `packages/sync_dart/lib/src/supervision.dart:22` | 2000 | un seuil de supervision du poste mère (propositions « à valider sur le matériel ») | paramètre d’exploitation de la mère |

### M5 Laboratoire & sang — 13 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | C | `domaine/labo/sang_regles.dart:30` | 90 | le délai minimal entre deux dons de sang (90 jours) qui rend un donneur éligible | paramètre médical validé par le biologiste |
| haute | D | `domaine/labo/res_saisie.dart:29` | motifsCommentaireGeneral : [Échantillon hémolysé — reprend \| Échantill | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| haute | D | `domaine/labo/res_saisie.dart:42` | valeursTypeVariable : [Positif \| Négatif \| Indéterminé] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | C | `domaine/labo/cat_regles.dart:372` | 30 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| moyenne | D | `poste/modules/m5/cat_catalogue.dart:17` | _delais : [Immédiat \| 1 h \| 2 h \| 4 h \| 6 h …] (8) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/labo/cat_regles.dart:65` | catDomainesUnite : [Hématologie \| Biochimie \| Hormonologie \| Bactériol | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/labo/res_stats.dart:58` | servicesDemandeursLabo : [maternite \| medecine \| specialite] (3) | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `domaine/labo/sang_regles.dart:27` | sangTypesDon : [Bénévole \| Familial \| Compensation] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `domaine/labo/cat_regles.dart:462` | LAB- | le préfixe de la numérotation de la pièce « LAB- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/labo/cat_regles.dart:467` | LAB-${(max + 1).toString().padLeft(4, '0')} | le préfixe de la numérotation de la pièce « LAB-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/labo/dem_regles.dart:49` | LAB- | le préfixe de la numérotation de la pièce « LAB- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/labo/sang_regles.dart:229` | DON- | le préfixe de la numérotation de la pièce « DON- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | H | `domaine/labo/res_stats.dart:38` | tranchesAge : 11 valeurs (5, 6, 15, 16, 25, 26…) | les tranches d’âge des statistiques (deux copies divergentes : 0-5/6-15… et 0-4/5-14…) | référentiel unique des tranches d’âge (format DHIS2 attendu par les rapports nationaux) |

### CFG Configuration & paramètres — 15 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | A | `domaine/configuration/cfb_fiscal_date.dart:944` | 2026 | la date « aujourd’hui » par défaut du calendrier fiscal (16/08/2026) quand l’appelant n’en passe pas | horloge du poste (obligatoire), jamais une date de jeu |
| haute | E | `domaine/configuration/cfa_regles.dart:677` | CERT-2026-${(nbToutes + 1).toString().padLeft(4, ' | le préfixe de la numérotation de la pièce « CERT-2026-… » AVEC L’ANNÉE 2026 FIGÉE | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | C | `domaine/configuration/cfa_regles.dart:664` | 45 | une borne de saisie | paramètre de clinique (definitions.dart) |
| moyenne | C | `domaine/configuration/cfb_regles.dart:185` | 30 | les échéances « proches » de la configuration fiscale (30 j) | paramètre `fiscal.delaiDeclarationJours` ou un réglage dédié |
| moyenne | C | `domaine/parametres/parametres_clinique.dart:17` | 30 | copie du défaut du paramètre `stock.joursArticlesImmobiles` | lire `stock.joursArticlesImmobiles` aux Paramètres |
| moyenne | C | `domaine/parametres/parametres_clinique.dart:20` | 90 | copie du défaut du paramètre `stock.delaiPreavisPeremptionJours` | lire `stock.delaiPreavisPeremptionJours` aux Paramètres |
| moyenne | D | `poste/modules/cfg/cft_tarifs.dart:57` | _famillesPrestations : [CONSULTATION \| ACTE \| HOSPITALISATION \| AMI \|  | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/configuration/cfa_regles.dart:70` | cfaFamillesTarif : [CONSULTATION \| IMAGERIE \| LABO \| AMI \| GYNECO …] ( | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/configuration/cfa_regles.dart:511` | cfaModelesProposes : [anniversaire \| nouvel_an \| fete \| rdv \| resultat | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `poste/modules/cfg/cfa_rappels.dart:154` | RPL- | le préfixe de la numérotation de la pièce « RPL- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `poste/modules/cfg/cfa_rappels.dart:163` | RPL-${(rang++).toString().padLeft(5, '0')} | le préfixe de la numérotation de la pièce « RPL-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/configuration/cfa_regles.dart:313` | PRD-${(nbToutes + 1).toString().padLeft(4, '0')} | le préfixe de la numérotation de la pièce « PRD-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/configuration/cfa_regles.dart:334` | ACT-${(nbToutes + 1).toString().padLeft(3, '0')} | le préfixe de la numérotation de la pièce « ACT-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/configuration/cfb_fiscal_date.dart:1021` | QUIT-$code-$exercice | le préfixe de la numérotation de la pièce « QUIT-$code-$exercice » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | F | `domaine/parametres/reglages_roles.dart:23` | comptable | le défaut semé du réglage « rôles qui clôturent l’inventaire » (comptable, admin) — écart E3584 à arbitrer | geste réservé (comme `achats_valider`), selon l’arbitrage |

### MOBILE (règles du téléphone) — 19 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| moyenne | C | `apps/mobile/lib/ui/reception.dart:33` | 120 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| moyenne | C | `domaine/mobile/mob_regles.dart:200` | 30 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_regles.dart:201` | 50 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_regles.dart:202` | 30 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_regles.dart:203` | 20 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_regles.dart:204` | 5 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_regles.dart:205` | 50 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_regles.dart:206` | 300 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_regles.dart:216` | 90 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:147` | 4 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:148` | 30 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:149` | 60 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:150` | 30 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:151` | 60 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:250` | 34 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:251` | 1000 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:300` | 30 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:301` | 10 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |
| moyenne | C | `domaine/mobile/mob_suite.dart:302` | 34 | les bornes de saisie des constantes au téléphone (refus de la saisie hors bornes) | référentiel des bornes cliniques, validé par le Directeur médical, partagé poste/mobile |

### MECeF — 5 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | E | `poste/modules/mecef/ecrans.dart:1520` | FN-2026- | le préfixe de la série des factures normalisées, avoirs et pro-forma affiché à la configuration MECeF, et le « prochain numéro » calculé sur la série 2026 | référentiel de numérotation par exercice (le moteur `emission.dart` prend déjà l’année de la facture) |
| haute | E | `poste/modules/mecef/ecrans.dart:1521` | AV-2026- | le préfixe de la série des factures normalisées, avoirs et pro-forma affiché à la configuration MECeF, et le « prochain numéro » calculé sur la série 2026 | référentiel de numérotation par exercice (le moteur `emission.dart` prend déjà l’année de la facture) |
| haute | E | `poste/modules/mecef/ecrans.dart:1522` | PRO-2026- | le préfixe de la série des factures normalisées, avoirs et pro-forma affiché à la configuration MECeF, et le « prochain numéro » calculé sur la série 2026 | référentiel de numérotation par exercice (le moteur `emission.dart` prend déjà l’année de la facture) |
| haute | E | `poste/modules/mecef/ecrans.dart:1524` | FN-2026- | le préfixe de la série des factures normalisées, avoirs et pro-forma affiché à la configuration MECeF, et le « prochain numéro » calculé sur la série 2026 | référentiel de numérotation par exercice (le moteur `emission.dart` prend déjà l’année de la facture) |
| moyenne | D | `poste/modules/mecef/ecrans.dart:1498` | options : [Automatique à l’émission \| Manuelle groupée \| Différée en f | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |

### PIL Pilotage — 6 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | B | `domaine/pilotage/pil_stats.dart:442` | 1000 | la retenue ORTB recalculée par le pilotage avec 1 000 / 3 000 / 60 000 écrits en dur, À CÔTÉ de la fiche ORTB-PARAMETRES que lit la paie | lire `PaiParametresOrtb` (la fiche en base), comme le moteur de paie |
| haute | B | `domaine/pilotage/pil_stats.dart:447` | 60000 | la retenue ORTB recalculée par le pilotage avec 1 000 / 3 000 / 60 000 écrits en dur, À CÔTÉ de la fiche ORTB-PARAMETRES que lit la paie | lire `PaiParametresOrtb` (la fiche en base), comme le moteur de paie |
| haute | D | `poste/modules/pil/pil_direction.dart:163` | _modes : [especes \| tpe \| mtn \| moov \| assurance] (5) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | A | `domaine/pilotage/pil_stats.dart:469` | 2026 | l’année retenue quand une fiche n’en porte pas | année de la date de la fiche ou horloge |
| moyenne | C | `domaine/pilotage/pil_stats.dart:131` | 30 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| moyenne | H | `domaine/pilotage/pil_stats.dart:23` | pilTranchesAgeExamens : 11 valeurs (4, 5, 14, 15, 24, 25…) | les tranches d’âge des statistiques (deux copies divergentes : 0-5/6-15… et 0-4/5-14…) | référentiel unique des tranches d’âge (format DHIS2 attendu par les rapports nationaux) |

### Import / reprise — 9 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | E | `domaine/import/jeux_import.dart:952` | AN-$an- | le préfixe de la numérotation de la pièce « AN-$an- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| haute | E | `domaine/import/jeux_import.dart:953` | AN-$an-${(existants + 1).toString().padLeft(5, '0' | le préfixe de la numérotation de la pièce « AN-$an-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | C | `domaine/import/jeux_import.dart:212` | 90 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| moyenne | D | `domaine/import/jeux_import_referentiels.dart:18` | importSecteursActivite : [Médecine générale \| Chirurgie \| Maternité \|  | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `domaine/import/jeux_import_tarifs.dart:14` | _famillesPrix : [CONSULTATION \| ACTE \| HOSPITALISATION \| AMI \| GYNECO  | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `domaine/import/jeux_import_referentiels.dart:302` | PE- | le préfixe de la numérotation de la pièce « PE- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/import/jeux_import_referentiels.dart:417` | IM- | le préfixe de la numérotation de la pièce « IM- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/import/jeux_import_referentiels.dart:505` | BG-$exercice- | le préfixe de la numérotation de la pièce « BG-$exercice- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/import/moteur_import.dart:733` | IMP-$an-${(max + 1).toString().padLeft(3, '0')} | le préfixe de la numérotation de la pièce « IMP-$an-… » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |

### M6 Pharmacie & stocks — 11 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| moyenne | C | `domaine/stock/stock.dart:22` | 90 | le préavis de péremption par défaut des fonctions de lot (90 j), copie du paramètre `stock.delaiPreavisPeremptionJours` | lire le paramètre (la constante ne doit pas servir de repli silencieux) |
| moyenne | C | `domaine/stock/stock.dart:25` | 30 | la teinte « urgente » d’un lot qui périme sous 30 jours | paramètre `stock.delaiPeremptionUrgentJours` |
| moyenne | D | `poste/modules/m6/mvt_inventaire.dart:126` | options : [Hebdomadaire \| Mensuel \| Annuel \| Tournant \| Ponctuel] (5) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `poste/modules/m6/mvt_transferts.dart:14` | _destinations : [Pharmacie d’urgence \| Pharmacie externe \| Laboratoire | une liste de services / secteurs de la clinique | collection `secteurs` (organigramme) — une seule liste |
| moyenne | D | `domaine/stock/emplacements.dart:16` | zonesEmplacement : [Rayonnage sec \| Chaîne du froid \| Armoire sécurisé | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/stock/mouvements_stock.dart:46` | categoriesProduit : [medicament \| reactif \| conso_labo \| conso_medical | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/stock/mouvements_stock.dart:92` | typesStock : [gros \| detail \| labo] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | D | `domaine/stock/mouvements_stock.dart:487` | naturesPerte : [casse \| peremption \| perte] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | E | `domaine/stock/delivrance_lignes.dart:445` | DISP- | le préfixe de la numérotation de la pièce « DISP- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/stock/mouvements_stock.dart:238` | TR- | le préfixe de la numérotation de la pièce « TR- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |
| moyenne | E | `domaine/stock/mouvements_stock.dart:536` | MVT- | le préfixe de la numérotation de la pièce « MVT- » | référentiel de numérotation (préfixe, format, remise à zéro par exercice) servi par les plages de numéros |

### MÈRE (console du poste mère) — 6 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| moyenne | C | `domaine/mere/indicateurs_clinique.dart:25` | 90 | copie du défaut du paramètre `stock.delaiPreavisPeremptionJours` | lire `stock.delaiPreavisPeremptionJours` aux Paramètres |
| basse | C | `poste/modules/mere/mrb_integrite.dart:78` | 30 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| basse | C | `poste/modules/mere/mrb_source.dart:144` | 90 | copie du défaut du paramètre `stock.delaiPreavisPeremptionJours` | lire `stock.delaiPreavisPeremptionJours` aux Paramètres |
| basse | C | `poste/modules/mere/mrb_source.dart:358` | 90 | copie du défaut du paramètre `stock.delaiPreavisPeremptionJours` | lire `stock.delaiPreavisPeremptionJours` aux Paramètres |
| basse | C | `domaine/mere/mrb_regles.dart:78` | 30 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |
| basse | C | `domaine/mere/mrb_regles.dart:126` | 30 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |

### DASH Tableaux de bord — 2 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| haute | D | `domaine/tableaux_de_bord/tba_regles.dart:509` | tbaModesPaiement : [especes \| tpe \| mtn \| moov \| assurance] (5) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| moyenne | C | `domaine/tableaux_de_bord/tba_regles.dart:279` | 5 | copie du défaut du paramètre `planning.delaiEntrePointagesBadge` | lire `planning.delaiEntrePointagesBadge` aux Paramètres |

### Assistant — 4 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| moyenne | C | `domaine/assistant/ast_conversation.dart:12` | 30 | copie du défaut du paramètre `assistant.retentionJours` | lire `assistant.retentionJours` aux Paramètres |
| moyenne | C | `domaine/assistant/ast_executeurs.dart:367` | 30 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| moyenne | C | `domaine/assistant/ast_executeurs.dart:609` | 30 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| moyenne | C | `domaine/assistant/ast_executeurs.dart:638` | 30 | copie du défaut du paramètre `stock.joursArticlesImmobiles` | lire `stock.joursArticlesImmobiles` aux Paramètres |

### Socle (kit, coque) — 2 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| moyenne | C | `poste/shell/centre_notifications.dart:66` | 3 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |
| moyenne | C | `poste/shell/son_alertes.dart:57` | 30 | une fenêtre ou un délai de gestion écrit en dur | paramètre de clinique de la famille du module |

### RAP Rapports — 2 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| basse | D | `domaine/rapports/rap_regles.dart:277` | rapDestinataires : [Direction \| Conseil de gestion \| Partenaire techni | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |
| basse | D | `domaine/rapports/rap_regles.dart:279` | rapFiligranes : [Document officiel \| Confidentiel \| Brouillon] (3) | les choix proposés à la saisie | référentiel administrable (collection `referentiels`) |

### RELAIS (Laravel) — 1 défaut(s)

| Gravité | Fam. | Fichier:ligne | Valeur | Ce qu’elle décide | Où elle devrait vivre |
|---|---|---|---|---|---|
| moyenne | C | `apps/web/app/Console/Commands/PurgerAudit.php:24` | 30 | un seuil ou une durée de gestion | paramètre de clinique (definitions.dart) |


### 2.R Référentiels compilés : fichiers engendrés et données de démonstration écrites dans `lib`

Ces fichiers ne sont pas comptés ligne par ligne. Ce sont des référentiels **statiques**, engendrés depuis la maquette (« NE PAS ÉDITER ») ou des données de démonstration. Ils sont tracés vers leur source, mais la clinique ne peut pas les modifier.

Ils ne sont pas tous fautifs : un plan comptable SYSCOHADA ou les icônes n’ont pas à être administrés. Mais plusieurs portent des **valeurs métier** que la clinique devra pouvoir régler :
- `cfb_donnees.dart` : la numérotation des pièces, avec `FN-2026-`, `BC-2026-`… en dur, les notifications et les obligations ;
- `mat_donnees.dart` : les bornes de la partographie, les fonctions SONU et les méthodes de planification familiale ;
- `cs_donnees.dart` : les appareils de l’examen clinique ;
- `mob_*_donnees.dart` : les formulaires et les bornes du mobile ;
- `adm_notes_donnees.dart` : les notes de service.

Les trois fichiers de **démonstration** de la liasse (`cpb_liasse.dart`, `cpc_*`) se remplacent par la liasse réellement déposée.

| Fichier | Nature | Lignes |
|---|---|--:|
| `apps/poste/lib/core/icones.dart` | engendré | 199 |
| `packages/domaine/lib/src/administration/adm_notes_donnees.dart` | engendré | 100 |
| `packages/domaine/lib/src/comptabilite/aib_donnees.dart` | engendré | 16 |
| `packages/domaine/lib/src/comptabilite/cpa_plan.dart` | engendré | 120 |
| `packages/domaine/lib/src/comptabilite/cpb_donnees.dart` | engendré | 152 |
| `packages/domaine/lib/src/comptabilite/cpb_liasse.dart` | démonstration | 1789 |
| `packages/domaine/lib/src/comptabilite/cpc_donnees.dart` | démonstration | 5 |
| `packages/domaine/lib/src/comptabilite/cpc_liasse.dart` | démonstration | 4 |
| `packages/domaine/lib/src/configuration/cfb_donnees.dart` | engendré | 424 |
| `packages/domaine/lib/src/consultation/cs_donnees.dart` | engendré | 460 |
| `packages/domaine/lib/src/import/donnees_import.dart` | engendré | 59 |
| `packages/domaine/lib/src/maternite/mat_donnees.dart` | engendré | 1124 |
| `packages/domaine/lib/src/mobile/mob_donnees.dart` | engendré | 114 |
| `packages/domaine/lib/src/mobile/mob_suite_donnees.dart` | engendré | 586 |
| `packages/domaine/lib/src/mobile/mob_transcription_donnees.dart` | engendré | 15 |
| `packages/domaine/lib/src/securite/sec_donnees.dart` | engendré | 231 |
| `packages/domaine/lib/src/stock/donnees_sage.dart` | engendré | 7 |


---

## 3. Ce qui est déjà propre et les garde-fous existants

**Familles et modules déjà propres** :
- **Identité de la clinique et noms de personnes : 0 trace.** Le contrôle `tools/baguidi/controle-identite.mjs` réussit. L’identité vient de `IdentiteClinique` (graine documentée, réglable à `cfg-identite`).
- **Rôles (famille F) : le cliquet tient.** `packages/domaine/test/roles_en_dur_global_test.dart` couvre les quatre racines. La relecture par le script retrouve exactement sa table : 0 écart. Sur les 141 sites tolérés, **un seul décide encore d’un droit** (cs_moteur.dart:190, signalé ci-dessus). L’autre site retenu est le défaut semé à arbitrer de `reglages_roles.dart`. Les autres sites tolérés sont des identifiants de champ, de poste, de section, de profil d’appareil ou de fonction.
- **Paramètres de clinique** : `definitions.dart` déclare 41 paramètres versionnés. Ils couvrent : MECeF, imprimante de caisse, AIB, circuit du planning, pointage, délais fiscaux, CCIB, sauvegarde hors site, péremption, articles immobiles, balance âgée des patients, rétention de l’assistant, limites d’export, alerte de la mère, rôles de clôture d’inventaire, validateur des achats.
- **Gestes réservés** : `gestes_reserves.dart` est la seule liste d’origine des droits de geste (environ 60 gestes), et la matrice les accorde ou les retire.
- **Taux et montants (B)** : **10 sites** seulement. Les tarifs, l’AIB (`baremeAib`, versionné), la CCIB, l’ORTB de la paie (fiche en base), la grille des primes (`grillePrimes`) et le barème NS 131 (`historiqueBareme`) sont déjà en base. Les défauts restants sont concentrés dans la paie et le pilotage.
- **Barèmes (H)** : **6 sites**. La plupart des grilles ont déjà été versionnées.
- **Relais Laravel** : **un seul site** (la conservation minimale de l’audit, 30 jours). Ses réglages vivent en base (`Reglages::valeur`) ou en configuration, et il ne décide d’aucune règle.
- **Modules à 5 défauts ou moins** : MECeF, Rapports, Tableaux de bord, Socle, Assistant, Relais.

**Exclus d’office, et décomptés** pour qu’on sache ce qui n’a pas été regardé comme un défaut :
- les commentaires ;
- les citations datées (« décision du 16/11/2026 ») et les références de notes de service ;
- les exemples d’aide à la saisie ;
- les constantes techniques : tailles, couleurs, durées en millisecondes, conversions d’unités, semaines calendaires, bornes de tri ;
- les énumérations d’états d’un circuit, dont la logique dépend ;
- les **semences déclarées** : défaut d’un paramètre de `definitions.dart`, constante `…Defaut` / `…Seme` lue en repli par le résolveur, fonction `amorcer…` / `semer…` / `…DeBase` ;
- les fonctions de démonstration.

**Une semence lue AUSSI directement ailleurs est comptée comme défaut** (« doublon de semence » : 16 sites). C’est le cas du préavis de péremption de 90 jours : il est écrit six fois, dont une dans le paramètre `stock.delaiPreavisPeremptionJours`.

Le détail du balayage :

| Famille | Candidats | Exclus d’office (technique, semence, citation, démo…) | Écartés à la main | **Défauts réels** |
|---|--:|--:|--:|--:|
| A Années, dates | 218 | 172 | 25 | **21** |
| B Taux, montants | 19 | 1 | 8 | **10** |
| C Seuils, durées | 213 | 31 | 104 | **78** |
| D Listes de choix | 1084 | 884 | 87 | **113** |
| E Préfixes de numérotation | 165 | 48 | 10 | **107** |
| F Rôles décisionnels | 149 | 142 | 5 | **2** |
| G Libellés d’organisation | 452 | 432 | 8 | **12** |
| H Barèmes figés | 10 | 0 | 4 | **6** |


---

## 4. Plan de lots pour ramener tout à zéro

Les lots sont regroupés par thème. Ils sont ordonnés par **urgence**, puis par **gravité**. Chaque lot convertit, ajoute ses vecteurs et ses tests, puis abaisse le cliquet (§ 4.2).

**Échelle des tailles** :
- S : 1 jour ou moins ;
- M : 2 à 4 jours ;
- L : 5 à 10 jours.

### 4.1 Les lots

| Lot | Thème | Contenu | Sites | Taille |
|---|---|---|--:|---|
| **0, avant le 31/12/2026** | Année figée | Code patient de la synchronisation (×3) ; préfixes `*-2026-` (×10) ; série MECeF à la configuration (×4) ; statut clos/ouvert des exercices de la liasse ; compteurs « de l’année 2026 » (patients, maternité, baseline) ; mois de référence des courbes (comptabilité, paie) ; date de jeu par défaut du calendrier fiscal | ≈ 30 | M |
| 1 | Paie et fiscal | CNSS et VPS en paramètre versionné ; ITS en barème daté confirmé par geste ; ORTB du pilotage lue sur la fiche ; une seule graine NS 132 ; participation standard aux événements | 8 | M |
| 2 | Numérotation | Un **référentiel de numérotation** (type de pièce, préfixe, format, largeur, remise à zéro par exercice) servi par `PlagesNumeros`. Les 107 sites E passent par une fonction unique `numeroSuivant(typePiece, date)`. On supprime au passage les numéros calculés sur le *compte* des pièces (`T-`, `FC-`, `FE-`, `FI-`), qui se dédoublent hors ligne. | 107 | L |
| 3 | Sécurité et droits | Verrouillage de session (une seule valeur) ; politique de mot de passe (90 j, 24 h, 15 min) ; portée de l’imagerie par fonction et rubriques chirurgicales converties en gestes ; arbitrage E3584 (rôles de clôture d’inventaire) | ≈ 12 | M |
| 4 | Seuils de gestion | Les 16 doublons de semence lisent leur paramètre. Nouveaux paramètres : balance âgée des créances assureurs, péremption « urgente », échéances proches, validité et alerte des badges, délai entre deux dons de sang (avec validation du biologiste), vérification des numéros d’ambulance, fenêtres de rendez-vous et d’historique, seuils de supervision de la mère | ≈ 60 | M |
| 5 | Listes de choix | Un **écran générique « Listes de la clinique »** sur la collection `referentiels` (code, libellé, ordre, actif, date d’effet). Dans l’ordre : services et secteurs (×9, vers la collection `secteurs`) ; modes et moyens de paiement ; motifs (avoir, report, retrait de badge, heures supplémentaires, avance, intervention, relance) ; RH (natures de contrat, de congé, de mission) ; administration et qualité ; listes médicales (antécédents, allergies, techniques d’anesthésie, complications, check-liste, évolutions, issues), **sous validation du Directeur médical** | 113 | L |
| 6 | Bornes cliniques | Un référentiel unique des bornes de saisie des constantes, partagé entre le poste et le mobile (19 sites) ; une seule définition des tranches d’âge statistiques (deux copies divergentes aujourd’hui) | ≈ 22 | S à M |
| 7 | Libellés et barèmes restants | Les décisions prises sur un libellé passent sur le code ; adresse des liens d’enquête ; libellés d’étape du circuit RH (organigramme) ; tarif d’ambulance au catalogue ; barème de référence des garanties vers la collection `garanties` | ≈ 15 | S |
| 8 | Référentiels compilés (R) | Fichier par fichier, la Direction décide ce qui doit devenir administrable : numérotation et notifications de `cfb_donnees`, bornes de `mat_donnees`, formulaires du mobile. Pour chaque fichier retenu : semis, collection, écran. | 17 fichiers | M à L |

> **Lot 2 livré (branche `agent-num`)** : le référentiel de numérotation unique (`packages/domaine/lib/src/numerotation/`, collection `seriesNumerotation`, section « Numérotation des pièces » de `cfg-fiscalite`, geste `numerotation_modifier`). Famille E : **107 → 0**, plus une vingtaine de sites que le détecteur ne voyait pas. Le cliquet `--cliquet --famille=E` est en service (plafond zéro). Écarts E3860 à E3874 de `ECARTS-MAQUETTE.md` ; les rangs comptés (`FM`, `FI`, `FE`, `FC`, `ORD`…) restent à arbitrer (E3866).

**Ordre de grandeur total** : 6 à 8 semaines-personne. Le lot 0 doit être livré **avant le 1er janvier 2027**. Le lot 5 est le plus long, mais il est surtout mécanique une fois l’écran générique construit.

### 4.2 Le cliquet global « valeurs en dur »

**Proposition** : on adopte la même mécanique que pour les rôles, en réutilisant ce script.

1. On engendre la ligne de base une fois avec `node tools/baguidi/inventaire-en-dur.mjs --par-fichier`. Elle donne, pour chaque fichier et chaque famille, le nombre de défauts actuels. On la verse dans `tools/baguidi/valeurs-en-dur.plafonds.json`, avec un **motif** par fichier toléré.
2. Un mode `--cliquet`, à ajouter, relance le balayage et **échoue** dans deux cas :
   - un fichier dépasse son plafond dans une famille, c’est-à-dire qu’une nouvelle valeur en dur apparaît ;
   - un fichier passe **sous** son plafond sans que la ligne de base soit abaissée. La place libérée ne doit pas resservir, et le cliquet ne remonte jamais.

   Un fichier absent de la ligne de base a un plafond de zéro.
3. On le branche là où passe déjà `controle-identite.mjs` (vérification avant livraison). On pourra le porter plus tard en test Dart, sur le modèle de `roles_en_dur_global_test.dart`.
4. Les faux positifs vérifiés vivent dans la table `ECARTES` du script, avec leur raison. Une ligne écartée qui change de texte en sort d’elle-même et redevient un candidat. Le cliquet voit donc aussi les retouches d’un site déjà toléré.

---

## 5. Limites de la mesure

- **La détection est heuristique** : expressions et contexte, sans analyse de types. Avant tri, le balayage remonte 2310 candidats. Après les exclusions d’office, il en reste 600. **251 ont ensuite été écartés à la main**, soit environ 42 % de faux positifs dans la sortie brute des règles.
  - Familles les plus bruitées : C (57 %), A (54 %), D (44 %).
  - Famille la plus fiable : E (9 %). La famille F reprend le cliquet existant tel quel ; seuls 7 sites étaient hors des sections tolérées, dont 5 descriptifs.
- **Faux positifs restants** : deux tirages de 40 défauts retenus, vérifiés à la main, en ont trouvé 1 à 2 chacun, soit **environ 5 %**. Ce sont surtout des fenêtres d’affichage et des valeurs de résultat d’un type de variable.
- **Faux négatifs probables, non mesurés** :
  - Les listes construites autrement qu’en littéral : une suite de `if` ou un `switch` sur des codes, des listes produites par une fonction. Les 166 listes anonymes « incertaines », surtout des en-têtes et des boucles d’affichage, et les 367 libellés courts de fonctions et de services affichés sans comparaison n’ont pas été revus un par un. Un signataire imprimé peut s’y cacher.
  - Les montants et seuils portés par un nom que le lexique ne connaît pas.
  - Les décisions sur une fonction ou un service écrites sous une forme que le détecteur ne reconnaît pas.
  - Les valeurs en dur dans les **gabarits d’impression** (textes légaux, mentions) : elles relèvent des libellés et n’ont pas été jugées.
- **Ce qui n’est pas couvert par le balayage** :
  - les vues Blade et Livewire du relais, et les fichiers hors `app/` et `config/` ;
  - les scripts SQL et les migrations ;
  - les fichiers engendrés, comptés en bloc (§ 2.R) ;
  - les tests, vecteurs et fixtures, exclus par la demande.
- **Gravité** : elle est proposée par des règles (chemin, nom, famille), puis relue pour les défauts les plus graves. Les gravités « moyenne » et « basse » des longues listes n’ont pas toutes été relues une à une.
- **« Ce qu’elle décide » et « où elle devrait vivre »** : ces colonnes sont rédigées à la main pour les défauts notables. Pour les autres, elles sont déduites de la famille ; c’est une orientation, pas une spécification.
- **Instantané** : le comptage reflète la branche au 16/11/2026. Un chantier PTA tourne en parallèle dans un autre arbre et touche `adm_vues.dart` et `adm_regles.dart`. Ses sites (`Plan annuel de travail 2026`, `PA-2026-`, les avancements du plan) peuvent bouger.

### Annexe : faux positifs écartés à la main, par motif

| Famille — motif | Sites |
|---|--:|
| D — fiche construite, contrôleurs, en-têtes, icônes, énumération d’états ou vocabulaire structurel | 63 |
| C — plage d’affichage, semaine calendaire, arrondi, format ou garde technique | 51 |
| C — borne technique du relais (pagination, lot, réessais, tracé) — les réglages du relais sont déjà en base ou en configuration | 17 |
| C — constante technique (rendu, format de fichier, file interne, journal plafonné) | 15 |
| A — citation du classeur 2025 (baseline documentaire, données de démonstration) | 13 |
| E — identifiant technique interne | 10 |
| D — étiquettes d’un graphique (libellés d’affichage) | 8 |
| C — délai réseau, réessais ou format d’affichage (technique) | 7 |
| C — borne de validation d’un réglage (la valeur reste au paramètre) | 6 |
| G — mention légale (RG-07 : avis du Procureur) | 5 |
| F — champ descriptif `role` des tâches d’aval (toléré au cliquet : jamais lu pour décider) | 5 |
| D — énumération structurelle (zones du badge, types de question, niveaux d’urgence, natures de ligne lues par la logique) | 4 |
| A — exemple documentaire cité (circuit de la pièce réelle) | 3 |
| C — largeur du numéro (comptée en E) | 2 |
| C — nombre de résultats affichés (faux doublon de paramètre) | 2 |
| H — graduations d’affichage de la feuille de température | 2 |
| D — état civil (énumération normative) | 2 |
| D — groupes sanguins ABO/Rh (normatif) | 2 |
| B — garde technique contre le débordement d’entier | 2 |
| B — semence documentée (prix fixé par une note datée, semé au catalogue) | 2 |
| D — libellés des états calculés d’un prix (énumération structurelle) | 1 |
| C — fenêtre d’affichage des pièces récentes | 1 |
| D — libellés des états de présence (énumération structurelle) | 1 |
| H — étiquettes de graphique | 1 |
| A — citation du classeur 2025 (baseline documentaire) | 1 |
| A — identifiant d’écran | 1 |
| D — fiche construite | 1 |
| B — valeur de tri (sentinelle) | 1 |
| D — noms de champs / fiche construite | 1 |
| A — date de la validation écrite du biologiste (métadonnée de source) | 1 |
| C — texte d’affichage | 1 |
| A — compté en E (préfixe FN-2026-) | 1 |
| G — nom de domaine du ruban (manifeste) | 1 |
| D — énumération d’étapes du circuit | 1 |
| A — date du document source du barème (métadonnée) | 1 |
| D — références de la liasse SYSCOHADA (normatif) | 1 |
| D — variables de gabarit d’un message (structurel) | 1 |
| A — date d’effet de la note de service source (métadonnée) | 1 |
| B — plafond technique du texte OCR | 1 |
| A — port mémoire des essais (jour figé de test, non lu en production) | 1 |
| A — graine documentée de la fiche de l’organigramme | 1 |
| B — conversion en millièmes (format MECeF) | 1 |
| C — nombre d’anomalies listées (technique) | 1 |
| H — semence de la fiche ORTB-PARAMETRES (PaiParametresOrtb.semence, lue en base) | 1 |
| B — semence de la fiche ORTB-PARAMETRES (PaiParametresOrtb.semence, lue en base) | 1 |
| G — identifiant de section d’un modèle de rapport (toléré au cliquet des rôles) | 1 |
| D — journal d’exploitation SIMULÉ (tirage à graine de la maquette) | 1 |
| G — faux positif (texte formaté) | 1 |
| A — semence documentée (décision de la Direction datée) | 1 |
| C — message du même contrôle (compté une fois) | 1 |

