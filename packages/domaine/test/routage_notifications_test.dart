// LE ROUTAGE DES NOTIFICATIONS DE POSTE, RÉGLÉ PAR LA CLINIQUE (lot « destinataires des notifications », 17/11/2026) : la table « poste → geste » et les postes informés d'un besoin
// accordé sont deux réglages de clinique ; la valeur d'attente reprend à l'identique l'ancien code, une valeur illisible ne fait taire aucune alerte.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

const _bon = <String, Object?>{
  'reference': 'BEB-T-1',
  'service': 'Maternité',
  'montantEstime': 11500,
  'lignes': [
    {'produit': 'Gants', 'quantiteDemandee': 10, 'quantiteAccordee': 10, 'prixUnitaire': 1000},
  ],
};

void main() {
  test('la valeur d’attente du routage reprend les neuf postes de l’ancien code, chacun tenu par un geste qui existe', () {
    final t = routagePostesDe('');
    expect(t.keys.toList(), ['caisse', 'stock', 'comptable', 'direction', 'imagerie', 'laboratoire', 'prescripteur', 'salle_soins', 'hospitalisation']);
    expect(t['caisse'], gesteAlertesCaisse);
    expect(t['salle_soins'], gesteAlertesSalleSoins);
    for (final g in t.values) {
      expect(gesteReserve(g), isNotNull, reason: 'le geste $g doit exister au référentiel');
    }
    expect(routagePostesDe(null), t);
    expect(routagePostesDe(routagePostesSemence), t, reason: 'la semence est exactement la valeur d’attente');
  });

  test('la clinique CORRIGE entrée par entrée ; ce qu’elle n’a pas listé garde son geste d’attente ; une entrée mal formée ou un geste inconnu est ignoré', () {
    final t = routagePostesDe('caisse=$gesteAlertesStock ; mal formé ; =vide;laboratoire=geste_qui_n_existe_pas;nouveau_poste=$gesteAlertesDirection');
    expect(t['caisse'], gesteAlertesStock, reason: 'corrigé');
    expect(t['laboratoire'], gesteAlertesLaboratoire, reason: 'geste inconnu : la graine reste');
    expect(t['nouveau_poste'], gesteAlertesDirection, reason: 'un poste nouveau se route aussi');
    expect(t['stock'], gesteAlertesStock, reason: 'non listé : l’attente s’applique, aucune alerte ne se tait par omission');
    expect(t.length, 10);
  });

  test('un poste écrit `geste:<id>` désigne son geste sans passer par la table ; un poste inconnu n’est tenu par aucun geste', () {
    final t = routagePostesDe('');
    expect(gesteDuPosteRoute(posteGeste(gesteProposerPrixAchat), t), gesteProposerPrixAchat);
    expect(gesteDuPosteRoute('caisse', t), gesteAlertesCaisse);
    expect(gesteDuPosteRoute('un_role_destinataire', t), isNull);
    expect(gesteDuPosteRoute(null, t), isNull);
  });

  test('les deux réglages sont déclarés (famille « notifications ») avec leur valeur d’attente, sans geste dédié : le droit d’éditer les paramètres suffit', () {
    for (final (cle, semence) in [(cleRoutagePostes, routagePostesSemence), (cleDestinatairesBesoinAccorde, destinatairesBesoinAccordeSemence)]) {
      final d = definitionDeParametre(cle);
      expect(d, isNotNull, reason: cle);
      expect(d!.famille, 'notifications');
      expect(d.type, TypeParametre.texte);
      expect(d.defaut, semence);
      expect(d.mobile, isFalse);
      expect(d.geste, isNull);
    }
    expect(libellesFamillesParametres['notifications'], 'Notifications');
  });

  test('besoin accordé : les postes informés viennent du réglage ; la valeur d’attente reproduit les deux notifications d’avant, mot pour mot', () {
    final defaut = arbitrerBon(bon: _bon, quoi: Arbitrage.valider, utilisateur: 'U', maintenant: '2030-01-01T00:00:00.000Z');
    expect([for (final n in defaut.notifications) n['poste']], ['comptable', 'stock']);
    expect(defaut.notifications[0]['detail'], endsWith(' · engagement budgétaire et décaissement à préparer'));
    expect(defaut.notifications[1]['detail'], endsWith(' · achat à lancer ou distribution à planifier'));
    expect(defaut.message, 'Besoin BEB-T-1 accordé — le comptable et le gestionnaire de stock sont informés.');
    // La valeur d'attente lue comme un réglage donne EXACTEMENT le même résultat (le poste passe toujours le réglage lu).
    final lu = arbitrerBon(
        bon: _bon, quoi: Arbitrage.valider, utilisateur: 'U', maintenant: '2030-01-01T00:00:00.000Z', destinataires: destinatairesBesoinAccordeDe(destinatairesBesoinAccordeSemence));
    expect(lu.message, defaut.message);
    expect(lu.notifications, defaut.notifications);
  });

  test('besoin accordé : une clinique qui règle d’autres postes les voit notifiés, avec leur mention, et le message ne ment pas', () {
    final dest = destinatairesBesoinAccordeDe('direction=arbitrage à confirmer;caisse=');
    expect(dest, [(poste: 'direction', mention: 'arbitrage à confirmer'), (poste: 'caisse', mention: '')]);
    final r = arbitrerBon(bon: _bon, quoi: Arbitrage.valider, utilisateur: 'U', maintenant: '2030-01-01T00:00:00.000Z', destinataires: dest);
    expect([for (final n in r.notifications) n['poste']], ['direction', 'caisse']);
    expect(r.notifications[0]['detail'], endsWith(' · arbitrage à confirmer'));
    expect(r.notifications[1]['detail'], isNot(contains(' · arbitrage')), reason: 'une mention vide ne laisse pas de séparateur orphelin');
    expect(r.message, contains('direction, caisse'));
    expect(r.message, isNot(contains('gestionnaire de stock')));
    expect(r.message, contains('poste(s) informé(s)'));
  });

  test('un réglage des destinataires illisible retombe sur la valeur d’attente ; un rejet n’informe aucun poste', () {
    expect(destinatairesBesoinAccordeDe(''), destinatairesBesoinAccordeDe(destinatairesBesoinAccordeSemence));
    expect(destinatairesBesoinAccordeDe(';;sans égal;'), destinatairesBesoinAccordeDe(destinatairesBesoinAccordeSemence));
    final rejet = arbitrerBon(
        bon: _bon, quoi: Arbitrage.rejeter, motif: 'Budget épuisé', utilisateur: 'U', maintenant: '2030-01-01T00:00:00.000Z', destinataires: destinatairesBesoinAccordeDe('direction=x'));
    expect(rejet.notifications, isEmpty);
  });
}
