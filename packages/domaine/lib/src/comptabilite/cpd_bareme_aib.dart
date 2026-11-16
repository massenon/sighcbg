/// LE BARÈME DE L'AIB PAR SITUATION DE L'ACHETEUR (M12, `m12-aib`) : l'acompte sur impôt assis sur les bénéfices que la clinique retient à la source.
///
/// Le modèle est celui de la maquette de la Direction (lot A1, 09/11/2026) : DEUX collections du magasin. `situationsAib` dit les situations (le code, le
/// libellé, le déclencheur qui la choisit d'office : IFU saisi, IFU absent, ou choix à la main) ; `baremeAib` porte une fiche par VERSION et par SITUATION
/// (taux, date d'effet, source, motif). Aucun taux, aucune date, aucun code de situation n'est écrit dans le moteur : tout se lit au magasin.
///
/// Le barème est versionné par DATE D'EFFET, comme la grille des primes. Une correction n'écrase jamais une version arrêtée : elle AJOUTE une version à une
/// date d'effet postérieure, et le taux d'une date passée reste celui qui était en vigueur ce jour-là (un acompte déjà retenu ne se réécrit pas). Une
/// version s'archive, elle ne se supprime pas (RG-14). La fin d'une version est CALCULÉE (la veille de la version arrêtée suivante) : la stocker obligerait
/// à rouvrir la précédente à chaque retrait.
///
/// Une version est ARRÊTÉE (décidée par la Direction, avec la date et le décideur de l'arrêt) ou NON ARRÊTÉE (présente, marquée à valider). Seule une
/// version arrêtée s'applique : un taux non arrêté ne sert jamais à retenir quoi que ce soit, il est offert à la Direction. Sans version arrêtée
/// en vigueur à la date demandée, le moteur rend un taux absent (jamais zéro), le code nommé `AIB_SANS_BAREME` ET le motif.
///
/// Les comptes ne sont PAS portés par les fiches du barème (décision de la Direction, 09/11/2026 : « on va le corriger dans les Paramètres ») : l'unique source est la
/// rubrique `comptes` de `parametresAib` (`cpaComptesALaDate`). Les constantes ci-dessous ne sont que la GRAINE qui amorce cette rubrique : 4478 (AIB retenu, dette envers
/// l'État), 4492 (AIB subi, créance sur l'État), 891 (imputation sur l'impôt sur les bénéfices) — à confirmer par l'expert-comptable.
library;

import '../referentiels/versions_datees.dart';

typedef CpdFiche = Map<String, Object?>;

/// Le compte de l'AIB retenu par la clinique : une DETTE envers l'État, reversée le 10 du mois suivant.
const String cpdCompteAibRetenu = '4478';

/// Le compte de l'AIB subi sur ses propres factures : une CRÉANCE sur l'État.
const String cpdCompteAibSubi = '4492';

/// Le compte d'imputation de l'acompte sur l'impôt sur les bénéfices.
const String cpdCompteAibImputation = '891';

/// Le code du refus nommé quand aucune version arrêtée ne couvre la situation à la date (un tiret n'est pas un zéro).
const String cpdCodeAibSansBareme = 'AIB_SANS_BAREME';

/// Les statuts d'une version : arrêtée par la Direction, ou non arrêtée (à valider).
const String cpdStatutArrete = 'arrete';
const String cpdStatutNonArrete = 'non_arrete';

const List<(String, String)> cpdStatutsAib = [
  (cpdStatutArrete, 'Arrêté'),
  (cpdStatutNonArrete, 'Non arrêté (à valider)'),
];

/// Ce qui choisit une situation d'office (`declencheur` d'une fiche de `situationsAib`).
const String cpdDeclencheurIfuRenseigne = 'ifu_renseigne';
const String cpdDeclencheurIfuAbsent = 'ifu_absent';
const String cpdDeclencheurChoix = 'choix';

