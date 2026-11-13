# Dossier de présentation — spécimens des pièces imprimées

Ce dossier réunit **un spécimen de chaque document imprimable** du poste SIGH-CBG de la **CLINIQUE BAGUIDI « L’AS DU CŒUR »** : factures, ticket de caisse, reçus, ordonnance, bulletins
d’analyses, comptes rendus, certificats, bons de commande / livraison / sortie / transfert, bulletins de paie, états comptables et liasse, états de stock, badge, états d’imagerie, fiche
d’aptitude de médecine du travail, comptes rendus de spécialités, rapports de la Direction… Il sert à **montrer le papier** (à une réunion, à un auditeur, à l’imprimeur) sans ouvrir
le logiciel.

> **Ce sont des spécimens de démonstration.** Toutes les données viennent du **jeu de démonstration livré** avec le poste (patients et opérations fictifs ; les agents de la clinique
> n’y paraissent que comme utilisateurs ou signataires). Aucun de ces documents n’a de valeur : une mention diagonale **« SPÉCIMEN · DONNÉES FICTIVES »** est apposée sur chaque page
> **après coup** (`tool/specimens/tamponner.py`) — le gabarit d’impression du logiciel n’est pas modifié pour cela, et les vraies pièces n’ont pas cette mention.

**171 spécimens** en 20 rubriques, 268 pages, 20.9 Mo (le plus lourd : m12-comptabilite/plan-comptable-syscohada.pdf, 337 Ko).

## Ce que montrent tous les spécimens

Chaque pièce A4 reprend le **papier à en-tête** de la clinique, produit par le même gabarit que celui du poste :

- **en-tête en trois zones** : à gauche le logo et la devise manuscrite « Votre bien-être est notre raison d’être » ; au centre la dénomination « CLINIQUE BAGUIDI « L’AS DU CŒUR » » et
  l’intitulé de l’établissement ; à droite les coordonnées (BP, téléphones, e-mail, adresse), l’**IFU**, le **RCCM** et le numéro d’enregistrement ;
- **double filet** (rouge et bleu) sous l’en-tête, puis le **titre** de la pièce et son sous-titre ;
- le **cartouche** d’identification, le **tableau** dont le **total est recalculé** depuis les lignes réellement imprimées, le lieu et la date (« Fait à Parakou, le … ») ;
- les **signatures** : le nom du signataire se lit au dossier du personnel selon sa qualité, jamais dans le code (sans titulaire, la ligne reste à signer à la main) ;
- le **pied normalisé** : dénomination, IFU, RCCM, utilisateur ayant édité, date et heure, référence `CBG-AAAAMMJJ-NNNN`, pagination « Page n / N » (l’en-tête n’est porté que par la première page), « Édité depuis le SIGH-CBG ».

Deux gabarits sortent de ce modèle : le **ticket de caisse 80 mm** (rouleau, bloc MECeF, montant arrêté en lettres) et le **badge CR80** (carte 85,6 × 54 mm, recto puis verso, QR du matricule et du numéro
de série ; ni IFU ni RCCM, mentions fiscales qui n’ont rien à faire sur une carte).

## Index par module

Le tableau de **couverture** complet (écran source, rôle, pages, particularités, documents non produits et pourquoi) est dans **[INDEX.md](INDEX.md)**.

### M1 — Patients & dossier médical

- [CERTIFICAT MÉDICAL D’ACCOUCHEMENT](m01-patients/certificat-medical-d-accouchement.pdf) (1 p.)
- [CERTIFICAT MÉDICAL D’APTITUDE](m01-patients/certificat-medical-d-aptitude.pdf) (1 p.)
- [Dossier complet du patient](m01-patients/dossier-complet-du-patient.pdf) (2 p.)
- [FICHE DE RÉFÉRENCE](m01-patients/fiche-de-reference.pdf) (1 p.)
- [Fiche patient](m01-patients/fiche-patient.pdf) (2 p.)
- [État d’avancement de la numérisation](m01-patients/etat-d-avancement-de-la-numerisation.pdf) (1 p.)

### M2 — Rendez-vous, consultations, imagerie, spécialités

