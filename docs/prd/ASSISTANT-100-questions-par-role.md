# Les 100 questions de l’assistant, par rôle, avec la décision de la Direction (16/11/2026)

Colonnes : numéro, rôle, question telle que dite, intention du catalogue (I01 à I25, HC = hors catalogue), état au 16/11/2026, droit à vérifier (RG-13), décision de la Direction.

Les questions sont des propositions écrites par l’équipe (aucune question réelle n’a encore été collectée) : la Direction les a relues une à une. Une question réelle d’un agent, mot pour mot, remplace la proposition.


## Administrateur système (`admin`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 1 | La mère est à jour ? Quel poste a du retard ? | I22 | calculable | oui (écran mere-supervision) | Validée |
| 2 | Il y a des alertes de synchronisation ouvertes ce matin ? | I22 | calculable | oui (écran mere-supervision) | Validée |
| 3 | Quand a été faite la dernière sauvegarde ? | HC | hors catalogue | écran visible du rôle (m14-sauvegardes, mere-sauvegardes) ; à ajouter au catalogue avec ce droit | Validée (intention « dernière sauvegarde » à ajouter) |
| 4 | Comment je crée un nouvel utilisateur et je lui donne un rôle ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) | Validée (fiche d aide à rédiger) |
| 5 | Quels rôles peuvent ouvrir les écrans de la paie ? | HC | hors catalogue | écran visible du rôle (m14-roles) ; à ajouter au catalogue avec ce droit | Validée (intention à ajouter) |

## Direction / Gérance (`direction`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 6 | Combien de consultations et d'admissions aujourd'hui ? | I21 | calculable | oui (écran dash-direction) | Validée |
| 7 | Recettes de la semaine par secteur, comparées à la semaine d'avant | I14 | calculable | oui (écran m8-recettes) | Validée |
| 8 | Qui nous doit le plus d'argent, les assureurs ou les patients ? | I16 | après petit lot (tranches fixes, balance des patients à faire) | oui (écran m9-creances) | Validée (petit lot balance des patients) |
| 9 | Il y a des commandes de stock qui attendent ma validation ? | I13 | calculable | oui (écran m7-commandes) | Reformulée : « Quelles commandes de stock attendent la validation de la DAF ? » (suivi, sans valider) |
| 10 | Combien coûte la masse salariale du mois ? | HC | hors catalogue | écran visible du rôle (m11-calcul) ; à ajouter au catalogue avec ce droit | Validée (intention à ajouter) |

## Directeur Médical (`dm`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 11 | Combien d'admissions cette semaine ? | I21 | calculable | oui (écran dash-direction) | Validée |
| 12 | Lits libres en hospitalisation | I04 | calculable | oui (écran m3-admissions) | Validée |
| 13 | Le résultat de tel examen du patient CNT/…/26 est rendu ? | I19 | calculable (résultat rendu seulement) | oui (écran m5-demandes) | Validée |
| 14 | Recettes du mois, ventilées par secteur | I14 | calculable (recettes (encaissé) ou chiffre d'affaires (facturé) à trancher) | oui (écran m8-recettes) | Validée : « recettes » donne LES DEUX chiffres, encaissé et facturé, chacun nommé |
| 15 | Qui est de garde ce week-end ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) | Ouvrir au DM : la fiche RBAC du Directeur Médical s ouvre au planning des gardes en LECTURE seule (changement de droits à faire) |

