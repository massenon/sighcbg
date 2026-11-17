// LES RÈGLES DE LA MÈRE LISENT SON REGISTRE DATÉ (consigne du 18/11/2026 : « plus de valeur en dur »). Un changement de réglage CHANGE le comportement : fenêtre de réinitialisation,
// délai de la sauvegarde quotidienne, âge limite d'une copie de nuit, seuils de la supervision. Sans réglage, la valeur d'attente (le comportement d'avant). Hors bornes ou paire
// incohérente : les valeurs d'attente ENSEMBLE, jamais zéro.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:sigh_sync/src/reglages_mere.dart';
import 'package:sigh_sync/src/supervision.dart';
import 'package:test/test.dart';

Future<void> regler(Mere m, Map<String, Object?> valeurs, {String date = '2020-01-01', int version = 1}) async {
  for (final e in valeurs.entries) {
    final d = definitionDeParametre(e.key)!;
    await m.ecrire(parCollectionParametres, '${e.key}@$date@$version', Fiche({
      'cle': e.key, 'famille': d.famille, 'type': d.type.name, 'valeur': e.value, 'defaut': d.defaut, 'dateEffet': date, 'version': version, 'auteur': 'admin', 'creeLe': '2026-11-18T08:00:00Z', 'mobile': false, 'sensible': false,
    }, {}, false));
  }
}

Map<String, Object?> controle(List<Map<String, Object?>> l, String nom) => l.firstWhere((c) => '${c['nom']}'.startsWith(nom));

void main() {
  late Mere m;
  setUp(() async => m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:')));
  final maintenant = DateTime.now();

  test('sans réglage : les valeurs d\'attente (le comportement d\'avant)', () async {
    expect(await m.fenetreReinit(), const Duration(minutes: 30));
    expect(await seuilMere(m.base, mereCleDelaiSauvegardeQuotidienne, maintenant), 20);
    expect(await seuilMere(m.base, mereCleAgeLimiteCopieMagasin, maintenant), 30);
    final s = await Seuils.depuis(m.base, maintenant);
    expect((s.disqueAttentionOctets, s.disqueAlerteOctets), (10 << 30, 2 << 30));
    expect((s.sauvegardeAttentionHeures, s.sauvegardeAlerteHeures), (26, 50));
    expect((s.posteSilenceAttentionMin, s.posteSilenceAlerteMin, s.posteRetardOperations), (30, 240, 500));
    expect((s.relaisRetardAttention, s.relaisRetardAlerte, s.deriveHorlogeMin), (50, 2000, 2));
  });

  test('fenêtre de réinitialisation : un réglage de 60 minutes garde ouverte une fenêtre ouverte depuis 45 minutes (30 minutes l\'aurait refermée)', () async {
    await m.base.poserMeta('reinit_ouverte', 1);
    await m.base.poserMeta('reinit_ouverte_ms', maintenantMs() - 45 * 60 * 1000);
    expect(await m.reinitOuverte(), isFalse, reason: 'valeur d\'attente de 30 minutes : refermée');
    await m.base.poserMeta('reinit_ouverte', 1);
    await m.base.poserMeta('reinit_ouverte_ms', maintenantMs() - 45 * 60 * 1000);
    await regler(m, {mrbCleFenetreReinit: 60});
    expect(await m.fenetreReinit(), const Duration(minutes: 60));
    expect(await m.reinitOuverte(), isTrue, reason: 'réglage de 60 minutes : encore ouverte');
  });

  test('une valeur hors bornes (24 heures de fenêtre) retombe sur la valeur d\'attente, jamais sur zéro ni sur la valeur saisie', () async {
    await regler(m, {mrbCleFenetreReinit: 1440});
    expect(await m.fenetreReinit(), const Duration(minutes: 30));
  });

  test('sauvegarde quotidienne et copie de nuit : les délais se lisent au registre', () async {
    await regler(m, {mereCleDelaiSauvegardeQuotidienne: 12, mereCleAgeLimiteCopieMagasin: 48});
    expect(await seuilMere(m.base, mereCleDelaiSauvegardeQuotidienne, maintenant), 12);
    expect(await seuilMere(m.base, mereCleAgeLimiteCopieMagasin, maintenant), 48);
    // une version future ne s'applique pas encore
    await regler(m, {mereCleDelaiSauvegardeQuotidienne: 6}, date: '2999-01-01', version: 2);
    expect(await seuilMere(m.base, mereCleDelaiSauvegardeQuotidienne, maintenant), 12);
  });

  test('supervision : la sauvegarde de 30 h passe de « attention » à « ok » quand le réglage relève le seuil ; la paire incohérente retombe ensemble sur l\'attente', () async {
    Future<String> etat(int heures) async {
      await m.base.poserMeta('derniere_sauvegarde', maintenantMs() - heures * 3600 * 1000);
      return '${controle(await controlesMere(m, disqueLibre: 100 << 30), 'Sauvegarde')['etat']}';
    }

    expect(await etat(30), 'attention');
    await regler(m, {mereCleSauvegardeAttentionHeures: 40, mereCleSauvegardeAlerteHeures: 80});
    expect(await etat(30), 'ok');
    expect(await etat(60), 'attention');
    expect(await etat(100), 'alerte');
    // paire renversée (attention 90 > alerte 80) : les DEUX reviennent à 26 et 50
    await regler(m, {mereCleSauvegardeAttentionHeures: 90}, date: '2021-01-01', version: 2);
    expect(await etat(30), 'attention');
    expect(await etat(60), 'alerte');
  });

  test('supervision : disque (en Go), silence des postes, dérive d\'horloge', () async {
    await regler(m, {mereCleDisqueAttenteGo: 100, mereCleDisqueAlerteGo: 50});
    Future<String> disque(int go) async => '${controle(await controlesMere(m, disqueLibre: go << 30), 'Espace disque')['etat']}';
    expect(await disque(80), 'attention', reason: '80 Go libres sont sous les 100 Go réglés (l\'attente de 10 Go dirait « ok »)');
    expect(await disque(40), 'alerte');
    await m.base.exec("INSERT INTO appareils(uuid,etiquette,role,etat,dernier_contact,dernier_seq,derive_ms) VALUES('p2','Accueil','fileul','actif',?,0,90000)", [maintenantMs() - 60 * 1000]);
    expect(controle(await controlesMere(m, disqueLibre: 500 << 30), 'Poste « Accueil »')['etat'], 'ok', reason: 'dérive de 1,5 minute, sous les 2 minutes d\'attente');
    await regler(m, {mereCleDeriveHorlogeMin: 1});
    expect(controle(await controlesMere(m, disqueLibre: 500 << 30), 'Poste « Accueil »')['etat'], 'attention', reason: 'réglée à 1 minute, la même dérive est signalée');
  });
}
