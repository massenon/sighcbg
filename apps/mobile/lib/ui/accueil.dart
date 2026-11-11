import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show mobEcranOuvertAuProfil, mobLibelleEcran, mobProfilDe;

import '../moteur/moteur_mobile.dart';
import 'a_traiter.dart';
import 'agenda.dart';
import 'lot.dart';
import 'reglages.dart';
import 'reception.dart';
import 'tournee.dart';

/// Bandeau d'état : ce que le téléphone dit toujours de lui-même — jamais un voyant muet.
class BandeauEtat extends StatelessWidget {
  const BandeauEtat({super.key, required this.etat, this.ouvrirATraiter});
  final EtatMobile etat;

  /// Un refus à traiter se lit : toucher le bandeau ouvre l'écran « À traiter ».
  final VoidCallback? ouvrirATraiter;

  String get texte {
    if (etat.suspendu) return 'Téléphone suspendu — contactez la clinique';
    final attente = etat.enAttente > 0 ? ' · ${etat.enAttente} en attente d’envoi' : '';
    final traiter = etat.aTraiter > 0 ? ' · ${etat.aTraiter} à traiter' : '';
    final lot = etat.lotExpire != null && etat.lotExpire! > 0 && DateTime.now().millisecondsSinceEpoch >= etat.lotExpire! ? ' · lot de tournée expiré' : '';
    return '${etat.horsLigne ? 'Hors ligne' : 'Connecté'}$attente$traiter$lot';
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: etat.aTraiter > 0 ? ouvrirATraiter : null,
        child: Container(
          key: const Key('bandeau'),
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: etat.suspendu || etat.aTraiter > 0 ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(texte),
        ),
      );
}

/// L'accueil dépend du PROFIL : le soignant a sa tournée, la réception de secours son formulaire d'accueil. Aucun des deux
/// ne voit l'autre — ce que le profil ne couvre pas n'est pas proposé (et le serveur le refuserait de toute façon).
class Accueil extends StatelessWidget {
  const Accueil({super.key, required this.moteur, this.coffreActif = false, this.apresReinitialisation});
  final MoteurMobile moteur;

  /// Vrai quand le code PIN garde l'application (l'écran des réglages ne dit « Activé » que si c'est vrai).
  final bool coffreActif;
  final VoidCallback? apresReinitialisation;

  /// Le profil du simulateur de ce téléphone (`soignant`, `medecin`, `sagefemme`, `reception`).
  String get _profil => mobProfilDe(reception: moteur.profil != ProfilMobile.soignant, fonction: moteur.soignant?.session.fonction ?? '');
  String get _agent => moteur.soignant?.session.agent ?? (moteur is ExtensionsMobile ? (moteur as ExtensionsMobile).agent : '');

  /// Réglages pour tous les profils ; lot de tournée pour ceux dont le simulateur l'ouvre (la commande est ABSENTE de la réception de secours).
  List<Widget> _actions(BuildContext context) => [
        if (moteur.soignant != null && mobEcranOuvertAuProfil(_profil, 'lot'))
          IconButton(
            key: const Key('ouvrir-lot'),
            tooltip: mobLibelleEcran('lot'),
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranLot(moteur: moteur, service: ServiceSuite.depuisSoignant(moteur.soignant!)))),
          ),
        IconButton(
          key: const Key('ouvrir-reglages'),
          tooltip: mobLibelleEcran('parametres'),
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => EcranReglages(moteur: moteur, profil: _profil, agent: _agent, verrouillageActif: coffreActif, apresReinitialisation: apresReinitialisation))),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    // L'accueil relit la matrice à CHAQUE décision de la mère : un onglet dont le droit de voir est retiré disparaît, sans redémarrer l'application.
    return ValueListenableBuilder<EtatDroits>(valueListenable: moteur.droits, builder: (c, _, __) => _accueil(c));
  }

  Widget _accueil(BuildContext context) {
    final soignant = moteur.profil == ProfilMobile.soignant;
    final droits = moteur.droits;
    final bandeau = ValueListenableBuilder<EtatMobile>(
        valueListenable: moteur.etat,
        builder: (_, e, __) => BandeauEtat(etat: e, ouvrirATraiter: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ATraiter(moteur: moteur)))));
    if (!soignant || moteur.soignant == null) {
      return Scaffold(
        appBar: AppBar(title: Text(soignant ? 'Ma tournée' : 'Réception de secours'), actions: _actions(context)),
        body: Column(children: [bandeau, Expanded(child: soignant ? Tournee(moteur: moteur) : Reception(moteur: moteur))]),
      );
    }
    // Soignant : l'agenda du jour d'abord (ce qu'on ouvre en arrivant), puis les dossiers du lot. Chaque onglet suit un droit de voir : sans aucun, la page le DIT.
    final onglets = <(Key, String, Widget)>[
      if (droits.peutVoir('agenda')) (const Key('onglet-agenda'), 'Agenda du jour', AgendaJour(moteur: moteur)),
      if (droits.peutVoir('dossier')) (const Key('onglet-dossiers'), 'Dossiers du lot', Tournee(moteur: moteur)),
    ];
    if (onglets.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ma tournée'), actions: _actions(context)),
        body: Column(children: [
          bandeau,
          const Expanded(
              child: Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucun écran n’est ouvert à votre profil sur ce téléphone : les droits de la clinique ne le permettent pas. Demandez à l’administrateur de les modifier, ils se mettront à jour à la prochaine synchronisation.',
                          key: Key('aucun-ecran'), textAlign: TextAlign.center)))),
        ]),
      );
    }
    return DefaultTabController(
      key: ValueKey(onglets.map((o) => o.$2).join('|')),
      length: onglets.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ma tournée'),
          actions: _actions(context),
          bottom: onglets.length < 2 ? null : TabBar(tabs: [for (final o in onglets) Tab(key: o.$1, text: o.$2)]),
        ),
        body: Column(children: [
          bandeau,
          Expanded(child: TabBarView(children: [for (final o in onglets) o.$3])),
        ]),
      ),
    );
  }
}
