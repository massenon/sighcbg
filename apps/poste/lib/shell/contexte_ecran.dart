import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/donnees_navigation.dart';
import '../donnees/magasin.dart';

/// Ce qu'un écran porté reçoit de la coque : son identifiant, le rôle de l'agent, ses droits SUR CET ÉCRAN (jamais ceux d'un autre module),
/// le magasin de données et la navigation. Équivalent de `K.droits()` et de `app.go()` de la maquette.
class ContexteEcran extends InheritedWidget {
  const ContexteEcran({
    super.key,
    required this.ecranId,
    required this.role,
    required this.droit,
    required this.magasin,
    required this.aller,
    this.utilisateur = '',
    this.agentConnecte,
    this.horloge,
    this.ouvre,
    this.donnees,
    required super.child,
  });

  final String ecranId;
  final String role;
  final Droit droit;
  final Magasin magasin;

  /// `app.go(id)` : ouvre un autre écran (refusé par la coque s'il est fermé au rôle).
  final void Function(String id) aller;

  /// `ecranOuvert(id)` : l'écran est-il ouvert au profil de l'agent ? (parcours des tableaux de bord : une étape fermée reste visible mais non cliquable). `null` = non branché : tout est réputé ouvert.
  final bool Function(String id)? ouvre;

  /// Manifeste, droits et parité (écrans qui décrivent le logiciel lui-même : aide, plan du site). `null` = non branché.
  final DonneesNavigation? donnees;

  /// Nom affiché de l'agent connecté (RG-12 : aucune action anonyme).
  final String utilisateur;

  /// L'agent NOMINATIF de la session (A1) : `null` quand le poste n'a pas de session nominative (développement, tests).
  final Agent? agentConnecte;

  /// L'agent qui agit : l'agent de la session, sinon l'agent de DÉMONSTRATION du rôle (déterministe, nom = [utilisateur]). Les écrans ne lisent jamais
  /// [utilisateur] pour s'attribuer un geste : ils passent par `acteur(contexte)` du kit, qui lit ceci.
  Agent get agent =>
      agentConnecte ??
      agentDemonstration(role, nom: utilisateur.isEmpty ? null : utilisateur);

  /// Horloge du poste, fixable par un test ; `null` = l'horloge réelle (`C.aujourdhui()`).
  final DateTime Function()? horloge;
  DateTime get aujourdhui => (horloge ?? DateTime.now)();

  static ContexteEcran of(BuildContext context) {
    final c = context.dependOnInheritedWidgetOfExactType<ContexteEcran>();
    assert(c != null,
        'ContexteEcran absent : l’écran doit être monté par la coque.');
    return c!;
  }

  /// UNE COPIE de ce contexte pour un sous-arbre posé AILLEURS que sous l'écran (D5, Direction 09/11/2026). Les modales et les tiroirs sont des routes du
  /// navigateur RACINE : ils se montent dans l'overlay, au-dessus de la page, donc HORS de l'arbre de l'écran. Tout widget qu'on y met et qui lit
  /// `ContexteEcran.of(context)` (la fiche du patient, ses impressions) levait « ContexteEcran absent » — alors que la même fiche, ouverte en page, marchait.
  /// Le relais se fait UNE fois, dans `afficherModale` et `afficherTiroir` : écrire `ContexteEcran(...)` à chaque appelant aurait laissé le défaut revenir
  /// avec le prochain tiroir. Le contexte est celui de l'ouverture (instantané, comme `InheritedTheme.capture`) ; sans écran au-dessus de [origine]
  /// (écran autonome, test de widget nu), l'enfant est rendu tel quel.
  static ContexteEcran? capturer(BuildContext origine) => origine.mounted ? origine.getInheritedWidgetOfExactType<ContexteEcran>() : null;

  /// Le sous-arbre [enfant] sous une copie de [capture] (rendu tel quel si `null`). La capture se fait à l'OUVERTURE ([capturer]) : le constructeur de page de
  /// la route est rejoué plus tard, et le contexte d'origine peut alors être désactivé (« Looking up a deactivated widget's ancestor is unsafe »).
  static Widget relayer(ContexteEcran? capture, Widget enfant) {
    final c = capture;
    if (c == null) return enfant;
    return ContexteEcran(
        ecranId: c.ecranId,
        role: c.role,
        droit: c.droit,
        magasin: c.magasin,
        aller: c.aller,
        utilisateur: c.utilisateur,
        agentConnecte: c.agentConnecte,
        horloge: c.horloge,
        ouvre: c.ouvre,
        donnees: c.donnees,
        child: enfant);
  }

  static ContexteEcran? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContexteEcran>();

  @override
  bool updateShouldNotify(ContexteEcran o) =>
      o.ecranId != ecranId ||
      o.role != role ||
      o.droit != droit ||
      o.agentConnecte != agentConnecte ||
      o.magasin != magasin ||
      o.ouvre != ouvre;
}

/// Un écran qui déclare lui-même son en-tête de page (`SIGH.screen({title, description, regle, actions})`).
mixin EcranMaquette on Widget {
  /// Titre de la page quand il diffère de l'intitulé du ruban (`SIGH.screen({title})`).
  String? get titre => null;

  String? get description => null;

  /// Texte brut (les balises de mise en forme de la maquette sont retirées).
  String? get regle => null;
  List<Widget> actionsEntete(BuildContext context) => const [];
}

/// `<strong>…</strong>` et consorts de la maquette → texte brut.
String sansBalises(String s) =>
    s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&');
