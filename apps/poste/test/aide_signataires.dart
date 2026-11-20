import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';

/// L'INTITULÉ qu'imprime une signature à qualité : celui du poste de l'organigramme (collection `postes`) du magasin, à défaut le repli écrit à l'appelant (lot « noms et signataires »
/// de l'inventaire des valeurs en dur, 17/11/2026). Une pièce n'écrit plus « La Directrice Administrative » : elle écrit ce que l'organigramme de la clinique nomme.
String intituleSigne(Magasin m, PaiQualite q, String repli) => paiIntituleSignataire(m.collection('postes').actives, q) ?? repli;
