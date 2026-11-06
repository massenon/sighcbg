import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';

/// L'IDENTITÉ ENREGISTRÉE DE LA CLINIQUE (décision de la Direction du 06/11/2026, écart E841 levé).
///
/// L'écran « Identité & papier à en-tête » (`cfg-branding`) enregistre l'identité dans UNE fiche de la collection `ressources` (identifiant
/// [idFicheIdentite], type `identite`) : c'est la collection de configuration que l'écran écrit déjà pour le logo et le cachet, que la mère diffuse
/// aux postes fileuls, et que l'assistant d'installation surveille pour l'étape « en-tête officiel ». Ce fichier relit cette fiche et l'applique à
/// [IdentiteClinique] : au démarrage du poste, à chaque écriture de la collection (une modification reçue de la mère comprise), et à chaque
/// enregistrement. Toutes les pièces lisent [IdentiteClinique] : elles reprennent la valeur enregistrée sans rien savoir de ce mécanisme.
///
/// Une fiche ARCHIVÉE ne compte plus (RG-14) : l'archiver depuis la corbeille rend l'identité initiale ; la restaurer la rétablit.
const idFicheIdentite = 'IDENTITE';

/// Change à chaque application : les widgets qui affichent l'identité hors d'un écran (pied légal de la coque) se reconstruisent.
final ValueNotifier<int> versionIdentite = ValueNotifier<int>(0);

/// La fiche d'identité active du magasin, ou `null` (aucune identité enregistrée : l'identité initiale s'applique).
Fiche? ficheIdentite(Magasin m) => m.collection('ressources').actives.where((f) => f['id'] == idFicheIdentite).firstOrNull;

/// Les valeurs enregistrées (`identite` de la fiche), ou `null`.
Map<String, Object?>? identiteEnregistree(Magasin m) {
  final v = ficheIdentite(m)?['identite'];
  return v is Map ? v.cast<String, Object?>() : null;
}

/// Applique l'identité enregistrée du magasin à [IdentiteClinique].
void appliquerIdentite(Magasin m) {
  final avant = IdentiteClinique.surcharge;
  IdentiteClinique.appliquer(identiteEnregistree(m));
  if ('$avant' != '${IdentiteClinique.surcharge}') versionIdentite.value++;
}

final Expando<VoidCallback> _branches = Expando<VoidCallback>('identite');

/// Branche l'identité sur le magasin : application immédiate, puis à chaque changement de la collection `ressources`. Idempotent.
void brancherIdentite(Magasin m) {
  appliquerIdentite(m);
  if (_branches[m] != null) return;
  void ecoute() => appliquerIdentite(m);
  m.collection('ressources').addListener(ecoute);
  _branches[m] = ecoute;
}

/// ENREGISTRE l'identité saisie dans le formulaire : écrit la fiche (création la première fois, modification ensuite : la collection journalise
/// l'une et l'autre, avec les valeurs avant et après pour une modification, RG-12), puis l'applique. Les champs d'identité sont nettoyés (espaces
/// de bord) ; un champ vidé reste VIDE et cesse d'être imprimé. Les options d'impression (double logo, pied, filigrane) voyagent dans la même fiche.
void enregistrerIdentite(Magasin m, Map<String, Object?> valeurs, {required String auteur, required DateTime quand}) {
  final identite = <String, Object?>{
    for (final k in IdentiteClinique.champs)
      if (valeurs.containsKey(k)) k: k == 'telephones' ? IdentiteClinique.lireTelephones(valeurs[k]) : '${valeurs[k] ?? ''}'.trim(),
  };
  final options = <String, Object?>{
    for (final k in const ['doubleLogo', 'piedPage', 'filigrane'])
      if (valeurs.containsKey(k)) k: valeurs[k],
  };
  final col = m.collection('ressources');
  final existante = col.parId(idFicheIdentite);
  final patch = <String, Object?>{'identite': identite, 'options': options, 'modifiePar': auteur, 'modifieLe': quand.toIso8601String()};
  if (existante == null) {
    col.inserer({
      'id': idFicheIdentite,
      'statut': 'actif',
      'type': 'identite',
      'libelle': 'Identité légale imprimée',
      ...patch,
    });
  } else {
    // Une fiche archivée puis ré-enregistrée revient en service : l'identité enregistrée est celle qu'on vient de saisir.
    if (CollectionMagasin.estArchivee(existante)) col.restaurer(idFicheIdentite);
    col.mettreAJour(idFicheIdentite, patch);
  }
  appliquerIdentite(m);
}

/// Les options d'impression enregistrées avec l'identité (double logo, pied normalisé, filigrane), ou `null`.
Map<String, Object?>? optionsIdentite(Magasin m) {
  final v = ficheIdentite(m)?['options'];
  return v is Map ? v.cast<String, Object?>() : null;
}
