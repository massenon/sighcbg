import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m8/commun.dart' show mecefEnService;
import 'cs_commun.dart' show stockDe;

/// Briques communes des spécialités (PRD P0-12) : la collection `specialites`, les listes de choix, le formulaire ENGENDRÉ du modèle d'une fiche, et
/// l'enregistrement d'une consultation spécialisée (la pièce, sa facture). Les règles vivent dans `packages/domaine/lib/src/specialites/`.
///
/// UNE SEULE MÉCANIQUE : aucun de ces gestes ne nomme une spécialité. Ajouter une quinzième fiche suffit à faire naître son ruban, son hub, son formulaire,
/// son agenda et ses statistiques.

CollectionMagasin colSpecialites(Magasin m) => m.collection('specialites');

/// Les spécialités ACTIVES, dans l'ordre de la clinique. Une fiche archivée (RG-14) n'apparaît plus au ruban ; ses consultations restent lisibles.
List<Fiche> specialitesActives(Magasin m) =>
    trierPar<Fiche>(colSpecialites(m).actives, (f) => (f['ordre'] as num?) ?? 9999);

Fiche? specialiteDeCode(Magasin m, String code) =>
    colSpecialites(m).actives.where((f) => f['code'] == code).firstOrNull;

String libelleSpec(Fiche f) => '${f['libelle'] ?? f['code']}';

/// Les praticiens qu'on peut choisir pour une spécialité : ceux que la fiche rattache (identifiants de la fiche du personnel) ; sans rattachement, tous
/// les médecins de la clinique — une information, pas un oubli : la fiche n'a pas à être tenue à jour pour qu'on puisse consulter.
List<Fiche> praticiensDe(Magasin m, Fiche spec) {
  final medecins = [
    for (final e in m.collection('personnel').actives)
      if (e['fonction'] == 'medecin') e
  ];
  final rattaches = {for (final x in (spec['praticiens'] as List? ?? const [])) '$x'};
  if (rattaches.isEmpty) return medecins;
  final choisis = [for (final e in medecins) if (rattaches.contains('${e['id']}')) e];
  return choisis.isEmpty ? medecins : choisis;
}

List<OptionChamp> optionsPraticiens(Magasin m, Fiche spec) =>
    [for (final p in praticiensDe(m, spec)) OptionChamp('${p['nomComplet']}', '${p['nomComplet']}')];

List<OptionChamp> optionsPatients(Magasin m) => [
      for (final p in trierPar<Fiche>(m.collection('patients').actives, (p) => p['code']))
        OptionChamp('${p['code']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
    ];

Fiche? patientParCode(Magasin m, Object? code) =>
    m.collection('patients').actives.where((p) => p['code'] == code).firstOrNull;

/// Les champs du modèle d'une fiche, en champs du kit : LE générateur (`specChampsDepuisModele`) fait le travail, ceci ne fait que le traduire.
List<ChampDef> champsDeModeleSpec(Object? modele) => [
      for (final f in specChampsDepuisModele(modele))
        if (f.type == 'section')
          ChampDef.section(f.libelle)
        else
          ChampDef(
              nom: f.nom,
              libelle: f.libelle,
              type: switch (f.type) {
                'nombre' => TypeChamp.nombre,
                'select' => TypeChamp.select,
                'textarea' => TypeChamp.textarea,
                'date' => TypeChamp.date,
                _ => TypeChamp.texte,
              },
              requis: f.requis,
              col: f.plein ? ColChamp.plein : ColChamp.demi,
              lignes: f.lignes,
              aide: f.aide,
              options: [for (final o in f.options) OptionChamp(o)])
    ];

/// L'entête commun de la consultation : le patient, le praticien, la date, le motif — puis le formulaire engendré du modèle.
List<ChampDef> champsConsultationSpec(Magasin m, Fiche spec, {Fiche? rdv}) => [
      const ChampDef.section('Consultation'),
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient (dossier du répertoire)',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          recherche: true,
          options: rdv != null && patientParCode(m, rdv['patientCode']) != null
              ? [for (final o in optionsPatients(m)) if (o.valeur == rdv['patientCode']) o]
              : optionsPatients(m)),
      ChampDef(nom: 'medecin', libelle: 'Praticien', type: TypeChamp.select, requis: true, options: optionsPraticiens(m, spec)),
      const ChampDef(nom: 'date', libelle: 'Date et heure', type: TypeChamp.dateHeure, requis: true),
      const ChampDef(nom: 'motif', libelle: 'Motif de la consultation', col: ColChamp.plein),
      ...champsDeModeleSpec(spec['modele']),
    ];

