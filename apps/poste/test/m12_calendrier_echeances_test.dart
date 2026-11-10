import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
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

  // --- Calendrier fiscal corrigé et paramétré (Baguidi, 10/11/2026) ------------------------------------------------------------------------------------

  casM14('l\'exercice suivant se génère à la demande depuis les versions en vigueur : le bouton disparaît ensuite, les dates tombent au dernier jour réel du mois', (t) async {
    final m = magasinLivre();
    final suivant = m.collection('echeancesFiscales').toutes.map((e) => int.parse('${e['exercice']}')).reduce((a, b) => a > b ? a : b) + 1;
    expect(m.collection('echeancesFiscales').toutes.any((e) => e['exercice'] == suivant), isFalse);
    await ouvrirM14(t, m, 'm12-echeances');
    final bouton = find.byKey(const Key('cpc:generer-exercice'));
    expect(bouton, findsOneWidget);
    await toucherM14(t, bouton);
    final nouvelles = m.collection('echeancesFiscales').toutes.where((e) => e['exercice'] == suivant).toList();
    expect(nouvelles.length, greaterThan(60));
    expect(nouvelles.every((e) => e['paye'] == false), isTrue, reason: 'aucune quittance inventée');
    expect(nouvelles.firstWhere((e) => e['code'] == 'ETATS-FIN')['echeanceTheorique'], '$suivant-04-30', reason: 'le 30 avril, plus le 28');
    expect(m.collection('audit').toutes.any((a) => '${a['action']}' == 'Exercice généré'), isTrue, reason: 'RG-12');
    expect(find.byKey(const Key('cpc:generer-exercice')), findsNothing, reason: 'l\'exercice existe : la commande disparaît');
  });

  casM14('les seuils de l\'écran de suivi viennent des paramètres : réglés à 7 jours, le libellé du compteur le dit', (t) async {
    final m = magasinLivre();
    final s = serviceParametres(m, auteur: () => 'Essai', horloge: () => DateTime(2026, 10, 30));
    s.semerDefauts();
    expect(s.regler('fiscal.delaiAPayerJours', 7, '2026-10-01', motif: 'Essai').ok, isTrue);
    expect(seuilsEcheance(m, DateTime(2026, 10, 30)).aPayerJours, 7);
    expect(seuilsEcheance(m, DateTime(2026, 9, 30)).aPayerJours, 10, reason: 'avant la date d\'effet : le défaut');
    await ouvrirM14(t, m, 'm12-echeances');
    expect(find.text('À payer sous 7 jours'), findsOneWidget);
    expect(find.text('À payer sous 10 jours'), findsNothing);
  });

  casM14('un poste jamais semé retombe sur les défauts : 10 jours, CCIB 300 000', (t) async {
    final m = magasinLivre();
    expect(seuilsEcheance(m, DateTime(2026, 10, 30)).aPayerJours, 10);
    expect(seuilsEcheance(m, DateTime(2026, 10, 30)).declarationJours, 30);
    expect(ccibMontant(m, DateTime(2026, 10, 30)), cfbCcibTotal);
    final s = serviceParametres(m, auteur: () => 'Essai', horloge: () => DateTime(2026, 10, 30));
    s.semerDefauts();
    expect(s.regler('fiscal.ccibMontant', 400000, '2027-01-01', motif: 'Essai').ok, isTrue);
    expect(ccibMontant(m, DateTime(2026, 12, 31)), 300000);
    expect(ccibMontant(m, DateTime(2027, 1, 1)), 400000);
  });

  casM14('une version d\'obligation à venir est VISIBLE à cfg-comptabilite, avec ce qu\'elle remplace', (t) async {
    final m = magasinLivre();
    final its = m.collection('obligationsFiscales').actives.firstWhere((o) => o['code'] == 'ITS');
    final r = cfbModifierObligation(m.collection('obligationsFiscales').actives,
        id: '${its['id']}', valeurs: {'jour': 12}, dateEffet: '2026-12-01', motif: 'Essai', acteur: 'Essai', maintenant: DateTime(2026, 10, 30), aujourdhui: DateTime(2026, 10, 30));
    expect(r.ok, isTrue, reason: '${r.refus?.motif}');
    m.collection('obligationsFiscales').mettreAJour(r.id, r.fiche!);
    m.collection('historiqueObligations').inserer(r.historique!);
    await ouvrirM14(t, m, 'cfg-comptabilite');
    final note = find.byKey(const Key('cfb:obligations-a-venir'));
    expect(note, findsOneWidget);
    expect(find.descendant(of: note, matching: find.textContaining('ITS le 12 du mois suivant à partir du 01/12/2026')), findsOneWidget);
    expect(find.descendant(of: note, matching: find.textContaining('remplace le 10 du mois suivant')), findsOneWidget);
  });
}