- [Compte rendu de consultation](m02-consultations/compte-rendu-de-consultation.pdf) (1 p.)
- [DOSSIER DE CONSULTATION](m02-consultations/dossier-de-consultation.pdf) (1 p.)
- [FICHE D’APTITUDE — MÉDECINE DU TRAVAIL](m02-consultations/fiche-d-aptitude-medecine-du-travail.pdf) (1 p.) — Pièce certifiante de médecine du travail (avis d’aptitude, validité, cachet du médecin du travail).
- [IRM DU RACHIS LOMBAIRE](m02-consultations/irm-du-rachis-lombaire.pdf) (1 p.)
- [MAMMOGRAPHIE DIAGNOSTIQUE](m02-consultations/mammographie-diagnostique.pdf) (1 p.)
- [Ordonnance médicale](m02-consultations/ordonnance-medicale.pdf) (1 p.)
- [RADIOGRAPHIE DU RACHIS](m02-consultations/radiographie-du-rachis.pdf) (1 p.)
- [SCANNER CÉRÉBRAL](m02-consultations/scanner-cerebral.pdf) (1 p.)
- [Tableau de morbidité](m02-consultations/tableau-de-morbidite.pdf) (1 p.)
- [ÉCHOGRAPHIE ABDOMINALE](m02-consultations/echographie-abdominale.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — CARDIOLOGIE](m02-consultations/compte-rendu-de-consultation-cardiologie.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — CHIRURGIE](m02-consultations/compte-rendu-de-consultation-chirurgie.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — ENDOCRINOLOGIE](m02-consultations/compte-rendu-de-consultation-endocrinologie.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — GYNÉCOLOGIE](m02-consultations/compte-rendu-de-consultation-gynecologie.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — KINÉSITHÉRAPIE](m02-consultations/compte-rendu-de-consultation-kinesitherapie.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — MÉDECINE DU TRAVAIL](m02-consultations/compte-rendu-de-consultation-medecine-du-travail.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — NEUROLOGIE](m02-consultations/compte-rendu-de-consultation-neurologie.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — OPHTALMOLOGIE](m02-consultations/compte-rendu-de-consultation-ophtalmologie.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — PÉDIATRIE](m02-consultations/compte-rendu-de-consultation-pediatrie.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — RHUMATOLOGIE](m02-consultations/compte-rendu-de-consultation-rhumatologie.pdf) (1 p.)
- [COMPTE RENDU DE CONSULTATION — UROLOGIE](m02-consultations/compte-rendu-de-consultation-urologie.pdf) (1 p.)

### M3 — Hospitalisation, soins & bloc

- [BON DE PANSEMENT](m03-hospitalisation/bon-de-pansement.pdf) (1 p.)
- [Bon de sortie d’hospitalisation](m03-hospitalisation/bon-de-sortie-d-hospitalisation.pdf) (1 p.)
- [Bon d’admission](m03-hospitalisation/bon-d-admission.pdf) (1 p.)
- [COMPTE RENDU D’ANESTHÉSIE](m03-hospitalisation/compte-rendu-d-anesthesie.pdf) (1 p.)
- [COMPTE RENDU OPÉRATOIRE](m03-hospitalisation/compte-rendu-operatoire.pdf) (1 p.)
- [CONSULTATION PRÉ-ANESTHÉSIQUE](m03-hospitalisation/consultation-pre-anesthesique.pdf) (1 p.)
- [Feuille de mise en observation](m03-hospitalisation/feuille-de-mise-en-observation.pdf) (1 p.)
- [Feuille de soins](m03-hospitalisation/feuille-de-soins.pdf) (1 p.)
- [Feuille de température](m03-hospitalisation/feuille-de-temperature.pdf) (1 p.)
- [Plan d’occupation des lits](m03-hospitalisation/plan-d-occupation-des-lits.pdf) (1 p.)
- [RAPPORT MÉDICAL](m03-hospitalisation/rapport-medical.pdf) (1 p.)
- [Sortie contre avis médical](m03-hospitalisation/sortie-contre-avis-medical.pdf) (1 p.) — Filigrane « Document officiel », trois signatures.

### M4 — Maternité, naissances & décès

