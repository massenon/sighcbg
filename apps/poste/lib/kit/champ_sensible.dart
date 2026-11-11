/// LE POINT UNIQUE DU MASQUAGE DES DONNÉES SENSIBLES DU PATIENT (Direction, 11/11/2026).
///
/// Tout écran, tout tiroir, toute impression et la recherche globale passent ICI pour savoir ce que le profil peut lire : jamais une comparaison de nom de rôle.
/// Le droit vient de la matrice (`DroitsSensibles`, domaine) : décision de la clinique sur la fiche `rbac` du rôle, sinon le défaut de la catégorie (le droit
/// de voir l'écran dont elle dépend). Il est RELU à chaque appel — un droit accordé ou retiré à l'instant s'applique à la lecture suivante — et les écrans
/// qui l'affichent s'abonnent à `rbac` ([EcouteDroitsSensibles]) pour se redessiner sans redémarrage.
///
/// Un champ masqué le DIT ([mentionReservee]) : un champ vide se lirait comme une donnée absente.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';
import '../shell/contexte_ecran.dart';

/// Ce que le profil de l'écran courant peut lire. Se construit à l'usage ([AccesSensible.de]) : rien n'est gardé d'un appel à l'autre.
class AccesSensible {
  AccesSensible(this.role, this._droits);

  /// Le profil qui regarde (rôle de la session, issu de la coque — jamais comparé à un nom).
  final String role;
  final DroitsSensibles _droits;

  /// Depuis le contexte d'un écran : les fiches `rbac` du magasin (toujours à jour) et la matrice en force de la coque. Hors coque (test nu), la matrice
  /// n'est pas branchée : les écrans sont réputés ouverts et seules les décisions explicites masquent.
  factory AccesSensible.de(ContexteEcran c) => AccesSensible.depuis(role: c.role, magasin: c.magasin, donnees: c.donnees?.matrice);

  factory AccesSensible.depuis({required String role, required Magasin magasin, MatriceDroits? donnees}) => AccesSensible(
      role, DroitsSensibles(fiches: magasin.collection('rbac').actives, peutVoirEcran: donnees == null ? null : donnees.peutVoir));

  bool peut(String categorie) => _droits.peut(role, categorie);

  /// « Information réservée — droit requis : <catégorie> ».
  String mention(String categorie) => mentionReservee(categorie);

  /// La valeur, ou la mention si la catégorie est refusée : pour une cellule de texte, une paire de [DescListeSigh], une ligne d'état imprimé.
  Object? masquerSi(String categorie, Object? valeur) => peut(categorie) ? valeur : mention(categorie);

  /// Pour une cellule de tableau (`String Function(Fiche)`) : le texte, ou la mention.
  String texteSi(String categorie, String texte) => peut(categorie) ? texte : mention(categorie);

  /// Le widget de la catégorie, ou la mention posée dans une carte discrète.
  Widget champ(String categorie, Widget Function() rendu) => peut(categorie) ? rendu() : MentionReservee(categorie);

  /// Le champ [nom] d'un enregistrement patient : sa valeur, ou la mention de SA catégorie. Un champ d'identification minimale (code, nom, sexe…) se lit toujours.
  Object? lire(Map<String, Object?> fiche, String nom) {
    final c = categorieDuChamp(nom);
    if (c == null || peut(c.code)) return fiche[nom];
    return mention(c.code);
  }

  /// Le champ [nom] est-il lisible ?
  bool peutLireChamp(String nom) {
    final c = categorieDuChamp(nom);
    return c == null || peut(c.code);
  }

  /// L'enregistrement sans les champs refusés.
  Map<String, Object?> masquer(Map<String, Object?> fiche, {Set<String>? masques}) => _droits.masquer(role, fiche, masques: masques);

  /// Les catégories refusées à ce profil (vide : rien n'est masqué).
  List<CategorieSensible> get refusees => _droits.refusees(role);
}

/// La mention d'un champ ou d'une rubrique masquée.
class MentionReservee extends StatelessWidget {
  const MentionReservee(this.categorie, {super.key});
  final String categorie;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, key: Key('sensible:$categorie'), children: [
        const Icon(LucideIcons.lock, size: 13, color: JetonsShell.slate400),
        const SizedBox(width: 6),
        Flexible(
            child: Text(mentionReservee(categorie),
                style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic))),
      ]);
}

/// Redessine son contenu quand les droits changent : une décision de droits (collection `rbac`) ou une fermeture d'activité s'applique sans rien rouvrir.
class EcouteDroitsSensibles extends StatelessWidget {
  const EcouteDroitsSensibles({super.key, required this.builder});

  /// Reçoit l'accès RECALCULÉ.
  final Widget Function(BuildContext context, AccesSensible acces) builder;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: Listenable.merge([c.magasin.collection('rbac'), c.magasin.collection('modulesActifs')]),
        builder: (ctx, _) => builder(ctx, AccesSensible.de(c)));
  }
}

/// Garde d'un écran ENTIER dont tout le contenu relève d'une catégorie (le dossier de consultation, la fiche, les ordonnances) : refusée, il dit « Information
/// réservée » au lieu de s'ouvrir sur des données que le profil n'a pas le droit de lire. S'abonne aux droits : accordé à chaud, il s'ouvre sans rien recharger.
class GardeSensible extends StatelessWidget {
  const GardeSensible({super.key, required this.categorie, required this.enfant});
  final String categorie;
  final Widget enfant;

  @override
  Widget build(BuildContext context) => EcouteDroitsSensibles(
      builder: (ctx, a) => a.peut(categorie)
          ? enfant
          : Padding(
              key: Key('garde-sensible:$categorie'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
                  child: MentionReservee(categorie))));
}
