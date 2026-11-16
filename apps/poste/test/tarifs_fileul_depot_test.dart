import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// La Direction est un FILEUL (seuls l'administrateur et la DAF portent la mère) : sur un poste fileul RATTACHÉ, « Tarifs et prix » doit offrir « Proposer un changement » (le
/// fileul DÉPOSE une demande, la mère l'applique). Le défaut, relevé chez la clinique sœur par l'essai le plus proche de l'application réelle : la coque mettait tout écran du
/// module CFG en lecture seule sur un fileul rattaché, donc la Direction ne pouvait ni proposer ni décider depuis son poste, alors que la matrice le lui donne.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('sur un fileul rattaché, la Direction a « Proposer un changement » sur « Tarifs et prix »', (t) async {
    final m = magasinM14();
    await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
    expect(ServiceInstallation.de(m).rattache, isTrue);
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'direction');
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, 'MG01');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('Consulter'), findsWidgets);
    expect(find.byTooltip('Proposer un changement'), findsWidgets, reason: 'le fileul dépose, la mère applique : la commande doit être offerte');
    expect(find.textContaining('Réglé sur la mère'), findsNothing, reason: 'l\'écran n\'est plus en lecture seule : pas de bandeau qui dit le contraire');
  });

  casM14('le geste complet : la Direction (fileul rattaché) propose, la demande est DÉPOSÉE (rien d\'écrit chez le fileul), la mère l\'applique sous le rôle direction ; un « Oui » de fileul est un dépôt', (t) async {
    final m = magasinM14();
    await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'direction');
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, 'MG01');
    await t.pump(const Duration(milliseconds: 500));
    await toucherM14(t, find.byTooltip('Proposer un changement').first);
    await saisir(t, 'prixNonAssure', '5200');
    await saisir(t, 'prixAssure', '3100');
    await saisir(t, 'motif', 'Test : dépôt depuis un fileul');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final deposees = m.collection('propositionsTarif').toutes;
    expect(deposees.length, 1, reason: 'le fileul DÉPOSE une demande');
    expect([deposees.single['genre'], deposees.single['etat'], deposees.single['demandeRole']], ['proposition', 'deposee', 'direction']);
    expect(TarifsPoste.lire(m).versionsDe('MG01').where((v) => v['statut'] == 'propose'), isEmpty, reason: 'rien n\'est écrit dans versionsTarif chez le fileul');

    // La VRAIE mère (le moteur de `ApplicateurDemandesTarif`, même code) applique sous le rôle de l'auteur.
    final mere = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'test/fixtures/jeu_sobre');
    mere.collection('propositionsTarif').appliquerDistante(Map<String, Object?>.of(deposees.single));
    final poste = TarifsPoste(mere,
        role: 'mere', auteur: () => 'Poste mère', peutEditerPour: (r) => donneesNav.matrice.peutEditer(r, 'cfg-tarifs'), horloge: () => aujourdhui);
    expect(poste.appliquerDemandes(), 1);
    final verdict = mere.collection('propositionsTarif').toutes.single;
    expect(verdict['etat'], 'appliquee', reason: '${verdict['resultatCode']} ${verdict['resultatMessage']}');
    final v = TarifsPoste.lire(mere).versionsDe('MG01').last;
    expect([v['statut'], v['proposeRole']], ['propose', 'direction']);
  });
}