- [Attestation de naissance](m04-maternite/attestation-de-naissance.pdf) (1 p.)
- [Carte maternelle — suivi CPN](m04-maternite/carte-maternelle-suivi-cpn.pdf) (1 p.)
- [CERTIFICAT DE REPOS](m04-maternite/certificat-de-repos.pdf) (1 p.)
- [Consultation post-natale](m04-maternite/consultation-post-natale.pdf) (1 p.)
- [Dossier obstétrical](m04-maternite/dossier-obstetrical.pdf) (2 p.) — Le cahier de la parturiente : CPN, partogramme, accouchement, nouveau-né.
- [Déclaration de décès](m04-maternite/declaration-de-deces.pdf) (1 p.)
- [Fiche de planification familiale](m04-maternite/fiche-de-planification-familiale.pdf) (1 p.)
- [Fiche de suivi de grossesse](m04-maternite/fiche-de-suivi-de-grossesse.pdf) (1 p.)
- [Fiche d’accouchement](m04-maternite/fiche-d-accouchement.pdf) (1 p.)
- [PARTOGRAPHIE](m04-maternite/partographie.pdf) (1 p.) — Partogramme coté (alerte à 4 cm, action décalée de 4 h).
- [Registre SONUB / SONUC — fiche d’urgence](m04-maternite/registre-sonub-sonuc-fiche-d-urgence.pdf) (1 p.)
- [Volet nouveau-né](m04-maternite/volet-nouveau-ne.pdf) (1 p.)

### M5 — Laboratoire & banque de sang

- [Activité du laboratoire d’analyses biomédicales](m05-laboratoire/activite-du-laboratoire-d-analyses-biomedicales.pdf) (1 p.)
- [Bon de demande de sang](m05-laboratoire/bon-de-demande-de-sang.pdf) (1 p.)
- [Bon de prélèvement](m05-laboratoire/bon-de-prelevement.pdf) (1 p.)
- [Bulletin d’analyses bio-médicales](m05-laboratoire/bulletin-d-analyses-bio-medicales.pdf) (1 p.)
- [Carte de donneur de sang](m05-laboratoire/carte-de-donneur-de-sang.pdf) (1 p.)
- [Référentiel des valeurs de référence](m05-laboratoire/referentiel-des-valeurs-de-reference.pdf) (7 p.)
- [Résultat d’analyse de laboratoire](m05-laboratoire/resultat-d-analyse-de-laboratoire.pdf) (1 p.)
- [Tarifs des analyses de laboratoire](m05-laboratoire/tarifs-des-analyses-de-laboratoire.pdf) (2 p.)

### M6 — Pharmacie & stocks

- [Bon de sortie de stock — dispensation](m06-pharmacie-stocks/bon-de-sortie-de-stock-dispensation.pdf) (1 p.)
- [Bon de transfert de stock](m06-pharmacie-stocks/bon-de-transfert-de-stock.pdf) (1 p.)
- [Bon d’expression de besoins](m06-pharmacie-stocks/bon-d-expression-de-besoins.pdf) (1 p.)
- [Bordereau de reprise du stock initial](m06-pharmacie-stocks/bordereau-de-reprise-du-stock-initial.pdf) (5 p.)
- [Constat de pertes et casses](m06-pharmacie-stocks/constat-de-pertes-et-casses.pdf) (1 p.)
- [Fiche article](m06-pharmacie-stocks/fiche-article.pdf) (1 p.)
- [Fiche de lot](m06-pharmacie-stocks/fiche-de-lot.pdf) (1 p.)
- [Point détaillé des ventes](m06-pharmacie-stocks/point-detaille-des-ventes.pdf) (7 p.)
- [Point global des ventes](m06-pharmacie-stocks/point-global-des-ventes.pdf) (1 p.)
- [Registre des transferts gros → détail](m06-pharmacie-stocks/registre-des-transferts-gros-detail.pdf) (8 p.)
- [Stock restant à la pharmacie](m06-pharmacie-stocks/stock-restant-a-la-pharmacie.pdf) (5 p.)
- [État des produits périmés](m06-pharmacie-stocks/etat-des-produits-perimes.pdf) (1 p.)
- [État du stock détail (pharmacie d’urgence)](m06-pharmacie-stocks/etat-du-stock-detail-pharmacie-d-urgence.pdf) (3 p.)
- [État du stock gros (magasin central)](m06-pharmacie-stocks/etat-du-stock-gros-magasin-central.pdf) (4 p.)
- [État détaillé des articles transférés](m06-pharmacie-stocks/etat-detaille-des-articles-transferes.pdf) (8 p.)
- [État d’inventaire](m06-pharmacie-stocks/etat-d-inventaire.pdf) (2 p.)
- [Étiquettes produits](m06-pharmacie-stocks/etiquettes-produits.pdf) (1 p.)

