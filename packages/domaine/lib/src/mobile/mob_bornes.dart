// LES BORNES DE PLAUSIBILITÉ DE SAISIE DU TÉLÉPHONE sont des RÉGLAGES (consigne de la Direction du 18/11/2026 : « plus de valeur en dur »).
//
// Une borne de plausibilité dit seulement « au-delà, c'est une faute de frappe » (une température de 450, un âge de 1 200 ans) : ce n'est NI un seuil clinique de décision NI une
// donnée de santé. C'est donc le SEUL contenu de clinique que le téléphone reçoit (RG-13) : chaque borne est un paramètre déclaré `mobile` dans la liste blanche ci-dessous,
// famille `mobile` (non réservée), jamais sensible, numérique et BORNÉ (une enveloppe `min`/`max` que la clinique ne peut pas franchir, pour qu'un réglage ne désactive pas le
// contrôle). La liste blanche est EXPLICITE : une borne ajoutée ici part au téléphone, une autre non ; un test le rapproche de ce que le registre déclare.
//
// Le téléphone lit ces réglages par le canal que la mère lui livre déjà (`Pont.diffuser`) : la mère publie les versions de la liste blanche, le téléphone les garde dans sa base
// chiffrée et en tire une [MobBornes]. SANS réglage reçu (jamais synchronisé, hors ligne dès l'appairage), la valeur d'attente de la définition s'applique : le comportement d'avant.
//
// Dart pur, aucune horloge : la date est toujours fournie.
library;

import '../parametres/parametres_clinique.dart' show seuilNombreA, seuilNombreSeme;
import '../parametres/parametres.dart' show DefinitionParametre, TypeParametre;

/// La famille des réglages du téléphone (non réservée à RG-13 : ce ne sont que des bornes de saisie).
const String mobFamilleBornes = 'mobile';

/// Une borne de saisie : un champ d'un écran du téléphone, ses deux bornes d'attente, et l'enveloppe qu'aucun réglage ne franchit.
class MobBorneDef {
  const MobBorneDef(this.ecran, this.champ, this.libelle, this.unite, this.min, this.max, this.plancher, this.plafond);

  /// L'écran du téléphone (`constantes`, `prescription`, `cpn`, `cpon`, `surveillance`).
  final String ecran;
  final String champ;

  /// Le libellé de la mesure (« La température »), tel qu'il s'écrit dans le refus nommé.
  final String libelle;
  final String unite;

  /// Les bornes d'ATTENTE (le comportement d'avant) : la plus basse et la plus haute valeur acceptées.
  final num min, max;

  /// L'enveloppe : aucune borne réglée ne sort de [plancher]..[plafond].
  final num plancher, plafond;

  String get cleMin => 'mobile.saisie.$ecran.${champ}Min';
  String get cleMax => 'mobile.saisie.$ecran.${champ}Max';
}

/// La clé de l'âge maximal déclaré à la réception du téléphone (la borne basse, 0, est structurelle : un âge n'est pas négatif).
const String mobCleAgeMax = 'mobile.saisie.reception.ageDeclareMaxAns';

/// LA LISTE BLANCHE. Chaque ligne : écran, champ, libellé, unité, bornes d'attente, enveloppe (plancher, plafond).
const List<MobBorneDef> mobBornesDefs = [
  // Écran « Constantes »
  MobBorneDef('constantes', 'temperature', 'La température', '°C', 30, 45, 20, 50),
  MobBorneDef('constantes', 'sys', 'La systolique', 'mmHg', 50, 260, 30, 350),
  MobBorneDef('constantes', 'dia', 'La diastolique', 'mmHg', 30, 160, 20, 250),
  MobBorneDef('constantes', 'pouls', 'Le pouls', '/min', 20, 250, 10, 350),
  MobBorneDef('constantes', 'fr', 'La FR', '/min', 5, 80, 1, 150),
  MobBorneDef('constantes', 'spo2', 'La SpO₂', '%', 50, 100, 0, 100),
  MobBorneDef('constantes', 'poids', 'Le poids', 'kg', 0.5, 300, 0, 700),
  // Écran « Prescription »
  MobBorneDef('prescription', 'duree', 'La durée', 'jours', 1, 90, 1, 365),
  // Visite prénatale
  MobBorneDef('cpn', 'sa', 'Le terme', 'SA', 4, 45, 1, 60),
  MobBorneDef('cpn', 'poids', 'Le poids', 'kg', 30, 200, 1, 400),
  MobBorneDef('cpn', 'sys', 'La systolique', 'mmHg', 60, 260, 30, 350),
  MobBorneDef('cpn', 'dia', 'La diastolique', 'mmHg', 30, 160, 20, 250),
  MobBorneDef('cpn', 'bcf', 'Le BCF', '/min', 60, 220, 30, 300),
  // Visite post-natale
  MobBorneDef('cpon', 't', 'La température', '°C', 34, 43, 20, 50),
  MobBorneDef('cpon', 'pb', 'Le poids du bébé', 'g', 1000, 6000, 300, 10000),
  // Surveillance mère-bébé
  MobBorneDef('surveillance', 'mpouls', 'Le pouls', '/min', 30, 220, 10, 350),
  MobBorneDef('surveillance', 'bfr', 'La FR du bébé', '/min', 10, 100, 1, 150),
  MobBorneDef('surveillance', 'bt', 'La T° du bébé', '°C', 34, 41, 20, 50),
];

