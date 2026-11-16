import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/impression/piece.dart' show PieceA4;
import 'package:sigh_poste/modules/m2/sp_commun.dart' show enregistrerConsultationSpec, specialiteDeCode;
import 'package:sigh_poste/modules/m2/sp_travail.dart' show enregistrerVisiteTravail, entreprisesClientes;
import 'package:sigh_poste/modules/m1/fiche_impression.dart' show imprimerDossierComplet;
import 'package:sigh_poste/modules/m2/cs_commun.dart' as cs show imprimerDossier, imprimerOrdonnance;
import 'package:sigh_poste/modules/m3/bloc_avis_medical.dart' show EcranSortieAvisMedical;
import 'package:sigh_poste/modules/m3/bloc_pansements.dart' show EcranBonsPansements;
import 'package:sigh_poste/modules/m3/bloc_sorties.dart' show EcranSorties;
import 'package:sigh_poste/modules/m6/flux_dispensation.dart' show EcranDispensation;
import 'package:sigh_poste/modules/m7/pv_reception.dart' show imprimerPv;
import 'package:sigh_poste/modules/m8/avoirs.dart' show imprimerAvoir;
import 'package:sigh_poste/modules/m8/remboursements.dart' show pieceOperation;
import 'package:sigh_poste/modules/m8/commun.dart' show lignesDe;
import 'package:sigh_poste/modules/m8/impression.dart' show imprimerEngagement, imprimerFacture, imprimerRecu;
import 'package:sigh_poste/modules/mecef/commun.dart' show imprimerFactureNormalisee;
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'explorateur.dart';

/// Une pièce que le balayage d'écrans n'atteint pas (sélection de ligne, geste de flux, saisie préalable) : elle est produite par sa FABRIQUE d'impression, avec
/// une fiche du jeu de démonstration, dans le contexte réel d'un écran du module (magasin, agent connecté, horloge, identité à la date de la pièce).
class Recette {
  const Recette(this.id, this.module, this.ecran, this.role, this.lancer, {this.titre});
  final String id;
  final String module;
  final String ecran;
  final String role;
  final String? titre;
  final Future<void> Function(BuildContext ctx, Magasin m) lancer;
}

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

Fiche _un(Magasin m, String col, [bool Function(Fiche)? ok]) {
  final l = m.collection(col).actives.where(ok ?? (_) => true);
  if (l.isEmpty) throw StateError('collection « $col » : aucune fiche utilisable dans le jeu');
  return l.first;
}


Fiche _pat(Magasin m, {String? sexe}) => _un(m, 'patients', (f) => sexe == null || f['sexe'] == sexe);
String _nom(Fiche p) => '${p['nom']} ${p['prenom']}';

/// Une opération de caisse d'exemple (remboursement ou annulation), bâtie sur une vraie facture du jeu : le jeu livré n'en porte aucune.
Future<void> _operation(BuildContext c, Magasin m, String nature) {
  final f = _un(m, 'factures', (f) => f['statutPaiement'] == 'soldee' && _n(f['montantPaye']) > 0);
  final ce = ContexteEcran.of(c);
  final r = {
    'reference': nature == 'Annulation' ? 'ANN-2026-0001' : 'RMB-2026-0001',
    'date': '2026-11-05',
    'nature': nature,
    'factureNumero': f['numero'],
    'patient': f['patient'],
    'montant': _n(f['montantPaye']),
    'motif': nature == 'Annulation' ? 'Erreur de saisie de la prestation, à refacturer.' : 'Trop-perçu constaté à la caisse.',
    'autorisePar': ce.agent.nom,
  };
  return afficherApercu(c, pieceOperation(r, utilisateur: ce.agent.nom, edite: ce.aujourdhui, reference: PieceA4.reference_(ce.aujourdhui, 92)));
}

