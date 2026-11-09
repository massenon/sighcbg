import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'magasin.dart';

/// LES PARAMÈTRES DE L'AIB LUS EN BASE à une date (collection `parametresAib`, versionnée) : base de la retenue, branchement IFU, taux de repli, longueur de
/// l'IFU. Aucune valeur n'est lue dans le code : la graine ne sert qu'à amorcer la collection et à répondre quand elle est vide (poste jamais semé).
d.CpdParametresAib parametresAib(Magasin m, DateTime date) => d.cpaParametresALaDate(m.collection(d.cpaCollection).actives, date);

/// Le taux d'AIB PAR DÉFAUT à [date] pour les endroits sans fenêtre (retransmission, vente sans acheteur, affichage de la configuration) : le barème arrêté
/// en vigueur pour la situation que le branchement donne à [ifu], sinon le taux de repli des Paramètres, avec son motif.
d.AibParDefaut aibParDefaut(Magasin m, DateTime date, {Object? ifu}) => d.aibParDefautALaDate(
    ifu: ifu,
    date: date,
    situations: m.collection('situationsAib').actives,
    versions: m.collection('baremeAib').actives,
    parametres: parametresAib(m, date));
