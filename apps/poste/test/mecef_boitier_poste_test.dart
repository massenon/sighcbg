import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/mecef_poste.dart';
import 'package:sigh_poste/donnees/normalisation_mecef.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LE BOÎTIER MECeF DE BAGUIDI : un ELTRADE CC300 (décision de la Direction du 16/11/2026). Le MODÈLE est un réglage de clinique semé, affiché à la configuration,
/// porté sur la pièce et au journal MECeF là où le mode l'est ; l'adaptateur reste NON CONFIGURÉ (aucun protocole dans le dépôt) et le dit. Aucune requête réseau.
final aujourdhui = DateTime(2026, 10, 30);

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Fiche vente(Magasin m) => m.collection('factures').inserer({
      'numero': 'FN-TEST-CC300',
      'montantTTC': 10000,
      'montantPaye': 10000,
      'statutPaiement': 'soldee',
      'statutMecef': 'en_attente',
      'statut': 'actif',
      'lignes': [
        {'id': 'L1', 'designation': 'Consultation', 'quantite': 1, 'prixUnitaire': 10000, 'partAssureur': 0, 'partPatient': 10000, 'statutPaiement': 'paye'}
      ],
    }, prefixe: 'FAC').fiche;

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  test('le modèle se LIT au registre : semé à « ELTRADE CC300 », réglable par une version datée', () {
    final m = magasin();
    expect(modeleBoitierDuPoste(m, aujourdhui), 'ELTRADE CC300');
    final s = serviceParametres(m, auteur: () => 'DAF', horloge: () => aujourdhui);
    expect(s.regler(mecefCleModeleBoitier, 'ELTRADE CC300 (série 2)', parametreDateIso(aujourdhui), motif: 'essai').ok, isTrue);
    expect(modeleBoitierDuPoste(m, aujourdhui), 'ELTRADE CC300 (série 2)');
  });

  test('une vente en mode boîtier : en attente, AUCUN numéro, la pièce et le journal MECeF portent le modèle', () {
    final m = magasin();
    final f = vente(m);
    final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
    expect(r.ok, isFalse);
    expect(r.code, mecefCodeNonConfigure);
    expect(r.motif, contains('adaptateur ELTRADE CC300 : intégration à fournir par l’éditeur du boîtier'));
    final apres = m.collection('factures').parId(f['id'])!;
    expect(apres['numeroMecef'], isNull);
    expect(apres['modeMecef'], 'boitier');
    expect(apres['modeleBoitierMecef'], 'ELTRADE CC300');
    final j = m.collection('audit').toutes.lastWhere((x) => x['action'] == 'Normalisation en attente (adaptateur non configuré)');
    expect((j['apres'] as Map)['boitier'], 'ELTRADE CC300');
    expect((j['apres'] as Map)['mode'], 'boitier');
  });

  test('en mode e-MECeF, le modèle du boîtier n’est PAS porté (il ne concerne pas la tentative)', () {
    final m = magasin();
    serviceParametres(m, auteur: () => 'DAF', horloge: () => aujourdhui).regler(mecefCleMode, 'emecef', parametreDateIso(aujourdhui));
    final f = vente(m);
    normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
    final apres = m.collection('factures').parId(f['id'])!;
    expect(apres['modeMecef'], 'emecef');
    expect(apres.containsKey('modeleBoitierMecef'), isFalse);
  });

  casM14('la configuration MECeF affiche le modèle et « adaptateur ELTRADE CC300 : intégration à fournir par l’éditeur du boîtier » ; le modèle se règle et se versionne', (t) async {
    final m = magasin();
    await ouvrirM14(t, m, 'mecef-config', horloge: aujourdhui);
    expect(find.textContaining('Boîtier physique : ELTRADE CC300'), findsOneWidget);
    expect(find.byKey(const Key('mecef-adaptateur-boitier')), findsOneWidget);
    expect(find.textContaining('Adaptateur ELTRADE CC300 : intégration à fournir par l’éditeur du boîtier (adaptateur non configuré)'), findsOneWidget);
    await saisir(t, 'modele', 'ELTRADE CC300 v2');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer le mode'));
    expect(modeleBoitierDuPoste(m, aujourdhui), 'ELTRADE CC300 v2');
    expect(m.collection('parametres').toutes.where((v) => v['cle'] == mecefCleModeleBoitier && v['valeur'] == 'ELTRADE CC300 v2').length, 1);
    expect(m.collection('parametres').toutes.where((v) => v['cle'] == mecefCleMode && v['version'] != 0), isEmpty,
        reason: 'le mode inchangé n’ajoute pas de version');
  });

  // L'ÉCRAN DES MODES MECeF (Direction de Baguidi, 16/11/2026, E3760) : la section « Mode de certification » de « Configuration fiscale » dit, mode par mode, ce
  // qui est prêt et ce qui manque ; aucun n'est configuré, aucun numéro n'est simulé.
  casM14('les deux modes disent ce qui est prêt et ce qui manque : boîtier ELTRADE CC300 (adaptateur à fournir) et e-MECeF (dossier DGI), aucun « configuré »', (t) async {
    final m = magasin();
    await ouvrirM14(t, m, 'mecef-config', horloge: aujourdhui);
    final boitier = find.byKey(const Key('mecef:etat-mode:boitier'));
    final emecef = find.byKey(const Key('mecef:etat-mode:emecef'));
    expect(boitier, findsOneWidget);
    expect(emecef, findsOneWidget);
    expect(find.descendant(of: boitier, matching: find.text('Mode retenu')), findsOneWidget);
    expect(find.descendant(of: emecef, matching: find.text('Mode retenu')), findsNothing);
    expect(find.text('Non configuré'), findsNWidgets(2));
    expect(find.text('Configuré'), findsNothing);
    expect(find.descendant(of: boitier, matching: find.textContaining('Modèle du boîtier réglé : ELTRADE CC300')), findsOneWidget);
    expect(find.descendant(of: boitier, matching: find.textContaining('Adaptateur ELTRADE CC300 : intégration à fournir par l’éditeur du boîtier : manuel')), findsOneWidget);
    expect(find.descendant(of: emecef, matching: find.textContaining('Dossier d’interface de la DGI')), findsOneWidget);
    expect(find.descendant(of: boitier, matching: find.textContaining('sans aucun numéro simulé')), findsOneWidget);
    // Basculer sur e-MECeF déplace « Mode retenu » ; toujours rien de configuré, toujours aucun numéro.
    await toucherM14(t, find.text('Boîtier physique').first);
    await toucherM14(t, find.text('e-MECeF').last);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer le mode'));
    expect(modeMecefDuPoste(m, aujourdhui), 'emecef');
    expect(find.descendant(of: find.byKey(const Key('mecef:etat-mode:emecef')), matching: find.text('Mode retenu')), findsOneWidget);
    final f = vente(m);
    normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
    expect(m.collection('factures').parId(f['id'])!['numeroMecef'], isNull, reason: 'aucun numéro de certification simulé');
    expect(m.collection('factures').parId(f['id'])!['statutMecef'], 'en_attente');
  });

  // L'IMPRIMANTE DE CAISSE (E3761, E3762) : aucun modèle fourni pour Baguidi — « à renseigner », à valider ; la largeur sert l'aperçu du ticket.
  test('l’imprimante se LIT au registre : intégrée au boîtier par défaut (une machine, deux fonctions), papier 80 mm semé ; décochée, « à renseigner » ; une version datée règle la largeur', () {
    final m = magasin();
    final i = imprimanteCaisseDuPoste(m, aujourdhui);
    final boitier = modeleBoitierDuPoste(m, aujourdhui);
    expect(boitier, isNotNull);
    expect([i.integree, i.modele, i.interface, i.largeurMm, i.aRenseigner], [true, boitier, imprimanteInterfaceIntegree, 80, false]);
    expect(i.mentionIntegree, contains('une machine, deux fonctions'));
    final dep = serviceParametres(m, auteur: () => 'DAF', horloge: () => aujourdhui);
    expect(dep.regler(cleImprimanteIntegree, false, parametreDateIso(aujourdhui), motif: 'imprimante distincte').ok, isTrue);
    final distincte = imprimanteCaisseDuPoste(m, aujourdhui);
    expect([distincte.integree, distincte.modele, distincte.interface, distincte.aRenseigner], [false, null, null, true]);
    final m2 = magasin();
    final s = serviceParametres(m2, auteur: () => 'DAF', horloge: () => aujourdhui);
    expect(s.regler(cleImprimanteLargeurPapier, 58, parametreDateIso(aujourdhui), motif: 'essai').ok, isTrue);
    expect(imprimanteCaisseDuPoste(m2, aujourdhui).largeurMm, 58);
  });

  casM14('« Imprimante de caisse » : intégrée au boîtier (une machine, deux fonctions), 80 mm ; décochée, « à renseigner » ; réglée sous le droit « configuration MECeF », la largeur passe à l’aperçu du ticket', (t) async {
    final m = magasin();
    await ouvrirM14(t, m, 'mecef-config', horloge: aujourdhui);
    final carte = find.byKey(const Key('mecef:imprimante'));
    expect(carte, findsOneWidget);
    final boitier = modeleBoitierDuPoste(m, aujourdhui)!;
    expect(find.descendant(of: carte, matching: find.text(boitier)), findsOneWidget, reason: 'le modèle de l’imprimante est celui du boîtier');
    expect(find.descendant(of: carte, matching: find.text(imprimanteInterfaceIntegree)), findsOneWidget);
    expect(find.descendant(of: carte, matching: find.text('à renseigner')), findsNothing);
    expect(find.descendant(of: carte, matching: find.text('80 mm')), findsOneWidget);
    expect(find.descendant(of: carte, matching: find.text('À valider : à renseigner par la clinique')), findsNothing);
    expect(find.byKey(const Key('mecef:imprimante-integree')), findsOneWidget);
    expect(find.textContaining('une machine, deux fonctions'), findsWidgets);
    expect(find.byKey(const Key('mecef:boitier-imprimante')), findsOneWidget, reason: 'la carte du boîtier le dit aussi');
    expect(find.descendant(of: carte, matching: find.textContaining('aucun pilote d’impression n’est branché')), findsOneWidget);
    // Une largeur hors bornes est refusée en le disant, rien n'est écrit.
    await saisir(t, 'imprimanteLargeur', '300');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer l’imprimante'));
    expect(find.text('Largeur du papier refusée.'), findsOneWidget);
    expect(m.collection('parametres').toutes.where((v) => v['cle'] == cleImprimanteLargeurPapier && v['version'] != 0), isEmpty);
    await toucherM14(t, find.text('L’imprimante de caisse est le boîtier MECeF (une machine, deux fonctions)').first);
    await saisir(t, 'imprimanteModele', 'Modèle essai');
    await saisir(t, 'imprimanteLargeur', '58');
    await saisir(t, 'imprimanteInterface', 'USB');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer l’imprimante'));
    final i = imprimanteCaisseDuPoste(m, aujourdhui);
    expect([i.integree, i.modele, i.largeurMm, i.interface, i.aRenseigner], [false, 'Modèle essai', 58, 'USB', false]);
    expect(find.descendant(of: carte, matching: find.text('À valider : à renseigner par la clinique')), findsNothing);
    // L'aperçu du ticket prend la largeur réglée et dit l'imprimante.
    final ctx = t.element(find.byType(CarteSigh).first);
    afficherApercuTicket(ctx, EntreeTicket(operateur: 'CAISSE', numero: 'FN-1', date: aujourdhui, partPatient: 1000, total: 1000), 'T-1');
    await t.pump(const Duration(milliseconds: 600));
    expect(t.getSize(find.byKey(const Key('impression:ticket'))).width, closeTo(mm(58), 0.01));
    expect(find.text('Imprimante de caisse : Modèle essai — papier 58 mm — interface : USB'), findsOneWidget);
  });

  casM14('sans le droit « configuration MECeF », l’imprimante se lit sans se régler (commande absente)', (t) async {
    await ouvrirM14(t, magasin(), 'mecef-config', role: 'direction', horloge: aujourdhui);
    expect(find.byKey(const Key('mecef:imprimante')), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Enregistrer l’imprimante'), findsNothing);
    expect(find.byKey(const Key('kit:champ:imprimanteModele')), findsNothing);
  });

  testWidgets('sans magasin, l’aperçu du ticket garde 80 mm et dit l’imprimante « à renseigner »', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    expect(ContexteEcran.maybeOf(ctx), isNull);
    afficherApercuTicket(ctx, EntreeTicket(operateur: 'CAISSE', numero: 'FN-1', date: aujourdhui, partPatient: 1000, total: 1000), 'T-1');
    await t.pump(const Duration(milliseconds: 600));
    expect(t.getSize(find.byKey(const Key('impression:ticket'))).width, closeTo(mm(80), 0.01));
    expect(find.text('Imprimante de caisse : à renseigner — papier 80 mm — interface : à renseigner'), findsOneWidget);
  });
}
