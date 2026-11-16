/// LES SEMENCES DU RÉFÉRENTIEL DE NUMÉROTATION (lot 2, 16/11/2026) : une série par famille de pièce, au format EXACT que le code portait au 16/11/2026.
///
/// Chaque ligne reprend le préfixe, la place et le format de l'année, le séparateur et la longueur du rang tels que le code les écrivait : aucune pièce
/// existante ne change de numéro (RG-01, une pièce émise ne se renumérote jamais), et un test par série le prouve (`numerotation_test.dart`). Toutes sont
/// « à valider » : aucun document de la clinique ne fixe ces formats, ils viennent de la maquette. Les séries qui portaient « 2026 » EN DUR (bons
/// d'expression de besoins, commandes, CPA, CRA, observations, réunions, missions d'ambulance, certificats, série MECeF affichée) prennent désormais
/// l'année de la DATE DE LA PIÈCE : en 2026, le numéro est identique au caractère près ; au 1ᵉʳ janvier 2027, la série repart sous « 2027 ».
///
/// `remiseAnnuelle` reprend le comportement du code : vrai quand le rang se cherchait sous un préfixe millésimé (plus grand rang de l'année), faux quand il
/// comptait toutes les pièces, toutes années confondues (`FM-`, `FI-`, `FE-`, `FC-`, `ORD-`, `CERT-`, `OBS-` : écart E3866, rang compté conservé).
/// Ajouter une série = ajouter sa ligne ici ; le code ne nomme jamais que son `code`.
library;

import 'numerotation.dart';

const _n = 'Format repris du code au 16/11/2026 (proposition à valider).';

/// Les cinq séries qui PARTAGEAIENT leur préfixe avec un autre registre (E3874) : décision du 17/11/2026, un préfixe PAR registre. Le préfixe retenu est une PROPOSITION à valider ; les pièces
/// déjà émises sous l'ancien gardent leur numéro, et leurs rangs restent lus (`prefixesAnterieurs`) pour que le registre ne redonne jamais un rang déjà pris.
const _nSepare = 'Préfixe PROPRE à ce registre depuis le 17/11/2026 (il partageait l’ancien avec une autre série) : proposition à valider ; les numéros déjà émis ne changent pas.';

