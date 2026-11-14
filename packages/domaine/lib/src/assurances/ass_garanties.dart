/// LES GARANTIES SONT DATÉES (T13, décision de la Direction du 14/11/2026 : « dater aussi les garanties des assureurs »).
///
/// Le principe est celui des prix (une version par date d'effet, jamais un écrasement) et de la couverture d'assurance du patient (`couverturesAssurance`) : quand une donnée de référence change
/// alors que des pièces ont été émises sous l'ancienne, on VERSIONNE. Une garantie est une SÉRIE (souscripteur, catégorie, libellé normalisé) ; chaque changement de taux ou de plafond ajoute
/// une ligne à la série, qui porte sa date d'effet et son rang. La version remplacée reste écrite : une facture émise garde son taux, et une date d'effet qu'une facture a déjà dépassée est
/// refusée. La prise en charge (RG-09, `repartir`) lit la version EN VIGUEUR à la DATE DE LA PIÈCE, jamais la plus récente.
///
/// Les fiches sont passées en ARGUMENT (souscripteurs, garanties, factures, patients, couvertures) : aucune lecture d'une base, aucune date lue sur l'horloge. Un refus se NOMME (code, motif,
/// geste) ; l'essai contrôle sans rien écrire. Le moteur est celui que la clinique sœur a livré et vérifié à son lot 8b ; la garde du magasin, la migration d'un poste déjà peuplé et la vue
/// « une ligne par série » sont propres à Baguidi (E2601 à E2615).
library;

import '../caisse/prise_en_charge.dart' show cleSerieGarantie, garantiesEnVigueur, souscripteurDe;
import '../format/format_fr.dart' show dateFR;
import 'ass_regles.dart' show assCategoriesGarantie, assDate, assUnitesPlafond;

typedef _Fiche = Map<String, Object?>;

final _jourIso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Les versions d'une série (souscripteur, catégorie, libellé), de la plus ancienne à la plus récente (une ligne sans date vaut « depuis l'ouverture » : elle passe la première).
/// [garanties] : les fiches actives. Le tri est STABLE : à date égale, l'ordre de pose est conservé.
List<_Fiche> assVersionsGarantie(Iterable<_Fiche> garanties, Object? souscripteurId, Object? categorie, Object? libelle, {Object? assureur}) {
  final cle = cleSerieGarantie({'souscripteurId': souscripteurId, 'assureur': assureur, 'categorie': categorie, 'libelle': libelle});
  final rows = <_Fiche>[for (final g in garanties) if (g['statut'] != 'archive' && cleSerieGarantie(g) == cle) g];
  final avecRang = [for (var i = 0; i < rows.length; i++) (i, rows[i])]
    ..sort((a, b) {
      final c = '${a.$2['dateEffet'] ?? ''}'.compareTo('${b.$2['dateEffet'] ?? ''}');
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final x in avecRang) x.$2];
}

/// La première facture non archivée d'un assuré de ce souscripteur datée du jour dit ou après : ce qu'une version ne peut pas rattraper (la pièce émise garde son taux).
_Fiche? assFactureSousGrille(_Fiche sous, String jour,
    {required Iterable<_Fiche> factures, required Iterable<_Fiche> patients, required List<_Fiche> couvertures, required List<_Fiche> souscripteurs}) {
  final parId = {for (final p in patients) p['id']: p};
  final trouvees = <_Fiche>[];
  for (final f in factures) {
    if (f['statut'] == 'archive') continue;
    final date = '${f['date'] ?? ''}';
    if (f['assureur'] == null || f['assureur'] == '' || f['assureur'] != sous['assureur'] || date.isEmpty || (date.length >= 10 ? date.substring(0, 10) : date).compareTo(jour) < 0) continue;
    final p = parId[f['patientId']];
    final sd = p == null ? null : souscripteurDe(p, couvertures, souscripteurs, date);
    if (sd != null && sd['id'] == sous['id']) trouvees.add(f);
  }
  trouvees.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
  return trouvees.firstOrNull;
}

/// Ce que `assPoserGarantie` rend : un refus nommé, ou la version à ÉCRIRE (`fiche`, nulle en essai), avec la version remplacée (`ancienne`) et le rang de la nouvelle.
class AssPoseGarantie {
  const AssPoseGarantie.refus(String this.code, String this.motif, String this.geste)
      : ok = false,
        ancienne = null,
        version = null,
        fiche = null;
  const AssPoseGarantie.ok({this.ancienne, required int this.version, this.fiche}) : ok = true, code = null, motif = null, geste = null;
  final bool ok;
  final String? code, motif, geste;
  final _Fiche? ancienne, fiche;
  final int? version;
}

