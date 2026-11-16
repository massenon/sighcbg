/// LES CONFIRMATIONS FISCALES (Direction de Baguidi, compléments du 16/11/2026, section 7 « Fiscal ») : le bouton « Confirmer » des TAUX DE LA CNSS et des VERSIONS DU
/// BARÈME DE L'AIB — et, depuis le lot 1 de l'inventaire des valeurs en dur, du VPS et du BARÈME DE L'ITS.
///
/// LA CONFIRMATION AGIT SUR LES VALEURS (lot 1) : la CNSS, le VPS et le barème de l'ITS sont des PARAMÈTRES DATÉS (`paie/pai_baremes.dart`) que le moteur de paie lit à
/// la date du bulletin. « Confirmer » atteste la version EN VIGUEUR à la date d'effet ; « Nouvelle version » ([fcoPoserVersion]) pose une valeur nouvelle datée (motif
/// obligatoire, même geste réservé) et la confirme du même coup. Un bulletin déjà généré garde le taux de sa date ; une version qui contredirait un mois déjà généré
/// est refusée (`PAIE_DEJA_GENEREE`). Le barème de l'ITS reste « à confirmer » tant qu'aucune confirmation de la valeur en vigueur ne CITE un texte (`TEXTE_REQUIS`).
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

import 'dart:convert';

import '../comptabilite/cpd_bareme_aib.dart';
import '../format/format_fr.dart' show money;
import '../droits/gestes_reserves.dart';
import '../paie/pai_baremes.dart';
import '../parametres/definitions.dart' show definitionDeParametre;
import '../parametres/parametres.dart';
import '../referentiels/versions_datees.dart' show isoJour;

/// La collection des confirmations (famille R : la mère seule écrit, les postes la reçoivent).
const String fcoCollection = 'confirmationsFiscales';

/// Ce qui se confirme.
const String fcoObjetCnss = 'cnss';
const String fcoObjetBaremeAib = 'bareme_aib';
const String fcoObjetVps = 'vps';
const String fcoObjetBaremeIts = 'bareme_its';
const String fcoObjetAnciennete = 'anciennete';
const String fcoObjetTva = 'tva';

/// La cible unique de la CNSS : ses taux et son plafond, confirmés ensemble.
const String fcoCibleCnssTaux = 'taux';

/// La cible unique du VPS (son taux) et celle du barème de l'ITS (le barème entier, toutes tranches).
const String fcoCibleVpsTaux = 'taux';
const String fcoCibleBaremeIts = 'bareme';

/// Un refus nommé : code stable, motif lisible, geste de correction.
class FcoRefus {
  const FcoRefus(this.code, this.motif, this.geste);
  final String code, motif, geste;
  @override
  String toString() => '$code : $motif';
}

/// CE QUI EXISTE DE LA CNSS : la part ouvrière et la part patronale EN VIGUEUR ([t] : les taux à la date voulue, [PaiTauxPaie.aLaDate] ; absent : les valeurs semées,
/// CDCT 3,6 % et 16,4 %), et le PLAFOND — il n'en existe pas : la paie cotise « sans plafond ». Confirmer « aucun plafond » est une confirmation comme une autre ; un
/// plafond chiffré n'est pas inventé ici.
Map<String, Object?> fcoValeursCnss([PaiTauxPaie? t]) =>
    {'tauxOuvrier': (t ?? PaiTauxPaie.semence).cnssOuvriere, 'tauxPatronal': (t ?? PaiTauxPaie.semence).cnssPatronale, 'plafond': null};

/// Le taux du VPS en vigueur ([t] absent : la valeur semée, 4 %).
Map<String, Object?> fcoValeursVps([PaiTauxPaie? t]) => {'taux': (t ?? PaiTauxPaie.semence).vps};

/// Le barème de l'ITS en vigueur, tranches `[plancher, plafond, taux]` ([t] absent : le barème semé).
Map<String, Object?> fcoValeursIts([PaiTauxPaie? t]) => {'bareme': jsonDecode(paiBaremeItsVersJson((t ?? PaiTauxPaie.semence).baremeIts))};