/// Les semences, dans l'ordre des modules.
const List<SerieNumerotation> seriesNumerotationSemence = [
  // M1 Patients & DMI
  SerieNumerotation(code: 'patients.constantes', libelle: 'Relevés de constantes', module: 'M1', prefixe: 'CST', largeur: 5, note: _n),
  SerieNumerotation(code: 'patients.documents', libelle: 'Documents du dossier patient (GED)', module: 'M1', prefixe: 'GED', largeur: 5, note: _n),
  SerieNumerotation(code: 'patients.fiches-reference', libelle: 'Fiches de référence', module: 'M1', prefixe: 'REF', largeur: 5, champ: 'numero', note: _n),
  SerieNumerotation(code: 'patients.contre-references', libelle: 'Contre-références', module: 'M1', prefixe: 'CRF', largeur: 5, note: _n),
  SerieNumerotation(code: 'patients.factures-certificats', libelle: 'Factures des pièces certifiantes', module: 'M1', prefixe: 'FC', annee: anneeLongue, largeur: 5, champ: 'numero', note: _n),
  SerieNumerotation(code: 'patients.factures-externes', libelle: 'Factures des patients externes', module: 'M1', prefixe: 'FE', annee: anneeLongue, largeur: 5, champ: 'numero', note: _n),
  // M2 Consultations, imagerie
  SerieNumerotation(code: 'consultation.dossiers', libelle: 'Dossiers de consultation', module: 'M2', prefixe: 'DOS', largeur: 5, note: _n),
  SerieNumerotation(code: 'consultation.consultations', libelle: 'Consultations', module: 'M2', prefixe: 'C', separateur: '', largeur: 5, note: _n),
  SerieNumerotation(code: 'agenda.rendezvous', libelle: 'Rendez-vous et venues', module: 'M2', prefixe: 'RDV', largeur: 5, prefixesAnterieurs: ['C'], note: _nSepare),
  SerieNumerotation(code: 'agenda.appels', libelle: 'Registre des appels', module: 'M2', prefixe: 'A', separateur: '', largeur: 5, note: _n),
  SerieNumerotation(code: 'consultation.ordonnances', libelle: 'Ordonnances', module: 'M2', prefixe: 'ORD', annee: anneeLongue, largeur: 5, champ: 'numero', note: _n),
  SerieNumerotation(code: 'consultation.factures', libelle: 'Factures de la prescription (consultation)', module: 'M2', prefixe: 'FP', annee: anneeLongue, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: _n),
  SerieNumerotation(code: 'soins.prescriptions', libelle: 'Prescriptions de soins', module: 'M2', prefixe: 'PRS', largeur: 5, note: _n),
  SerieNumerotation(code: 'soins.administrations', libelle: 'Administrations de soins', module: 'M2', prefixe: 'ADM', largeur: 5, note: _n),
  SerieNumerotation(code: 'imagerie.demandes', libelle: 'Demandes d’imagerie', module: 'M2', prefixe: 'IME', largeur: 5, note: _n),
  SerieNumerotation(code: 'imagerie.comptes-rendus', libelle: 'Comptes rendus d’imagerie', module: 'M2', prefixe: 'IMG', largeur: 4, note: _n),
  SerieNumerotation(code: 'imagerie.factures', libelle: 'Factures d’imagerie (patient adressé)', module: 'M2', prefixe: 'FI', annee: anneeLongue, largeur: 5, champ: 'numero', note: _n),
  // M3 Hospitalisation & bloc
  SerieNumerotation(code: 'hospitalisation.observations', libelle: 'Mises en observation', module: 'M3', prefixe: 'OBS', annee: anneeLongue, largeur: 4, note: _n),
  SerieNumerotation(code: 'hospitalisation.admissions', libelle: 'Admissions', module: 'M3', prefixe: 'H', separateur: '', largeur: 5, note: _n),
  SerieNumerotation(code: 'hospitalisation.sorties-contre-avis', libelle: 'Sorties contre avis médical', module: 'M3', prefixe: 'SAM', separateur: '', largeur: 4, note: _n),
  SerieNumerotation(code: 'hospitalisation.glasgow', libelle: 'Scores de Glasgow', module: 'M3', prefixe: 'GCS', largeur: 4, note: _n),
  SerieNumerotation(code: 'hospitalisation.rapports', libelle: 'Rapports de surveillance', module: 'M3', prefixe: 'RAP', largeur: 4, note: _n),
  SerieNumerotation(code: 'hospitalisation.transfusions', libelle: 'Surveillances de transfusion', module: 'M3', prefixe: 'TRF', largeur: 4, note: _n),
  SerieNumerotation(code: 'bloc.cpa', libelle: 'Consultations pré-anesthésiques (CPA)', module: 'M3', prefixe: 'CPA', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'bloc.cra', libelle: 'Comptes rendus d’anesthésie (CRA)', module: 'M3', prefixe: 'CRA', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'bloc.cro', libelle: 'Comptes rendus opératoires (CRO)', module: 'M3', prefixe: 'CRO', largeur: 4, note: _n),
  SerieNumerotation(code: 'bloc.checklists', libelle: 'Check-listes du bloc', module: 'M3', prefixe: 'CKL', largeur: 4, note: _n),
  // M4 Maternité
  SerieNumerotation(code: 'maternite.partogrammes', libelle: 'Partogrammes', module: 'M4', prefixe: 'PARTO', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.accouchements', libelle: 'Accouchements', module: 'M4', prefixe: 'ACC', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.naissances', libelle: 'Naissances', module: 'M4', prefixe: 'NAI', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.deces', libelle: 'Décès', module: 'M4', prefixe: 'DEC', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.cpn', libelle: 'Consultations prénatales (CPN)', module: 'M4', prefixe: 'CPN', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.cpon', libelle: 'Consultations postnatales (CPoN)', module: 'M4', prefixe: 'CPO', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.planification', libelle: 'Planification familiale', module: 'M4', prefixe: 'PF', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.sonu', libelle: 'Registre SONU', module: 'M4', prefixe: 'SONU', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.ptme', libelle: 'PTME', module: 'M4', prefixe: 'PTME', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.soins-curatifs', libelle: 'Soins curatifs de la maternité', module: 'M4', prefixe: 'SCM', largeur: 4, note: _n),
  SerieNumerotation(code: 'maternite.comptes-rendus', libelle: 'Comptes rendus de la maternité', module: 'M4', prefixe: 'CRM', largeur: 4, note: _n),
  // M5 Laboratoire & sang
  SerieNumerotation(code: 'labo.demandes', libelle: 'Demandes d’analyses', module: 'M5', prefixe: 'LAB', largeur: 5, note: _n),
  SerieNumerotation(code: 'labo.reactifs', libelle: 'Codes des réactifs du laboratoire', module: 'M5', prefixe: 'REA', largeur: 4, champ: 'code', prefixesAnterieurs: ['LAB-'], note: _nSepare),
  SerieNumerotation(code: 'labo.donneurs', libelle: 'Donneurs de sang', module: 'M5', prefixe: 'DON', largeur: 4, note: _n),
  // M6 Pharmacie & stocks
  SerieNumerotation(code: 'stock.produits', libelle: 'Codes des produits', module: 'M6', prefixe: 'PRD', largeur: 4, champ: 'code', note: _n),
  SerieNumerotation(code: 'stock.dispensations', libelle: 'Dispensations', module: 'M6', prefixe: 'DISP', largeur: 5, note: _n),
  SerieNumerotation(code: 'stock.transferts', libelle: 'Bons de transfert', module: 'M6', prefixe: 'TR', largeur: 5, note: _n),
  SerieNumerotation(code: 'stock.mouvements', libelle: 'Mouvements de stock', module: 'M6', prefixe: 'M', separateur: '', largeur: 6, note: _n),
  SerieNumerotation(code: 'stock.pertes', libelle: 'Pertes déclarées (mouvements)', module: 'M6', prefixe: 'MVT', largeur: 5, note: _n),
  SerieNumerotation(code: 'stock.inventaires', libelle: 'Inventaires', module: 'M6', prefixe: 'INV', largeur: 4, note: _n),
  // M7 Achats & fournisseurs
  SerieNumerotation(code: 'achats.besoins', libelle: 'Bons d’expression de besoins', module: 'M7', prefixe: 'BEB', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'achats.commandes', libelle: 'Bons de commande', module: 'M7', prefixe: 'BC', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'achats.livraisons', libelle: 'Bons de livraison', module: 'M7', prefixe: 'BL', largeur: 5, note: _n),
  SerieNumerotation(code: 'achats.pv-consommables', libelle: 'PV de réception des consommables', module: 'M7', prefixe: 'PV-CON', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'achats.pv-reactifs', libelle: 'PV de réception des réactifs', module: 'M7', prefixe: 'PV-REA', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  // M8 Facturation & caisse
  SerieNumerotation(code: 'caisse.factures', libelle: 'Factures normalisées', module: 'M8', prefixe: 'FN', annee: anneeLongue, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: _n),
  SerieNumerotation(code: 'caisse.proformas', libelle: 'Factures pro-forma', module: 'M8', prefixe: 'PRO', annee: anneeLongue, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: _n),
  SerieNumerotation(code: 'caisse.factures-tiers', libelle: 'Factures à une entreprise (tiers payeur)', module: 'M8', prefixe: 'FT', annee: anneeLongue, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: 'Série créée le 17/11/2026 pour la facture à une entreprise (proposition à valider) : distincte de la facture du patient (FN).'),
  SerieNumerotation(code: 'caisse.avoirs', libelle: 'Avoirs', module: 'M8', prefixe: 'AV', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'caisse.pieces', libelle: 'Pièces de caisse (journal CAI)', module: 'M8', prefixe: 'CAI', annee: anneeLongue, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: _n),
  SerieNumerotation(code: 'caisse.remboursements', libelle: 'Remboursements', module: 'M8', prefixe: 'RB', largeur: 5, note: _n),
  SerieNumerotation(code: 'caisse.tickets', libelle: 'Tickets de caisse (aperçu)', module: 'M8', prefixe: 'T', largeur: 5, champ: 'numero', note: _n),
  // M9 Assurances & créances
  SerieNumerotation(code: 'assurances.relances', libelle: 'Relances des assureurs', module: 'M9', prefixe: 'REL', largeur: 4, note: _n),
  SerieNumerotation(code: 'assurances.factures-meres', libelle: 'Factures mères', module: 'M9', prefixe: 'FM', annee: anneeLongue, largeur: 4, champ: 'numero', note: _n),
  SerieNumerotation(code: 'assurances.reglements', libelle: 'Règlements des factures mères (journal BQ)', module: 'M9', prefixe: 'BQ', annee: anneeLongue, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: _n),
  // M10 RH
  SerieNumerotation(code: 'rh.conges', libelle: 'Congés', module: 'M10', prefixe: 'CG', largeur: 4, note: _n),
  SerieNumerotation(code: 'rh.contrats', libelle: 'Contrats', module: 'M10', prefixe: 'CT', largeur: 4, note: _n),
  SerieNumerotation(code: 'rh.prestataires', libelle: 'Prestataires externes', module: 'M10', prefixe: 'PE', largeur: 4, note: _n),
  SerieNumerotation(code: 'rh.evaluations', libelle: 'Évaluations', module: 'M10', prefixe: 'EV', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'rh.evenements', libelle: 'Événements du personnel', module: 'M10', prefixe: 'EVT', largeur: 4, note: _n),
  SerieNumerotation(code: 'rh.recus-participation', libelle: 'Reçus de participation', module: 'M10', prefixe: 'REC-PART', largeur: 4, champ: 'recu', note: _n),
  SerieNumerotation(code: 'rh.securite-entretien', libelle: 'Matricules du personnel de sécurité et d’entretien', module: 'M10', prefixe: 'SE', largeur: 3, champ: 'matricule', note: _n),
  SerieNumerotation(code: 'rh.ordres-mission', libelle: 'Ordres de mission', module: 'M10', prefixe: 'OM', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'rh.badges', libelle: 'Badges du personnel', module: 'M10', prefixe: 'BDG', annee: anneeLongue, positionAnnee: anneeApres, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: _n),
  // M11 Paie
  SerieNumerotation(code: 'paie.bulletins', libelle: 'Bulletins de paie (registre)', module: 'M11', prefixe: 'BUL', largeur: 5, prefixesAnterieurs: ['BP-'], note: _nSepare),
  SerieNumerotation(code: 'paie.bulletins-agent', libelle: 'Bulletin d’un agent (matricule et mois)', module: 'M11', prefixe: 'BP', genre: genreDerive, note: _n),
  SerieNumerotation(code: 'paie.prets', libelle: 'Prêts', module: 'M11', prefixe: 'PRT', largeur: 4, note: _n),
  SerieNumerotation(code: 'paie.heures-sup', libelle: 'Heures supplémentaires', module: 'M11', prefixe: 'HS', largeur: 4, note: _n),
  SerieNumerotation(code: 'paie.avances', libelle: 'Avances sur salaire', module: 'M11', prefixe: 'AVS', largeur: 4, note: _n),
  SerieNumerotation(code: 'paie.pieces', libelle: 'Pièces de paie (journal SAL)', module: 'M11', prefixe: 'SAL', annee: anneeLongue, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: _n),
  SerieNumerotation(code: 'paie.piece-periode', libelle: 'Pièce de paie d’une période', module: 'M11', prefixe: 'PAIE', genre: genreDerive, champ: 'pieceId', note: _n),
  // M12 Comptabilité
  SerieNumerotation(code: 'compta.depenses', libelle: 'Dépenses', module: 'M12', prefixe: 'DEP', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'compta.cloture', libelle: 'Pièces de clôture (journal CL)', module: 'M12', prefixe: 'CL', annee: anneeLongue, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: _n),
  SerieNumerotation(code: 'compta.cloture-contrepassation', libelle: 'Contre-passations de clôture', module: 'M12', prefixe: 'CL', annee: anneeLongue, largeur: 5, prefixeRang: 'C', remiseAnnuelle: true, champ: 'numero', note: _n),
  SerieNumerotation(code: 'compta.a-nouveaux', libelle: 'À-nouveaux (journal AN)', module: 'M12', prefixe: 'AN', annee: anneeLongue, largeur: 5, remiseAnnuelle: true, champ: 'numero', note: _n),
  SerieNumerotation(code: 'compta.a-nouveaux-contrepassation', libelle: 'Contre-passations des à-nouveaux', module: 'M12', prefixe: 'AN', annee: anneeLongue, largeur: 5, prefixeRang: 'C', remiseAnnuelle: true, champ: 'numero', note: _n),
  SerieNumerotation(code: 'compta.archives-cloture', libelle: 'Archives de clôture (version de l’année)', module: 'M12', prefixe: 'ARC', annee: anneeLongue, largeur: 2, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'compta.attestations-aib', libelle: 'Pièces de retenue AIB (opérée)', module: 'M12', prefixe: 'AIB', genre: genreDerive, champ: 'numero', note: _n),
  SerieNumerotation(code: 'compta.attestations-aib-subie', libelle: 'Pièces d’AIB subie', module: 'M12', prefixe: 'AIBS', genre: genreDerive, champ: 'numero', note: _n),
  SerieNumerotation(code: 'compta.budgets', libelle: 'Budgets (par exercice)', module: 'M12', prefixe: 'BG', annee: anneeLongue, largeur: 3, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'compta.immobilisations', libelle: 'Immobilisations', module: 'M12', prefixe: 'IM', largeur: 3, note: _n),
  // M13 Administration, qualité
  SerieNumerotation(code: 'adm.courriers-arrivee', libelle: 'Courriers arrivée', module: 'M13', prefixe: 'ARR', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'adm.courriers-depart', libelle: 'Courriers départ', module: 'M13', prefixe: 'COU', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, prefixesAnterieurs: ['DEP-'], note: _nSepare),
  SerieNumerotation(code: 'adm.evenements', libelle: 'Événements de l’établissement', module: 'M13', prefixe: 'EVE', largeur: 4, prefixesAnterieurs: ['EVT-'], note: _nSepare),
  SerieNumerotation(code: 'adm.reunions', libelle: 'Réunions', module: 'M13', prefixe: 'RU', annee: anneeLongue, largeur: 3, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'adm.ambulance', libelle: 'Missions d’ambulance', module: 'M13', prefixe: 'AM', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  SerieNumerotation(code: 'adm.materiel', libelle: 'Parc technique (équipements)', module: 'M13', prefixe: 'EQ', largeur: 3, note: _n),
  SerieNumerotation(code: 'qualite.enquetes', libelle: 'Enquêtes de satisfaction', module: 'M13', prefixe: 'ENQ', largeur: 3, note: _n),
  SerieNumerotation(code: 'mdt.fiches-aptitude', libelle: 'Fiches d’aptitude (médecine du travail)', module: 'M13', prefixe: 'FA', annee: anneeCourte, positionAnnee: anneeApres, separateurAnnee: '/', largeur: 4, remiseAnnuelle: true, note: _n),
  // M14 Sécurité & accès
  SerieNumerotation(code: 'acces.support', libelle: 'Demandes de support', module: 'M14', prefixe: 'SUP', annee: anneeLongue, largeur: 4, remiseAnnuelle: true, note: _n),
  // CFG Configuration
  SerieNumerotation(code: 'cfg.rappels', libelle: 'Rappels (messages)', module: 'CFG', prefixe: 'RPL', largeur: 5, note: _n),
  SerieNumerotation(code: 'cfg.actes', libelle: 'Codes des actes', module: 'CFG', prefixe: 'ACT', largeur: 3, champ: 'code', note: _n),
  SerieNumerotation(code: 'cfg.certificats', libelle: 'Certificats', module: 'CFG', prefixe: 'CERT', annee: anneeLongue, largeur: 4, champ: 'numero', note: _n),
  SerieNumerotation(code: 'fiscal.quittances', libelle: 'Quittances d’échéances fiscales', module: 'CFG', prefixe: 'QUIT', genre: genreDerive, note: _n),
  // Import / reprise
  SerieNumerotation(code: 'import.lots', libelle: 'Lots d’import', module: 'CFG', prefixe: 'IMP', annee: anneeLongue, largeur: 3, remiseAnnuelle: true, note: _n),
];