## Directrice de l’Administration et des Finances (DAF) (`da`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 16 | Commandes de stock gros en attente de ma validation | I13 | calculable (validateur : RG-04 seulement, pas un réglage lu en base) | oui (écran m7-commandes) | Validée |
| 17 | Créances par ancienneté, assureurs et patients | I16 | après petit lot (tranches fixes, balance des patients à faire) | oui (écran m9-creances) | Validée (petit lot) |
| 18 | Factures de la semaine non certifiées MECeF | I15 | calculable | oui (écran m8-factures) | Validée |
| 19 | Combien on doit à tel fournisseur ? | I12 | calculable (deux définitions de la dette (écart E21)) | oui (écran m7-fournisseurs) | Validée : LES DEUX chiffres (factures non payées et solde comptable), chacun nommé, et l écart |
| 20 | Valeur du stock au CUMP, secteur par secteur | I10 | calculable (secteur = groupe de famille d'article) | oui (écran m6-point-stock) | Validée |

## Médecin (`medecin`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 21 | Dans quel lit est le patient CNT/…/26 ? | I04 | calculable | oui (écran m3-admissions) | Validée |
| 22 | Le résultat de tel examen de CNT/…/26 est rendu ? | I19 | calculable (résultat rendu seulement) | oui (écran m5-demandes) | Validée |
| 23 | Retrouve l'ordonnance d'hier du patient CNT/…/26 | I17 | après petit lot (vue unifiée du dossier à élargir) | oui (écran m1-documents) | Validée (petit lot) |
| 24 | Il reste du tel médicament à la pharmacie ? | I07 | calculable | oui (écran m6-produits) | Validée |
| 25 | Quelle dose de tel médicament pour un enfant de tel poids ? | HC | hors catalogue (avis thérapeutique : refus attendu AVIS_MEDICAL_REFUSE) | refus attendu, nommé AVIS_MEDICAL_REFUSE (aucune aide au traitement) | Refus gardé (preuve AVIS_MEDICAL_REFUSE) |

## Infirmier / Sage-femme (`infirmier`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 26 | Lits libres en maternité | I04 | calculable | oui (écran m3-admissions) | Validée |
| 27 | Le patient CNT/…/26 est toujours hospitalisé ? Quel lit ? | I04 | calculable | oui (écran m3-admissions) | Validée |
| 28 | Le résultat de l'analyse de ce patient est prêt ? | I19 | calculable (résultat rendu seulement) | oui (écran m5-demandes) | Validée |
| 29 | Comment je note la sortie d'un patient hospitalisé ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) | Validée (fiche d aide à rédiger) |
| 30 | Qui est de garde cette nuit ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) | Ouvrir à l infirmier : la fiche RBAC s ouvre au planning des gardes en LECTURE seule |