List<Recette> recettes() => [
      // ---- M8 : facturation et caisse
      Recette('facture-assure', 'M8', 'm8-factures', 'caissier', (c, m) => imprimerFacture(c, _un(m, 'factures', (f) => f['assureur'] != null && f['numeroMecef'] != null))),
      Recette('facture-proforma', 'M8', 'm8-proforma', 'caissier', (c, m) => imprimerFacture(c, _un(m, 'factures'), proforma: true),
          titre: 'Facture pro-forma'),
      Recette('recu-detaille', 'M8', 'm8-paiements', 'caissier', (c, m) => imprimerRecu(c, _un(m, 'factures', (f) => f['statutPaiement'] == 'partielle'))),
      Recette('engagement-paiement', 'M8', 'm8-reliquats', 'caissier', (c, m) {
        final f = _un(m, 'factures', (f) => f['statutPaiement'] == 'partielle' || f['statutPaiement'] == 'impayee');
        return imprimerEngagement(c, f);
      }),
      Recette('facture-avoir', 'M8', 'm8-facture-avoir', 'caissier', (c, m) => imprimerAvoir(c, _un(m, 'avoirs'))),
      Recette('ticket-caisse', 'M8', 'm8-facturation', 'caissier', (c, m) {
        final f = _un(m, 'factures', (f) => f['assureur'] != null && f['numeroMecef'] != null);
        final lignes = [
          for (final l in lignesDe(f))
            if (l['designation'] != null)
              LigneArticle(
                  designation: '${l['designation']}'.toUpperCase(),
                  quantite: _n(l['quantite']),
                  prixUnitaire: _n(l['prixNet'] ?? l['prixUnitaire']),
                  montant: _n(l['montant'] ?? _n(l['quantite']) * _n(l['prixUnitaire'])))
        ];
        final ce = ContexteEcran.of(c);
        return afficherApercuTicket(
            c,
            EntreeTicket(
                operateur: ce.agent.nom,
                numero: 'T-${'${f['numero']}'.split('-').last}',
                typeVente: 'ASSURANCE',
                assureur: '${f['assureur']}',
                assure: '${f['patient']}',
                dossier: '${f['patientCode']}',
                date: ce.aujourdhui,
                mecef: BlocMecef(nim: 'NIM00000000', code: 'CODE-DGI-DEMONSTRATION', compteurs: '1/1 FN'),
                lignes: lignes,
                total: _n(f['montantTTC']),
                partAssureur: _n(f['partAssurance']),
                partPatient: _n(f['partPatient']),
                regle: _n(f['montantPaye']),
                baseMecef: _n(f['baseMecef'])),
            '${f['numero']}');
      }, titre: 'Ticket de caisse 80 mm'),
      // ---- MECeF
      Recette('mecef-facture', 'MECEF', 'mecef-factures', 'da', (c, m) => imprimerFactureNormalisee(c, _un(m, 'factures', (f) => f['numeroMecef'] != null))),
      // ---- M2 : ordonnance et dossier de consultation
      Recette('ordonnance', 'M2', 'm2-ordonnances', 'medecin', (c, m) => cs.imprimerOrdonnance(c, _un(m, 'ordonnances'))),
      Recette('dossier-consultation', 'M2', 'm2-dossiers-consultation', 'medecin', (c, m) => cs.imprimerDossier(c, _un(m, 'dossiersConsultation'))),

      // ---- M7 : procès-verbal de réception des réactifs (nature distincte des consommables : chaîne du froid)
      Recette('pv-reactifs', 'M7', 'm7-pv-reception-reactifs', 'stock', (c, m) => imprimerPv(c, _un(m, 'pvReceptions', (f) => f['nature'] == 'reactifs'), 'reactifs'),
          titre: 'Procès-verbal de réception — réactifs'),
      // ---- M8 : attestation de remboursement et avis d'annulation (le jeu n'en porte aucune : fiche d'exemple bâtie sur une facture du jeu)
      Recette('remboursement-attestation', 'M8', 'm8-remboursements', 'caissier', (c, m) => _operation(c, m, 'Remboursement'),
          titre: 'Attestation de remboursement'),
      Recette('annulation-avis', 'M8', 'm8-remboursements', 'caissier', (c, m) => _operation(c, m, 'Annulation'), titre: 'Avis d’annulation de facture'),
      // ---- M6 : bon de sortie de stock de la dispensation (aucune délivrance au jeu : exemple bâti sur une ordonnance et deux produits du jeu)
      Recette('bon-dispensation', 'M6', 'm6-dispensation', 'stock', (c, m) {
        final ce = ContexteEcran.of(c);
        final p = _pat(m);
        final produits = m.collection('produits').actives.where((x) => _n(x['prixVente'] ?? x['prix'] ?? x['prixUnitaire']) > 0).take(3).toList();
        if (produits.isEmpty) throw StateError('aucun produit tarifé dans le jeu');
        final d = {
          'reference': 'DLV-2026-0001',
          'patient': _nom(p),
          'patientCode': p['code'],
          'date': '2026-11-05',
          'dispensePar': ce.agent.nom,
          'lignes': [
            for (final x in produits)
              {'produit': '${x['designation'] ?? x['nom']}', 'unite': '${x['unite'] ?? 'boîte'}', 'quantite': 2, 'prix': _n(x['prixVente'] ?? x['prix'] ?? x['prixUnitaire'])}
          ],
        };
        return afficherApercu(
            c, const EcranDispensation().pieceBon(d, utilisateur: ce.agent.nom, edite: ce.aujourdhui, reference: PieceA4.reference_(ce.aujourdhui, 91)));
      }),
      // ---- M3 : décharge de sortie contre avis médical (le jeu n'en porte aucune)
      Recette('sortie-avis-medical', 'M3', 'm3-sortie-avis-medical', 'infirmier', (c, m) {
        final p = _pat(m);
        EcranSortieAvisMedical.imprimer(c, {
          'reference': 'SAM-2026-0001',
          'patient': _nom(p),
          'patientCode': p['code'],
          'lit': 'A2 LIT1',
          'dateSortie': '2026-11-06',
          'heureSortie': '16h30',
          'motif': 'Obligations familiales impérieuses',
          'risques': 'Aggravation de l’état clinique, reprise de la fièvre, nécessité d’une nouvelle hospitalisation.',
          'avisProcureur': false,
          'decharge': true,
        });
        return Future.value();
      }),
      // ---- M3 : bon de pansement (trois séances) et bon de sortie d'hospitalisation, sur une ordonnance et une admission du jeu
      Recette('bon-pansement', 'M3', 'm3-bons-pansements', 'infirmier', (c, m) {
        final o = _un(m, 'ordonnances');
        EcranBonsPansements.imprimerBon(c, {
          ...o,
          'numero': 'ORD-2026-90001',
          'actes': [
            for (var i = 0; i < 3; i++) {'code': 'GY-PAN', 'acteCode': 'GY-PAN', 'designation': 'Pansement simple', 'prix': 6000, 'quantite': 1}
          ],
        });
        return Future.value();
      }),
      Recette('bon-sortie-hospitalisation', 'M3', 'm3-sorties', 'infirmier', (c, m) {
        EcranSorties.bonSortie(c, _un(m, 'admissions'), const {});
        return Future.value();
      }),
      // ---- M1 : dossier complet du patient
      Recette('dossier-patient-complet', 'M1', 'm1-patients', 'reception', (c, m) => Future.sync(() => imprimerDossierComplet(c, _un(m, 'patients'))),
          titre: 'Dossier complet du patient'),
    ];


