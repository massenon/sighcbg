/// LES CONFIRMATIONS FISCALES (Direction de Baguidi, compléments du 16/11/2026, section 7 « Fiscal ») : le bouton « Confirmer » des TAUX DE LA CNSS et des VERSIONS DU
/// BARÈME DE L'AIB.
///
/// Trois règles, et elles commandent tout :
///
///  * une confirmation exige un MOTIF (`MOTIF_OBLIGATOIRE`) et une DATE D'EFFET ; elle est TRACÉE : auteur (le compte de la session, jamais un nom saisi), rôle, horodatage,
///    motif, et la VALEUR confirmée recopiée telle qu'elle était (on sait ce qui a été confirmé, même si la valeur change ensuite) ;
///  * elle est RÉSERVÉE au geste réservé `fiscal_confirmer` de la matrice (origine PROPOSÉE : le Comptable et la DAF, à valider par la Direction) — `CONFIRMATION_RESERVEE` ;
///    un fileul ne confirme pas : la configuration fiscale est tenue par la mère (`FILEUL_LECTURE_SEULE`) ;
///  * RIEN N'EST ÉCRASÉ : une confirmation est une fiche de plus de la collection [fcoCollection] (famille R), datée ; une confirmation ne se réécrit pas
///    (`CONFIRMATION_EXISTANTE` à la même date d'effet) et ne s'insère pas avant la plus récente (`DATE_EFFET_ANTERIEURE` : elle masquerait l'historique). La valeur reste
///    versionnée par date : pour le barème de l'AIB, la confirmation d'une version NON ARRÊTÉE l'arrête à la date d'effet choisie (la mécanique d'arrêt de `m12-aib`,
///    `cpdControlerVersionAib`, la même) ; une version déjà arrêtée garde sa date d'effet.
///
/// Fonctions PURES : elles rendent ce qu'il faut écrire ; l'appelant écrit, journalise (RG-12) et notifie. Symboles préfixés `fco` / `Fco`.
library;

import '../comptabilite/cpd_bareme_aib.dart';
import '../droits/gestes_reserves.dart';
import '../paie/pai_moteur.dart' show paiCnssOuvriere, paiCnssPatronale;
import '../referentiels/versions_datees.dart' show isoJour;

/// La collection des confirmations (famille R : la mère seule écrit, les postes la reçoivent).
const String fcoCollection = 'confirmationsFiscales';

/// Ce qui se confirme.
const String fcoObjetCnss = 'cnss';
const String fcoObjetBaremeAib = 'bareme_aib';

/// La cible unique de la CNSS : ses taux et son plafond, confirmés ensemble.
const String fcoCibleCnssTaux = 'taux';

/// Un refus nommé : code stable, motif lisible, geste de correction.
class FcoRefus {
  const FcoRefus(this.code, this.motif, this.geste);
  final String code, motif, geste;
  @override
  String toString() => '$code : $motif';
}

/// CE QUI EXISTE DE LA CNSS aujourd'hui : la part ouvrière et la part patronale (constantes du moteur de paie, CDCT : 3,6 % et 16,4 %), et le PLAFOND — il n'en existe
/// pas : la paie cotise « sans plafond ». Confirmer « aucun plafond » est une confirmation comme une autre ; un plafond chiffré n'est pas inventé ici.
Map<String, Object?> fcoValeursCnss() => {'tauxOuvrier': paiCnssOuvriere, 'tauxPatronal': paiCnssPatronale, 'plafond': null};

/// Le libellé d'une valeur de la CNSS (« part ouvrière 3,6 %, part patronale 16,4 %, aucun plafond »).
String fcoLibelleCnss(Map<String, Object?> v) {
  String pct(Object? x) {
    final n = x is num ? x : num.tryParse('$x');
    if (n == null) return '—';
    return '${n == n.roundToDouble() ? n.toInt() : n}'.replaceAll('.', ',');
  }

  final plafond = v['plafond'];
  return 'part ouvrière ${pct(v['tauxOuvrier'])} %, part patronale ${pct(v['tauxPatronal'])} %, ${plafond == null ? 'aucun plafond' : 'plafond de ${pct(plafond)} F'}';
}

