/// LE BARÈME DE L'AIB (M12, `m12-aib`) : l'acompte sur impôt assis sur les bénéfices que la clinique retient à la source.
///
/// Le barème est une DONNÉE versionnée par DATE D'EFFET, comme la grille des primes : chaque fiche de la collection `baremeAIB` est une VERSION d'une
/// catégorie (identifiée par son `code`). Une correction n'écrase jamais une version arrêtée : elle AJOUTE une version à une date d'effet postérieure,
/// et le taux d'une date passée reste celui qui était en vigueur ce jour-là (un acompte déjà retenu ne se réécrit pas). Une version s'archive, elle ne
/// se supprime pas (RG-14).
///
/// Une version est ARRÊTÉE (décidée par la Direction, avec la date et le décideur de l'arrêt) ou NON ARRÊTÉE (présente, marquée à valider). Seule une
/// version arrêtée s'applique : un taux non arrêté ne sert jamais à retenir quoi que ce soit, il est offert à la Direction. Sans version arrêtée
/// en vigueur à la date demandée, le moteur rend un taux nul ET le motif — jamais une valeur commode.
///
/// Les comptes : 4478 (AIB retenu, dette envers l'État), 4492 (AIB subi, créance sur l'État), 891 (imputation sur l'impôt sur les bénéfices).
library;

import '../referentiels/versions_datees.dart';

typedef CpdFiche = Map<String, Object?>;

/// Le compte de l'AIB retenu par la clinique : une DETTE envers l'État, reversée le 10 du mois suivant.
const String cpdCompteAibRetenu = '4478';

/// Le compte de l'AIB subi sur ses propres factures : une CRÉANCE sur l'État.
const String cpdCompteAibSubi = '4492';

/// Le compte d'imputation de l'acompte sur l'impôt sur les bénéfices.
const String cpdCompteAibImputation = '891';

/// Les statuts d'une version : arrêtée par la Direction, ou non arrêtée (à valider).
const String cpdStatutArrete = 'arrete';
const String cpdStatutNonArrete = 'non_arrete';

const List<(String, String)> cpdStatutsAib = [
  (cpdStatutArrete, 'Arrêté'),
  (cpdStatutNonArrete, 'Non arrêté (à valider)'),
];

/// Une version est-elle arrêtée ? Le statut est lu sur la fiche (`arrete: true`, ou `statutArret: 'arrete'`).
bool cpdEstArretee(CpdFiche f) => f['arrete'] == true || '${f['statutArret'] ?? ''}' == cpdStatutArrete;

String _jour(Object? d) => d == null || '$d'.isEmpty ? '' : isoJour(d);

bool _actif(CpdFiche f) => '${f['statut'] ?? 'actif'}' == 'actif';

num? _taux(Object? v) => v is num ? v : num.tryParse('$v'.replaceAll(',', '.'));

/// Ce que le moteur répond pour une catégorie à une date : le taux (nul si rien ne s'applique), la version retenue, et toujours un MOTIF.
class CpdTauxAib {
  const CpdTauxAib({required this.taux, required this.motif, this.version, this.enAttente = const []});

  /// Le taux en vigueur (en %), `null` si aucune version arrêtée ne couvre la date.
  final num? taux;
  final String motif;

  /// La version arrêtée qui s'applique (`null` si aucune).
  final CpdFiche? version;

  /// Les versions non arrêtées de la catégorie : offertes à la Direction, jamais appliquées.
  final List<CpdFiche> enAttente;
}

String _pct(num t) => t == t.roundToDouble() ? '${t.toInt()}' : '$t'.replaceAll('.', ',');