/// Un écran dont le registre est VIDE au jeu livré : on y inscrit une fiche d'exemple (patient et personnel du jeu, valeurs fictives) dans un magasin éphémère,
/// puis l'explorateur ouvre l'écran et déclenche l'édition comme pour les autres. Ce que le jeu ne porte pas est dit au README, jamais passé sous silence.
class Alimentation {
  const Alimentation(this.id, this.ecran, this.role, this.ajouter);
  final String id;
  final String ecran;
  final String role;
  final void Function(Magasin m) ajouter;
}

void _ins(Magasin m, String col, Fiche f, String prefixe) => m.collection(col).inserer({'statut': 'actif', ...f}, prefixe: prefixe);

List<Alimentation> alimentations() => [
      Alimentation('deces', 'm4-deces', 'infirmier', (m) {
        final p = _pat(m);
        _ins(m, 'deces', {'reference': 'DEC-2026-0001', 'patientId': p['id'], 'patient': _nom(p), 'patientCode': p['code'], 'dateHeure': '2026-10-21T04:20:00.000Z',
          'cause': 'Choc septique', 'lieu': 'Hospitalisation', 'medecin': 'IDOHOU Abraham', 'declare': false}, 'DEC');
      }),
      Alimentation('planification', 'm4-planification', 'infirmier', (m) {
        final p = _pat(m, sexe: 'F');
        _ins(m, 'planificationFamiliale', {'reference': 'PF-2026-0001', 'date': '2026-10-28', 'patientId': p['id'], 'patient': _nom(p), 'patientCode': p['code'], 'acceptante': 'N',
          'methode': 'implant', 'methodeLabel': 'Implant', 'methodeAnterieure': 'Aucune', 'ddr': '2026-10-12', 'constantes': '62 kg · 11/7', 'rdv': '2027-01-28', 'sageFemme': 'AKONDE Octave'}, 'PF');
      }),
      Alimentation('sonu', 'm4-sonu', 'infirmier', (m) {
        final p = _pat(m, sexe: 'F');
        _ins(m, 'registreSONU', {'reference': 'SONU-2026-0001', 'dateHeure': '2026-10-30T22:10:00.000Z', 'patientId': p['id'], 'patient': _nom(p), 'patientCode': p['code'], 'gestite': 2,
          'parite': 1, 'evacuation': true, 'provenance': 'Venue d’elle-même', 'heureAbordVeineux': '22h25', 'fonctions': [1, 2, 8], 'heureFinGestes': '23h40', 'evolution': 'Favorable',
          'agent': 'AKONDE Octave'}, 'SNU');
      }),
      Alimentation('ambulance', 'm13-ambulance', 'agentadmin', (m) {
        final p = _pat(m);
        _ins(m, 'ambulance', {'reference': 'AM-2026-0001', 'dateHeure': '2026-11-02T20:00:00.000Z', 'patientId': p['id'], 'patient': _nom(p), 'patientCode': p['code'],
          'motif': 'Transfert inter-hospitalier', 'destination': 'CHU de référence de Lomé', 'kilometrage': 24, 'chauffeur': 'Chauffeur de garde', 'accompagnant': 'Infirmier',
          'etat': 'terminee', 'tarif': 30000, 'facture': false}, 'AMB');
      }),
      Alimentation('reunion', 'm13-reunions', 'agentadmin', (m) {
        _ins(m, 'reunions', {'reference': 'RU-2026-001', 'date': '2026-10-20', 'heure': '10:00', 'type': 'Comité d’hygiène', 'lieu': 'Bureau de la Direction', 'president': 'BAGUIDI Rafiou',
          'participants': 8, 'ordreDuJour': 'Point sur l’hygiène hospitalière ; plan de formation du trimestre', 'compteRendu': true}, 'REU');
      }),
      Alimentation('reference', 'm1-reference', 'reception', (m) {
        final p = _pat(m);
        _ins(m, 'fichesReference', {'numero': 'REF-00001', 'sens': 'sortante', 'urgent': true, 'patientId': p['id'], 'patient': _nom(p), 'patientCode': p['code'], 'age': 41, 'sexe': p['sexe'],
          'adresse': '${p['adresse']}', 'formationSanitaire': 'Clinique Baguidi', 'centreAlerte': false, 'dateAdmission': '2026-10-30', 'heureAdmission': '18h00', 'pouls': 98,
          'temperature': 38.4, 'tension': '12/8', 'abordVeineux': true, 'contactNom': 'Contact fictif', 'contactAdresse': 'Baguidi — 00 00 00 00 01', 'symptomes': 'Fièvre persistante',
          'traitements': 'Perfusion, antipyrétiques', 'observations': '', 'motifs': ['Plateau technique insuffisant'], 'centreDestination': 'CHU de référence de Lomé',
          'dateReference': '2026-10-30', 'heureReference': '19h30', 'moyen': 'Ambulance', 'agentReferent': 'AKONDE Octave — Infirmier', 'ambulancier': 'Chauffeur de garde'}, 'REF');
      }),
      Alimentation('rapport-medical', 'm3-rapport', 'infirmier', (m) {
        final p = _pat(m);
        _ins(m, 'rapportsMedicaux', {'reference': 'RAP-2026-0001', 'patientId': p['id'], 'patient': _nom(p), 'patientCode': p['code'], 'age': 41, 'sexe': p['sexe'], 'adresse': '${p['adresse']}',
          'telephone': '${p['telephone']}', 'dateEntree': '2026-10-09', 'dateSortie': '2026-10-13', 'motif': 'Fièvre et vomissements',
          'anamnese': 'Début brutal il y a trois jours, automédication sans amélioration.', 'examenPhysique': 'État général altéré, abdomen souple, pas de signe de focalisation.',
          'hypotheses': 'Paludisme grave à confirmer.', 'traitementEntree': 'Artésunate IV, perfusion.', 'examensParacliniques': 'GE-DP, NFS.', 'diagnosticRetenu': 'Paludisme grave',
          'traitementReajuste': 'Relais per os après apyrexie.', 'evolution': 'Favorable, apyrexie à J3.', 'traitementSortie': 'Poursuite du traitement oral pendant sept jours.',
          'diagnosticSortie': 'Paludisme grave — guérison', 'medecin': 'IDOHOU Abraham'}, 'RAP');
      }),
      Alimentation('courrier', 'm13-courriers', 'agentadmin', (m) {
        _ins(m, 'courriers', {'reference': 'DEP-2026-0001', 'sens': 'depart', 'objet': 'Bon de commande de médicaments', 'correspondant': 'Fournisseur pharmaceutique', 'date': '2026-10-15',
          'nature': 'Courriel', 'affecteA': 'Comptabilité', 'traitement': 'traite', 'accuseReception': true, 'numerise': false}, 'COU');
      }),
      Alimentation('document-ged', 'ged-bibliotheque', 'agentadmin', (m) {
        _ins(m, 'documents', {'reference': 'DOC-2026-00001', 'categorie': 'facture_fournisseur', 'rattachement': 'Fournisseur', 'rattacheA': 'Fournisseur pharmaceutique',
          'codeRattachement': 'FOU01', 'libelle': 'Factures fournisseur — Fournisseur pharmaceutique', 'date': '2026-10-24', 'taille': 4321, 'format': 'PDF', 'version': 1,
          'etatValidation': 'en_attente', 'signe': true, 'archive': true, 'deposePar': 'SOKOU Peace', 'consultations': 3, 'conservation': 5}, 'GED');
      }),
      Alimentation('mission', 'm10-missions', 'da', (m) {
        final a = _un(m, 'personnel');
        _ins(m, 'missions', {'reference': 'OM-2026-0001', 'libelle': 'Recyclage en soins obstétricaux d’urgence', 'nature': 'Formation', 'objet': 'Recyclage en soins obstétricaux d’urgence',
          'agentId': a['id'], 'agent': '${a['nomComplet']}', 'fonction': '${a['poste']}', 'structurePrise': 'Organisme de formation', 'destination': 'Cotonou', 'dateDepart': '2026-11-10',
          'dateRetour': '2026-11-14', 'moyen': 'Moyen personnel', 'observation': '', 'statutMission': 'planifiee'}, 'OM');
      }),
      Alimentation('evenement-participations', 'm10-participations', 'da', (m) {
        final ag = m.collection('personnel').actives;
        _ins(m, 'evenements', {'id': 'EVT-DEMO', 'reference': 'EVT-0001', 'nature': 'naissance', 'libelle': 'Naissance — enfant d’un agent', 'beneficiaireId': ag.first['id'],
          'beneficiaire': '${ag.first['nomComplet']}', 'date': '2026-10-23', 'montantParAgent': 1000, 'periodePaiement': '2026-10', 'modeParDefaut': 'comptant', 'portee': 'tous'}, 'EVT');
        for (final a in ag.skip(1)) {
          _ins(m, 'participations', {'reference': 'PAR-${a['id']}', 'evenementId': 'EVT-DEMO', 'evenementLibelle': 'Naissance — enfant d’un agent', 'nature': 'naissance',
            'dateEvenement': '2026-10-23', 'employeId': a['id'], 'agent': '${a['nomComplet']}', 'matricule': '${a['matricule']}', 'fonction': '${a['fonction']}', 'service': '${a['service']}',
            'montant': 1000, 'mode': 'comptant', 'statutPaiement': 'paye', 'datePaiement': '2026-10-27'}, 'PAR');
        }
      }),
      Alimentation('evenement-liste', 'm13-evenements', 'agentadmin', (m) {
        final ag = m.collection('personnel').actives;
        _ins(m, 'evenements', {'id': 'EVT-DEMO', 'reference': 'EVT-0001', 'nature': 'naissance', 'libelle': 'Naissance — enfant d’un agent', 'beneficiaireId': ag.first['id'],
          'beneficiaire': '${ag.first['nomComplet']}', 'date': '2026-10-23', 'montantParAgent': 1000, 'periodePaiement': '2026-10', 'modeParDefaut': 'comptant', 'portee': 'tous'}, 'EVT');
      }),
      Alimentation('badge', 'm10-badges', 'da', (m) {
        final a = _un(m, 'personnel');
        _ins(m, 'badges', {'numero': 'BDG-00001-2026', 'personnelId': a['id'], 'matricule': '${a['matricule']}', 'agent': '${a['nomComplet']}', 'poste': '${a['poste']}',
          'service': '${a['service']}', 'modeleId': 'MDB001', 'emisLe': '2026-11-02', 'expireLe': '2028-11-02', 'etat': 'emis', 'emisPar': 'Spécimen de démonstration'}, 'BDG');
      }),
      Alimentation('badge-planche', 'm10-badges-impression', 'da', (m) {
        final a = _un(m, 'personnel');
        _ins(m, 'badges', {'numero': 'BDG-00001-2026', 'personnelId': a['id'], 'matricule': '${a['matricule']}', 'agent': '${a['nomComplet']}', 'poste': '${a['poste']}',
          'service': '${a['service']}', 'modeleId': 'MDB001', 'emisLe': '2026-11-02', 'expireLe': '2028-11-02', 'etat': 'emis', 'emisPar': 'Spécimen de démonstration'}, 'BDG');
      }),
    ];