bool _actif(Map<String, Object?> f) => '${f['statut'] ?? 'actif'}' == 'actif';
String _jour(Object? d) => d == null || '$d'.trim().isEmpty ? '' : isoJour(d);
String _dateFr(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';

/// Les confirmations ACTIVES d'un objet et d'une cible, par date d'effet croissante (l'historique).
List<Map<String, Object?>> fcoHistorique(Iterable<Map<String, Object?>> existantes, String objet, String cible) {
  final out = [for (final f in existantes) if (_actif(f) && f['objet'] == objet && '${f['cible']}' == cible) f];
  out.sort((a, b) {
    final c = _jour(a['dateEffet']).compareTo(_jour(b['dateEffet']));
    return c != 0 ? c : '${a['confirmeLe'] ?? ''}'.compareTo('${b['confirmeLe'] ?? ''}');
  });
  return out;
}

/// La confirmation EN VIGUEUR à [date] : la plus récente dont la date d'effet ne dépasse pas [date], ou `null` (non confirmé à cette date).
Map<String, Object?>? fcoConfirmationALaDate(Iterable<Map<String, Object?>> existantes, String objet, String cible, DateTime date) {
  final j = isoJour(date);
  Map<String, Object?>? retenue;
  for (final f in fcoHistorique(existantes, objet, cible)) {
    if (_jour(f['dateEffet']).compareTo(j) <= 0) retenue = f;
  }
  return retenue;
}

/// Le droit de confirmer : le geste `fiscal_confirmer` de la matrice en force ([gestes], absent : l'origine), et un poste qui tient sa configuration.
FcoRefus? fcoControleDroit({required String role, bool fileul = false, DroitsGestes? gestes}) {
  if (fileul) {
    return const FcoRefus('FILEUL_LECTURE_SEULE', 'Ce poste est un fileul : la configuration fiscale est tenue par la mère, la confirmation s’y fait.',
        'Confirmer depuis le poste mère : la confirmation arrivera ici par la synchronisation.');
  }
  if (role.isEmpty || !(gestes ?? gestesOrigine()).peut(role, gesteFiscalConfirmer)) {
    return const FcoRefus('CONFIRMATION_RESERVEE', 'Confirmer un taux fiscal est un geste réservé (« Confirmer un taux fiscal ») que votre rôle ne détient pas.',
        'Demander au comptable ou à la DAF, ou faire accorder le geste au rôle dans « Rôles et permissions › Gestes réservés ».');
  }
  return null;
}

/// UNE CONFIRMATION : le refus nommé, ou la fiche à AJOUTER (jamais une réécriture). [valeur] : la valeur confirmée, recopiée telle quelle sur la fiche ; [libelle] : ce qu'on
/// confirme, en clair (pour le registre et le journal).
({FcoRefus? refus, Map<String, Object?>? fiche}) fcoConfirmer({
  required String objet,
  required String cible,
  required String libelle,
  required Map<String, Object?> valeur,
  required Object? dateEffet,
  required String? motif,
  required String role,
  required String auteur,
  required DateTime maintenant,
  required Iterable<Map<String, Object?>> existantes,
  DroitsGestes? gestes,
  bool fileul = false,
}) {
  ({FcoRefus? refus, Map<String, Object?>? fiche}) non(FcoRefus r) => (refus: r, fiche: null);
  final d = fcoControleDroit(role: role, fileul: fileul, gestes: gestes);
  if (d != null) return non(d);
  final m = (motif ?? '').trim();
  if (m.isEmpty) {
    return non(const FcoRefus('MOTIF_OBLIGATOIRE', 'Le motif de la confirmation est obligatoire.', 'Dire sur quoi repose la confirmation : texte, notification de l’organisme, avis de l’expert-comptable.'));
  }
  final effet = _jour(dateEffet);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(effet)) {
    return non(const FcoRefus('DATE_EFFET_REQUISE', 'La date d’effet de la confirmation est obligatoire.', 'Choisir la date à partir de laquelle la valeur est confirmée.'));
  }
  final histo = fcoHistorique(existantes, objet, cible);
  if (histo.any((f) => _jour(f['dateEffet']) == effet)) {
    return non(FcoRefus('CONFIRMATION_EXISTANTE', 'Une confirmation de « $libelle » prend déjà effet le ${_dateFr(effet)} : une confirmation ne se réécrit pas.',
        'Choisir une date d’effet postérieure.'));
  }
  if (histo.isNotEmpty && _jour(histo.last['dateEffet']).compareTo(effet) > 0) {
    final der = _jour(histo.last['dateEffet']);
    return non(FcoRefus('DATE_EFFET_ANTERIEURE', 'La confirmation la plus récente de « $libelle » prend effet le ${_dateFr(der)} : une confirmation insérée avant elle masquerait l’historique.',
        'Choisir une date d’effet au plus tôt le ${_dateFr(der)}.'));
  }
  return (
    refus: null,
    fiche: <String, Object?>{
      'id': 'CFO-$objet-$cible-$effet',
      'statut': 'actif',
      'objet': objet,
      'cible': cible,
      'libelle': libelle,
      'valeur': {...valeur},
      'dateEffet': effet,
      'motif': m,
      'confirmePar': auteur,
      'confirmeRole': role,
      'confirmeLe': maintenant.toUtc().toIso8601String(),
    }
  );
}