## Biologiste médical (`laborantin`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 31 | Où en est la demande d'analyse du patient CNT/…/26 ? | I19 | calculable | oui (écran m5-demandes) | Validée |
| 32 | Le résultat de tel examen est validé ? | I19 | calculable | oui (écran m5-demandes) | Validée |
| 33 | Combien coûte tel examen, assuré et non assuré ? | I05 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : cfg-tarifs, m8-facturation) | Ouvrir les prix : la fiche RBAC du biologiste s ouvre aux tarifs en LECTURE seule |
| 34 | Où en est la commande de réactifs ? | I13 | calculable | oui (écran m7-commandes) | Validée |
| 35 | Il reste combien de tel réactif ? | I07 | calculable (le stock « du laboratoire » n'est pas un stock distinct, lecture par article) | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m6-produits, m6-stock-gros, m6-stock-detail, m6-lots) | Ouvrir le stock labo : lecture du stock des articles du laboratoire seulement (périmètre secteur Laboratoire) |

## Gestionnaire de Stock (`stock`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 36 | Articles en rupture | I08 | calculable | oui (écran m6-alertes) | Validée |
| 37 | Quel lot de tel article je sors en premier ? | I07 | calculable (FEFO (RG-05)) | oui (écran m6-produits) | Validée |
| 38 | Les articles qui n'ont pas bougé depuis un an | I09 | après petit lot (sorties par article à agréger, durée réglable) | oui (écran m6-mouvements) | Validée (petit lot, durée réglable) |
| 39 | Où en est l'inventaire, quels écarts ? | I11 | calculable | oui (écran m6-inventaire) | Validée |
| 40 | Quels articles n'ont pas été comptés à l'inventaire ? | I11 | non disponible (« non compté » n'est pas enregistré) | oui (écran m6-inventaire) | Validée (après INVENT-NC) |

## Caissier, Dispensaire (Pharmacie) (`caissier`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 41 | Recettes du jour par mode de paiement | I14 | calculable | oui (écran m8-recettes) | Validée |
| 42 | La carte d'assurance du patient CNT/…/26 est valable aujourd'hui ? | I02 | calculable (RG-09) | oui (écran m1-patients) | Validée |
| 43 | Combien reste-t-il à payer pour CNT/…/26 ? | I03 | calculable | oui (écran m8-factures) | Validée |
| 44 | Quels médicaments vont périmer dans trois mois ? | I08 | calculable (délai de 90 jours codé en dur à corriger) | oui (écran m6-alertes) | Validée (délai en base après PARAM-CLINIQUE) |
| 45 | Combien il y avait de tel médicament à la fin du mois dernier ? | I07 | non disponible (NON_CALCULABLE_HISTORIQUE, jamais zéro) | oui (écran m6-produits) | Validée, À CONSTRUIRE : reconstituer le stock à une date passée depuis les mouvements |

## Comptable (`comptable`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 46 | Factures de la semaine qui ne sont pas certifiées MECeF | I15 | calculable | oui (écran m8-factures) | Validée |
| 47 | Valeur du stock de la pharmacie au CUMP | I10 | calculable | oui (écran m6-point-stock) | Validée |
| 48 | Impayés de plus de 60 jours | I16 | après petit lot (N libre (60) n'existe pas, tranches fixes) | oui (écran m9-creances) | Validée (petit lot : nombre de jours libre) |
| 49 | Quand le prix de tel acte a-t-il changé ? | I06 | calculable (acte du référentiel ; un produit n'a pas d'historique) | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : cfg-tarifs) | Ouvrir les tarifs : la fiche RBAC du comptable s ouvre aux tarifs et leur historique en LECTURE seule |
| 50 | Montre-moi la balance des comptes du mois | HC | hors catalogue | écran visible du rôle (m12-balance) ; à ajouter au catalogue avec ce droit | Validée (intention à ajouter) |

## Réception / Accueil (`reception`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 51 | Cherche Mme [nom] née en [année] | I01 | après petit lot (recherche par nom à porter, homonymes à lister) | oui (écran m1-patients) | Validée (petit lot) |
| 52 | Prix de la consultation générale, assuré et non assuré | I05 | calculable | oui (écran cfg-tarifs) | Validée |
| 53 | Combien coûte un certificat de tel type ? | I18 | calculable (prix unique, couverture SOS seule) | oui (écran cfg-tarifs) | Validée |
| 54 | Qui est de garde ce soir ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) | Ouvrir à la réception : planning des gardes en LECTURE seule |
| 55 | Le patient CNT/…/26 est hospitalisé ? Dans quel lit ? | I04 | calculable | oui (écran m3-admissions) | Validée |

## Agent Administratif (`agentadmin`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 56 | Retrouve le dernier courrier reçu pour le patient CNT/…/26 | I17 | après petit lot (courriers absents de la vue unifiée) | oui (écran m13-courriers) | Validée (petit lot : courriers dans la vue unifiée) |
| 57 | Cherche le patient CNT/…/26 | I01 | après petit lot (recherche par code à porter) | oui (écran m1-patients) | Validée (petit lot) |
| 58 | Comment j'enregistre un courrier entrant ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) | Validée (fiche d aide à rédiger) |
| 59 | Quelles réunions sont prévues cette semaine ? | HC | hors catalogue | écran visible du rôle (m13-reunions) ; à ajouter au catalogue avec ce droit | Validée (intention à ajouter) |
| 60 | Qui est dans le lit 5 ? | I04 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m3-admissions, m3-plan-lits) | Ouvrir les lits : l agent administratif lit l occupation des lits en LECTURE seule (à cadrer RG-13 : occupation, pas le dossier médical) |