### M7 — Achats & fournisseurs

- [Bon de commande](m07-achats/bon-de-commande.pdf) (1 p.)
- [Bon de livraison](m07-achats/bon-de-livraison.pdf) (1 p.)
- [Fiche fournisseur](m07-achats/fiche-fournisseur.pdf) (1 p.)
- [PROCÈS-VERBAL DE RÉCEPTION](m07-achats/proces-verbal-de-reception.pdf) (1 p.)
- [Procès-verbal de réception — réactifs](m07-achats/proces-verbal-de-reception-reactifs.pdf) (1 p.)
- [État des écarts de livraison](m07-achats/etat-des-ecarts-de-livraison.pdf) (1 p.)

### M8 — Facturation & caisse

- [Attestation de remboursement](m08-facturation-caisse/attestation-de-remboursement.pdf) (1 p.)
- [Avis d’annulation de facture](m08-facturation-caisse/avis-d-annulation-de-facture.pdf) (1 p.)
- [Engagement de paiement](m08-facturation-caisse/engagement-de-paiement.pdf) (1 p.) — Échéancier par tranches de 30 jours.
- [FACTURE D’AVOIR](m08-facturation-caisse/facture-d-avoir.pdf) (1 p.) — Filigrane « AVOIR », lignes annulées nommées, total négatif calculé.
- [Facture normalisée](m08-facturation-caisse/facture-normalisee.pdf) (1 p.) — Trois parts (assureur, non assurée, patient), base MECeF, montant arrêté en lettres.
- [Facture pro-forma](m08-facturation-caisse/facture-pro-forma.pdf) (1 p.) — Pièce non fiscale : ni bloc MECeF ni identifiant fiscal.
- [Reçu de paiement](m08-facturation-caisse/recu-de-paiement.pdf) (1 p.) — Détail des prestations réglées et de celles qui restent dues.
- [Ticket de caisse 80 mm](m08-facturation-caisse/ticket-de-caisse-80-mm.pdf) (1 p.) — Rouleau 80 mm (gabarit distinct du A4) : bloc MECeF, trois parts, montant arrêté en lettres.
- [État de caisse journalier](m08-facturation-caisse/etat-de-caisse-journalier.pdf) (1 p.)
- [État des recettes](m08-facturation-caisse/etat-des-recettes.pdf) (1 p.)

### M9 — Assurances & créances

- [Attestation de prise en charge](m09-assurances/attestation-de-prise-en-charge.pdf) (1 p.)
- [Convention de prise en charge](m09-assurances/convention-de-prise-en-charge.pdf) (1 p.)
- [FACTURE MÈRE — AFRICAINE DES ASSURANCES](m09-assurances/facture-mere-africaine-des-assurances.pdf) (1 p.)
- [FACTURE MÈRE — NSIA ASSURANCE](m09-assurances/facture-mere-nsia-assurance.pdf) (1 p.)
- [Facture — prestations de santé](m09-assurances/facture-prestations-de-sante.pdf) (1 p.)
- [Fiche compagnie d’assurance](m09-assurances/fiche-compagnie-d-assurance.pdf) (1 p.)
- [Lettre de relance](m09-assurances/lettre-de-relance.pdf) (1 p.)
- [Relevé des prestations de la clinique](m09-assurances/releve-des-prestations-de-la-clinique.pdf) (1 p.)
- [État des créances — tiers payeurs](m09-assurances/etat-des-creances-tiers-payeurs.pdf) (1 p.)

### M10 — Ressources humaines

