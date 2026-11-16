import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import '../donnees/reglages_clinique_poste.dart';
import '../modules/m7/besoins_commun.dart' show notifierPoste;

/// LA MÈRE MET DE CÔTÉ la pièce d'un fileul datée d'un exercice clos ou en clôture (Q1, continuité de service). Le fileul n'est jamais bloqué : il garde sa pièce et continue ; la mère ne
/// l'écrit pas à ses écritures, la conserve dans `piecesMisesDeCote` (jamais perdue, RG-14) avec le refus NOMMÉ (`exercice_clos` ou `exercice_en_cloture`) et le dit par une notification de poste
/// et une ligne de journal (RG-12). Idempotent : une pièce déjà mise de côté ne l'est pas deux fois (le pont repasse à chaque tour).
///
/// Branché au pont de la MÈRE (`PontActivite.gardeEntrante`) : rend `true` quand la pièce est écartée. Limite connue : le verdict ne revient pas au fileul par le pont ; il le lit au registre de la mère.
bool miseDeCotePieceFileul(Magasin m, String collection, Map<String, Object?> fiche) {
  if (collection != 'ecritures') return false;
  final refus = cpcRefusPieceFileul(m.collection('exercices').toutes, fiche, rolesInventaire: ReglagesClinique.rolesInventaire(m, m.horloge()));
  if (refus == null) return false;
  final cle = '${fiche['idSync'] ?? fiche['id']}';
  final col = m.collection('piecesMisesDeCote');
  if (col.toutes.any((x) => x['cle'] == cle)) return true;
  col.inserer({
    'cle': cle,
    'statut': 'actif',
    'numero': fiche['numero'],
    'date': fiche['date'],
    'code': refus.code,
    'motif': refus.motif,
    'geste': refus.geste,
    'miseDeCoteLe': m.horloge().toIso8601String(),
    'piece': Map<String, Object?>.from(fiche),
  }, prefixe: 'PMC');
  m.journaliser('Pièce de fileul mise de côté', 'M12', 'Écriture', '${fiche['numero'] ?? cle}', null, {'code': refus.code, 'motif': refus.motif});
  notifierPoste(m, {'type': 'cloture', 'poste': 'comptable', 'libelle': 'Pièce mise de côté (${refus.code})', 'detail': refus.motif, 'priorite': 'haute', 'reference': '${fiche['numero'] ?? cle}'}, m.horloge());
  return true;
}