num _nombre(double x) => x == x.truncateToDouble() ? x.toInt() : x;

/// Pose une VERSION de garantie. [spec] : `{souscripteurId, categorie, libelle, taux, plafond, unitePlafond, dateEffet, sansDate?, source?, motif?, code?, zone?}`. `sansDate` n'est admis que pour la
/// PREMIÈRE ligne d'une série (la grille d'une convention saisie d'un bloc : « depuis l'ouverture », aucune date n'est inventée). [champs] : traces posées sur la fiche (lot d'import).
AssPoseGarantie assPoserGarantie(
  Map<String, Object?> spec, {
  required List<_Fiche> souscripteurs,
  required List<_Fiche> garanties,
  required Iterable<_Fiche> factures,
  required Iterable<_Fiche> patients,
  required List<_Fiche> couvertures,
  bool essai = false,
  Map<String, Object?> champs = const {},
}) {
  AssPoseGarantie refus(String code, String motif, String geste) => AssPoseGarantie.refus(code, motif, geste);
  final sous = souscripteurs.where((s) => s['id'] == spec['souscripteurId']).firstOrNull;
  if (sous == null || sous['statut'] == 'archive') {
    return refus('SOUSCRIPTEUR_INCONNU', 'aucun souscripteur actif ne porte cette identité', 'Choisissez un souscripteur connu (écran « Conventions & garanties ») ou importez-le d’abord.');
  }
  if (!assCategoriesGarantie.any((c) => c.$1 == spec['categorie'])) {
    return refus('CATEGORIE_INCONNUE', 'la catégorie « ${spec['categorie']} » n’est pas une catégorie de garantie', 'Choisissez une catégorie de la liste.');
  }
  final libelle = '${spec['libelle'] ?? ''}'.trim();
  if (libelle.isEmpty) {
    return refus('GARANTIE_SANS_LIBELLE', 'la garantie n’a pas de libellé : la série ne se distinguerait pas des autres garanties de la catégorie', 'Saisissez le libellé de la garantie.');
  }
  final t = spec['taux'];
  final taux = t == null || t == '' ? double.nan : (t is num ? t.toDouble() : (double.tryParse('$t') ?? double.nan));
  if (!taux.isFinite || taux < 0 || taux > 100) {
    return refus('TAUX_INVALIDE', 'le taux doit être un nombre de 0 à 100', 'Saisissez un pourcentage entre 0 et 100.');
  }
  final pl = spec['plafond'];
  final double? plafond = pl == null || pl == '' ? null : (pl is num ? pl.toDouble() : (double.tryParse('$pl') ?? double.nan));
  if (plafond != null && (!plafond.isFinite || plafond < 0 || plafond.floorToDouble() != plafond)) {
    return refus('PLAFOND_INVALIDE', 'le plafond doit être un montant entier de francs, zéro ou plus', 'Saisissez un montant entier, ou laissez vide pour « sans plafond ».');
  }
  final unite = plafond == null ? null : (spec['unitePlafond'] == null || spec['unitePlafond'] == '' ? null : '${spec['unitePlafond']}');
  if (plafond != null && !assUnitesPlafond.containsKey(unite)) {
    return refus('UNITE_PLAFOND_REQUISE', 'un plafond se dit toujours « par quoi » (acte, jour, an…)', 'Choisissez l’unité du plafond.');
  }
  final sansDate = spec['sansDate'] == true;
  final de = '${spec['dateEffet'] ?? ''}';
  final jour = sansDate ? null : (_jourIso.hasMatch(de) ? de : '');
  if (!sansDate && (jour == null || jour.isEmpty)) {
    return refus('DATE_EFFET_REQUISE', 'la date d’effet est obligatoire : sans elle, la nouvelle version ne se distinguerait pas de l’ancienne sur les pièces déjà émises', 'Saisissez la date à laquelle la garantie change.');
  }
  final rows = assVersionsGarantie(garanties, sous['id'], spec['categorie'], libelle);
  if (sansDate) {
    if (rows.isNotEmpty) {
      return refus('SERIE_EXISTANTE', 'la garantie « $libelle » existe déjà pour ce souscripteur : elle ne se redéfinit pas « depuis l’ouverture »', 'Posez une nouvelle version avec sa date d’effet.');
    }
  } else {
    final j = jour!;
    final meme = rows.where((g) => '${g['dateEffet'] ?? ''}' == j).firstOrNull;
    final enForce = garantiesEnVigueur(rows, j).firstOrNull;
    final identique = enForce != null &&
        (enForce['taux'] as num?)?.toDouble() == taux &&
        (enForce['plafond'] == null ? null : (enForce['plafond'] as num).toDouble()) == plafond &&
        (plafond == null || enForce['unitePlafond'] == unite);
    if (identique) {
      return refus('GARANTIE_INCHANGEE', 'la garantie « $libelle » porte déjà ce taux et ce plafond à cette date', 'Rien à faire : aucune version n’est créée.');
    }
    if (meme != null) {
      return refus('VERSION_MEME_DATE', 'une version de « $libelle » prend déjà effet le ${dateFR(assDate(j))} avec d’autres valeurs : une version ne se réécrit pas', 'Choisissez une autre date d’effet.');
    }
    final plusRecente = rows.where((g) => '${g['dateEffet'] ?? ''}'.compareTo(j) > 0).firstOrNull;
    if (plusRecente != null) {
      return refus('VERSION_ANTERIEURE',
          'une version plus récente de « $libelle » prend effet le ${dateFR(assDate(plusRecente['dateEffet']))} : on ne glisse pas une version dans le passé d’une série', 'Choisissez une date d’effet postérieure à la dernière version.');
    }
    final fac = assFactureSousGrille(sous, j, factures: factures, patients: patients, couvertures: couvertures, souscripteurs: souscripteurs);
    if (fac != null) {
      return refus('FACTURE_DEJA_EMISE', 'la facture ${fac['numero']} du ${dateFR(assDate(fac['date']))} a été émise sous la grille de ce souscripteur : une pièce émise garde son taux',
          'Choisissez une date d’effet postérieure à la dernière facture émise (${dateFR(assDate(fac['date']))}).');
    }
  }
  final ancienne = rows.isEmpty ? null : (garantiesEnVigueur(rows, jour ?? '9999-12-31').firstOrNull ?? rows.last);
  if (essai) return AssPoseGarantie.ok(ancienne: ancienne, version: rows.length + 1);
  final fiche = <String, Object?>{
    'souscripteurId': sous['id'],
    'assureur': sous['assureur'],
    'code': spec['code'] ?? (rows.isNotEmpty ? rows.first['code'] : null),
    'libelle': libelle,
    'categorie': spec['categorie'],
    'taux': _nombre(taux),
    'plafond': plafond == null ? null : _nombre(plafond),
    'unitePlafond': unite,
    'zone': (rows.isNotEmpty ? rows.first['zone'] : null) ?? spec['zone'],
    'dateEffet': sansDate ? null : jour,
    'version': rows.length + 1,
    'motif': spec['motif'],
    'source': spec['source'],
    ...champs,
  };
  return AssPoseGarantie.ok(ancienne: ancienne, version: rows.length + 1, fiche: fiche);
}