## Ambulancier (`ambulancier`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 61 | Retrouve le patient CNT/…/26 que je dois transporter | I01 | après petit lot (recherche par code à porter) | oui (écran m1-patients) | Validée (petit lot) |
| 62 | Quelle ambulance est disponible aujourd'hui ? | HC | hors catalogue | écran visible du rôle (m13-ambulance) ; à ajouter au catalogue avec ce droit | Validée (intention à ajouter) |
| 63 | Qui est de garde ce soir ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) | Ouvrir à l ambulancier : planning des gardes en LECTURE seule |
| 64 | Comment je remplis la fiche de transport ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) | Validée (fiche d aide à rédiger) |
| 65 | Dans quel lit est le patient CNT/…/26 ? | I04 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m3-admissions, m3-plan-lits) | Ouvrir les lits : l aide-soignante lit les admissions (lit du patient) en LECTURE seule |

## Aide-soignante (`aide_soignant`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 66 | Quels lits sont libres dans le service ? | I04 | calculable | oui (écran m3-plan-lits) | Validée |
| 67 | Qui est dans le lit 12 ? | I04 | calculable | oui (écran m3-plan-lits) | Validée |
| 68 | Où je note les constantes d'un patient ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) | Validée (fiche d aide à rédiger) |
| 69 | Les résultats du patient CNT/…/26 sont rendus ? | I19 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m5-demandes, m5-resultats, m2-imagerie-demandes) | Refus gardé (RG-13). Précision de la Direction : c est le médecin qui a reçu et examiné le patient qui donne les soins à faire à l aide-soignante ; l accueil peut voir le STATUT d un résultat (Oui, Non, En attente) sans jamais en voir le contenu |
| 70 | Quand est ma prochaine garde ? | HC | hors catalogue | écran visible du rôle (m10-mes) ; à ajouter au catalogue avec ce droit | Validée (intention « ma prochaine garde » pour tous les agents) |

## Technicien d’échographie (`echographiste`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 71 | L'échographie du patient CNT/…/26 est validée ? | I19 | calculable | oui (écran m5-demandes) | Validée |
| 72 | Combien d'échographies ont été faites aujourd'hui ? | HC | hors catalogue | écran visible du rôle (m2-stats-echographie) ; à ajouter au catalogue avec ce droit | Validée (intention à ajouter : comptage des examens d imagerie par type) |
| 73 | Retrouve le patient CNT/…/26 | I01 | après petit lot (recherche par code à porter) | oui (écran m1-patients) | Validée (petit lot) |
| 74 | Quels examens d'imagerie attendent aujourd'hui ? | I19 | calculable | oui (écran m5-demandes) | Validée |
| 75 | Prix d'une échographie obstétricale | I05 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : cfg-tarifs, m8-facturation) | Ouvrir les prix : le technicien d imagerie lit le prix des examens d imagerie en LECTURE seule |

## Surveillant (`surveillant`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 76 | Qui est de garde ce soir ? | I20 | calculable | oui (écran m10-planning) | Validée |
| 77 | Planning de permanence de la semaine | I20 | calculable | oui (écran m10-planning) | Validée |
| 78 | Qui est en congé cette semaine ? | HC | hors catalogue | écran visible du rôle (m10-conges) ; à ajouter au catalogue avec ce droit | Validée (intention à ajouter) |
| 79 | Lits libres en maternité | I04 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m3-admissions, m3-plan-lits) | Ouvrir les lits : le surveillant lit l occupation des lits en LECTURE seule |
| 80 | Comment je valide une proposition de planning ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) | Validée (fiche d aide à rédiger) |

