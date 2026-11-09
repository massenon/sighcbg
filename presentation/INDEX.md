# Index et couverture des spécimens

Fichier **engendré** par `apps/poste/tool/specimens/finaliser.py` à partir de `couverture.json` (écrit par `generer_specimens_test.dart`) : ne pas l’éditer à la main.

**171 spécimens**, 268 pages, 20.9 Mo de PDF.

## Couverture par module

| Module | Spécimens |
|---|---|
| M1 — Patients & dossier médical | 6 |
| M2 — Rendez-vous, consultations, imagerie, spécialités | 21 |
| M3 — Hospitalisation, soins & bloc | 12 |
| M4 — Maternité, naissances & décès | 12 |
| M5 — Laboratoire & banque de sang | 8 |
| M6 — Pharmacie & stocks | 17 |
| M7 — Achats & fournisseurs | 6 |
| M8 — Facturation & caisse | 10 |
| M9 — Assurances & créances | 9 |
| M10 — Ressources humaines | 19 |
| M11 — Paie & primes | 7 |
| M12 — Comptabilité & gestion | 20 |
| M13 — Administration & ambulance | 6 |
| M14 — Sécurité & utilisateurs | 3 |
| MECeF — Facture normalisée | 2 |
| GED — Gestion documentaire | 2 |
| RAP — Rapports & états officiels | 2 |
| PIL — Pilotage & statistiques | 3 |
| CFG — Configuration de la clinique | 5 |
| Transverse — gabarit commun des listes filtrées | 1 |

## M1 — Patients & dossier médical

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| CERTIFICAT MÉDICAL D’ACCOUCHEMENT | [`m01-patients/certificat-medical-d-accouchement.pdf`](m01-patients/certificat-medical-d-accouchement.pdf) | 1 | `m1-pieces` | reception |  |
| CERTIFICAT MÉDICAL D’APTITUDE | [`m01-patients/certificat-medical-d-aptitude.pdf`](m01-patients/certificat-medical-d-aptitude.pdf) | 1 | `m1-pieces` | reception |  |
| Dossier complet du patient | [`m01-patients/dossier-complet-du-patient.pdf`](m01-patients/dossier-complet-du-patient.pdf) | 2 | `m1-patients` | reception |  |
| FICHE DE RÉFÉRENCE | [`m01-patients/fiche-de-reference.pdf`](m01-patients/fiche-de-reference.pdf) | 1 | `m1-reference` | reception |  |
| Fiche patient | [`m01-patients/fiche-patient.pdf`](m01-patients/fiche-patient.pdf) | 2 | `m1-patients` | reception |  |
| État d’avancement de la numérisation | [`m01-patients/etat-d-avancement-de-la-numerisation.pdf`](m01-patients/etat-d-avancement-de-la-numerisation.pdf) | 1 | `m1-numerisation` | reception |  |