String _pct(Object? x) {
  final n = x is num ? x : num.tryParse('$x');
  if (n == null) return '—';
  return '${n == n.roundToDouble() ? n.toInt() : n}'.replaceAll('.', ',');
}

/// Le libellé du VPS (« 4 % du salaire brut »).
String fcoLibelleVps(Map<String, Object?> v) => '${_pct(v['taux'])} % du salaire brut';

/// Le libellé d'un barème de l'ITS (« 5 tranches : 0 % jusqu'à 60 000 F … 30 % au-delà de 500 000 F »).
String fcoLibelleIts(Map<String, Object?> v) {
  final b = paiBaremeItsDepuisJson(v['bareme']);
  if (b == null) return 'barème illisible';
  return '${b.length} tranche${b.length > 1 ? 's' : ''} : ${[for (final t in b) t.a == null ? '${_pct(t.taux)} % au-delà de ${money(t.de - 1)}' : '${_pct(t.taux)} % de ${money(t.de)} à ${money(t.a)}'].join(' ; ')}';
}

/// Le libellé d'une valeur de la CNSS (« part ouvrière 3,6 %, part patronale 16,4 %, aucun plafond »).
String fcoLibelleCnss(Map<String, Object?> v) {
  final plafond = v['plafond'];
  return 'part ouvrière ${_pct(v['tauxOuvrier'])} %, part patronale ${_pct(v['tauxPatronal'])} %, ${plafond == null ? 'aucun plafond' : 'plafond de ${_pct(plafond)} F'}';
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
  String? texte,
  bool texteRequis = false,
}) {
  ({FcoRefus? refus, Map<String, Object?>? fiche}) non(FcoRefus r) => (refus: r, fiche: null);
  final d = fcoControleDroit(role: role, fileul: fileul, gestes: gestes);
  if (d != null) return non(d);
  final m = (motif ?? '').trim();
  if (m.isEmpty) {
    return non(const FcoRefus('MOTIF_OBLIGATOIRE', 'Le motif de la confirmation est obligatoire.', 'Dire sur quoi repose la confirmation : texte, notification de l’organisme, avis de l’expert-comptable.'));
  }
  final cite = (texte ?? '').trim();
  if (texteRequis && cite.isEmpty) {
    return non(const FcoRefus('TEXTE_REQUIS', 'Cette valeur ne se confirme qu’en citant le texte qui la fonde (loi de finances, décret, arrêté).',
        'Renseigner le texte cité : sa référence et sa date.'));
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
      if (cite.isNotEmpty) 'texte': cite,
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

// =====================================================================================================================================================
// LOT 1 DE L'INVENTAIRE DES VALEURS EN DUR : LA CONFIRMATION AGIT SUR LES VALEURS DATÉES (CNSS, VPS, barème de l'ITS)
// =====================================================================================================================================================

/// Les clés de paramètre que porte chaque objet confirmable (`paie/pai_baremes.dart`) : une nouvelle version de la CNSS pose ses deux parts ensemble.
const Map<String, List<String>> fcoClesParObjet = {
  fcoObjetCnss: [paiCleCnssOuvriere, paiCleCnssPatronale],
  fcoObjetVps: [paiCleVps],
  fcoObjetBaremeIts: [paiCleBaremeIts],
  fcoObjetAnciennete: [paiCleAncienneteTaux, paiCleAncienneteSeuil],
  fcoObjetTva: [paiCleTvaNormal],
};

/// La cible de confirmation d'un objet daté.
String fcoCibleDe(String objet) => switch (objet) {
      fcoObjetCnss => fcoCibleCnssTaux,
      fcoObjetVps => fcoCibleVpsTaux,
      fcoObjetBaremeIts => fcoCibleBaremeIts,
      fcoObjetAnciennete || fcoObjetTva => 'taux',
      _ => '',
    };

/// La valeur confirmable d'un objet, lue dans les taux [t] (en vigueur à la date voulue).
Map<String, Object?> fcoValeursDe(String objet, PaiTauxPaie t) => switch (objet) {
      fcoObjetCnss => fcoValeursCnss(t),
      fcoObjetVps => fcoValeursVps(t),
      fcoObjetAnciennete => {'taux': t.ancienneteTaux, 'seuilAns': t.ancienneteSeuilAns},
      fcoObjetTva => {'taux': t.tvaNormal},
      _ => fcoValeursIts(t),
    };

/// Le libellé (registre, journal) de la valeur d'un objet daté.
String fcoLibelleDe(String objet, Map<String, Object?> v) => switch (objet) {
      fcoObjetCnss => 'CNSS — ${fcoLibelleCnss(v)}',
      fcoObjetVps => 'VPS — ${fcoLibelleVps(v)}',
      fcoObjetAnciennete => 'Prime d’ancienneté — ${_pct(v['taux'])} % du salaire de base par année, dès ${v['seuilAns']} ans',
      fcoObjetTva => 'TVA du régime normal — ${_pct(v['taux'])} %',
      _ => 'Barème de l’ITS — ${fcoLibelleIts(v)}',
    };

Object? _canon(Object? v) {
  if (v is num) return v == v.truncateToDouble() ? v.toInt() : v;
  if (v is Map) {
    final cles = [for (final k in v.keys) '$k']..sort();
    return {for (final k in cles) k: _canon(v[k])};
  }
  if (v is List) return [for (final x in v) _canon(x)];
  return v;
}

/// Deux valeurs confirmées sont-elles la même ? (les nombres se comparent en valeur : 4 et 4,0 sont le même taux).
bool fcoMemeValeur(Object? a, Object? b) => jsonEncode(_canon(a)) == jsonEncode(_canon(b));

/// La confirmation qui atteste la valeur EN VIGUEUR [valeur] à [date] : la confirmation en vigueur ce jour-là, si elle porte la MÊME valeur ; `null` sinon (jamais
/// confirmée, ou la valeur a changé depuis la dernière confirmation — une confirmation n'atteste que ce qu'elle a recopié).
Map<String, Object?>? fcoConfirmationDeLaValeur(Iterable<Map<String, Object?>> existantes, String objet, String cible, DateTime date, Map<String, Object?> valeur) {
  final c = fcoConfirmationALaDate(existantes, objet, cible, date);
  if (c == null) return null;
  final v = c['valeur'];
  return fcoMemeValeur(v is Map ? v : null, valeur) ? c : null;
}

/// Le barème de l'ITS en vigueur à [date] ([t]) est-il encore « À CONFIRMER » ? Oui tant qu'aucune confirmation de CETTE valeur ne cite un texte : le barème semé est
/// celui de la maquette, « à confirmer par le service comptable ».
bool fcoBaremeItsAConfirmer(Iterable<Map<String, Object?>> existantes, DateTime date, PaiTauxPaie t) {
  final c = fcoConfirmationDeLaValeur(existantes, fcoObjetBaremeIts, fcoCibleBaremeIts, date, fcoValeursIts(t));
  return c == null || '${c['texte'] ?? ''}'.trim().isEmpty;
}

/// « CONFIRMER » la valeur d'un objet daté (CNSS, VPS, barème de l'ITS) : la valeur confirmée est celle EN VIGUEUR À LA DATE D'EFFET choisie, lue dans les versions de la
/// collection `parametres` ([parametres]). Le barème de l'ITS ne se confirme qu'en citant un texte ([texte], `TEXTE_REQUIS`). Rend la fiche à ajouter ou le refus nommé.
({FcoRefus? refus, Map<String, Object?>? fiche}) fcoConfirmerTaux({
  required String objet,
  required Iterable<Map<String, Object?>> parametres,
  required Object? dateEffet,
  required String? motif,
  String? texte,
  required String role,
  required String auteur,
  required DateTime maintenant,
  required Iterable<Map<String, Object?>> existantes,
  DroitsGestes? gestes,
  bool fileul = false,
}) {
  if (!fcoClesParObjet.containsKey(objet)) {
    return (refus: FcoRefus('OBJET_INCONNU', 'Rien de tel à confirmer : « $objet ».', 'Choisir la CNSS, le VPS, le barème de l’ITS, la prime d’ancienneté ou la TVA.'), fiche: null);
  }
  final effet = _jour(dateEffet);
  final t = Parametres.dateValide(effet) ? PaiTauxPaie.aLaDate(parametres, effet) : PaiTauxPaie.semence;
  final valeur = fcoValeursDe(objet, t);
  return fcoConfirmer(
      objet: objet,
      cible: fcoCibleDe(objet),
      libelle: fcoLibelleDe(objet, valeur),
      valeur: valeur,
      dateEffet: dateEffet,
      motif: motif,
      role: role,
      auteur: auteur,
      maintenant: maintenant,
      existantes: existantes,
      gestes: gestes,
      fileul: fileul,
      texte: texte,
      texteRequis: objet == fcoObjetBaremeIts);
}

/// « NOUVELLE VERSION » d'un objet daté, sous le geste `fiscal_confirmer` : une valeur NOUVELLE à partir d'une date d'effet, avec un motif. Rend les VERSIONS à ajouter à la
/// collection `parametres` (jamais une réécriture : `Parametres.proposer`, qui refuse une date déjà couverte par une pièce) ET la confirmation qui les atteste, ou le refus
/// nommé — rien n'est écrit à moitié : les contrôles passent tous avant que l'appelant n'écrive.
///
/// [valeurs] : par clé de paramètre ([fcoClesParObjet]) un nombre pour un taux, un `List<PaiTranche>` pour le barème. [bulletins] : les bulletins générés — une version
/// qui prendrait effet au plus tard le premier jour du dernier mois généré contredirait des bulletins déjà calculés (`PAIE_DEJA_GENEREE`). [texte] : le texte cité ; pour
/// le barème de l'ITS, sans lui la version est posée mais reste « à confirmer ».
({FcoRefus? refus, List<Map<String, Object?>> versions, Map<String, Object?>? confirmation}) fcoPoserVersion({
  required String objet,
  required Map<String, Object?> valeurs,
  required Object? dateEffet,
  required String? motif,
  String? texte,
  required String role,
  required String auteur,
  required DateTime maintenant,
  required Iterable<Map<String, Object?>> parametres,
  required Iterable<Map<String, Object?>> usages,
  required Iterable<Map<String, Object?>> existantes,
  required Iterable<Map<String, Object?>> bulletins,
  DroitsGestes? gestes,
  bool fileul = false,
}) {
  ({FcoRefus? refus, List<Map<String, Object?>> versions, Map<String, Object?>? confirmation}) non(FcoRefus r) => (refus: r, versions: const [], confirmation: null);
  final cles = fcoClesParObjet[objet];
  if (cles == null) return non(FcoRefus('OBJET_INCONNU', 'Rien de tel à versionner : « $objet ».', 'Choisir la CNSS, le VPS, le barème de l’ITS, la prime d’ancienneté ou la TVA.'));
  final d = fcoControleDroit(role: role, fileul: fileul, gestes: gestes);
  if (d != null) return non(d);
  final m = (motif ?? '').trim();
  if (m.isEmpty) {
    return non(const FcoRefus('MOTIF_OBLIGATOIRE', 'Le motif de la nouvelle version est obligatoire.', 'Dire sur quoi repose le changement : texte, notification de l’organisme, avis de l’expert-comptable.'));
  }
  final effet = _jour(dateEffet);
  if (!Parametres.dateValide(effet)) {
    return non(const FcoRefus('DATE_EFFET_REQUISE', 'La date d’effet de la nouvelle version est obligatoire.', 'Choisir la date à partir de laquelle la valeur s’applique.'));
  }
  final der = paiDernierePeriodeGeneree(bulletins);
  if (der != null) {
    final borne = paiDateTauxBulletin(der.annee, der.mois);
    if (effet.compareTo(borne) <= 0) {
      return non(FcoRefus('PAIE_DEJA_GENEREE',
          'Des bulletins sont déjà générés jusqu’au mois commençant le ${_dateFr(borne)}, au taux en vigueur ce jour-là : une version effective au ${_dateFr(effet)} les contredirait.',
          'Choisir une date d’effet postérieure au ${_dateFr(borne)} (le mois suivant) ; un bulletin généré ne se recalcule pas.'));
    }
  }
  // Les valeurs nouvelles, contrôlées, sous la forme qui voyage.
  final avant = PaiTauxPaie.aLaDate(parametres, effet);
  final ecrites = <String, Object?>{};
  for (final cle in cles) {
    final v = valeurs[cle];
    final lib = definitionDeParametre(cle)?.libelle ?? cle;
    if (cle == paiCleAncienneteSeuil) {
      final r = paiControlerSeuilAns(v);
      if (r != null) return non(FcoRefus('VALEUR_INVALIDE', r, 'Saisir un nombre entier d’années.'));
      ecrites[cle] = (v as num).toInt();
      continue;
    }
    if (cle == paiCleBaremeIts) {
      if (v is! List<PaiTranche>) return non(FcoRefus('VALEUR_INVALIDE', '$lib : barème illisible.', 'Saisir une tranche par ligne : plancher, plafond (ou « et plus »), taux.'));
      final r = paiControlerBaremeIts(v);
      if (r != null) return non(FcoRefus('VALEUR_INVALIDE', '$lib : $r', 'Corriger les tranches.'));
      ecrites[cle] = paiBaremeItsVersJson(v);
    } else {
      final r = paiControlerTaux(v, lib);
      if (r != null) return non(FcoRefus('VALEUR_INVALIDE', r, 'Saisir le taux en pourcentage (par exemple 3,6).'));
      ecrites[cle] = (v as num).toDouble();
    }
  }
  final apres = PaiTauxPaie(
      cnssOuvriere: (ecrites[paiCleCnssOuvriere] as num?) ?? avant.cnssOuvriere,
      cnssPatronale: (ecrites[paiCleCnssPatronale] as num?) ?? avant.cnssPatronale,
      vps: (ecrites[paiCleVps] as num?) ?? avant.vps,
      baremeIts: ecrites[paiCleBaremeIts] == null ? avant.baremeIts : paiBaremeItsDepuisJson(ecrites[paiCleBaremeIts])!,
      ancienneteTaux: (ecrites[paiCleAncienneteTaux] as num?) ?? avant.ancienneteTaux,
      ancienneteSeuilAns: (ecrites[paiCleAncienneteSeuil] as num?)?.toInt() ?? avant.ancienneteSeuilAns,
      tvaNormal: (ecrites[paiCleTvaNormal] as num?) ?? avant.tvaNormal);
  final valeurApres = fcoValeursDe(objet, apres);
  if (fcoMemeValeur(fcoValeursDe(objet, avant), valeurApres)) {
    return non(FcoRefus('VALEUR_IDENTIQUE', 'La valeur saisie est déjà celle en vigueur au ${_dateFr(effet)} : rien ne change.',
        'Pour attester la valeur en vigueur, utiliser « Confirmer ».'));
  }
  // Les versions, par la règle commune des paramètres (numérotation, date déjà couverte par une pièce).
  final toutes = [
    for (final f in parametres)
      if (f['statut'] != 'archive') Parametre.fromJson(f)
  ];
  final versions = <Map<String, Object?>>[];
  for (final cle in cles) {
    final r = Parametres.proposer(
        definition: definitionDeParametre(cle),
        versions: [for (final v in toutes) if (v.cle == cle) v],
        usages: [for (final u in usages) if (u['cle'] == cle) u],
        valeur: ecrites[cle],
        dateEffet: effet,
        auteur: auteur,
        creeLe: maintenant.toUtc().toIso8601String(),
        motif: m);
    if (!r.ok) return non(FcoRefus(r.refus!.code.toUpperCase(), r.refus!.motif, r.refus!.geste));
    versions.add({'id': r.valeur!.id, 'statut': 'actif', ...r.valeur!.toJson()});
  }
  final c = fcoConfirmer(
      objet: objet,
      cible: fcoCibleDe(objet),
      libelle: fcoLibelleDe(objet, valeurApres),
      valeur: valeurApres,
      dateEffet: effet,
      motif: m,
      role: role,
      auteur: auteur,
      maintenant: maintenant,
      existantes: existantes,
      gestes: gestes,
      fileul: fileul,
      texte: texte);
  if (c.refus != null) return non(c.refus!);
  return (refus: null, versions: versions, confirmation: {...c.fiche!, 'nouvelleVersion': true});
}