## Assistant de Direction (`assistant_comptable`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 81 | Retrouve le dernier courrier de telle compagnie d'assurance | I17 | après petit lot (courriers absents de la vue unifiée) | oui (écran m13-courriers) | Validée (petit lot) |
| 82 | Quelles réunions sont prévues cette semaine ? | HC | hors catalogue | écran visible du rôle (m13-reunions) ; à ajouter au catalogue avec ce droit | Validée |
| 83 | Combien de consultations aujourd'hui ? | I21 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : dash-direction, dash-da, dash-croise) | Ouvrir l activité : l Assistant de Direction lit le tableau de bord de la Direction en LECTURE seule |
| 84 | Comment je fais une note de service ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) | Validée (fiche d aide à rédiger) |
| 85 | Imprime l'état des ventes de la semaine | I23 | calculable (droit de la bibliothèque ET de l'écran de l'état) | refus attendu, nommé LECTURE_NON_AUTORISEE (écran de l'état fermé : m6-point-ventes ; bibliothèque : oui) | Ouvrir l état : l Assistant de Direction lit et imprime l état des ventes en LECTURE seule |

## Chirurgien (`chirurgien`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 86 | Quel patient est dans le lit 8 ? | I04 | calculable | oui (écran m3-admissions) | Validée |
| 87 | Le bilan pré-opératoire du patient CNT/…/26 est rendu ? | I19 | calculable | oui (écran m5-demandes) | Validée |
| 88 | Retrouve le compte rendu opératoire du patient CNT/…/26 | I17 | après petit lot (vue unifiée du dossier à élargir) | oui (écran m1-documents) | Validée (petit lot) |
| 89 | Qui est de garde ce week-end ? | I20 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m10-planning) | Ouvrir au chirurgien : planning des gardes en LECTURE seule |
| 90 | Où en est la demande d'imagerie du patient CNT/…/26 ? | I19 | calculable | oui (écran m5-demandes) | Validée |

## Anesthésiste, Réanimateur (`anesthesiste`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 91 | Le bilan sanguin du patient CNT/…/26 est rendu ? | I19 | calculable | oui (écran m5-demandes) | Validée |
| 92 | Dans quel lit est le patient CNT/…/26 ? | I04 | calculable | oui (écran m3-admissions) | Validée |
| 93 | Retrouve la fiche d'anesthésie du patient CNT/…/26 | I17 | après petit lot (vue unifiée du dossier à élargir) | oui (écran m1-documents) | Validée (petit lot) |
| 94 | Comment on remplit la check-list du bloc ? | I24 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) | Validée (fiche après validation de la check-liste par le professionnel nommé) |
| 95 | Il reste du tel produit anesthésique à la pharmacie ? | I07 | calculable | refus attendu, nommé LECTURE_NON_AUTORISEE (aucun écran visible : m6-produits, m6-stock-gros, m6-stock-detail, m6-lots) | Ouvrir le stock : l anesthésiste lit la disponibilité des produits en pharmacie en LECTURE seule |

## Assistant Comptable (`aide_comptable`)

| N° | Question | Intention | État | Droit à vérifier | Décision de la Direction |
|---|---|---|---|---|---|
| 96 | Factures de la semaine non certifiées MECeF | I15 | calculable | oui (écran m8-factures) | Validée |
| 97 | Combien doit encore le patient CNT/…/26 ? | I03 | calculable | oui (écran m8-factures) | Validée |
| 98 | Les impayés des patients par ancienneté | I16 | après petit lot (balance des patients à faire) | oui (écran m9-creances) | Validée (petit lot) |
| 99 | C'est quoi un avoir ? | I25 | non disponible (aucune fiche validée) | ouvert à tous (geste « utiliser l'assistant » à déclarer, fiche réservée à un rôle absente) | Validée (fiche de définition à rédiger) |
| 100 | Combien on doit à tel fournisseur ? | I12 | calculable (deux définitions de la dette (écart E21)) | oui (écran m7-fournisseurs) | Validée : les deux chiffres et l écart, comme pour la DAF |