- [Badge du personnel — carte CR80](m10-ressources-humaines/badge-du-personnel-carte-cr80.pdf) (2 p.) — Carte CR80 (85,6 × 54 mm), recto puis verso ; QR = matricule et n° de série seulement ; ni IFU ni RCCM.
- [Contrat de travail](m10-ressources-humaines/contrat-de-travail.pdf) (1 p.)
- [DESCRIPTION DE POSTE](m10-ressources-humaines/description-de-poste.pdf) (1 p.)
- [Décision de congé](m10-ressources-humaines/decision-de-conge.pdf) (1 p.)
- [Fiche individuelle de l’agent](m10-ressources-humaines/fiche-individuelle-de-l-agent.pdf) (1 p.)
- [Note de service](m10-ressources-humaines/note-de-service.pdf) (1 p.)
- [Note de service — primes diverses](m10-ressources-humaines/note-de-service-primes-diverses.pdf) (1 p.)
- [Ordre de mission](m10-ressources-humaines/ordre-de-mission.pdf) (1 p.)
- [Planche de badges (A4)](m10-ressources-humaines/planche-de-badges-a4.pdf) (2 p.) — Planche A4 de cartes CR80.
- [Planning de garde et de permanence](m10-ressources-humaines/planning-de-garde-et-de-permanence.pdf) (1 p.)
- [Planning des agents de sécurité et d’entretien](m10-ressources-humaines/planning-des-agents-de-securite-et-d-entretien.pdf) (1 p.)
- [Reçu de participation](m10-ressources-humaines/recu-de-participation.pdf) (1 p.)
- [Statistiques des permanences](m10-ressources-humaines/statistiques-des-permanences.pdf) (1 p.)
- [Taux de présence par service](m10-ressources-humaines/taux-de-presence-par-service.pdf) (1 p.)
- [État de la prise en charge du personnel](m10-ressources-humaines/etat-de-la-prise-en-charge-du-personnel.pdf) (1 p.)
- [État de rémunération — prestataire externe](m10-ressources-humaines/etat-de-remuneration-prestataire-externe.pdf) (1 p.)
- [État des gardes effectuées](m10-ressources-humaines/etat-des-gardes-effectuees.pdf) (1 p.)
- [État des participations du personnel](m10-ressources-humaines/etat-des-participations-du-personnel.pdf) (1 p.)
- [État des primes diverses](m10-ressources-humaines/etat-des-primes-diverses.pdf) (1 p.)

### M11 — Paie & primes

- [Bulletin de paie](m11-paie/bulletin-de-paie.pdf) (1 p.) — Bulletin individuel : rubriques, retenues, net à payer.
- [Demande d’avance sur salaire](m11-paie/demande-d-avance-sur-salaire.pdf) (1 p.)
- [Journal de paie](m11-paie/journal-de-paie.pdf) (1 p.) — Total général calculé depuis les lignes imprimées.
- [État de l’impôt sur les traitements et salaires](m11-paie/etat-de-l-impot-sur-les-traitements-et-salaires.pdf) (1 p.)
- [État des cotisations CNSS](m11-paie/etat-des-cotisations-cnss.pdf) (1 p.)
- [État des redevances ORTB](m11-paie/etat-des-redevances-ortb.pdf) (1 p.)
- [État du versement patronal de solidarité](m11-paie/etat-du-versement-patronal-de-solidarite.pdf) (1 p.)

### M12 — Comptabilité & gestion