## M2 — Rendez-vous, consultations, imagerie, spécialités

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Compte rendu de consultation | [`m02-consultations/compte-rendu-de-consultation.pdf`](m02-consultations/compte-rendu-de-consultation.pdf) | 1 | `m2-rendezvous` | medecin |  |
| DOSSIER DE CONSULTATION | [`m02-consultations/dossier-de-consultation.pdf`](m02-consultations/dossier-de-consultation.pdf) | 1 | `m2-dossiers-consultation` | medecin |  |
| FICHE D’APTITUDE — MÉDECINE DU TRAVAIL | [`m02-consultations/fiche-d-aptitude-medecine-du-travail.pdf`](m02-consultations/fiche-d-aptitude-medecine-du-travail.pdf) | 1 | `m2-mdt-visites` | medecin | Pièce certifiante de médecine du travail (avis d’aptitude, validité, cachet du médecin du travail). |
| IRM DU RACHIS LOMBAIRE | [`m02-consultations/irm-du-rachis-lombaire.pdf`](m02-consultations/irm-du-rachis-lombaire.pdf) | 1 | `m2-imagerie-irm` | medecin |  |
| MAMMOGRAPHIE DIAGNOSTIQUE | [`m02-consultations/mammographie-diagnostique.pdf`](m02-consultations/mammographie-diagnostique.pdf) | 1 | `m2-imagerie-mammographie` | medecin |  |
| Ordonnance médicale | [`m02-consultations/ordonnance-medicale.pdf`](m02-consultations/ordonnance-medicale.pdf) | 1 | `m2-ordonnances` | medecin |  |
| RADIOGRAPHIE DU RACHIS | [`m02-consultations/radiographie-du-rachis.pdf`](m02-consultations/radiographie-du-rachis.pdf) | 1 | `m2-imagerie-radiographie` | medecin |  |
| SCANNER CÉRÉBRAL | [`m02-consultations/scanner-cerebral.pdf`](m02-consultations/scanner-cerebral.pdf) | 1 | `m2-imagerie-scanner` | medecin |  |
| Tableau de morbidité | [`m02-consultations/tableau-de-morbidite.pdf`](m02-consultations/tableau-de-morbidite.pdf) | 1 | `m2-pathologies` | medecin |  |
| ÉCHOGRAPHIE ABDOMINALE | [`m02-consultations/echographie-abdominale.pdf`](m02-consultations/echographie-abdominale.pdf) | 1 | `m2-dashboard-imagerie` | medecin |  |
| COMPTE RENDU DE CONSULTATION — CARDIOLOGIE | [`m02-consultations/compte-rendu-de-consultation-cardiologie.pdf`](m02-consultations/compte-rendu-de-consultation-cardiologie.pdf) | 1 | `spec-cardiologie-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — CHIRURGIE | [`m02-consultations/compte-rendu-de-consultation-chirurgie.pdf`](m02-consultations/compte-rendu-de-consultation-chirurgie.pdf) | 1 | `spec-chirurgie-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — ENDOCRINOLOGIE | [`m02-consultations/compte-rendu-de-consultation-endocrinologie.pdf`](m02-consultations/compte-rendu-de-consultation-endocrinologie.pdf) | 1 | `spec-endocrinologie-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — GYNÉCOLOGIE | [`m02-consultations/compte-rendu-de-consultation-gynecologie.pdf`](m02-consultations/compte-rendu-de-consultation-gynecologie.pdf) | 1 | `spec-gynecologie-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — KINÉSITHÉRAPIE | [`m02-consultations/compte-rendu-de-consultation-kinesitherapie.pdf`](m02-consultations/compte-rendu-de-consultation-kinesitherapie.pdf) | 1 | `spec-kinesitherapie-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — MÉDECINE DU TRAVAIL | [`m02-consultations/compte-rendu-de-consultation-medecine-du-travail.pdf`](m02-consultations/compte-rendu-de-consultation-medecine-du-travail.pdf) | 1 | `spec-medecine-travail-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — NEUROLOGIE | [`m02-consultations/compte-rendu-de-consultation-neurologie.pdf`](m02-consultations/compte-rendu-de-consultation-neurologie.pdf) | 1 | `spec-neurologie-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — OPHTALMOLOGIE | [`m02-consultations/compte-rendu-de-consultation-ophtalmologie.pdf`](m02-consultations/compte-rendu-de-consultation-ophtalmologie.pdf) | 1 | `spec-ophtalmologie-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — PÉDIATRIE | [`m02-consultations/compte-rendu-de-consultation-pediatrie.pdf`](m02-consultations/compte-rendu-de-consultation-pediatrie.pdf) | 1 | `spec-pediatrie-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — RHUMATOLOGIE | [`m02-consultations/compte-rendu-de-consultation-rhumatologie.pdf`](m02-consultations/compte-rendu-de-consultation-rhumatologie.pdf) | 1 | `spec-rhumatologie-consultation` | medecin |  |
| COMPTE RENDU DE CONSULTATION — UROLOGIE | [`m02-consultations/compte-rendu-de-consultation-urologie.pdf`](m02-consultations/compte-rendu-de-consultation-urologie.pdf) | 1 | `spec-urologie-consultation` | medecin |  |

## M3 — Hospitalisation, soins & bloc

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| BON DE PANSEMENT | [`m03-hospitalisation/bon-de-pansement.pdf`](m03-hospitalisation/bon-de-pansement.pdf) | 1 | `m3-bons-pansements` | infirmier |  |
| Bon de sortie d’hospitalisation | [`m03-hospitalisation/bon-de-sortie-d-hospitalisation.pdf`](m03-hospitalisation/bon-de-sortie-d-hospitalisation.pdf) | 1 | `m3-sorties` | infirmier |  |
| Bon d’admission | [`m03-hospitalisation/bon-d-admission.pdf`](m03-hospitalisation/bon-d-admission.pdf) | 1 | `m3-admissions` | infirmier |  |
| COMPTE RENDU D’ANESTHÉSIE | [`m03-hospitalisation/compte-rendu-d-anesthesie.pdf`](m03-hospitalisation/compte-rendu-d-anesthesie.pdf) | 1 | `m3-cr-anesthesie` | infirmier |  |
| COMPTE RENDU OPÉRATOIRE | [`m03-hospitalisation/compte-rendu-operatoire.pdf`](m03-hospitalisation/compte-rendu-operatoire.pdf) | 1 | `m3-bloc-cro` | infirmier |  |
| CONSULTATION PRÉ-ANESTHÉSIQUE | [`m03-hospitalisation/consultation-pre-anesthesique.pdf`](m03-hospitalisation/consultation-pre-anesthesique.pdf) | 1 | `m3-cpa` | infirmier |  |
| Feuille de mise en observation | [`m03-hospitalisation/feuille-de-mise-en-observation.pdf`](m03-hospitalisation/feuille-de-mise-en-observation.pdf) | 1 | `m3-observation` | infirmier |  |
| Feuille de soins | [`m03-hospitalisation/feuille-de-soins.pdf`](m03-hospitalisation/feuille-de-soins.pdf) | 1 | `m3-soins` | infirmier |  |
| Feuille de température | [`m03-hospitalisation/feuille-de-temperature.pdf`](m03-hospitalisation/feuille-de-temperature.pdf) | 1 | `m3-feuille-temperature` | infirmier |  |
| Plan d’occupation des lits | [`m03-hospitalisation/plan-d-occupation-des-lits.pdf`](m03-hospitalisation/plan-d-occupation-des-lits.pdf) | 1 | `m3-chambres` | infirmier |  |
| RAPPORT MÉDICAL | [`m03-hospitalisation/rapport-medical.pdf`](m03-hospitalisation/rapport-medical.pdf) | 1 | `m3-rapport` | infirmier |  |
| Sortie contre avis médical | [`m03-hospitalisation/sortie-contre-avis-medical.pdf`](m03-hospitalisation/sortie-contre-avis-medical.pdf) | 1 | `m3-sortie-avis-medical` | infirmier | Filigrane « Document officiel », trois signatures. |

## M4 — Maternité, naissances & décès

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Attestation de naissance | [`m04-maternite/attestation-de-naissance.pdf`](m04-maternite/attestation-de-naissance.pdf) | 1 | `m4-naissances` | infirmier |  |
| Carte maternelle — suivi CPN | [`m04-maternite/carte-maternelle-suivi-cpn.pdf`](m04-maternite/carte-maternelle-suivi-cpn.pdf) | 1 | `m4-cpn` | infirmier |  |
| CERTIFICAT DE REPOS | [`m04-maternite/certificat-de-repos.pdf`](m04-maternite/certificat-de-repos.pdf) | 1 | `m4-accouchements` | infirmier |  |
| Consultation post-natale | [`m04-maternite/consultation-post-natale.pdf`](m04-maternite/consultation-post-natale.pdf) | 1 | `m4-cpon` | infirmier |  |
| Dossier obstétrical | [`m04-maternite/dossier-obstetrical.pdf`](m04-maternite/dossier-obstetrical.pdf) | 2 | `m4-dossier-obstetrical` | infirmier | Le cahier de la parturiente : CPN, partogramme, accouchement, nouveau-né. |
| Déclaration de décès | [`m04-maternite/declaration-de-deces.pdf`](m04-maternite/declaration-de-deces.pdf) | 1 | `m4-deces` | infirmier |  |
| Fiche de planification familiale | [`m04-maternite/fiche-de-planification-familiale.pdf`](m04-maternite/fiche-de-planification-familiale.pdf) | 1 | `m4-planification` | infirmier |  |
| Fiche de suivi de grossesse | [`m04-maternite/fiche-de-suivi-de-grossesse.pdf`](m04-maternite/fiche-de-suivi-de-grossesse.pdf) | 1 | `m4-maternite` | infirmier |  |
| Fiche d’accouchement | [`m04-maternite/fiche-d-accouchement.pdf`](m04-maternite/fiche-d-accouchement.pdf) | 1 | `m4-accouchements` | infirmier |  |
| PARTOGRAPHIE | [`m04-maternite/partographie.pdf`](m04-maternite/partographie.pdf) | 1 | `m4-partogramme` | infirmier | Partogramme coté (alerte à 4 cm, action décalée de 4 h). |
| Registre SONUB / SONUC — fiche d’urgence | [`m04-maternite/registre-sonub-sonuc-fiche-d-urgence.pdf`](m04-maternite/registre-sonub-sonuc-fiche-d-urgence.pdf) | 1 | `m4-sonu` | infirmier |  |
| Volet nouveau-né | [`m04-maternite/volet-nouveau-ne.pdf`](m04-maternite/volet-nouveau-ne.pdf) | 1 | `m4-dossier-bebe` | infirmier |  |

## M5 — Laboratoire & banque de sang

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Activité du laboratoire d’analyses biomédicales | [`m05-laboratoire/activite-du-laboratoire-d-analyses-biomedicales.pdf`](m05-laboratoire/activite-du-laboratoire-d-analyses-biomedicales.pdf) | 1 | `m5-stats` | laborantin |  |
| Bon de demande de sang | [`m05-laboratoire/bon-de-demande-de-sang.pdf`](m05-laboratoire/bon-de-demande-de-sang.pdf) | 1 | `m5-banque-sang` | laborantin |  |
| Bon de prélèvement | [`m05-laboratoire/bon-de-prelevement.pdf`](m05-laboratoire/bon-de-prelevement.pdf) | 1 | `m5-demandes` | laborantin |  |
| Bulletin d’analyses bio-médicales | [`m05-laboratoire/bulletin-d-analyses-bio-medicales.pdf`](m05-laboratoire/bulletin-d-analyses-bio-medicales.pdf) | 1 | `m5-prelevement` | laborantin |  |
| Carte de donneur de sang | [`m05-laboratoire/carte-de-donneur-de-sang.pdf`](m05-laboratoire/carte-de-donneur-de-sang.pdf) | 1 | `m5-donneurs` | laborantin |  |
| Référentiel des valeurs de référence | [`m05-laboratoire/referentiel-des-valeurs-de-reference.pdf`](m05-laboratoire/referentiel-des-valeurs-de-reference.pdf) | 7 | `m5-valeurs-reference` | laborantin |  |
| Résultat d’analyse de laboratoire | [`m05-laboratoire/resultat-d-analyse-de-laboratoire.pdf`](m05-laboratoire/resultat-d-analyse-de-laboratoire.pdf) | 1 | `m5-impression-resultats` | laborantin |  |
| Tarifs des analyses de laboratoire | [`m05-laboratoire/tarifs-des-analyses-de-laboratoire.pdf`](m05-laboratoire/tarifs-des-analyses-de-laboratoire.pdf) | 2 | `m5-catalogue` | laborantin |  |

## M6 — Pharmacie & stocks

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Bon de sortie de stock — dispensation | [`m06-pharmacie-stocks/bon-de-sortie-de-stock-dispensation.pdf`](m06-pharmacie-stocks/bon-de-sortie-de-stock-dispensation.pdf) | 1 | `m6-dispensation` | stock |  |
| Bon de transfert de stock | [`m06-pharmacie-stocks/bon-de-transfert-de-stock.pdf`](m06-pharmacie-stocks/bon-de-transfert-de-stock.pdf) | 1 | `m6-transferts` | stock |  |
| Bon d’expression de besoins | [`m06-pharmacie-stocks/bon-d-expression-de-besoins.pdf`](m06-pharmacie-stocks/bon-d-expression-de-besoins.pdf) | 1 | `m6-alertes` | stock |  |
| Bordereau de reprise du stock initial | [`m06-pharmacie-stocks/bordereau-de-reprise-du-stock-initial.pdf`](m06-pharmacie-stocks/bordereau-de-reprise-du-stock-initial.pdf) | 5 | `m6-import-grand-stock` | stock |  |
| Constat de pertes et casses | [`m06-pharmacie-stocks/constat-de-pertes-et-casses.pdf`](m06-pharmacie-stocks/constat-de-pertes-et-casses.pdf) | 1 | `m6-pertes` | stock |  |
| Fiche article | [`m06-pharmacie-stocks/fiche-article.pdf`](m06-pharmacie-stocks/fiche-article.pdf) | 1 | `m6-produits` | stock |  |
| Fiche de lot | [`m06-pharmacie-stocks/fiche-de-lot.pdf`](m06-pharmacie-stocks/fiche-de-lot.pdf) | 1 | `m6-lots` | stock |  |
| Point détaillé des ventes | [`m06-pharmacie-stocks/point-detaille-des-ventes.pdf`](m06-pharmacie-stocks/point-detaille-des-ventes.pdf) | 7 | `m6-point-ventes` | stock |  |
| Point global des ventes | [`m06-pharmacie-stocks/point-global-des-ventes.pdf`](m06-pharmacie-stocks/point-global-des-ventes.pdf) | 1 | `m6-point-ventes` | stock |  |
| Registre des transferts gros → détail | [`m06-pharmacie-stocks/registre-des-transferts-gros-detail.pdf`](m06-pharmacie-stocks/registre-des-transferts-gros-detail.pdf) | 8 | `m6-transferts` | stock |  |
| Stock restant à la pharmacie | [`m06-pharmacie-stocks/stock-restant-a-la-pharmacie.pdf`](m06-pharmacie-stocks/stock-restant-a-la-pharmacie.pdf) | 5 | `m6-point-stock` | stock |  |
| État des produits périmés | [`m06-pharmacie-stocks/etat-des-produits-perimes.pdf`](m06-pharmacie-stocks/etat-des-produits-perimes.pdf) | 1 | `m6-lots` | stock |  |
| État du stock détail (pharmacie d’urgence) | [`m06-pharmacie-stocks/etat-du-stock-detail-pharmacie-d-urgence.pdf`](m06-pharmacie-stocks/etat-du-stock-detail-pharmacie-d-urgence.pdf) | 3 | `m6-stock-detail` | stock |  |
| État du stock gros (magasin central) | [`m06-pharmacie-stocks/etat-du-stock-gros-magasin-central.pdf`](m06-pharmacie-stocks/etat-du-stock-gros-magasin-central.pdf) | 4 | `m6-stock-gros` | stock |  |
| État détaillé des articles transférés | [`m06-pharmacie-stocks/etat-detaille-des-articles-transferes.pdf`](m06-pharmacie-stocks/etat-detaille-des-articles-transferes.pdf) | 8 | `m6-transferts` | stock |  |
| État d’inventaire | [`m06-pharmacie-stocks/etat-d-inventaire.pdf`](m06-pharmacie-stocks/etat-d-inventaire.pdf) | 2 | `m6-inventaire` | stock |  |
| Étiquettes produits | [`m06-pharmacie-stocks/etiquettes-produits.pdf`](m06-pharmacie-stocks/etiquettes-produits.pdf) | 1 | `m6-etiquetage` | stock |  |

## M7 — Achats & fournisseurs

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Bon de commande | [`m07-achats/bon-de-commande.pdf`](m07-achats/bon-de-commande.pdf) | 1 | `m7-commandes` | stock |  |
| Bon de livraison | [`m07-achats/bon-de-livraison.pdf`](m07-achats/bon-de-livraison.pdf) | 1 | `m7-livraisons` | stock |  |
| Fiche fournisseur | [`m07-achats/fiche-fournisseur.pdf`](m07-achats/fiche-fournisseur.pdf) | 1 | `m7-fournisseurs` | stock |  |
| PROCÈS-VERBAL DE RÉCEPTION | [`m07-achats/proces-verbal-de-reception.pdf`](m07-achats/proces-verbal-de-reception.pdf) | 1 | `m7-pv-reception-consommables` | stock |  |
| Procès-verbal de réception — réactifs | [`m07-achats/proces-verbal-de-reception-reactifs.pdf`](m07-achats/proces-verbal-de-reception-reactifs.pdf) | 1 | `m7-pv-reception-reactifs` | stock |  |
| État des écarts de livraison | [`m07-achats/etat-des-ecarts-de-livraison.pdf`](m07-achats/etat-des-ecarts-de-livraison.pdf) | 1 | `m7-ecarts` | stock |  |

## M8 — Facturation & caisse

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Attestation de remboursement | [`m08-facturation-caisse/attestation-de-remboursement.pdf`](m08-facturation-caisse/attestation-de-remboursement.pdf) | 1 | `m8-remboursements` | caissier |  |
| Avis d’annulation de facture | [`m08-facturation-caisse/avis-d-annulation-de-facture.pdf`](m08-facturation-caisse/avis-d-annulation-de-facture.pdf) | 1 | `m8-remboursements` | caissier |  |
| Engagement de paiement | [`m08-facturation-caisse/engagement-de-paiement.pdf`](m08-facturation-caisse/engagement-de-paiement.pdf) | 1 | `m8-reliquats` | caissier | Échéancier par tranches de 30 jours. |
| FACTURE D’AVOIR | [`m08-facturation-caisse/facture-d-avoir.pdf`](m08-facturation-caisse/facture-d-avoir.pdf) | 1 | `m8-facture-avoir` | da | Filigrane « AVOIR », lignes annulées nommées, total négatif calculé. |
| Facture normalisée | [`m08-facturation-caisse/facture-normalisee.pdf`](m08-facturation-caisse/facture-normalisee.pdf) | 1 | `m8-factures` | caissier | Trois parts (assureur, non assurée, patient), base MECeF, montant arrêté en lettres. |
| Facture pro-forma | [`m08-facturation-caisse/facture-pro-forma.pdf`](m08-facturation-caisse/facture-pro-forma.pdf) | 1 | `m8-proforma` | caissier | Pièce non fiscale : ni bloc MECeF ni identifiant fiscal. |
| Reçu de paiement | [`m08-facturation-caisse/recu-de-paiement.pdf`](m08-facturation-caisse/recu-de-paiement.pdf) | 1 | `m8-paiements` | caissier | Détail des prestations réglées et de celles qui restent dues. |
| Ticket de caisse 80 mm | [`m08-facturation-caisse/ticket-de-caisse-80-mm.pdf`](m08-facturation-caisse/ticket-de-caisse-80-mm.pdf) | 1 | `m8-facturation` | caissier | Rouleau 80 mm (gabarit distinct du A4) : bloc MECeF, trois parts, montant arrêté en lettres. |
| État de caisse journalier | [`m08-facturation-caisse/etat-de-caisse-journalier.pdf`](m08-facturation-caisse/etat-de-caisse-journalier.pdf) | 1 | `m8-caisse` | caissier |  |
| État des recettes | [`m08-facturation-caisse/etat-des-recettes.pdf`](m08-facturation-caisse/etat-des-recettes.pdf) | 1 | `m8-recettes` | caissier |  |

## M9 — Assurances & créances

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Attestation de prise en charge | [`m09-assurances/attestation-de-prise-en-charge.pdf`](m09-assurances/attestation-de-prise-en-charge.pdf) | 1 | `m9-assures` | da |  |
| Convention de prise en charge | [`m09-assurances/convention-de-prise-en-charge.pdf`](m09-assurances/convention-de-prise-en-charge.pdf) | 1 | `m9-conventions` | da |  |
| FACTURE MÈRE — AFRICAINE DES ASSURANCES | [`m09-assurances/facture-mere-africaine-des-assurances.pdf`](m09-assurances/facture-mere-africaine-des-assurances.pdf) | 1 | `m9-facture-mere` | da |  |
| FACTURE MÈRE — NSIA ASSURANCE | [`m09-assurances/facture-mere-nsia-assurance.pdf`](m09-assurances/facture-mere-nsia-assurance.pdf) | 1 | `m9-facture-mere` | da |  |
| Facture — prestations de santé | [`m09-assurances/facture-prestations-de-sante.pdf`](m09-assurances/facture-prestations-de-sante.pdf) | 1 | `m9-factures-assureur` | da |  |
| Fiche compagnie d’assurance | [`m09-assurances/fiche-compagnie-d-assurance.pdf`](m09-assurances/fiche-compagnie-d-assurance.pdf) | 1 | `m9-compagnies` | da |  |
| Lettre de relance | [`m09-assurances/lettre-de-relance.pdf`](m09-assurances/lettre-de-relance.pdf) | 1 | `m9-relances` | da |  |
| Relevé des prestations de la clinique | [`m09-assurances/releve-des-prestations-de-la-clinique.pdf`](m09-assurances/releve-des-prestations-de-la-clinique.pdf) | 1 | `m9-factures-assureur` | da |  |
| État des créances — tiers payeurs | [`m09-assurances/etat-des-creances-tiers-payeurs.pdf`](m09-assurances/etat-des-creances-tiers-payeurs.pdf) | 1 | `m9-creances` | da |  |

## M10 — Ressources humaines

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Badge du personnel — carte CR80 | [`m10-ressources-humaines/badge-du-personnel-carte-cr80.pdf`](m10-ressources-humaines/badge-du-personnel-carte-cr80.pdf) | 2 | `m10-badges` | da | Carte CR80 (85,6 × 54 mm), recto puis verso ; QR = matricule et n° de série seulement ; ni IFU ni RCCM. |
| Contrat de travail | [`m10-ressources-humaines/contrat-de-travail.pdf`](m10-ressources-humaines/contrat-de-travail.pdf) | 1 | `m10-contrats` | da |  |
| DESCRIPTION DE POSTE | [`m10-ressources-humaines/description-de-poste.pdf`](m10-ressources-humaines/description-de-poste.pdf) | 1 | `m10-fiches-poste` | da |  |
| Décision de congé | [`m10-ressources-humaines/decision-de-conge.pdf`](m10-ressources-humaines/decision-de-conge.pdf) | 1 | `m10-conges` | da |  |
| Fiche individuelle de l’agent | [`m10-ressources-humaines/fiche-individuelle-de-l-agent.pdf`](m10-ressources-humaines/fiche-individuelle-de-l-agent.pdf) | 1 | `m10-personnel` | da |  |
| Note de service | [`m10-ressources-humaines/note-de-service.pdf`](m10-ressources-humaines/note-de-service.pdf) | 1 | `m10-evaluations` | da |  |
| Note de service — primes diverses | [`m10-ressources-humaines/note-de-service-primes-diverses.pdf`](m10-ressources-humaines/note-de-service-primes-diverses.pdf) | 1 | `m10-primes` | da |  |
| Ordre de mission | [`m10-ressources-humaines/ordre-de-mission.pdf`](m10-ressources-humaines/ordre-de-mission.pdf) | 1 | `m10-missions` | da |  |
| Planche de badges (A4) | [`m10-ressources-humaines/planche-de-badges-a4.pdf`](m10-ressources-humaines/planche-de-badges-a4.pdf) | 2 | `m10-badges-impression` | da | Planche A4 de cartes CR80. |
| Planning de garde et de permanence | [`m10-ressources-humaines/planning-de-garde-et-de-permanence.pdf`](m10-ressources-humaines/planning-de-garde-et-de-permanence.pdf) | 1 | `m10-planning` | da |  |
| Planning des agents de sécurité et d’entretien | [`m10-ressources-humaines/planning-des-agents-de-securite-et-d-entretien.pdf`](m10-ressources-humaines/planning-des-agents-de-securite-et-d-entretien.pdf) | 1 | `m10-securite-entretien` | da |  |
| Reçu de participation | [`m10-ressources-humaines/recu-de-participation.pdf`](m10-ressources-humaines/recu-de-participation.pdf) | 1 | `m10-participations` | da |  |
| Statistiques des permanences | [`m10-ressources-humaines/statistiques-des-permanences.pdf`](m10-ressources-humaines/statistiques-des-permanences.pdf) | 1 | `m10-stats-permanences` | da |  |
| Taux de présence par service | [`m10-ressources-humaines/taux-de-presence-par-service.pdf`](m10-ressources-humaines/taux-de-presence-par-service.pdf) | 1 | `m10-stats-presence` | da |  |
| État de la prise en charge du personnel | [`m10-ressources-humaines/etat-de-la-prise-en-charge-du-personnel.pdf`](m10-ressources-humaines/etat-de-la-prise-en-charge-du-personnel.pdf) | 1 | `m10-assurance-personnel` | da |  |
| État de rémunération — prestataire externe | [`m10-ressources-humaines/etat-de-remuneration-prestataire-externe.pdf`](m10-ressources-humaines/etat-de-remuneration-prestataire-externe.pdf) | 1 | `m10-prestataires` | da |  |
| État des gardes effectuées | [`m10-ressources-humaines/etat-des-gardes-effectuees.pdf`](m10-ressources-humaines/etat-des-gardes-effectuees.pdf) | 1 | `m10-stats-gardes` | da |  |
| État des participations du personnel | [`m10-ressources-humaines/etat-des-participations-du-personnel.pdf`](m10-ressources-humaines/etat-des-participations-du-personnel.pdf) | 1 | `m10-participations` | da |  |
| État des primes diverses | [`m10-ressources-humaines/etat-des-primes-diverses.pdf`](m10-ressources-humaines/etat-des-primes-diverses.pdf) | 1 | `m10-primes` | da |  |

## M11 — Paie & primes

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Bulletin de paie | [`m11-paie/bulletin-de-paie.pdf`](m11-paie/bulletin-de-paie.pdf) | 1 | `m11-calcul` | da | Bulletin individuel : rubriques, retenues, net à payer. |
| Demande d’avance sur salaire | [`m11-paie/demande-d-avance-sur-salaire.pdf`](m11-paie/demande-d-avance-sur-salaire.pdf) | 1 | `m11-avances` | da |  |
| Journal de paie | [`m11-paie/journal-de-paie.pdf`](m11-paie/journal-de-paie.pdf) | 1 | `m11-calcul` | da | Total général calculé depuis les lignes imprimées. |
| État de l’impôt sur les traitements et salaires | [`m11-paie/etat-de-l-impot-sur-les-traitements-et-salaires.pdf`](m11-paie/etat-de-l-impot-sur-les-traitements-et-salaires.pdf) | 1 | `m11-cotisations` | da |  |
| État des cotisations CNSS | [`m11-paie/etat-des-cotisations-cnss.pdf`](m11-paie/etat-des-cotisations-cnss.pdf) | 1 | `m11-cotisations` | da |  |
| État des redevances ORTB | [`m11-paie/etat-des-redevances-ortb.pdf`](m11-paie/etat-des-redevances-ortb.pdf) | 1 | `m11-cotisations` | da |  |
| État du versement patronal de solidarité | [`m11-paie/etat-du-versement-patronal-de-solidarite.pdf`](m11-paie/etat-du-versement-patronal-de-solidarite.pdf) | 1 | `m11-cotisations` | da |  |

## M12 — Comptabilité & gestion

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Balance analytique | [`m12-comptabilite/balance-analytique.pdf`](m12-comptabilite/balance-analytique.pdf) | 1 | `m12-analytique` | comptable |  |
| Balance générale des comptes | [`m12-comptabilite/balance-generale-des-comptes.pdf`](m12-comptabilite/balance-generale-des-comptes.pdf) | 1 | `m12-balance` | comptable |  |
| Barème de l’AIB — Acheteur avec IFU actif | [`m12-comptabilite/bareme-de-l-aib-acheteur-avec-ifu-actif.pdf`](m12-comptabilite/bareme-de-l-aib-acheteur-avec-ifu-actif.pdf) | 1 | `m12-aib` | comptable |  |
| Barème de l’AIB — Acheteur sans IFU actif | [`m12-comptabilite/bareme-de-l-aib-acheteur-sans-ifu-actif.pdf`](m12-comptabilite/bareme-de-l-aib-acheteur-sans-ifu-actif.pdf) | 1 | `m12-aib` | comptable |  |
| Besoin en fonds de roulement | [`m12-comptabilite/besoin-en-fonds-de-roulement.pdf`](m12-comptabilite/besoin-en-fonds-de-roulement.pdf) | 1 | `m12-bfr` | comptable |  |
| Bilan | [`m12-comptabilite/bilan.pdf`](m12-comptabilite/bilan.pdf) | 2 | `m12-immobilisations` | comptable | Feuillet de la liasse (références AD, AI, XB…) : mêmes références et même ordre que le formulaire déposé. |
| Bilan d’ouverture — à-nouveaux | [`m12-comptabilite/bilan-d-ouverture-a-nouveaux.pdf`](m12-comptabilite/bilan-d-ouverture-a-nouveaux.pdf) | 1 | `m12-ouverture` | comptable |  |
| Compte de résultat | [`m12-comptabilite/compte-de-resultat.pdf`](m12-comptabilite/compte-de-resultat.pdf) | 2 | `m12-compte-resultat` | comptable | Feuillet 7/51 de la liasse. |
| Compte de résultat — exercice 2025 | [`m12-comptabilite/compte-de-resultat-exercice-2025.pdf`](m12-comptabilite/compte-de-resultat-exercice-2025.pdf) | 2 | `m12-baseline-2025` | comptable |  |
| Coût à l’activité — marge sur consommables | [`m12-comptabilite/cout-a-l-activite-marge-sur-consommables.pdf`](m12-comptabilite/cout-a-l-activite-marge-sur-consommables.pdf) | 1 | `m12-cout-activite` | comptable |  |
| Fiche de synthèse des principaux indicateurs financiers | [`m12-comptabilite/fiche-de-synthese-des-principaux-indicateurs-financiers.pdf`](m12-comptabilite/fiche-de-synthese-des-principaux-indicateurs-financiers.pdf) | 2 | `m12-etats-financiers` | comptable |  |
| Grand livre | [`m12-comptabilite/grand-livre.pdf`](m12-comptabilite/grand-livre.pdf) | 1 | `m12-grand-livre` | comptable | État de plusieurs pages : en-tête sur la première page, pied et pagination sur toutes. |
| Journal comptable | [`m12-comptabilite/journal-comptable.pdf`](m12-comptabilite/journal-comptable.pdf) | 1 | `m12-journaux` | comptable |  |
| Justificatif de paiement — obligation fiscale | [`m12-comptabilite/justificatif-de-paiement-obligation-fiscale.pdf`](m12-comptabilite/justificatif-de-paiement-obligation-fiscale.pdf) | 1 | `m12-echeances` | comptable |  |
| Pièce de dépense | [`m12-comptabilite/piece-de-depense.pdf`](m12-comptabilite/piece-de-depense.pdf) | 1 | `m12-depenses` | comptable |  |
| Plan comptable SYSCOHADA | [`m12-comptabilite/plan-comptable-syscohada.pdf`](m12-comptabilite/plan-comptable-syscohada.pdf) | 41 | `m12-plan-comptable` | comptable | État de plusieurs pages (plan de 93 comptes). |
| Report des immobilisations à l’actif du bilan | [`m12-comptabilite/report-des-immobilisations-a-l-actif-du-bilan.pdf`](m12-comptabilite/report-des-immobilisations-a-l-actif-du-bilan.pdf) | 1 | `m12-immobilisations` | comptable |  |
| Seuil de rentabilité | [`m12-comptabilite/seuil-de-rentabilite.pdf`](m12-comptabilite/seuil-de-rentabilite.pdf) | 1 | `m12-seuil-rentabilite` | comptable |  |
| Tableau des flux de trésorerie | [`m12-comptabilite/tableau-des-flux-de-tresorerie.pdf`](m12-comptabilite/tableau-des-flux-de-tresorerie.pdf) | 2 | `m12-flux-tresorerie` | comptable | Feuillet 8/51 de la liasse, avec sa ligne de contrôle. |
| État des dépenses de trésorerie | [`m12-comptabilite/etat-des-depenses-de-tresorerie.pdf`](m12-comptabilite/etat-des-depenses-de-tresorerie.pdf) | 2 | `m12-depenses` | comptable |  |

## M13 — Administration & ambulance

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Compte rendu de réunion | [`m13-administration/compte-rendu-de-reunion.pdf`](m13-administration/compte-rendu-de-reunion.pdf) | 1 | `m13-reunions` | agentadmin |  |
| Fiche de courrier | [`m13-administration/fiche-de-courrier.pdf`](m13-administration/fiche-de-courrier.pdf) | 1 | `m13-courriers` | agentadmin |  |
| Fiche d’intervention — ambulance | [`m13-administration/fiche-d-intervention-ambulance.pdf`](m13-administration/fiche-d-intervention-ambulance.pdf) | 1 | `m13-ambulance` | agentadmin |  |
| Fiche d’équipement | [`m13-administration/fiche-d-equipement.pdf`](m13-administration/fiche-d-equipement.pdf) | 1 | `m13-maintenance` | agentadmin |  |
| Plan annuel de travail | [`m13-administration/plan-annuel-de-travail.pdf`](m13-administration/plan-annuel-de-travail.pdf) | 1 | `m13-plan-annuel` | agentadmin |  |
| Registre du courrier | [`m13-administration/registre-du-courrier.pdf`](m13-administration/registre-du-courrier.pdf) | 1 | `m13-courriers` | agentadmin |  |

## M14 — Sécurité & utilisateurs

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Fiche de compte utilisateur | [`m14-securite/fiche-de-compte-utilisateur.pdf`](m14-securite/fiche-de-compte-utilisateur.pdf) | 1 | `m14-utilisateurs` | admin |  |
| Journal d’audit | [`m14-securite/journal-d-audit.pdf`](m14-securite/journal-d-audit.pdf) | 1 | `m14-audit` | admin |  |
| Matrice des droits d’accès (RBAC) | [`m14-securite/matrice-des-droits-d-acces-rbac.pdf`](m14-securite/matrice-des-droits-d-acces-rbac.pdf) | 2 | `m14-roles` | admin |  |

## MECeF — Facture normalisée

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Avoir sur facture normalisée | [`mecef/avoir-sur-facture-normalisee.pdf`](mecef/avoir-sur-facture-normalisee.pdf) | 1 | `mecef-avoirs` | da |  |
| Facture de vente — normalisée | [`mecef/facture-de-vente-normalisee.pdf`](mecef/facture-de-vente-normalisee.pdf) | 1 | `mecef-factures` | da |  |

## GED — Gestion documentaire

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Bordereau d’archivage documentaire | [`ged/bordereau-d-archivage-documentaire.pdf`](ged/bordereau-d-archivage-documentaire.pdf) | 1 | `ged-archives` | agentadmin |  |
| Fiche documentaire | [`ged/fiche-documentaire.pdf`](ged/fiche-documentaire.pdf) | 1 | `ged-bibliotheque` | agentadmin |  |

## RAP — Rapports & états officiels

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Point mensuel — par client | [`rap-etats/point-mensuel-par-client.pdf`](rap-etats/point-mensuel-par-client.pdf) | 3 | `rapports-direction` | da |  |
| Rapport d’activité | [`rap-etats/rapport-d-activite.pdf`](rap-etats/rapport-d-activite.pdf) | 1 | `rapports-generateur` | da |  |

## PIL — Pilotage & statistiques

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Rapport d’activité — Direction | [`pil-pilotage/rapport-d-activite-direction.pdf`](pil-pilotage/rapport-d-activite-direction.pdf) | 1 | `dash-direction` | direction |  |
| Statistiques des hospitalisations | [`pil-pilotage/statistiques-des-hospitalisations.pdf`](pil-pilotage/statistiques-des-hospitalisations.pdf) | 1 | `m3-stats-hospitalisations` | direction |  |
| Tableau de bord décisionnel | [`pil-pilotage/tableau-de-bord-decisionnel.pdf`](pil-pilotage/tableau-de-bord-decisionnel.pdf) | 1 | `m12-tableau-decisionnel` | direction |  |

## CFG — Configuration de la clinique

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Aperçu du papier à en-tête | [`cfg-configuration/apercu-du-papier-a-en-tete.pdf`](cfg-configuration/apercu-du-papier-a-en-tete.pdf) | 1 | `cfg-branding` | admin |  |
| Grille tarifaire des actes et prestations | [`cfg-configuration/grille-tarifaire-des-actes-et-prestations.pdf`](cfg-configuration/grille-tarifaire-des-actes-et-prestations.pdf) | 2 | `cfg-tarifs` | admin |  |
| Matrice de traçabilité des règles métier | [`cfg-configuration/matrice-de-tracabilite-des-regles-metier.pdf`](cfg-configuration/matrice-de-tracabilite-des-regles-metier.pdf) | 2 | `cfg-regles` | admin |  |
| Organigramme de la CLINIQUE BAGUIDI | [`cfg-configuration/organigramme-de-la-clinique-baguidi.pdf`](cfg-configuration/organigramme-de-la-clinique-baguidi.pdf) | 1 | `cfg-organisation` | admin |  |
| Répartition des secteurs de la clinique | [`cfg-configuration/repartition-des-secteurs-de-la-clinique.pdf`](cfg-configuration/repartition-des-secteurs-de-la-clinique.pdf) | 1 | `cfg-organisation` | admin |  |

## Transverse — gabarit commun des listes filtrées

| Document | Fichier | Pages | Écran source | Rôle | Particularité |
|---|---|---|---|---|---|
| Sélection — liste filtrée d’un registre | [`transverse/selection-liste-filtree-d-un-registre.pdf`](transverse/selection-liste-filtree-d-un-registre.pdf) | 1 | `m4-dossier-obstetrical` | infirmier | Gabarit commun des « Imprimer la sélection » de tous les registres ; rappelle les filtres en force. |

## Documents NON produits, et pourquoi

| Module | Document | Écran | Raison |
|---|---|---|---|
| M1 | Documents numérisés du patient (m1-documents) et pièces des patients adressés de l’extérieur (m1-externe) | `m1-documents, m1-externe` | Écrans dont l’édition naît d’une ligne de registre ou d’une saisie ; les deux registres sont vides au jeu livré et la fiche ne se construit pas sans le formulaire d’accueil. Le gabarit est celui de « Fiche patient » et des certificats (M1). |
| M2 | Registre des consultations et soins à domicile | `m2-domicile` | Registre vide au jeu livré (aucune intervention à domicile) ; l’édition par ligne n’a donc rien à imprimer. |
| M3 | Fiche de demande d’examen du service | `m3-demande-examen` | La pièce n’existe qu’au moment de l’enregistrement d’un formulaire (elle porte la facture et le code d’analyse créés par le même geste) ; sa fabrique est privée à l’écran et ne peut pas être appelée avec une fiche du jeu. |
| M10 | Notification de sanction (barème NS 131) | `m10-sanctions` | Le jeu livré ne contient volontairement aucune évaluation NS 131 : aucune sanction à notifier. |
| M10 | Liste de collecte d’un événement du personnel | `m13-evenements` | Aucun événement au jeu livré ; l’alimentation d’exemple inscrite par l’outil ne fait pas apparaître la commande d’édition de ce registre (la liste de collecte se lit depuis l’état des participations, produit). |
| M11 | Bulletins stockés (m11-bulletins) et validation de la paie (m11-validation) | `m11-bulletins, m11-validation` | Même gabarit que « Bulletin de paie » et « Journal de paie », produits depuis l’écran de calcul (m11-calcul) ; les deux écrans ne portent pas de gabarit propre. |
| M5 | Bon de demande de réactifs (m5-reactifs) | `m5-reactifs` | Commande qui n’ouvre un aperçu que lorsque des réactifs sont sous leur seuil d’alerte, ce que le jeu livré ne présente pas ; le gabarit est celui de « Bon d’expression de besoins » (M6/M7). |
| CFG | Réédition d’une pièce certifiante (cfg-certificats) | `cfg-certificats` | Collection des pièces délivrées vide au jeu livré ; les pièces s’éditent depuis M1 (pièces certifiantes), produites. |
| AUTH | Code de secours de l’administrateur | `auth (installation)` | Pièce secrète produite une seule fois à l’initialisation du poste, hors manifeste d’écrans ; non rejouable sans réinstaller. |
| DASH | Fiche « Situation du patient » du tableau de bord patient | `dash-patient` | Commande atteinte seulement depuis le tableau de bord patient connecté à un dossier ; l’explorateur ne suit pas les raccourcis de navigation des tableaux de bord. |

## Éditions qui partagent le gabarit « liste filtrée d’un registre »

Un seul spécimen (`transverse/`) les représente ; les éditions suivantes ne diffèrent que par les colonnes du registre :

- Sélection — accouchements (m4-accouchements)
- Sélection — agents (m10-personnel)
- Sélection — avances (m11-avances)
- Sélection — compagnies (m9-compagnies)
- Sélection — comptes (m12-plan-comptable)
- Sélection — comptes (m14-utilisateurs)
- Sélection — congés (m10-conges)
- Sélection — consultations PF (m4-planification)
- Sélection — consultations post-natales (m4-cpon)
- Sélection — contrats (m10-contrats)
- Sélection — conventions (m2-mdt-conventions)
- Sélection — courriers (m13-courriers)
- Sélection — donneurs (m5-donneurs)
- Sélection — dossiers bébé (m4-dossier-bebe)
- Sélection — dossiers obstétricaux (m4-dossier-obstetrical)
- Sélection — déclarations (m11-heures-sup)
- Sélection — décès (m4-deces)
- Sélection — fournisseurs (m7-fournisseurs)
- Sélection — grossesses suivies (m4-cpn)
- Sélection — interventions (m13-ambulance)
- Sélection — modèles de badge (m10-badges-modeles)
- Sélection — mouvements (m6-mouvements)
- Sélection — naissances (m4-naissances)
- Sélection — prestataires (m10-prestataires)
- Sélection — réunions (m13-reunions)
- Sélection — situations de l’acheteur (m12-aib)
- Sélection — suivis de grossesse (m4-maternite)
- Sélection — taux d’AIB (versions) (m12-aib)
- Sélection — urgences obstétricales (m4-sonu)
- Sélection — équipements (m13-maintenance)
