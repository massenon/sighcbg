import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/m8/commun.dart' show pieceFacture;
import 'package:sigh_poste/modules/mecef/commun.dart' show pieceFactureNormalisee, paramFiscal;

import 'aide_polices.dart';

/// E5252 : un poste de production ne présente JAMAIS un numéro MECeF fabriqué comme fiscal. Le jeu livré porte des numéros « MECEF… »
/// fabriqués (marqués `mecefSimule`) : partout où l'un d'eux est montré, la mention « exemple de démonstration » l'accompagne ; une pièce sans
/// certification réelle (aucun numéro) n'affiche aucun numéro.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);
final numeroNu = RegExp(r'^MECEF\d{7}$');

/// Le jeu LIVRÉ (assets), pas le jeu de test de la maquette : c'est lui qu'un poste de production présente.
Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Les textes affichés qui sont un numéro MECeF NU (sans mention) : ce qu'un poste ne doit jamais montrer pour un numéro fabriqué.
Finder numerosNus() => find.byWidgetPredicate((w) => w is Text && numeroNu.hasMatch(w.data ?? ''));
Finder numerosMarques() =>
    find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('MECEF') && (w.data ?? '').contains(mentionMecefDemonstration));

void main() {
  setUpAll(chargerPolices);

  test('le jeu livré : TOUT numéro MECeF fabriqué est marqué simulé', () {
    final m = magasin();
    final avecNumero = m.collection('factures').toutes.where((f) => '${f['numeroMecef'] ?? ''}'.isNotEmpty).toList();
    expect(avecNumero, isNotEmpty);
    for (final f in avecNumero) {
      expect(f['mecefSimule'], true, reason: '${f['numero']} porte un numéro sans être marqué exemple de démonstration');
    }
  });

  test('numeroMecefAffiche : le réel seul, le fabriqué avec sa mention, l’absent sans numéro', () {
    expect(numeroMecefAffiche({'numeroMecef': 'MECEF1234567'}), 'MECEF1234567');
    expect(numeroMecefAffiche({'numeroMecef': 'MECEF1234567', 'mecefSimule': true}), contains(mentionMecefDemonstration));
    expect(numeroMecefAffiche({'numeroMecef': 'MECEF1234567', 'mecefSimule': true}), startsWith('MECEF1234567'));
    expect(numeroMecefAffiche({'statutMecef': 'en_attente'}), '—');
    expect(numeroMecefAffiche({'statutMecef': 'en_attente'}, 'Non transmise'), 'Non transmise');
    expect(numeroMecefAffiche({'numeroMecef': '', 'mecefSimule': true}), '—');
  });

  test('pièces imprimées : le numéro fabriqué porte l’exemple de démonstration ; une pièce sans certification n’affiche aucun numéro', () {
    final m = magasin();
    final p = paramFiscal(m);
    final base = m.collection('factures').actives.firstWhere((f) => f['proforma'] != true && '${f['numeroMecef'] ?? ''}'.isNotEmpty && f['statutMecef'] == 'valide');
    final numero = '${base['numeroMecef']}';
    List<String> textes(PieceA4 pc) => [for (final b in pc.blocs) if (b is BlocTexte) b.texte];

    final caisse = pieceFacture(base, utilisateur: 'T', edite: aujourdhui, reference: 'R');
    expect(caisse.sousTitre, contains(mentionMecefDemonstration));
    expect(textes(caisse).any((x) => x.contains('EXEMPLE DE DÉMONSTRATION')), isTrue);
    final fiscale = pieceFactureNormalisee(base, p, utilisateur: 'T', edite: aujourdhui, reference: 'R');
    expect(fiscale.sousTitre, contains(mentionMecefDemonstration));
    expect(textes(fiscale).any((x) => x.contains('EXEMPLE DE DÉMONSTRATION')), isTrue);

    final sans = {...base}..remove('numeroMecef');
    sans['statutMecef'] = 'en_attente';
    for (final pc in [pieceFacture(sans, utilisateur: 'T', edite: aujourdhui, reference: 'R'), pieceFactureNormalisee(sans, p, utilisateur: 'T', edite: aujourdhui, reference: 'R')]) {
      expect(pc.sousTitre, isNot(contains('MECEF')), reason: 'aucun numéro sur une pièce non certifiée');
      expect(pc.sousTitre, isNot(contains(numero)));
      expect(textes(pc).any((x) => x.contains(numero)), isFalse);
      expect(textes(pc).any((x) => x.contains('EXEMPLE DE DÉMONSTRATION')), isFalse, reason: 'aucun numéro, donc aucune mention à porter');
    }

    // Un numéro réel (non simulé) se lit nu : la mention ne s'applique qu'au fabriqué.
    final reel = {...base}..remove('mecefSimule');
    expect(pieceFacture(reel, utilisateur: 'T', edite: aujourdhui, reference: 'R').sousTitre, isNot(contains(mentionMecefDemonstration)));
  });

  for (final ecran in ['m8-factures', 'mecef-factures']) {
    testWidgets('« $ecran » : aucun numéro MECeF fabriqué n’est montré nu, la mention l’accompagne', (t) async {
      await ouvrir(t, magasin(), ecran);
      expect(numerosNus(), findsNothing);
      expect(numerosMarques(), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('« $ecran » : sans le marquage (numéro réel), le numéro se lit nu — la sonde distingue bien les deux', (t) async {
      final m = magasin();
      for (final f in m.collection('factures').toutes) {
        if (f['mecefSimule'] == true) m.collection('factures').mettreAJour('${f['id']}', {'mecefSimule': false});
      }
      await ouvrir(t, m, ecran);
      expect(numerosNus(), findsWidgets);
      expect(numerosMarques(), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });
  }
}
