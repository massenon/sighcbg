/// MODIFIER UNE SÉRIE DE NUMÉROTATION : une VERSION DATÉE, sous geste réservé, écrite par la mère (famille R), déposée par un fileul (lot 2, 16/11/2026).
///
/// Une modification n'efface rien et ne renumérote rien : elle AJOUTE une fiche (une par version, immuable) à `seriesNumerotation`, dont la date d'effet
/// est au plus tôt AUJOURD'HUI — elle ne s'applique donc qu'aux pièces à venir ; les pièces déjà émises gardent leur numéro (RG-01). Refus nommés :
/// série inconnue, geste réservé absent, date passée, motif manquant, format invalide, version déjà posée à cette date ; une version identique à celle
/// en vigueur est SANS EFFET (sauf pour ARRÊTER une semence « à valider » : la version identique lève la mention).
///
/// Sur un poste rattaché, le geste ne s'écrit pas : il se DÉPOSE dans `validationsDeposees` (genre [valGenreNumerotation]) — le mécanisme de la continuité
/// des validations, pas un second —, et la mère l'APPLIQUE sous le rôle et le nom de son auteur en refaisant tous les contrôles avec SA matrice et SES
/// versions. Fonctions PURES : le poste y branche ses collections, sa matrice et son journal.
library;

import '../droits/gestes_reserves.dart';
import '../validation/validation.dart' show RefusValidation, valInstant;
import '../validation/validation_deposee.dart';
import 'numerotation.dart';

/// Le genre de dépôt d'une modification de série (à côté de `referentiel`, `circuit_achat`, `reglage_clinique`).
const String valGenreNumerotation = 'serie_numerotation';

/// Les champs qu'une version peut changer (le code, le genre et le champ des fiches restent ceux de la semence).
const List<String> champsSerieModifiables = ['prefixe', 'annee', 'positionAnnee', 'separateur', 'separateurAnnee', 'largeur', 'prefixeRang', 'remiseAnnuelle'];

String _jourIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Les versions (fiches actives de la collection) d'une série.
List<Map<String, Object?>> _versionsDe(String code, Iterable<Map<String, Object?>> fiches) => [
      for (final f in fiches)
        if (f['statut'] != 'archive' && f['code'] == code) f
    ];

/// La série en vigueur à [jour] d'après les fiches données (et non le registre de processus : la mère contrôle avec SES versions).
SerieNumerotation serieALaDate(String code, Iterable<Map<String, Object?>> fiches, String jour) {
  final base = Numerotation.semence(code);
  SerieNumerotation retenue = base;
  final vs = [
    for (final f in _versionsDe(code, fiches))
      if (f['dateEffet'] != null) SerieNumerotation.depuisFiche(f, base)
  ].whereType<SerieNumerotation>().toList()
    ..sort((a, b) => a.dateEffet!.compareTo(b.dateEffet!));
  for (final v in vs) {
    if (v.dateEffet!.compareTo(jour) <= 0) retenue = v;
  }
  return retenue;
}

