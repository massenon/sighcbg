import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'magasin.dart';

/// LES PARAMÈTRES DE L'AIB LUS EN BASE à une date (collection `parametresAib`, versionnée) : base de la retenue, branchement IFU, taux de repli, longueur de
/// l'IFU. Aucune valeur n'est lue dans le code : la graine ne sert qu'à amorcer la collection et à répondre quand elle est vide (poste jamais semé).
d.CpdParametresAib parametresAib(Magasin m, DateTime date) => d.cpaParametresALaDate(m.collection(d.cpaCollection).actives, date);

/// Les COMPTES de l'AIB EN VIGUEUR à [date] (rubrique `comptes` de `parametresAib`) : AIB subi, AIB retenu, imputation, fournisseur. Les moteurs de pièces (retenue,
/// AIB subi) les lisent À LA DATE DE LA PIÈCE ; la graine du code ne répond que si la collection est vide, et [d.CpdComptesAib.deLaGraine] le dit.
d.CpdComptesAib comptesAib(Magasin m, DateTime date) => d.cpaComptesALaDate(m.collection(d.cpaCollection).actives, date);