/// Un geste d'écran propre à une pièce (choisir la compagnie et le mois avant d'éditer le relevé, par exemple), rejoué par l'explorateur.
class Geste {
  const Geste(this.id, this.ecran, this.role, this.jouer);
  final String id;
  final String ecran;
  final String role;
  final Future<void> Function(Explorateur ex, Magasin m) jouer;
}

List<Geste> gestes() => [
      // Relevé, facture mensuelle (M9) : l'écran s'ouvre sur la première compagnie et sur le mois en cours — sans prestation, il refuse d'éditer. On choisit NSIA.
      Geste('releve-facture-mensuelle', 'm9-factures-assureur', 'da', (ex, m) async {
        final nom = '${m.collection('assureurs').actives.first['nom']}';
        final nsia = '${m.collection('assureurs').actives.firstWhere((a) => a['code'] == 'NSIA')['nom']}';
        await ex.choisirCombo(nom, nsia);
        await ex.balayer('NSIA, mois en cours');
      }),
      Geste('facture-mere-apercu', 'm9-facture-mere', 'da', (ex, m) async {
        final nom = '${m.collection('assureurs').actives.first['nom']}';
        final nsia = '${m.collection('assureurs').actives.firstWhere((a) => a['code'] == 'NSIA')['nom']}';
        await ex.choisirCombo(nom, nsia);
        await ex.balayer('NSIA');
      }),
    ];