String dateHeureLocale(DateTime d) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}T${p(d.hour)}:${p(d.minute)}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La caisse : une prestation tarifée passe par la facture, jamais à côté
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce qu'une émission a écrit, et de quoi la défaire.
class EmissionSpec {
  const EmissionSpec(this.factures, this.annuler, {this.note});
  final List<Fiche> factures;

  /// Défait TOUT ce que l'émission a écrit (factures et écritures du comptable) : l'enregistrement d'une consultation est annulable d'un bloc.
  final VoidCallback annuler;

  /// Pourquoi rien n'a été facturé, quand c'est le cas (acte sans tarif : un tiret n'est pas un zéro).
  final String? note;
}

/// La ligne d'une prestation du catalogue, au tarif de la grille pour CE patient (assuré si sa carte est valide à la date : RG-09). `null` si l'acte est
/// absent ou sans tarif — l'appelant le DIT.
({Map<String, Object?>? ligne, String? note}) ligneActe(ContexteEcran c, Fiche patient, String? codeActe, {String? categorie, DateTime? date}) {
  if (codeActe == null || codeActe.isEmpty) {
    return (ligne: null, note: 'Aucun acte tarifé n’est rattaché : rien à facturer.');
  }
  final m = c.magasin;
  final acte = m.collection('actes').actives.where((a) => a['code'] == codeActe).firstOrNull;
  if (acte == null) return (ligne: null, note: 'L’acte $codeActe n’est pas au catalogue : rien à facturer.');
  final jour = iso(date ?? c.aujourdhui);
  final assure = carteValide(patient, m.collection('couverturesAssurance').actives, jour);
  final pr = csTarifPrix(stockDe(c), acte['codeTarif'], assure);
  if (pr.montant == null) {
    return (ligne: null, note: 'L’acte « ${acte['libelle']} » n’a pas de tarif à la grille : rien n’a été facturé (un tiret n’est pas un zéro).');
  }
  final l = ligneSaisie(
      nature: 'acte', designation: '${acte['libelle']}', quantite: 1, prixUnitaire: pr.montant!, secteur: '${acte['secteur']}');
  return (ligne: {...l, 'categorie': categorie ?? l['categorie'], 'acteCode': codeActe}, note: null);
}

