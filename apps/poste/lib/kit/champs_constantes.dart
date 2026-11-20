import 'package:sigh_domaine/sigh_domaine.dart';

import 'formulaire.dart';

/// LES CHAMPS DE CONSTANTES, DÉFINIS UNE SEULE FOIS (lot B, 13/11/2026) : la tension et la diurèse se saisissent de la MÊME façon à l'accueil (`m1-constantes`), sur la feuille
/// de température et à la feuille d'observation. Trois définitions écrites trois fois auraient fini par diverger — c'est exactement ce qui faisait saisir des litres ici et des
/// millilitres là, un texte « 12/8 » ici et deux nombres là. Les noms de champs (`tensionSys`, `tensionDia`, `diurese`), les unités (cmHg, mL) et les bornes viennent du domaine
/// (`hos_constantes.dart`) : proposition à valider par un soignant, reprise de l'accueil.
String? Function(Object?, Map<String, Object?>) _borne(num min, num max, {bool entier = false}) => (v, _) {
      final n = num.tryParse('$v'.replaceAll(',', '.'));
      if (n == null || n < min || n > max) return 'Valeur comprise entre $min et $max.';
      if (entier && n != n.truncate()) return 'Nombre entier, sans décimale.';
      return null;
    };

/// La tension en DEUX nombres entiers, en cmHg : systolique puis diastolique. [requis] : la feuille de température et la feuille d'observation l'exigent, l'accueil non.
List<ChampDef> champsTension({bool requis = false, ColChamp? col}) => [
      ChampDef(
          nom: 'tensionSys',
          libelle: 'Tension systolique ($hosUniteTension)',
          type: TypeChamp.nombre,
          requis: requis,
          col: col ?? ColChamp.demi,
          valider: _borne(hosTensionSysMin, hosTensionSysMax)),
      ChampDef(
          nom: 'tensionDia',
          libelle: 'Tension diastolique ($hosUniteTension)',
          type: TypeChamp.nombre,
          requis: requis,
          col: col ?? ColChamp.demi,
          valider: _borne(hosTensionDiaMin, hosTensionDiaMax)),
    ];

/// La diurèse en MILLILITRES, entière.
ChampDef champDiurese({bool requis = false}) => ChampDef(
    nom: 'diurese',
    libelle: 'Diurèse ($hosUniteDiurese)',
    type: TypeChamp.nombre,
    requis: requis,
    aide: 'En millilitres, sans décimale (1,5 L = 1 500 mL).',
    valider: _borne(hosDiureseMin, hosDiureseMax, entier: true));