/// LA CONFIRMATION D'UNE VERSION DU BARÈME DE L'AIB : le refus nommé, ou la fiche de confirmation à ajouter ET, pour une version NON ARRÊTÉE, le patch d'ARRÊT de la
/// version (à la date d'effet choisie, décidée par l'auteur à la date du jour) — contrôlé par la mécanique de `m12-aib` (`cpdControlerVersionAib`), la même. Une version
/// ARRÊTÉE garde SA date d'effet (le passé ne se réécrit pas) : sa confirmation ne fait que s'ajouter. [situations] : les situations de l'acheteur.
({FcoRefus? refus, Map<String, Object?>? fiche, Map<String, Object?>? arret}) fcoConfirmerVersionAib({
  required Map<String, Object?> version,
  required Iterable<Map<String, Object?>> versions,
  required Iterable<Map<String, Object?>> situations,
  required Object? dateEffet,
  required String? motif,
  required String role,
  required String auteur,
  required DateTime maintenant,
  required Iterable<Map<String, Object?>> existantes,
  DroitsGestes? gestes,
  bool fileul = false,
}) {
  ({FcoRefus? refus, Map<String, Object?>? fiche, Map<String, Object?>? arret}) non(FcoRefus r) => (refus: r, fiche: null, arret: null);
  if (!_actif(version)) return non(const FcoRefus('VERSION_ARCHIVEE', 'Une version archivée du barème ne se confirme pas.', 'Choisir une version active.'));
  final arretee = cpdEstArretee(version);
  final effet = arretee ? _jour(version['dateEffet']) : _jour(dateEffet);
  final sit = '${version['situation'] ?? ''}';
  final libSit = [for (final s in situations) if ('${s['code']}' == sit) '${s['libelle'] ?? sit}'].firstOrNull ?? sit;
  final taux = version['taux'];
  final libelle = 'AIB ${cpdLibelleBareme(cpdBaremeDeSituation([for (final s in situations) if ('${s['code']}' == sit) s].firstOrNull ?? const {}))} — $libSit : $taux %';
  // Une version arrêtée SANS date d'effet (héritée, « depuis l'adoption ») se confirme depuis la date d'effet saisie.
  final effetRetenu = effet.isEmpty ? _jour(dateEffet) : effet;
  final c = fcoConfirmer(
      objet: fcoObjetBaremeAib,
      cible: '${version['id']}',
      libelle: libelle,
      valeur: {'situation': sit, 'bareme': [for (final s in situations) if ('${s['code']}' == sit) cpdBaremeDeSituation(s)].firstOrNull, 'taux': taux, 'versionId': version['id']},
      dateEffet: effetRetenu,
      motif: motif,
      role: role,
      auteur: auteur,
      maintenant: maintenant,
      existantes: existantes,
      gestes: gestes,
      fileul: fileul);
  if (c.refus != null) return non(c.refus!);
  if (arretee) return (refus: null, fiche: c.fiche, arret: null);
  final jour = isoJour(maintenant);
  final saisie = <String, Object?>{
    'situation': sit,
    'taux': taux,
    'source': version['source'],
    'motif': version['motif'] ?? motif,
    'statutArret': cpdStatutArrete,
    'dateEffet': effetRetenu,
    'dateArret': jour,
    'decideurArret': auteur,
  };
  final refus = cpdControlerVersionAib(saisie, version, versions, maintenant, situations: situations);
  if (refus != null) {
    final code = refus.contains(' : ') ? refus.split(' : ').first : 'AIB_ARRET_REFUSE';
    return non(FcoRefus(code, refus, 'Corriger la date d’effet, ou ajouter une version à l’écran « Acompte sur impôt (AIB) ».'));
  }
  return (
    refus: null,
    fiche: c.fiche,
    arret: {
      'dateEffet': effetRetenu,
      'statutArret': cpdStatutArrete,
      'arrete': true,
      'aValider': false,
      'dateArret': jour,
      'decideurArret': auteur,
      'confirmationId': c.fiche!['id'],
    }
  );
}