/// Le contrôle UNIQUE (écran à blanc, mère à l'application) : `refus`, ou la fiche de version à écrire ; `sansEffet` quand la version demandée est déjà en
/// vigueur à cette date et arrêtée.
({RefusValidation? refus, bool sansEffet, Map<String, Object?>? version}) serieControler({
  required String code,
  required Map<String, Object?> valeurs,
  required String dateEffet,
  required String role,
  required String acteur,
  required DroitsGestes gestes,
  required Iterable<Map<String, Object?>> fiches,
  required DateTime maintenant,
  String? motif,
}) {
  if (!Numerotation.connue(code)) {
    return (refus: RefusValidation('SERIE_INCONNUE', 'La série « $code » n’existe pas au référentiel de numérotation.', 'Choisir une série de la liste'), sansEffet: false, version: null);
  }
  if (!gestes.peut(role, gesteNumerotationModifier)) {
    final g = gesteReserve(gesteNumerotationModifier);
    return (
      refus: RefusValidation('NUMEROTATION_RESERVEE', 'Modifier une série de numérotation est le geste réservé « ${g?.libelle ?? gesteNumerotationModifier} » : le rôle « $role » ne le détient pas.',
          'Demander à un rôle qui détient le geste, ou à la Direction de l’accorder dans Rôles et permissions › Gestes réservés'),
      sansEffet: false,
      version: null
    );
  }
  final aujourdhui = _jourIso(maintenant);
  final jour = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateEffet) ? dateEffet : '';
  if (jour.isEmpty) {
    return (refus: const RefusValidation('DATE_INVALIDE', 'La date d’effet doit être une date (AAAA-MM-JJ).', 'Saisir la date à partir de laquelle la série change'), sansEffet: false, version: null);
  }
  if (jour.compareTo(aujourdhui) < 0) {
    return (
      refus: RefusValidation('NUMEROTATION_RETROACTIVE',
          'Une série ne change que pour les pièces À VENIR : la date d’effet ($jour) est passée. Les pièces déjà émises gardent leur numéro (RG-01).', 'Choisir une date d’effet à partir du $aujourdhui'),
      sansEffet: false,
      version: null
    );
  }
  final m = (motif ?? '').trim();
  if (m.isEmpty) {
    return (refus: const RefusValidation('MOTIF_REQUIS', 'Le motif du changement est obligatoire : il reste au journal et sur la version.', 'Dire pourquoi la série change'), sansEffet: false, version: null);
  }
  final actuelle = serieALaDate(code, fiches, jour);
  final base = Numerotation.semence(code);
  final brute = <String, Object?>{...actuelle.toJson(), for (final k in champsSerieModifiables) if (valeurs.containsKey(k)) k: valeurs[k], 'dateEffet': jour, 'aValider': false};
  if (brute['largeur'] is String) brute['largeur'] = int.tryParse('${brute['largeur']}'.trim()) ?? -1;
  if (brute['separateurAnnee'] == '' || brute['separateurAnnee'] == brute['separateur']) brute.remove('separateurAnnee');
  final nouvelle = SerieNumerotation.depuisFiche(brute, base);
  if (nouvelle == null) {
    final ess = SerieNumerotation(
        code: code, libelle: base.libelle, module: base.module, prefixe: '${brute['prefixe'] ?? ''}', annee: '${brute['annee'] ?? ''}', positionAnnee: '${brute['positionAnnee'] ?? ''}',
        separateur: '${brute['separateur'] ?? ''}', separateurAnnee: brute['separateurAnnee'] as String?, largeur: brute['largeur'] is int ? brute['largeur'] as int : -1,
        prefixeRang: '${brute['prefixeRang'] ?? ''}', remiseAnnuelle: brute['remiseAnnuelle'] == true, genre: base.genre);
    return (refus: RefusValidation('FORMAT_INVALIDE', serieInvalide(ess) ?? 'Format de série invalide.', 'Corriger la série'), sansEffet: false, version: null);
  }
  bool meme(SerieNumerotation a, SerieNumerotation b) => champsSerieModifiables.every((k) => '${a.toJson()[k]}' == '${b.toJson()[k]}');
  if (meme(actuelle, nouvelle) && !actuelle.aValider) return (refus: null, sansEffet: true, version: null);
  if (_versionsDe(code, fiches).any((f) => f['dateEffet'] == jour)) {
    return (
      refus: RefusValidation('VERSION_EXISTANTE', 'Une version de la série « ${base.libelle} » prend déjà effet le $jour : une version est immuable.', 'Choisir une autre date d’effet'),
      sansEffet: false,
      version: null
    );
  }
  return (
    refus: null,
    sansEffet: false,
    version: {
      'id': 'SN-$code-$jour',
      'statut': 'actif',
      ...nouvelle.toJson(),
      'motif': m,
      'creePar': acteur,
      'creeParRole': role,
      'creeLe': valInstant(maintenant),
      if (meme(actuelle, nouvelle)) 'arreteeSansChangement': true,
    }
  );
}