- [Balance analytique](m12-comptabilite/balance-analytique.pdf) (1 p.)
- [Balance générale des comptes](m12-comptabilite/balance-generale-des-comptes.pdf) (1 p.)
- [Barème de l’AIB — Acheteur avec IFU actif](m12-comptabilite/bareme-de-l-aib-acheteur-avec-ifu-actif.pdf) (1 p.)
- [Barème de l’AIB — Acheteur sans IFU actif](m12-comptabilite/bareme-de-l-aib-acheteur-sans-ifu-actif.pdf) (1 p.)
- [Besoin en fonds de roulement](m12-comptabilite/besoin-en-fonds-de-roulement.pdf) (1 p.)
- [Bilan](m12-comptabilite/bilan.pdf) (2 p.) — Feuillet de la liasse (références AD, AI, XB…) : mêmes références et même ordre que le formulaire déposé.
- [Bilan d’ouverture — à-nouveaux](m12-comptabilite/bilan-d-ouverture-a-nouveaux.pdf) (1 p.)
- [Compte de résultat](m12-comptabilite/compte-de-resultat.pdf) (2 p.) — Feuillet 7/51 de la liasse.
- [Compte de résultat — exercice 2025](m12-comptabilite/compte-de-resultat-exercice-2025.pdf) (2 p.)
- [Coût à l’activité — marge sur consommables](m12-comptabilite/cout-a-l-activite-marge-sur-consommables.pdf) (1 p.)
- [Fiche de synthèse des principaux indicateurs financiers](m12-comptabilite/fiche-de-synthese-des-principaux-indicateurs-financiers.pdf) (2 p.)
- [Grand livre](m12-comptabilite/grand-livre.pdf) (1 p.) — État de plusieurs pages : en-tête sur la première page, pied et pagination sur toutes.
- [Journal comptable](m12-comptabilite/journal-comptable.pdf) (1 p.)
- [Justificatif de paiement — obligation fiscale](m12-comptabilite/justificatif-de-paiement-obligation-fiscale.pdf) (1 p.)
- [Pièce de dépense](m12-comptabilite/piece-de-depense.pdf) (1 p.)
- [Plan comptable SYSCOHADA](m12-comptabilite/plan-comptable-syscohada.pdf) (41 p.) — État de plusieurs pages (plan de 93 comptes).
- [Report des immobilisations à l’actif du bilan](m12-comptabilite/report-des-immobilisations-a-l-actif-du-bilan.pdf) (1 p.)
- [Seuil de rentabilité](m12-comptabilite/seuil-de-rentabilite.pdf) (1 p.)
- [Tableau des flux de trésorerie](m12-comptabilite/tableau-des-flux-de-tresorerie.pdf) (2 p.) — Feuillet 8/51 de la liasse, avec sa ligne de contrôle.
- [État des dépenses de trésorerie](m12-comptabilite/etat-des-depenses-de-tresorerie.pdf) (2 p.)

### M13 — Administration & ambulance

- [Compte rendu de réunion](m13-administration/compte-rendu-de-reunion.pdf) (1 p.)
- [Fiche de courrier](m13-administration/fiche-de-courrier.pdf) (1 p.)
- [Fiche d’intervention — ambulance](m13-administration/fiche-d-intervention-ambulance.pdf) (1 p.)
- [Fiche d’équipement](m13-administration/fiche-d-equipement.pdf) (1 p.)
- [Plan annuel de travail](m13-administration/plan-annuel-de-travail.pdf) (1 p.)
- [Registre du courrier](m13-administration/registre-du-courrier.pdf) (1 p.)

### M14 — Sécurité & utilisateurs

- [Fiche de compte utilisateur](m14-securite/fiche-de-compte-utilisateur.pdf) (1 p.)
- [Journal d’audit](m14-securite/journal-d-audit.pdf) (1 p.)
- [Matrice des droits d’accès (RBAC)](m14-securite/matrice-des-droits-d-acces-rbac.pdf) (2 p.)

### MECeF — Facture normalisée

- [Avoir sur facture normalisée](mecef/avoir-sur-facture-normalisee.pdf) (1 p.)
- [Facture de vente — normalisée](mecef/facture-de-vente-normalisee.pdf) (1 p.)

### GED — Gestion documentaire

- [Bordereau d’archivage documentaire](ged/bordereau-d-archivage-documentaire.pdf) (1 p.)
- [Fiche documentaire](ged/fiche-documentaire.pdf) (1 p.)

### RAP — Rapports & états officiels

- [Point mensuel — par client](rap-etats/point-mensuel-par-client.pdf) (3 p.)
- [Rapport d’activité](rap-etats/rapport-d-activite.pdf) (1 p.)

### PIL — Pilotage & statistiques

- [Rapport d’activité — Direction](pil-pilotage/rapport-d-activite-direction.pdf) (1 p.)
- [Statistiques des hospitalisations](pil-pilotage/statistiques-des-hospitalisations.pdf) (1 p.)
- [Tableau de bord décisionnel](pil-pilotage/tableau-de-bord-decisionnel.pdf) (1 p.)

