import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// `m12-echeances` : le calendrier fiscal se SÈME à l'ouverture depuis les obligations en vigueur (jeu LIVRÉ de Baguidi : déclaration unique CNSS au 10, versement CNSS-VERS au 15 du mois suivant, non arrêté), et la
/// VUE CALENDRIER range les échéances de l'exercice par mois, l'état dit par une icône ET un libellé (jamais la couleur seule), chaque échéance ouvrant sa
/// fiche de suivi.
Magasin magasinLivre() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('l\'écran de suivi s\'ouvre PEUPLÉ sur l\'exercice 2026 : la collection, vide au départ, est semée depuis les obligations, CNSS le 10 et CNSS-VERS le 15', (t) async {
    final m = magasinLivre();
    // Le jeu livré porte désormais ses échéances (sous-lot finance) : pour éprouver le SEMIS à l'ouverture, on part d'une collection vidée.
    m.collection('echeancesFiscales').remplacerContenu(const []);
    expect(m.collection('echeancesFiscales').toutes, isEmpty);
    await ouvrirM14(t, m, 'm12-echeances');
    final e = m.collection('echeancesFiscales').actives;
    expect(e, isNotEmpty);
    expect(e.every((x) => '${x['echeance']}'.startsWith('2026')), isTrue);
    final decl = e.where((x) => x['code'] == 'CNSS').toList(), vers = e.where((x) => x['code'] == 'CNSS-VERS').toList();
    expect(decl.length, 12, reason: 'une déclaration unique par mois de l\'exercice');
    expect(vers.length, 12, reason: 'un versement des cotisations par mois de l\'exercice');
    expect(decl.every((x) => '${x['echeanceTheorique']}'.endsWith('-10')), isTrue, reason: 'la déclaration unique est due le 10 du mois suivant');
    expect(vers.every((x) => '${x['echeanceTheorique']}'.endsWith('-15')), isTrue, reason: 'le versement est dû le 15 du mois suivant (décision du 09/11/2026)');
    expect(find.text('Échéances de l’exercice 2026'), findsOneWidget);
  });

  casM14('la vue CALENDRIER : douze mois, une échéance en retard dite par son ICÔNE et son LIBELLÉ, cliquable vers le suivi', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'm12-echeances');
    await toucherM14(t, find.text('Calendrier'));
    for (var i = 1; i <= 12; i++) {
      expect(find.byKey(Key('cpc:cal:mois:$i')), findsOneWidget, reason: 'mois $i');
    }
    expect(find.text('Janvier 2026'), findsOneWidget);
    expect(find.text('Décembre 2026'), findsOneWidget);
    // au 30/10/2026, les mois écoulés portent des échéances non réglées : elles sont EN RETARD, avec libellé et icône
    expect(find.text('En retard'), findsWidgets);
    expect(find.byIcon(LucideIcons.alarmClock), findsWidgets, reason: 'l\'icône accompagne le libellé : jamais la couleur seule');
    final cnssNov = find.byKey(const Key('cpc:cal:CNSS-VERS:2026-11-16'));
    expect(cnssNov, findsOneWidget, reason: 'versement CNSS d\'octobre dû le 15/11 (dimanche), reporté au lundi 16/11');
    await toucherM14(t, cnssNov);
    expect(find.textContaining('reportée au jour ouvrable suivant'), findsOneWidget);
  });

  casM14('cfg-comptabilite (la RÉFÉRENCE) porte les DEUX lignes CNSS (le 10 et le 15 du mois suivant) : c\'est la source unique de l\'écran de suivi', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'cfg-comptabilite');
    expect(find.textContaining('le 15 du mois suivant'), findsWidgets);
    expect(find.textContaining('le 10 du mois suivant'), findsWidgets);
    expect(find.text('Déclaration unique (ITS, VPS, déclaration CNSS)'), findsWidgets);
    expect(find.text('CNSS, versement des cotisations'), findsWidgets);
  });
}