const List<(String, String)> cpdDeclencheursAib = [
  (cpdDeclencheurIfuRenseigne, 'Un IFU de 13 chiffres est saisi'),
  (cpdDeclencheurIfuAbsent, 'Aucun IFU saisi'),
  (cpdDeclencheurChoix, 'Choisie à la main'),
];

/// Une version est-elle arrêtée ? Le statut est lu sur la fiche (`arrete: true`, ou `statutArret: 'arrete'`).
bool cpdEstArretee(CpdFiche f) => f['arrete'] == true || '${f['statutArret'] ?? ''}' == cpdStatutArrete;

String _jour(Object? d) => d == null || '$d'.isEmpty ? '' : isoJour(d);

bool _actif(CpdFiche f) => '${f['statut'] ?? 'actif'}' == 'actif';

num? _taux(Object? v) => v is num ? v : num.tryParse('$v'.replaceAll(',', '.'));

/// Ce que le moteur répond pour une situation à une date : le taux (absent si rien ne s'applique), la version retenue, et toujours un MOTIF.
class CpdTauxAib {
  const CpdTauxAib({required this.taux, required this.motif, this.version, this.enAttente = const [], this.code, this.rang});

  /// Le taux en vigueur (en %), `null` si aucune version arrêtée ne couvre la date.
  final num? taux;
  final String motif;

  /// La version arrêtée qui s'applique (`null` si aucune).
  final CpdFiche? version;

  /// Les versions non arrêtées de la situation : offertes à la Direction, jamais appliquées.
  final List<CpdFiche> enAttente;

  /// `AIB_SANS_BAREME` quand [taux] est absent, `null` sinon.
  final String? code;

  /// Le rang (à partir de 1) de la version retenue parmi les versions actives de la situation, par date d'effet.
  final int? rang;

  bool get ok => taux != null;
}

String _pct(num t) => t == t.roundToDouble() ? '${t.toInt()}' : '$t'.replaceAll('.', ',');