// --- la garde du magasin ----------------------------------------------------------------------------------------------------

/// Les champs d'une version posée : elle explique des pièces déjà émises, elle ne se réécrit pas (une correction AJOUTE une version).
const assChampsImmuablesGarantie = ['souscripteurId', 'assureur', 'categorie', 'libelle', 'taux', 'plafond', 'unitePlafond', 'dateEffet', 'version'];

bool _meme(Object? a, Object? b) {
  final va = (a == null || a == '') ? null : a, vb = (b == null || b == '') ? null : b;
  if (va == null || vb == null) return va == vb;
  if (va is num && vb is num) return va.toDouble() == vb.toDouble();
  return va == vb;
}

/// Le motif du refus d'une écriture sur `garanties`, ou `null`. Tenue AU MOTEUR du magasin (masquer un bouton ne protège rien) : une version est immuable ; une version ne s'ajoute qu'à une
/// série dont elle est la plus récente, avec une date d'effet que ni une version ni une facture émise n'a dépassée ; une version ne s'archive pas sous une version plus récente ni sous une
/// facture émise. [apres] : la fiche telle qu'elle serait ; [avant] : la fiche stockée ; [garanties] : TOUTES les fiches stockées ; [factureSousGrille] : la première facture émise sous la
/// grille d'un souscripteur depuis un jour (ou `null`), lue au magasin par l'appelant.
String? assGardeGarantie(
  String operation,
  _Fiche apres,
  _Fiche? avant, {
  required Iterable<_Fiche> garanties,
  required _Fiche? Function(Object? souscripteurId) souscripteur,
  required _Fiche? Function(_Fiche souscripteur, String jour) factureSousGrille,
}) {
  final toutes = [for (final g in garanties) if (g['id'] != apres['id']) g];
  List<_Fiche> serie(_Fiche g) => assVersionsGarantie(toutes, g['souscripteurId'], g['categorie'], g['libelle'], assureur: g['assureur']);
  if (operation == 'modifier') {
    if (avant == null) return null;
    for (final k in assChampsImmuablesGarantie) {
      if (!_meme(avant[k], apres[k])) {
        return 'Une version de garantie est IMMUABLE (champ « $k ») : elle explique des pièces déjà émises. Une correction AJOUTE une version avec sa date d’effet (écran « Conventions & garanties »).';
      }
    }
    return null;
  }
  final ref = operation == 'archiver' ? (avant ?? apres) : apres;
  final rows = serie(ref);
  if (operation == 'archiver') {
    final d = '${ref['dateEffet'] ?? ''}';
    final posterieure = rows.where((g) => '${g['dateEffet'] ?? ''}'.compareTo(d) > 0).firstOrNull;
    if (posterieure != null) {
      return 'Une version plus récente de « ${ref['libelle']} » prend effet le ${dateFR(assDate(posterieure['dateEffet']))} : on n’archive pas une version sous la suivante. Archiver d’abord la plus récente.';
    }
    if (d.isNotEmpty) {
      final s = souscripteur(ref['souscripteurId']);
      final f = s == null ? null : factureSousGrille(s, d);
      if (f != null) {
        return 'La facture ${f['numero']} du ${dateFR(assDate(f['date']))} a été émise sous cette version : une garantie employée par une pièce émise ne s’archive plus. Posez une nouvelle version datée.';
      }
    }
    return null;
  }
  if (operation != 'inserer') return null;
  if (rows.isEmpty) return null;
  final d = '${apres['dateEffet'] ?? ''}';
  if (d.isEmpty) {
    return 'La garantie « ${apres['libelle']} » existe déjà pour ce souscripteur : elle ne se redéfinit pas « depuis l’ouverture ». Poser une nouvelle version avec sa date d’effet.';
  }
  if (rows.any((g) => '${g['dateEffet'] ?? ''}' == d)) {
    return 'Une version de « ${apres['libelle']} » prend déjà effet le ${dateFR(assDate(d))} : une version ne se réécrit pas. Choisir une autre date d’effet.';
  }
  final plus = rows.where((g) => '${g['dateEffet'] ?? ''}'.compareTo(d) > 0).firstOrNull;
  if (plus != null) {
    return 'Une version plus récente de « ${apres['libelle']} » prend effet le ${dateFR(assDate(plus['dateEffet']))} : on ne glisse pas une version dans le passé d’une série.';
  }
  final s = souscripteur(apres['souscripteurId']);
  final f = s == null ? null : factureSousGrille(s, d);
  if (f != null) {
    return 'La facture ${f['numero']} du ${dateFR(assDate(f['date']))} a été émise sous la grille de ce souscripteur : une pièce émise garde son taux. Choisir une date d’effet postérieure.';
  }
  return null;
}