### CFG — Configuration de la clinique

- [Aperçu du papier à en-tête](cfg-configuration/apercu-du-papier-a-en-tete.pdf) (1 p.)
- [Grille tarifaire des actes et prestations](cfg-configuration/grille-tarifaire-des-actes-et-prestations.pdf) (2 p.)
- [Matrice de traçabilité des règles métier](cfg-configuration/matrice-de-tracabilite-des-regles-metier.pdf) (2 p.)
- [Organigramme de la CLINIQUE BAGUIDI](cfg-configuration/organigramme-de-la-clinique-baguidi.pdf) (2 p., paysage)
- [Répartition des secteurs de la clinique](cfg-configuration/repartition-des-secteurs-de-la-clinique.pdf) (1 p.)

### Transverse — gabarit commun des listes filtrées

- [Sélection — liste filtrée d’un registre](transverse/selection-liste-filtree-d-un-registre.pdf) (1 p.) — Gabarit commun des « Imprimer la sélection » de tous les registres ; rappelle les filtres en force.


## Ce qui est bâti pour le spécimen (le jeu livré n'en porte pas)

Le jeu de démonstration laisse plusieurs registres vides. Pour ne pas se priver de leurs pièces, l'outil les montre à partir d'une **fiche d'exemple fictive**, bâtie sur un patient ou un agent du jeu dans
un magasin éphémère (rien n'est écrit au jeu livré) :

- **fiche d'exemple inscrite au registre, puis pièce éditée depuis l'écran** : déclaration de décès, fiche de planification familiale, fiche d'urgence SONUB/SONUC, fiche d'intervention d'ambulance, compte rendu
  de réunion, fiche de référence, rapport médical, fiche de courrier, fiche documentaire (GED), ordre de mission, reçu de participation, badge et planche de badges ;
- **pièce produite par sa fabrique d'impression sur une fiche d'exemple** : attestation de remboursement et avis d'annulation, bon de sortie de stock (dispensation), décharge de sortie contre avis médical,
  bon de pansement ;
- **enregistrement par le moteur de l'écran, comme le bouton « Enregistrer la visite »** : la visite de médecine du travail et sa **fiche d'aptitude** (pièce certifiante) ;
- **pièce produite par sa fabrique sur une fiche du jeu** (rien de bâti) : facture, facture pro-forma, reçu détaillé, engagement de paiement, facture d'avoir, ticket de caisse 80 mm, facture normalisée MECeF,
  ordonnance, dossier de consultation, dossier complet du patient, procès-verbal de réception des réactifs.

## Documents non produits

10 documents (ou familles de documents) n’ont pas de spécimen propre ; chacun est listé avec sa raison dans [INDEX.md](INDEX.md#documents-non-produits-et-pourquoi) (registre vide au jeu livré, pièce née d’une saisie de formulaire,
même gabarit qu’un spécimen présent…). Rien n’est passé sous silence : le fichier `couverture.json` garde en outre les avertissements de l’outil.

## Comment le régénérer

Depuis `apps/poste` (Flutter installé, `export PATH=/opt/sdk/flutter/bin:$PATH`) :

```bash
rm -rf ../../presentation
SIGH_SPECIMENS=1 SIGH_SPECIMENS_SORTIE=../../presentation \
  flutter test tool/specimens/generer_specimens_test.dart          # 10 à 25 minutes : ouvre ~370 écrans
python3 tool/specimens/finaliser.py ../../presentation              # mention SPÉCIMEN, INDEX.md, README.md (PyMuPDF requis)
python3 tool/specimens/controler.py ../../presentation              # aucune trace de l'autre clinique, PDF lisibles
node ../../tools/baguidi/controle-identite.mjs                      # contrôle d'identité du dépôt
```

Sans la variable `SIGH_SPECIMENS=1`, l’outil est **ignoré** (il ne tourne jamais dans la suite normale). `SIGH_SPECIMENS_ECRANS` et `SIGH_SPECIMENS_RECETTES` limitent le rejeu à des préfixes d’écrans ou de
pièces. Le principe et les pièges sont décrits dans `apps/poste/tool/specimens/README.md`.
