/// LES BORNES DE SAISIE DU TÉLÉPHONE, RELUES À LA BASE LOCALE (consigne du 18/11/2026 : « plus de valeur en dur »).
///
/// La mère livre au téléphone les versions des réglages de la LISTE BLANCHE (`mob_bornes.dart` du domaine : des bornes de plausibilité, rien de médical ni de sensible) ; elles
/// vivent dans la base chiffrée du téléphone, collection `parametres`. Cette fonction les relit À CHAQUE geste (une borne réglée à la clinique vaut donc dès la synchronisation
/// suivante, sans redémarrage) et en tire les bornes en vigueur à [maintenant]. SANS réglage reçu — téléphone jamais synchronisé, collection vide, base illisible — ce sont les
/// valeurs d'attente (le comportement d'avant) : un téléphone hors ligne ne perd jamais son contrôle de saisie.
library;

import 'package:sigh_domaine/sigh_domaine.dart';

import 'service_soignant.dart' show SourceMobile;

Future<MobBornes> bornesDe(SourceMobile source, DateTime maintenant) async {
  try {
    final lignes = await source.liste(parCollectionParametres);
    if (lignes.isEmpty) return MobBornes.attente;
    return MobBornes.depuisFiches([
      for (final l in lignes) {...l.data, 'id': l.id, if (l.archive) 'statut': 'archive'}
    ], parametreDateIso(maintenant));
  } catch (_) {
    return MobBornes.attente;
  }
}
