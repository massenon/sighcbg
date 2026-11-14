// LA BANQUE DE SANG (M5) : quinze donneurs fictifs, vingt poches à des états variés (deux périmées à détruire, trois à péremption proche, quatre transfusées,
// une réservée, le reste disponible) et quatre transfusions avec leur fiche de surveillance à temps imposés (avant la pose, 15, 30, 60, 90 minutes, fin,
// une et deux heures après). Une poche transfusée sort du stock disponible : elle est marquée réservée et porte la date et le patient de la transfusion.
//
// Aucun nom de personne réelle : les donneurs tirent leurs noms des listes du jeu. La durée de conservation retenue est de 35 jours (sang total sur
// solution anticoagulante), valeur d'attente que le biologiste de la clinique arrêtera.
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'clinique_base.dart';
import 'clinique_hospi.dart';
import 'clinique_noms.dart';
import 'clinique_patients.dart';

class _Don {
  _Don(this.nom, this.groupe, this.type);
  final String nom;
  final String groupe;
  final String type;
  int dons = 0;
  DateTime? dernier;
  String id = '';
}

const int _conservation = 35;

/// Planifie la banque de sang. Les donneurs et les poches s'écrivent d'un bloc (stock du jour) ; les transfusions suivent dans la file, aux dates où
/// la poche a servi.
void planifierSang(Jeu j, List<PatientJeu> pats, Set<String> exclus, Set<String> nomsPris) {
  final t = j.t;
  // --- Les quinze donneurs ---
  final noms = <String>{};
  final donneurs = <_Don>[];
  for (var i = 0; i < 15; i++) {
    for (;;) {
      final sexeF = t.chance(0.35);
      final n = t.choisir(patronymes);
      final p = t.choisir(sexeF ? prenomsFeminins : prenomsMasculins);
      final cle = '$n $p';
      if (nomsPris.contains(cle) || !noms.add(cle)) continue;
      final groupe = t.pondere({'O+': 40, 'A+': 24, 'B+': 22, 'AB+': 4, 'O-': 4, 'A-': 2, 'B-': 3, 'AB-': 1});
      donneurs.add(_Don('$n $p', groupe, t.pondere({'Bénévole': 6, 'Familial': 6, 'Compensation': 3})));
      break;
    }
  }
  // --- Les vingt poches : (prélèvement, état, rang du donneur, jour de la transfusion), par ordre de prélèvement ---
  // Quatre transfusées, deux périmées, trois en alerte (péremption sous sept jours), une réservée, dix disponibles. Quinze donneurs : cinq d'entre eux ont
  // donné début août puis de nouveau après les 90 jours de repos (30/10 au 06/11) ; aucun donneur ne donne deux fois en moins de 90 jours.
  final plan = <(DateTime, String, int, DateTime?)>[
    (DateTime.utc(2026, 8, 1, 9), 'perime', 0, null),
    (DateTime.utc(2026, 8, 3, 10), 'perime', 1, null),
    (DateTime.utc(2026, 8, 4, 9), 'transfusee', 2, DateTime.utc(2026, 8, 24)),
    (DateTime.utc(2026, 8, 6, 11), 'transfusee', 3, DateTime.utc(2026, 8, 31)),
    (DateTime.utc(2026, 8, 7, 10), 'transfusee', 4, DateTime.utc(2026, 9, 4)),
    (DateTime.utc(2026, 8, 29, 9), 'transfusee', 5, DateTime.utc(2026, 9, 2)),
    (DateTime.utc(2026, 10, 4, 9), 'alerte', 6, null),
    (DateTime.utc(2026, 10, 6, 10), 'alerte', 7, null),
    (DateTime.utc(2026, 10, 9, 9), 'alerte', 8, null),
    (DateTime.utc(2026, 10, 12, 10), 'actif', 9, null),
    (DateTime.utc(2026, 10, 14, 9), 'actif', 10, null),
    (DateTime.utc(2026, 10, 19, 11), 'actif', 11, null),
    (DateTime.utc(2026, 10, 23, 10), 'actif', 12, null),
    (DateTime.utc(2026, 10, 26, 9), 'actif', 13, null),
    (DateTime.utc(2026, 10, 28, 10), 'actif', 14, null),
    (DateTime.utc(2026, 10, 30, 9), 'actif', 0, null),
    (DateTime.utc(2026, 11, 1, 10), 'actif', 1, null),
    (DateTime.utc(2026, 11, 3, 9), 'actif', 2, null),
    (DateTime.utc(2026, 11, 5, 10), 'reserve', 3, null),
    (DateTime.utc(2026, 11, 6, 9), 'actif', 4, null),
  ];
  final poches = <({DateTime preleve, String etat, _Don don, String ref, DateTime? transfusion})>[];
  for (final (i, (quand, etat, rang, transf)) in plan.indexed) {
    final dn = donneurs[rang];
    if (dn.dernier != null && quand.difference(dn.dernier!).inDays < 90) {
      throw StateError('Le donneur ${dn.nom} donnerait deux fois en moins de 90 jours.');
    }
    dn.dons++;
    dn.dernier = quand;
    poches.add((preleve: quand, etat: etat, don: dn, ref: 'PSL-${100001 + i}', transfusion: transf));
  }
  // Les donneurs : un don historique avant la fenêtre pour ceux qui n'ont pas donné depuis, et le dernier don réel pour les autres.
  for (final (i, dn) in donneurs.indexed) {
    if (dn.dernier == null) {
      dn.dernier = DateTime.utc(2026, 5, 4 + i * 3);
      dn.dons = t.entre(1, 4);
    } else {
      dn.dons += t.entre(0, 3);
    }
    final id = j.ajouter(
        'donneurs',
        {
          'statut': 'actif',
          'reference': 'DON-${pad(i + 1, 4)}',
          'nom': dn.nom,
          'telephone': t.chance(0.5) ? '00 00 00 00 ${pad(70 + i, 2)}' : '',
          'groupe': dn.groupe,
          'type': dn.type,
          'nbDons': dn.dons,
          'dernierDon': jourDe(dn.dernier!),
          'eligible': i != 6 && i != 13,
          if (i == 6 || i == 13) 'observations': 'Non éligible : anémie à l’entretien pré-don, contrôle dans trois mois.',
          'fictif': true,
          'source': 'Donneur fictif de démonstration',
        },
        'DON',
        largeur: 4);
    dn.id = '${id['id']}';
  }
  for (final (i, p) in poches.indexed) {
    final peremption = p.preleve.add(const Duration(days: _conservation));
    final etat = p.etat == 'perime' ? 'perime' : (p.etat == 'alerte' ? 'alerte' : 'actif');
    j.ajouter(
        'poches',
        {
          'statut': 'actif',
          'reference': p.ref,
          'groupe': p.don.groupe,
          'volume': 450,
          'datePrelevement': jourDe(p.preleve),
          'datePeremption': jourDe(peremption),
          'donneur': p.don.nom,
          'observations': p.etat == 'perime'
              ? 'Périmée — à détruire selon la procédure de la banque de sang.'
              : (p.etat == 'transfusee' ? 'Transfusée : voir la fiche de surveillance transfusionnelle.' : (p.etat == 'reserve' ? 'Réservée pour une demande en cours.' : '')),
          'etat': etat,
          'reserve': p.etat == 'transfusee' || p.etat == 'reserve',
          'fictif': true,
        },
        'POC',
        largeur: 4);
    i.toString();
  }

  // --- Les quatre transfusions, sur les poches « transfusées » ---
  final services = ['Hospitalisation', 'Maternité', 'Urgences', 'Hospitalisation'];
  var n = 0;
  for (final p in poches.where((x) => x.etat == 'transfusee')) {
    final jour = p.transfusion!;
    final service = services[n++];
    final pp = chercherPatient(pats, t, ageMin: 16, ageMax: 65, creeAvant: DateTime(jour.year, jour.month, jour.day), exclus: exclus, sexe: service == 'Maternité' ? 'F' : null) ??
        chercherPatient(pats, t, creeAvant: DateTime(jour.year, jour.month, jour.day), exclus: exclus)!;
    exclus.add(pp.id);
    final debut = instant(jour, t.entre(8, 14), 0);
    final ref = p.ref;
    j.planifier(debut, () {
      final pat = pp.fiche(j);
      final flat = <String, Object?>{};
      for (final (k, tp) in d.hosTempsTransfusion.indexed) {
        flat['${tp.$1}_temperature'] = (36.6 + t.entre(0, 6) / 10).toStringAsFixed(1);
        flat['${tp.$1}_ta'] = '${t.entre(11, 13)}/${t.entre(6, 8)}';
        flat['${tp.$1}_fr'] = '${t.entre(14, 20)}';
        flat['${tp.$1}_fc'] = '${t.entre(68, 98)}';
        flat['${tp.$1}_spo2'] = '${t.entre(95, 99)}';
        flat['${tp.$1}_urines'] = 'claires';
        flat['${tp.$1}_conscience'] = 'normale';
        flat['${tp.$1}_autre'] = '';
        k.toString();
      }
      final r = d.hosValeursTransfusion(flat);
      final nT = j.ctx.collection('surveillancesTransfusion').toutes.length + 1;
      j.ajouter(
          'surveillancesTransfusion',
          {
            'statut': 'actif',
            'reference': 'TRF-${pad(nT, 4)}',
            'patientId': pat['id'],
            'patient': '${pat['nom']} ${pat['prenom']}',
            'patientCode': pat['code'],
            'service': service,
            'date': jourDe(jour),
            'pochePSL': ref,
            'debut': '${pad(debut.hour, 2)}h${pad(debut.minute, 2)}',
            'responsableId': infirmierSoignantId,
            'responsable': infirmierNom,
            'valeurs': r.valeurs,
            'releves': r.releves,
            'attendus': d.hosTempsTransfusion.length,
            'incident': false,
            'natureIncident': '',
            'conclusion': 'Transfusion bien tolérée, aucun incident, poche entièrement passée.',
            'fictif': true,
          },
          'TRF',
          largeur: 4);
      final poche = j.ctx.collection('poches').toutes.firstWhere((x) => x['reference'] == ref);
      j.maj('poches', poche['id'], {'transfuseeLe': jourDe(jour), 'transfuseePatientCode': pat['code']});
    });
  }
}