/// DÉPOSE une modification de série depuis un poste rattaché (qui n'écrit pas `seriesNumerotation`). Les contrôles sont ceux de l'application, à blanc ;
/// un dépôt identique qui attend déjà la mère n'est pas doublé.
VerdictDepot serieDeposer({
  required String code,
  required Map<String, Object?> valeurs,
  required String dateEffet,
  required String role,
  required String acteur,
  required String poste,
  required DateTime maintenant,
  required DroitsGestes gestes,
  required Iterable<Map<String, Object?>> fiches,
  required List<Map<String, Object?>> depots,
  required String Function() nouvelId,
  String? motif,
}) {
  final c = serieControler(code: code, valeurs: valeurs, dateEffet: dateEffet, role: role, acteur: acteur, gestes: gestes, fiches: fiches, maintenant: maintenant, motif: motif);
  if (c.refus != null) return VerdictDepot.refus(c.refus!);
  if (c.sansEffet) return VerdictDepot.refus(const RefusValidation('DEJA_EN_VIGUEUR', 'La série a déjà ce format à cette date : rien n’est transmis.', 'Aucun'));
  final v = {for (final k in champsSerieModifiables) if (c.version!.containsKey(k)) k: c.version![k]};
  for (final d in depots) {
    if (d['statut'] != 'archive' && d['etat'] == valDepotDeposee && d['genre'] == valGenreNumerotation && d['cible'] == code && d['dateEffet'] == dateEffet && '${d['valeur']}' == '$v') {
      return VerdictDepot.ok(d, dejaDepose: true);
    }
  }
  return VerdictDepot.ok({
    'id': nouvelId(),
    'statut': 'actif',
    'genre': valGenreNumerotation,
    'famille': code,
    'cible': code,
    'valeur': v,
    'dateEffet': dateEffet,
    'libelle': 'Série de numérotation « ${Numerotation.semence(code).libelle} »',
    'etat': valDepotDeposee,
    'demandeRole': role,
    'demandePar': acteur,
    'demandePoste': poste,
    'demandeLe': valInstant(maintenant),
    'motif': (motif ?? '').trim(),
  });
}

/// Le verdict d'un dépôt de série appliqué par la mère.
class ApplicationSerie {
  const ApplicationSerie({required this.etat, this.code, this.motif, this.geste, this.version});
  final String etat;
  final String? code;
  final String? motif;
  final String? geste;
  final Map<String, Object?>? version;
}

/// APPLIQUE un dépôt sur la mère, sous le RÔLE et le NOM de son auteur, tous les contrôles refaits avec les données de la mère. `null` : rien à faire.
/// La date d'effet est rejugée à l'heure de la MÈRE : un dépôt arrivé après sa date d'effet est refusé en le nommant (il ne s'applique jamais en arrière).
ApplicationSerie? serieAppliquerDepot(
  Map<String, Object?> depot, {
  required DroitsGestes gestes,
  required Iterable<Map<String, Object?>> fiches,
  required DateTime maintenant,
}) {
  if (depot['genre'] != valGenreNumerotation || depot['etat'] != valDepotDeposee || depot['statut'] == 'archive') return null;
  final valeur = depot['valeur'];
  final c = serieControler(
      code: '${depot['cible']}',
      valeurs: valeur is Map ? valeur.cast<String, Object?>() : const {},
      dateEffet: '${depot['dateEffet']}',
      role: '${depot['demandeRole'] ?? ''}',
      acteur: '${depot['demandePar'] ?? ''}',
      gestes: gestes,
      fiches: fiches,
      maintenant: maintenant,
      motif: ['${depot['motif'] ?? ''}'.trim(), 'déposé depuis le poste ${depot['demandePoste'] ?? '—'}'].where((x) => x.isNotEmpty).join(' — '));
  if (c.refus != null) return ApplicationSerie(etat: valDepotRefusee, code: c.refus!.code, motif: c.refus!.motif, geste: c.refus!.geste);
  if (c.sansEffet) return const ApplicationSerie(etat: valDepotSansEffet, code: 'DEJA_EN_VIGUEUR', motif: 'La série avait déjà ce format à cette date : aucune version n’est écrite une seconde fois.');
  return ApplicationSerie(etat: valDepotAppliquee, version: c.version);
}