// --- la migration d'un poste déjà peuplé ------------------------------------------------------------------------------------

/// Ce que la migration a fait : les fiches à réécrire (rang de version posé) et le compte.
class AssMigrationGaranties {
  const AssMigrationGaranties(this.fiches, this.series, this.versionsPosees, this.doublons);

  /// Les fiches dont le rang `version` vient d'être posé (toute la collection n'est pas réécrite : seules celles-ci changent).
  final List<_Fiche> fiches;
  final int series, versionsPosees, doublons;
  bool get aFait => versionsPosees > 0;
}

/// MIGRATION D'UN POSTE DÉJÀ PEUPLÉ : chaque garantie existante qui ne porte pas de rang devient la version 1 de sa série, « depuis l'ouverture » : sa date d'effet RESTE vide (la date que
/// personne n'a saisie ne s'invente pas : même doctrine que `debut: null` des couvertures). Aucun taux, plafond ni libellé ne change : ce que la prise en charge lisait avant, elle le lit après.
/// Une série qui portait deux fois la même garantie sans date (doublon d'avant le mécanisme) reçoit les rangs 1 et 2 dans l'ordre des fiches ; la lecture garde la première (voir
/// `garantiesEnVigueur`), et le doublon est COMPTÉ, jamais archivé en silence. Idempotente : une fiche qui porte déjà son rang n'est pas touchée.
AssMigrationGaranties assMigrerGaranties(Iterable<_Fiche> garanties) {
  final parSerie = <String, List<_Fiche>>{};
  for (final g in garanties) {
    if (g['statut'] == 'archive') continue;
    (parSerie[cleSerieGarantie(g)] ??= []).add(g);
  }
  final aEcrire = <_Fiche>[];
  var doublons = 0;
  for (final rows in parSerie.values) {
    final tries = [for (var i = 0; i < rows.length; i++) (i, rows[i])]
      ..sort((a, b) {
        final c = '${a.$2['dateEffet'] ?? ''}'.compareTo('${b.$2['dateEffet'] ?? ''}');
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    for (var k = 0; k < tries.length; k++) {
      final g = tries[k].$2;
      if (g['version'] == null) aEcrire.add({'id': g['id'], 'version': k + 1});
    }
    final sansDate = rows.where((g) => '${g['dateEffet'] ?? ''}'.isEmpty).length;
    if (sansDate > 1) doublons += sansDate - 1;
  }
  return AssMigrationGaranties(aEcrire, parSerie.length, aEcrire.length, doublons);
}

// --- la vue « une ligne par série » -------------------------------------------------------------------------------------------

/// Une série de garantie telle que l'écran la présente : sa version EN VIGUEUR au jour dit, la prochaine (à venir) et toutes les versions, de la plus ancienne à la plus récente.
class AssSerieGarantie {
  const AssSerieGarantie({required this.cle, required this.souscripteurId, required this.categorie, required this.libelle, required this.versions, required this.enVigueur, required this.aVenir});
  final String cle;
  final Object? souscripteurId;
  final String categorie, libelle;
  final List<_Fiche> versions;

  /// La version lue par la prise en charge au jour dit ; `null` quand la série ne prend effet que plus tard.
  final _Fiche? enVigueur;

  /// La prochaine version (date d'effet après le jour dit), ou `null`.
  final _Fiche? aVenir;
}

/// Les séries d'un ou de tous les souscripteurs ([souscripteurId] `null` : toutes), à raison d'UNE LIGNE par série : c'est ce que l'écran compte et liste (lister toutes les versions ferait
/// dire « six garanties » pour trois séries dont deux ont changé de taux). Ordre : celui de la première fiche de chaque série.
List<AssSerieGarantie> assSeriesGarantie(Iterable<_Fiche> garanties, String jour, {Object? souscripteurId}) {
  final ordre = <String>[];
  final parCle = <String, List<_Fiche>>{};
  for (final g in garanties) {
    if (g['statut'] == 'archive') continue;
    if (souscripteurId != null && g['souscripteurId'] != souscripteurId) continue;
    final k = cleSerieGarantie(g);
    (parCle[k] ??= []).add(g);
    if (!ordre.contains(k)) ordre.add(k);
  }
  return [
    for (final k in ordre)
      () {
        final rows = parCle[k]!;
        final v = assVersionsGarantie(rows, rows.first['souscripteurId'], rows.first['categorie'], rows.first['libelle'], assureur: rows.first['assureur']);
        final vigueur = garantiesEnVigueur(v, jour).firstOrNull;
        final venir = v.where((g) => '${g['dateEffet'] ?? ''}'.compareTo(jour) > 0).firstOrNull;
        return AssSerieGarantie(
            cle: k, souscripteurId: rows.first['souscripteurId'], categorie: '${rows.first['categorie']}', libelle: '${rows.first['libelle']}', versions: v, enVigueur: vigueur, aVenir: venir);
      }()
  ];
}

/// Le rang d'une version dans sa série : le rang écrit, sinon sa place dans l'ordre des dates (un poste qui n'a pas encore migré se lit pareil).
int assRangGarantie(_Fiche g, List<_Fiche> versionsDeLaSerie) {
  final r = g['version'];
  if (r is num) return r.toInt();
  final i = versionsDeLaSerie.indexWhere((x) => x['id'] == g['id']);
  return i < 0 ? 1 : i + 1;
}