/// La visite de médecine du travail et sa FICHE D'APTITUDE : le jeu n'en porte aucune. On l'enregistre par le moteur de l'écran (`enregistrerVisiteTravail`), comme
/// le fait le bouton « Enregistrer la visite », puis l'explorateur imprime la fiche depuis le tiroir de la visite.
Future<void> preparerVisiteTravail(BuildContext ctx, Magasin m) async {
  final c = ContexteEcran.of(ctx);
  final spec = specialiteDeCode(m, 'medecine-travail');
  if (spec == null) throw StateError('fiche « medecine-travail » absente de `specialites`');
  final p = _pat(m);
  final e = entreprisesClientes(m).first;
  enregistrerVisiteTravail(
      c,
      spec,
      {
        'nature': 'periodique',
        'entrepriseId': '${e['id']}',
        'patientCode': p['code'],
        'date': '2026-11-03T09:30',
        'medecin': 'IDOHOU Abraham',
        'q_aptitude': 'Apte',
        'q_poste': 'Agent d’accueil',
        'q_risques': 'Travail sur écran',
        'q_port_epi': 'Non',
        'diagnostic': 'Aucune contre-indication au poste de travail.',
        'avecFiche': true,
      },
      avecFiche: true);
}

Future<(List<Capture>, List<String>)> produireDirects(
    WidgetTester t, DonneesNavigation donnees, Magasin m0, DateTime horloge, bool Function(String) retenu) async {
  final ex = Explorateur(t, donnees, () => horloge);
  ex.brancher();
  for (final r in recettes()) {
    if (!retenu(r.id)) continue;
    final m = magasinLivre();
    await ex.recette(id: r.id, module: r.module, ecran: r.ecran, role: r.role, magasin: m, lancer: (c) => r.lancer(c, m), titre: r.titre);
  }
  for (final a in alimentations()) {
    if (!retenu(a.id)) continue;
    final m = magasinLivre();
    try {
      a.ajouter(m);
      await ex.ouvrir(a.ecran, a.role, m);
      await ex.explorer();
    } catch (e) {
      ex.notes.add('${a.id} : $e');
    }
  }
  for (final g in gestes()) {
    if (!retenu(g.id)) continue;
    final m = magasinLivre();
    try {
      await ex.ouvrir(g.ecran, g.role, m);
      await g.jouer(ex, m);
    } catch (e) {
      ex.notes.add('${g.id} : $e');
    }
  }
  if (retenu('consultation-specialite')) {
    final m = magasinLivre();
    try {
      await ex.ouvrir('spec-cardiologie-consultation', 'medecin', m);
      await ex.preparer((ctx) async {
        final c = ContexteEcran.of(ctx);
        final spec = specialiteDeCode(m, 'cardiologie')!;
        final p = _pat(m);
        enregistrerConsultationSpec(c, spec, {
          'patientCode': p['code'],
          'date': '2026-11-04T10:00',
          'medecin': 'IDOHOU Abraham',
          'motif': 'Palpitations d’effort',
          'q_tension': '12/8',
          'q_fc': 82,
          'q_dyspnee': 'À l’effort',
          'q_douleur_thoracique': 'Non',
          'q_ecg': 'Oui',
          'q_ecg_resultat': 'Rythme sinusal régulier, pas de trouble de la repolarisation.',
          'diagnostic': 'Extrasystoles bénignes, bilan cardiaque rassurant',
          'conduite': 'Contrôle dans trois mois',
        });
      });
      await ex.ouvrir('spec-cardiologie-consultation', 'medecin', m);
      await ex.explorer();
    } catch (e) {
      ex.notes.add('consultation-specialite : $e');
    }
  }
  if (retenu('visite-travail')) {
    final m = magasinLivre();
    try {
      await ex.ouvrir('m2-mdt-visites', 'medecin', m);
      await ex.preparer((ctx) => preparerVisiteTravail(ctx, m));
      await ex.ouvrir('m2-mdt-visites', 'medecin', m);
      await ex.explorer();
    } catch (e) {
      ex.notes.add('visite-travail : $e');
    }
  }
  return (ex.captures, ex.notes);
}