String _dateFr(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';

/// Les situations ACTIVES, dans l'ordre déclaré (puis par code).
List<CpdFiche> cpdSituationsActives(Iterable<CpdFiche> situations) {
  final out = [for (final s in situations) if (_actif(s) && '${s['code'] ?? ''}'.isNotEmpty) s];
  int ordre(CpdFiche s) => (s['ordre'] as num?)?.toInt() ?? 99;
  out.sort((a, b) {
    final o = ordre(a).compareTo(ordre(b));
    return o != 0 ? o : '${a['code']}'.compareTo('${b['code']}');
  });
  return out;
}

/// Les versions ACTIVES d'une situation, par date d'effet croissante (une version sans date d'effet passe en tête).
List<CpdFiche> cpdVersionsAibDe(Iterable<CpdFiche> versions, String situation) {
  final out = [for (final f in versions) if (_actif(f) && '${f['situation']}' == situation) f];
  out.sort((a, b) => _jour(a['dateEffet']).compareTo(_jour(b['dateEffet'])));
  return out;
}

/// La veille d'une date ISO.
String cpdVeille(String iso) => isoJour(DateTime.parse('${iso}T12:00:00').subtract(const Duration(days: 1)));

/// La FIN d'une version arrêtée : la veille de la version arrêtée suivante de la même situation, ou la date de fin écrite sur la fiche (version
/// héritée), ou rien (« en cours »). Une version non arrêtée n'a pas de fin : elle ne ferme rien.
String? cpdFinDeVersion(Iterable<CpdFiche> versions, CpdFiche v) {
  final explicite = _jour(v['dateFin']);
  final arretees = [for (final x in cpdVersionsAibDe(versions, '${v['situation']}')) if (cpdEstArretee(x) && _jour(x['dateEffet']).isNotEmpty) x];
  final effet = _jour(v['dateEffet']);
  final suivante = [for (final x in arretees) if (effet.isNotEmpty && _jour(x['dateEffet']).compareTo(effet) > 0) x];
  if (suivante.isNotEmpty) return cpdVeille(_jour(suivante.first['dateEffet']));
  return explicite.isEmpty ? null : explicite;
}

/// Le taux de la situation [situation] en vigueur à [date] : la version ARRÊTÉE et ACTIVE de plus grande date d'effet qui ne dépasse pas [date]. Une
/// version archivée ou non arrêtée est ignorée ; une version arrêtée sans date d'effet vaut « depuis l'adoption » (la plus ancienne). Quand [situations]
/// est fournie, une situation absente ou archivée est refusée en le disant.
CpdTauxAib cpdTauxAibALaDate(Iterable<CpdFiche> versions, String situation, DateTime date, {Iterable<CpdFiche>? situations}) {
  final jour = isoJour(date);
  CpdFiche? sit;
  if (situations != null) {
    final trouvees = [for (final s in situations) if (_actif(s) && '${s['code']}' == situation) s];
    if (trouvees.isEmpty) {
      return CpdTauxAib(
          taux: null,
          code: cpdCodeAibSansBareme,
          motif: 'La situation « $situation » n\'est pas active au barème de l\'AIB : aucun taux ne peut être rendu (un tiret n\'est pas un zéro).');
    }
    sit = trouvees.first;
  }
  final libelle = sit == null ? situation : '${sit['libelle'] ?? situation}';
  final deLaSituation = cpdVersionsAibDe(versions, situation);
  final enAttente = [for (final f in deLaSituation) if (!cpdEstArretee(f)) f];
  final arretees = [for (final f in deLaSituation) if (cpdEstArretee(f) && _taux(f['taux']) != null) f];
  final couvrantes = [
    for (final f in arretees)
      if (_jour(f['dateEffet']).isEmpty || _jour(f['dateEffet']).compareTo(jour) <= 0) f
  ];
  if (couvrantes.isNotEmpty) {
    final v = couvrantes.last;
    final fin = _jour(v['dateFin']);
    if (fin.isEmpty || fin.compareTo(jour) >= 0) {
      final t = _taux(v['taux'])!;
      final effet = _jour(v['dateEffet']);
      return CpdTauxAib(
          taux: t,
          version: v,
          enAttente: enAttente,
          rang: deLaSituation.indexOf(v) + 1,
          motif: 'Taux de ${_pct(t)} % arrêté${effet.isEmpty ? '' : ', en vigueur depuis le ${_dateFr(effet)}'}.');
    }
    return CpdTauxAib(
        taux: null,
        enAttente: enAttente,
        code: cpdCodeAibSansBareme,
        motif: 'Aucune version arrêtée ne couvre la situation « $libelle » au ${_dateFr(jour)} : la dernière a pris fin le ${_dateFr(fin)}.');
  }
  if (arretees.isNotEmpty) {
    final premiere = ([...arretees]..sort((a, b) => _jour(a['dateEffet']).compareTo(_jour(b['dateEffet'])))).first;
    return CpdTauxAib(
        taux: null,
        enAttente: enAttente,
        code: cpdCodeAibSansBareme,
        motif: 'Aucun taux arrêté avant le ${_dateFr(_jour(premiere['dateEffet']))} : la première version prend effet à cette date.');
  }
  if (enAttente.isNotEmpty) {
    return CpdTauxAib(
        taux: null,
        enAttente: enAttente,
        code: cpdCodeAibSansBareme,
        motif: 'Aucune version arrêtée : ${enAttente.map((f) => '${_pct(_taux(f['taux']) ?? 0)} %').join(' et ')} figure(nt) au barème mais n\'est pas arrêté — à valider par la Direction.');
  }
  return CpdTauxAib(taux: null, code: cpdCodeAibSansBareme, motif: 'Aucune version de la situation « $libelle » au barème.');
}

/// Le barème tel qu'il s'applique à [date] : une ligne par situation ACTIVE (code, libellé, réponse du moteur).
List<({String code, String libelle, CpdTauxAib reponse})> cpdBaremeEnVigueur(Iterable<CpdFiche> situations, Iterable<CpdFiche> versions, DateTime date) => [
      for (final s in cpdSituationsActives(situations))
        (
          code: '${s['code']}',
          libelle: '${s['libelle'] ?? s['code']}',
          reponse: cpdTauxAibALaDate(versions, '${s['code']}', date, situations: situations),
        )
    ];

/// Ce que la situation d'un acheteur donne : la situation retenue, la PRÉSOMPTION (un IFU saisi est présumé actif : le poste ne peut pas interroger la
/// DGI, et le dit), ou le refus nommé.
class CpdSituationAcheteur {
  const CpdSituationAcheteur({this.situation, this.presomption = false, this.avertissement, this.refusCode, this.refusMotif});
  final CpdFiche? situation;
  final bool presomption;
  final String? avertissement;
  final String? refusCode;
  final String? refusMotif;
  bool get ok => situation != null;
}

/// La situation qui se choisit d'OFFICE d'après l'IFU de l'acheteur : vide, la situation « IFU absent » ; [longueurIfu] chiffres (espaces tolérés), la
/// situation « IFU saisi », présumée active ; autre chose, un refus nommé `IFU_INVALIDE`.
///
/// Le BRANCHEMENT est celui des Paramètres (`parametresAib`, rubrique `branchement_ifu`) : [situationRenseigne] et [situationAbsente] nomment les situations
/// du barème retenues ; absentes (ou non actives au barème), la situation se retrouve par son déclencheur (`ifu_renseigne` / `ifu_absent`). [longueurIfu]
/// vient aussi des Paramètres (13 par défaut de graine : l'appelant du poste le lit toujours à la collection).
CpdSituationAcheteur cpdSituationPourAcheteur(Iterable<CpdFiche> situations,
    {Object? ifu, int longueurIfu = 13, String? situationRenseigne, String? situationAbsente}) {
  final nu = '${ifu ?? ''}'.replaceAll(RegExp(r'[\s  ]'), '');
  final String declencheur;
  if (nu.isEmpty) {
    declencheur = cpdDeclencheurIfuAbsent;
  } else if (RegExp('^\\d{$longueurIfu}\$').hasMatch(nu)) {
    declencheur = cpdDeclencheurIfuRenseigne;
  } else {
    return CpdSituationAcheteur(refusCode: 'IFU_INVALIDE', refusMotif: 'L\'IFU de l\'acheteur (« $nu ») doit comporter exactement $longueurIfu chiffres.');
  }
  final actives = cpdSituationsActives(situations);
  final voulue = declencheur == cpdDeclencheurIfuAbsent ? situationAbsente : situationRenseigne;
  var trouvees = [for (final s in actives) if (voulue != null && voulue.isNotEmpty && '${s['code']}' == voulue) s];
  if (trouvees.isEmpty) trouvees = [for (final s in actives) if ('${s['declencheur']}' == declencheur) s];
  if (trouvees.isEmpty) {
    return CpdSituationAcheteur(
        refusCode: cpdCodeAibSansBareme,
        refusMotif: 'Aucune situation active du barème de l\'AIB ne se choisit d\'office quand ${declencheur == cpdDeclencheurIfuAbsent ? 'aucun IFU n\'est saisi' : 'un IFU est saisi'}.');
  }
  final presume = declencheur == cpdDeclencheurIfuRenseigne;
  return CpdSituationAcheteur(
      situation: trouvees.first,
      presomption: presume,
      avertissement: presume ? 'IFU présumé actif : l\'activité de l\'IFU n\'est pas vérifiée auprès de la DGI.' : null);
}

/// Le montant de l'acompte retenu sur [base] au [taux] (en %), arrondi au franc : `base * taux / 100`.
int cpdMontantAib(num base, num taux) => (base * taux / 100).round();

/// Le contrôle d'une saisie AVANT écriture : un message de refus nommé, ou `null`. [record] est la version modifiée (`null` : nouvelle version),
/// [existantes] les versions du barème, [situations] les situations.
///
/// * la situation (qui doit exister et être active), le taux (entier de 0 à 100 : le poste calcule en montants entiers), la SOURCE du taux et le motif
///   de la version sont obligatoires : on ne retient pas un taux dont on ne peut pas citer le texte ;
/// * une version ARRÊTÉE exige sa date d'effet, la date de l'arrêt et le décideur ;
/// * une version arrêtée ne se corrige JAMAIS sur place (taux, date d'effet, situation, comptes, statut) : une correction ajoute une version à une date
///   d'effet postérieure ; seuls le motif et la source s'éditent ;
/// * deux versions d'une même situation ne partagent pas la même date d'effet (la seconde serait ambiguë) ; une version arrêtée ne s'insère pas avant la
///   plus récente version arrêtée (elle masquerait l'historique) ; la date de l'arrêt peut précéder la date d'effet (décision avant prise d'effet),
///   jamais être postérieure à aujourd'hui.
String? cpdControlerVersionAib(Map<String, Object?> saisie, CpdFiche? record, Iterable<CpdFiche> existantes, DateTime aujourdhui,
    {Iterable<CpdFiche>? situations}) {
  final situation = '${saisie['situation'] ?? ''}'.trim();
  final taux = _taux(saisie['taux']);
  if (situation.isEmpty) return 'AIB_SITUATION_INCONNUE : la situation de l\'acheteur est obligatoire.';
  if (situations != null && !cpdSituationsActives(situations).any((s) => '${s['code']}' == situation)) {
    return 'AIB_SITUATION_INCONNUE : la situation « $situation » n\'existe pas au barème de l\'AIB.';
  }
  if (taux == null || taux < 0 || taux > 100 || taux != taux.roundToDouble()) {
    return 'AIB_TAUX_INVALIDE : le taux (« ${saisie['taux'] ?? ''} ») doit être un pourcentage entier de 0 à 100.';
  }
  if ('${saisie['source'] ?? ''}'.trim().isEmpty) return 'AIB_SOURCE_ABSENTE : aucune source n\'est dite pour ce taux — on ne retient pas un taux dont on ne cite pas le texte.';
  if ('${saisie['motif'] ?? ''}'.trim().isEmpty) return 'AIB_MOTIF_ABSENT : le motif de cette version est obligatoire.';
  final arrete = '${saisie['statutArret'] ?? ''}' == cpdStatutArrete;
  final effet = _jour(saisie['dateEffet']);
  if (arrete) {
    if (effet.isEmpty) return 'AIB_DATE_INVALIDE : une version arrêtée exige sa date d\'effet.';
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
    final modifie = change('situation') ||
        taux != taux0 ||
        _jour(saisie['dateEffet']) != _jour(record['dateEffet']) ||
        !arrete ||
        change('dateArret', (v) => _jour(v)) ||
        change('decideurArret');
    if (modifie) {
      return 'AIB_VERSION_FIGEE : une version arrêtée ne se corrige pas sur place — ajouter une nouvelle version à une date d\'effet postérieure (le taux d\'une date passée reste celui qui était en vigueur).';
    }
  }
  if (effet.isNotEmpty) {
    for (final f in existantes) {
      if (!_actif(f) || (record != null && f['id'] == record['id'])) continue;
      if ('${f['situation']}' == situation && _jour(f['dateEffet']) == effet) {
        return 'AIB_DATE_EXISTANTE : une version de la situation « $situation » prend déjà effet le ${_dateFr(effet)} — une version ne se réécrit pas, choisir une autre date d\'effet.';
      }
    }
    if (arrete && record == null) {
      final plusRecente = [
        for (final f in existantes)
          if (_actif(f) && '${f['situation']}' == situation && cpdEstArretee(f) && _jour(f['dateEffet']).isNotEmpty) _jour(f['dateEffet'])
      ]..sort();
      if (plusRecente.isNotEmpty && plusRecente.last.compareTo(effet) > 0) {
        return 'AIB_DATE_ANTERIEURE : la version arrêtée la plus récente de cette situation commence le ${_dateFr(plusRecente.last)} — une version insérée avant elle masquerait l\'historique.';
      }
    }
  }
  return null;
}