String _dateFr(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';

/// Le taux de la catégorie [code] en vigueur à [date] : la version ARRÊTÉE et ACTIVE de plus grande date d'effet qui ne dépasse pas [date]. Une
/// version archivée ou non arrêtée est ignorée ; une version arrêtée sans date d'effet vaut « depuis l'adoption » (la plus ancienne).
CpdTauxAib cpdTauxAibALaDate(Iterable<CpdFiche> fiches, String code, DateTime date) {
  final jour = isoJour(date);
  final deLaCategorie = [for (final f in fiches) if (_actif(f) && '${f['code']}' == code) f];
  final enAttente = [for (final f in deLaCategorie) if (!cpdEstArretee(f)) f];
  final arretees = [for (final f in deLaCategorie) if (cpdEstArretee(f) && _taux(f['taux']) != null) f];
  final couvrantes = [
    for (final f in arretees)
      if (_jour(f['dateEffet']).isEmpty || _jour(f['dateEffet']).compareTo(jour) <= 0) f
  ]..sort((a, b) => _jour(a['dateEffet']).compareTo(_jour(b['dateEffet'])));
  if (couvrantes.isNotEmpty) {
    final v = couvrantes.last;
    final t = _taux(v['taux'])!;
    final effet = _jour(v['dateEffet']);
    return CpdTauxAib(
        taux: t,
        version: v,
        enAttente: enAttente,
        motif: 'Taux de ${_pct(t)} % arrêté${effet.isEmpty ? '' : ', en vigueur depuis le ${_dateFr(effet)}'}.');
  }
  if (arretees.isNotEmpty) {
    final premiere = ([...arretees]..sort((a, b) => _jour(a['dateEffet']).compareTo(_jour(b['dateEffet'])))).first;
    return CpdTauxAib(
        taux: null,
        enAttente: enAttente,
        motif: 'Aucun taux arrêté avant le ${_dateFr(_jour(premiere['dateEffet']))} : la première version prend effet à cette date.');
  }
  if (enAttente.isNotEmpty) {
    return CpdTauxAib(
        taux: null,
        enAttente: enAttente,
        motif: 'Aucune version arrêtée : ${enAttente.map((f) => '${_pct(_taux(f['taux']) ?? 0)} %').join(' et ')} figure(nt) au barème mais n\'est pas arrêté — à valider par la Direction.');
  }
  return const CpdTauxAib(taux: null, motif: 'Aucune version de cette catégorie au barème.');
}

/// Les codes de catégorie du barème, dans l'ordre d'apparition (versions archivées comprises : une catégorie ne disparaît pas avec sa dernière version).
List<String> cpdCodesAib(Iterable<CpdFiche> fiches) {
  final out = <String>[];
  for (final f in fiches) {
    final c = '${f['code'] ?? ''}';
    if (c.isNotEmpty && !out.contains(c)) out.add(c);
  }
  return out;
}

/// Le barème tel qu'il s'applique à [date] : une ligne par catégorie ACTIVE (code, libellé, réponse du moteur).
List<({String code, String libelle, CpdTauxAib reponse})> cpdBaremeEnVigueur(Iterable<CpdFiche> fiches, DateTime date) {
  final actives = [for (final f in fiches) if (_actif(f)) f];
  return [
    for (final code in cpdCodesAib(actives))
      (
        code: code,
        libelle: '${actives.firstWhere((f) => '${f['code']}' == code)['categorie'] ?? code}',
        reponse: cpdTauxAibALaDate(actives, code, date),
      )
  ];
}

/// Le montant de l'acompte retenu sur [base] au [taux] (en %), arrondi au franc : `base * taux / 100`.
int cpdMontantAib(num base, num taux) => (base * taux / 100).round();

/// Le contrôle d'une saisie AVANT écriture : un message de refus nommé, ou `null`. [record] est la version modifiée (`null` : nouvelle version),
/// [existantes] les versions du barème.
///
/// * le code, la catégorie et le taux (0 à 100) sont obligatoires ;
/// * une version ARRÊTÉE exige sa date d'effet, la date de l'arrêt et le décideur ;
/// * une version arrêtée ne se corrige JAMAIS sur place (taux, date d'effet, code, catégorie, comptes, statut) : une correction ajoute une version à
///   une date d'effet postérieure ; seul le motif s'édite ;
/// * deux versions d'une même catégorie ne partagent pas la même date d'effet (la seconde serait ambiguë) ; la date de l'arrêt peut précéder la date
///   d'effet (décision avant prise d'effet), jamais être postérieure à aujourd'hui.
String? cpdControlerVersionAib(Map<String, Object?> saisie, CpdFiche? record, Iterable<CpdFiche> existantes, DateTime aujourdhui) {
  final code = '${saisie['code'] ?? ''}'.trim();
  final taux = _taux(saisie['taux']);
  if (code.isEmpty) return 'Le code de la catégorie est obligatoire.';
  if ('${saisie['categorie'] ?? ''}'.trim().isEmpty) return 'Le libellé de la catégorie est obligatoire.';
  if (taux == null || taux < 0 || taux > 100) return 'Le taux doit être compris entre 0 et 100 %.';
  final arrete = '${saisie['statutArret'] ?? ''}' == cpdStatutArrete;
  final effet = _jour(saisie['dateEffet']);
  if (arrete) {
    if (effet.isEmpty) return 'Une version arrêtée exige sa date d\'effet.';
    if (_jour(saisie['dateArret']).isEmpty) return 'Une version arrêtée exige la date de l\'arrêt.';
    if ('${saisie['decideurArret'] ?? ''}'.trim().isEmpty) return 'Une version arrêtée exige le nom du décideur de l\'arrêt.';
    if (_jour(saisie['dateArret']).compareTo(isoJour(aujourdhui)) > 0) return 'La date de l\'arrêt ne peut pas être postérieure à aujourd\'hui.';
  }
  if (record != null && cpdEstArretee(record)) {
    bool change(String k, [Object? Function(Object?)? norm]) {
      final f = norm ?? (Object? v) => '${v ?? ''}'.trim();
      return f(saisie[k]) != f(record[k]);
    }

    final taux0 = _taux(record['taux']);
    final modifie = change('code') ||
        change('categorie') ||
        taux != taux0 ||
        _jour(saisie['dateEffet']) != _jour(record['dateEffet']) ||
        !arrete ||
        change('compteRetenu') ||
        change('compteSubi') ||
        change('compteImputation') ||
        change('dateArret', (v) => _jour(v)) ||
        change('decideurArret');
    if (modifie) {
      return 'Une version arrêtée ne se corrige pas sur place : ajouter une nouvelle version à une date d\'effet postérieure (le taux d\'une date passée reste celui qui était en vigueur).';
    }
  }
  if (effet.isNotEmpty) {
    for (final f in existantes) {
      if (!_actif(f) || (record != null && f['id'] == record['id'])) continue;
      if ('${f['code']}' == code && _jour(f['dateEffet']) == effet) {
        return 'Une version de la catégorie « $code » prend déjà effet le ${_dateFr(effet)} : choisir une autre date d\'effet.';
      }
    }
  }
  return null;
}
