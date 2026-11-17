/// LE PLAN DE NUMÉRISATION, CALCULÉ (lot « valeurs en dur », famille B) : l'écran de la maquette affichait des chiffres STATIQUES (fonds de 18 000 dossiers, 4 230 numérisés,
/// 6 200 prioritaires, six lots de reprise chiffrés, une cadence mensuelle). Ils sont désormais LUS ou CALCULÉS — jamais inventés :
///  * le FONDS papier est un réglage daté (`numerisation.fondsPapierDossiers`) : le papier ne se compte pas dans le logiciel, c'est une valeur DÉCLARÉE ;
///  * un dossier est NUMÉRISÉ quand le patient porte au moins un document dont le fichier est déposé (`docNumerise`, dérivé de la présence du fichier) ;
///  * un dossier est ACTIF (prioritaire) quand le patient a eu une consultation, une admission ou une analyse dans la fenêtre réglée ;
///  * les LOTS sont une liste de référence ordonnée (`listes.m1.lotsNumerisation`) : un patient appartient au premier lot dont il remplit le critère ;
///  * la CADENCE est le nombre de fichiers déposés par mois.
/// Ce qui ne peut pas se calculer se DIT (« non calculable », avec la raison) au lieu d'afficher un zéro ou un chiffre de démonstration.
library;

import '../format/format_fr.dart' show iso;
import '../parametres/listes_reference.dart' show EntreeReference;
import '../pilotage/pil_vue.dart' show pilParMois;
import 'doc_regles.dart' show docNumerise, docScan;

/// Les CRITÈRES de lot que le plan sait évaluer : des identifiants de structure (ce que le code sait calculer), pas des libellés.
const docCritereHospitalises = 'hospitalises';
const docCritereChroniques = 'chroniques';
const docCritereMaternite = 'maternite';
const docCritereAssures = 'assures';
const docCritereRecents = 'recents';
const docCritereInactifs = 'inactifs';

/// Un lot de reprise : [total] et [fait] valent `null` quand le lot n'est pas calculable ([raison] dit pourquoi).
class LotNumerisation {
  const LotNumerisation(this.critere, this.libelle, this.total, this.fait, {this.raison});
  final String critere;
  final String libelle;
  final int? total;
  final int? fait;
  final String? raison;
  bool get calculable => total != null;
}

class PlanNumerisation {
  const PlanNumerisation({
    required this.fondsDeclare,
    required this.fonds,
    required this.repertoire,
    required this.numerises,
    required this.prioritaires,
    required this.prioritairesNumerises,
    required this.lots,
    required this.cadenceEtiquettes,
    required this.cadence,
  });

  /// Le fonds papier DÉCLARÉ (réglage) ; [fonds] est celui retenu : jamais inférieur au répertoire (on ne numérise pas plus de dossiers qu'il n'en existe).
  final int fondsDeclare;
  final int fonds;
  final int repertoire;
  final int numerises;
  final int prioritaires;
  final int prioritairesNumerises;
  final List<LotNumerisation> lots;
  final List<String> cadenceEtiquettes;
  final List<num> cadence;

  int get prioritairesRestants => prioritaires - prioritairesNumerises;

  /// Vrai quand le répertoire compte plus de dossiers que le fonds déclaré : l'écran doit le dire.
  bool get fondsInferieurAuRepertoire => fondsDeclare < repertoire;

  /// Le reste du fonds : ni numérisé ni prioritaire.
  int get fondsInactif {
    final r = fonds - numerises - prioritairesRestants;
    return r < 0 ? 0 : r;
  }
}