/// L'émission d'une facture par le moteur UNIQUE (`emettreFacture`) : répartition assureur / patient par ligne (RG-09), pièces `-A` / `-B`, série annuelle,
/// et la créance constatée au comptable en brouillon (RG-10 contrôlé par le moteur). La pièce naît NON réglée : c'est la caisse qui encaisse.
EmissionSpec emettrePiece(ContexteEcran c, Fiche patient, List<Map<String, Object?>> lignes, String type, {Map<String, Object?> complement = const {}}) {
  final m = c.magasin;
  final jour = iso(c.aujourdhui);
  final r = emettreFacture(
    patient: patient,
    lignes: lignes,
    dateRepartition: jour,
    dateFacture: jour,
    type: type,
    mode: 'especes',
    rangDebut: rangSerieFactures(prefixeSerieFacture(proforma: false, dateFacture: jour), m.collection('factures').toutes) - 1,
    reglement: 0,
    mecefActif: mecefEnService(m),
    couvertures: m.collection('couverturesAssurance').actives,
    souscripteurs: m.collection('souscripteurs').actives,
    garanties: m.collection('garanties').actives,
  );
  final annulations = <VoidCallback>[];
  final creees = <Fiche>[];
  var rang = 0;
  for (final p in r.pieces) {
    final fiche = {...p, ...complement}..remove('mecef');
    if (p['mecef'] == true) {
      fiche['numeroMecef'] = numeroMecefSimule(c.aujourdhui.millisecondsSinceEpoch % 100000 + rang++);
    }
    fiche['statut'] = 'actif';
    final ins = m.collection('factures').inserer(fiche, prefixe: 'FAC');
    creees.add(ins.fiche);
    annulations.add(ins.annuler);
    final ecrs = m.collection('ecritures');
    for (final e in ecritureEncaissement(ins.fiche, 0.0, jour, ecrs.actives)) {
      annulations.add(ecrs.inserer(e, prefixe: 'ECR').annuler);
    }
  }
  return EmissionSpec(creees, () {
    for (final u in annulations.reversed) {
      u();
    }
  });
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// L'enregistrement d'une consultation spécialisée
// ---------------------------------------------------------------------------------------------------------------------------------------------

class ConsultationEnregistree {
  const ConsultationEnregistree(this.consultation, this.emission, this.annuler);
  final Fiche consultation;
  final EmissionSpec? emission;
  final VoidCallback annuler;
}

/// LE geste unique : une consultation spécialisée s'enregistre ici, quel que soit l'écran qui l'ouvre. Lève [RefusSpec] — rien n'est alors écrit.
///
///  * le patient doit exister au répertoire ; le diagnostic est obligatoire et les nombres restent dans les bornes du modèle (`specRefusSaisie`) ;
///  * la consultation s'écrit dans le registre des consultations, donc au DOSSIER du patient, avec la spécialité ;
///  * l'acte de consultation de la fiche, s'il est tarifé, passe par la caisse (facture non réglée) ;
///  * [existante] : le rendez-vous qu'on honore — il DEVIENT la consultation (un rendez-vous honoré EST la consultation : en créer une seconde la compterait
///    deux fois).
ConsultationEnregistree enregistrerConsultationSpec(ContexteEcran c, Fiche spec, Map<String, Object?> valeurs, {Fiche? existante}) {
  final m = c.magasin;
  final patient = patientParCode(m, valeurs['patientCode']);
  if (patient == null) throw RefusSpec('Patient introuvable au répertoire : ${valeurs['patientCode']}.');
  final refus = specRefusSaisie(spec['modele'], valeurs);
  if (refus != null) throw RefusSpec(refus);
  final saisie = specSeparer(spec['modele'], valeurs);
  final date = DateTime.tryParse('${valeurs['date'] ?? ''}') ?? c.aujourdhui;
  final col = m.collection('consultations');
  final reference = existante != null && '${existante['reference'] ?? ''}'.isNotEmpty
      ? '${existante['reference']}'
      : agReferenceSuivante('C', 5, col.toutes);
  final praticien = '${valeurs['medecin'] ?? ''}';
  final praticienId = m.collection('personnel').actives.where((e) => e['nomComplet'] == praticien).map((e) => '${e['id']}').firstOrNull;

  final annulations = <VoidCallback>[];
  // La facture d'abord : elle donne le montant que la consultation porte.
  EmissionSpec? emission;
  final lg = ligneActe(c, patient, spec['acteConsultation'] as String?, categorie: 'consultation', date: date);
  if (lg.ligne != null) {
    emission = emettrePiece(c, patient, [lg.ligne!], specTypeConsultation, complement: {'specialite': '${spec['code']}'});
    annulations.add(emission.annuler);
  }
  final montant = emission == null ? 0 : emission.factures.fold<num>(0, (a, f) => a + nombreOuZero(f['montantTTC']));
  final fiche = specNouvelleConsultation(
      fiche: spec,
      patient: patient,
      saisie: saisie,
      praticien: praticien,
      praticienId: praticienId,
      date: date,
      reference: reference,
      motif: '${valeurs['motif'] ?? ''}'.trim().isEmpty ? null : '${valeurs['motif']}'.trim(),
      tarif: montant);
  if (emission != null) {
    fiche['factureId'] = emission.factures.first['id'];
    fiche['factureNumero'] = emission.factures.first['numero'];
  }
  final Fiche ecrite;
  if (existante != null) {
    annulations.add(col.mettreAJour(existante['id'], fiche));
    ecrite = col.parId(existante['id']) ?? fiche;
  } else {
    final ins = col.inserer(fiche, prefixe: 'CON');
    annulations.add(ins.annuler);
    ecrite = ins.fiche;
  }
  if (emission != null) {
    for (final f in emission.factures) {
      m.collection('factures').mettreAJour(f['id'], {'consultationId': ecrite['id']});
    }
  }
  return ConsultationEnregistree(
      ecrite,
      emission == null && lg.note != null ? EmissionSpec(const [], () {}, note: lg.note) : emission,
      () {
        for (final u in annulations.reversed) {
          u();
        }
      });
}

class RefusSpec implements Exception {
  const RefusSpec(this.message);
  final String message;
  @override
  String toString() => message;
}