/// L'enveloppe de l'âge déclaré maximal (ans) et sa valeur d'attente (la borne basse, 0, est structurelle).
const int _ageAttente = 120, _agePlancher = 100, _agePlafond = 150;

String _nombreEcrit(num n) => n == n.truncate() ? '${n.truncate()}' : '$n';

/// Les définitions de la liste blanche, au registre des paramètres : `mobile: true`, famille `mobile`, valeur d'attente = le comportement d'avant, enveloppe = `min`/`max`.
List<DefinitionParametre> mobDefinitionsBornes() {
  const source = 'Valeur d\'attente reprise du code (borne de plausibilité de saisie du téléphone, littéral d\'avant le lot « valeurs en dur — famille C » du 18/11/2026) : '
      'à confirmer par les professionnels de la clinique';
  DefinitionParametre un(String cle, String libelle, String aide, num defaut, num plancher, num plafond) => DefinitionParametre(
        cle: cle,
        famille: mobFamilleBornes,
        type: TypeParametre.nombre,
        defaut: defaut,
        min: plancher.toInt(),
        max: plafond.toInt(),
        mobile: true,
        libelle: libelle,
        aide: aide,
        source: source,
        branche: true,
        appliquePar: 'Téléphone (saisie), livré par la mère à la liste blanche des réglages mobiles',
      );
  return [
    for (final d in mobBornesDefs) ...[
      un(d.cleMin, '${d.libelle} : valeur la plus basse acceptée (${d.unite})',
          'Borne de PLAUSIBILITÉ de la saisie au téléphone (écran « ${d.ecran} ») : en dessous, la valeur est refusée comme improbable, en la nommant. Ce n\'est pas un seuil clinique de décision. '
              'Entre ${_nombreEcrit(d.plancher)} et ${_nombreEcrit(d.plafond)} ${d.unite}, strictement inférieure à la borne haute ; sinon les deux bornes d\'attente (${_nombreEcrit(d.min)} et ${_nombreEcrit(d.max)}) s\'appliquent ensemble. '
              'Livré au téléphone par la mère (le seul réglage de clinique que le téléphone reçoit).',
          d.min, d.plancher, d.plafond),
      un(d.cleMax, '${d.libelle} : valeur la plus haute acceptée (${d.unite})',
          'Borne de PLAUSIBILITÉ de la saisie au téléphone (écran « ${d.ecran} ») : au-dessus, la valeur est refusée comme improbable, en la nommant. Voir la borne basse ; entre ${_nombreEcrit(d.plancher)} et ${_nombreEcrit(d.plafond)} ${d.unite}.',
          d.max, d.plancher, d.plafond),
    ],
    un(mobCleAgeMax, 'Réception du téléphone : âge déclaré le plus élevé accepté (ans)',
        'Borne de PLAUSIBILITÉ de l\'âge déclaré à la réception du téléphone : au-delà, c\'est une faute de frappe. Entier de $_agePlancher à $_agePlafond ; hors bornes, la valeur d\'attente de $_ageAttente ans s\'applique.',
        _ageAttente, _agePlancher, _agePlafond),
  ];
}

/// Les bornes de saisie EN VIGUEUR sur le téléphone. [attente] : aucun réglage reçu, les valeurs d'attente (le comportement d'avant).
class MobBornes {
  const MobBornes._(this._fiches, this._date);

  /// Aucun réglage reçu : les valeurs d'attente de la liste blanche.
  static const MobBornes attente = MobBornes._(null, '');

  /// Les bornes que les fiches de versions [fichesParametres] donnent à [date] (AAAA-MM-JJ) : les versions datées qui s'appliquent, sinon l'attente.
  factory MobBornes.depuisFiches(Iterable<Map<String, Object?>> fichesParametres, String date) => MobBornes._(List.of(fichesParametres), date);

  final List<Map<String, Object?>>? _fiches;
  final String _date;

  /// Les deux bornes du champ [champ] de l'écran [ecran]. Une paire incohérente (basse >= haute, ou hors enveloppe) retombe sur les deux valeurs d'attente ENSEMBLE :
  /// corriger une borne seule ferait un intervalle vide ou renversé.
  ({num min, num max}) intervalle(String ecran, String champ) {
    final d = mobBornesDefs.firstWhere((x) => x.ecran == ecran && x.champ == champ, orElse: () => throw ArgumentError('borne inconnue : $ecran.$champ'));
    final f = _fiches;
    if (f == null) return (min: seuilNombreSeme(d.cleMin), max: seuilNombreSeme(d.cleMax));
    final a = seuilNombreA(f, d.cleMin, _date), b = seuilNombreA(f, d.cleMax, _date);
    if (a < b) return (min: a, max: b);
    return (min: seuilNombreSeme(d.cleMin), max: seuilNombreSeme(d.cleMax));
  }

  /// L'âge déclaré le plus élevé accepté (ans).
  int get ageMaxAns {
    final f = _fiches;
    if (f == null) return seuilNombreSeme(mobCleAgeMax).toInt();
    return seuilNombreA(f, mobCleAgeMax, _date).toInt();
  }

  /// Le réglage en vigueur est-il celui d'attente (aucun réglage reçu) ? Pour les écrans et les tests.
  bool get estAttente => _fiches == null;
}