String _jour(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

/// Calcule le plan à [aujourdhui]. Toutes les listes sont celles des fiches ACTIVES (RG-14 : une fiche archivée ne compte pas).
PlanNumerisation docPlanNumerisation({
  required List<Map<String, Object?>> patients,
  required List<Map<String, Object?>> documents,
  required List<Map<String, Object?>> consultations,
  required List<Map<String, Object?>> admissions,
  required List<Map<String, Object?>> analyses,
  required List<Map<String, Object?>> grossesses,
  required DateTime aujourdhui,
  required int fondsDeclare,
  required int fenetreMois,
  required List<EntreeReference> lots,
}) {
  final debut = iso(DateTime(aujourdhui.year, aujourdhui.month - fenetreMois, aujourdhui.day));
  final ids = {for (final p in patients) '${p['id']}'};
  final numerises = {
    for (final d in documents)
      if (docNumerise(d) && ids.contains('${d['patientId']}')) '${d['patientId']}'
  };
  final actifs = <String>{};
  void actif(Iterable<Map<String, Object?>> fiches, List<String> champs) {
    for (final f in fiches) {
      final pid = '${f['patientId']}';
      if (!ids.contains(pid)) continue;
      for (final ch in champs) {
        if (_vrai(f[ch])) {
          if (_jour(f[ch]).compareTo(debut) >= 0) actifs.add(pid);
          break;
        }
      }
    }
  }

  actif(consultations, const ['date']);
  actif(admissions, const ['dateEntree']);
  actif(analyses, const ['date', 'dateDemande', 'dateHeure']);
  final hospitalises = {
    for (final a in admissions)
      if (a['statut'] == 'en_cours' && ids.contains('${a['patientId']}')) '${a['patientId']}'
  };
  final maternite = {
    for (final g in grossesses)
      if (ids.contains('${g['patientId']}')) '${g['patientId']}'
  };
  final assures = {
    for (final p in patients)
      if (_vrai(p['assureur'])) '${p['id']}'
  };

  // Un patient appartient au PREMIER lot dont il remplit le critère. `null` : critère non calculable (aucune donnée ne le porte).
  Set<String>? membres(String critere) => switch (critere) {
        docCritereHospitalises => hospitalises,
        docCritereMaternite => maternite,
        docCritereAssures => assures,
        docCritereRecents => actifs,
        docCritereInactifs => ids,
        _ => null,
      };
  String raisonNonCalculable(String critere) => critere == docCritereChroniques
      ? 'Aucun champ de la fiche patient ne marque une affection chronique : ce lot ne peut pas se calculer.'
      : 'Critère « $critere » inconnu du plan : ce lot ne peut pas se calculer.';

  final affectes = <String>{};
  final out = <LotNumerisation>[];
  for (final e in lots) {
    final m = membres(e.code);
    if (m == null) {
      out.add(LotNumerisation(e.code, e.libelle, null, null, raison: raisonNonCalculable(e.code)));
      continue;
    }
    final siens = {for (final id in m) if (!affectes.contains(id)) id};
    affectes.addAll(siens);
    out.add(LotNumerisation(e.code, e.libelle, siens.length, siens.where(numerises.contains).length));
  }
  final fonds = fondsDeclare < ids.length ? ids.length : fondsDeclare;
  // Le lot « fonds inactif » porte TOUT le reste du fonds papier : ce que le répertoire ne couvre pas existe sur le papier seulement.
  final autres = out.where((l) => l.critere != docCritereInactifs && l.calculable).fold<int>(0, (s, l) => s + l.total!);
  for (var i = 0; i < out.length; i++) {
    if (out[i].critere != docCritereInactifs) continue;
    final reste = fonds - autres;
    out[i] = LotNumerisation(out[i].critere, out[i].libelle, reste < (out[i].total ?? 0) ? out[i].total : reste, out[i].fait);
  }

  final deposes = [
    for (final d in documents)
      if (docScan(d) != null) <String, Object?>{'le': docScan(d)!['deposeLe']}
  ];
  final cad = pilParMois(deposes, 'le', ref: aujourdhui);
  return PlanNumerisation(
    fondsDeclare: fondsDeclare,
    fonds: fonds,
    repertoire: ids.length,
    numerises: numerises.length,
    prioritaires: actifs.length,
    prioritairesNumerises: actifs.where(numerises.contains).length,
    lots: out,
    cadenceEtiquettes: cad.etiquettes,
    cadence: cad.valeurs,
  );
}
