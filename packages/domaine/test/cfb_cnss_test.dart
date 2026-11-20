// LA CNSS EN DEUX OBLIGATIONS (décision de la Direction, 09/11/2026) : la « Déclaration unique (ITS, VPS, déclaration CNSS) » au 10 du mois suivant
// (code historique `CNSS`, identifiant technique conservé) et le « versement des cotisations » au 15 (code nouveau `CNSS-VERS`), MARQUÉ NON ARRÊTÉ : le 15
// vient de guides, la CNSS écrit « dans les quinze jours qui suivent la période », à confirmer auprès d'elle.
//
// Ce que ces tests tiennent : les deux lignes existent, le jour n'est lu que dans la DONNÉE, le marquage « non arrêtée » vit sur la fiche et tombe à l'arrêt
// (date et décideur), l'arrêt est réservé à la Direction / DAF / administrateur, modifier le jour d'une obligation non arrêtée la laisse non arrêtée et
// régénère les échéances non payées (les payées ne bougent jamais), un week-end est reporté au jour ouvrable SUIVANT et jamais avancé.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

final maintenant = DateTime.utc(2026, 11, 9, 10);
final aujourdhui = DateTime(2026, 11, 9);
const acteur = 'BICHIASI Cezoune Sichovian';

CfbObligation _obl(String code) => cfbCalendrierFiscal.firstWhere((o) => o.code == code);

void appliquer(CfbEcritureObligation r, List<M> obligations, List<M> historique) {
  expect(r.ok, isTrue, reason: '${r.refus}');
  if (r.historique != null) historique.add({...r.historique!, 'id': 'HOB${historique.length + 1}'});
  final i = obligations.indexWhere((o) => '${o['id']}' == r.id);
  obligations[i] = r.fiche!;
}

void main() {
  group('le calendrier : deux lignes, pas une', () {
    test('CNSS est la déclaration unique au 10 ; CNSS-VERS le versement au 15, avec les deux parts dans la note', () {
      final decl = _obl('CNSS'), vers = _obl('CNSS-VERS');
      expect(decl.libelle, 'Déclaration unique (ITS, VPS, déclaration CNSS)');
      expect([decl.periodicite, decl.jour], ['mensuelle', 10]);
      expect(decl.nonArretee, isFalse, reason: 'la déclaration unique au 10 est celle de la DGI : rien à arrêter');
      expect(vers.libelle, 'CNSS, versement des cotisations');
      expect([vers.periodicite, vers.jour, vers.part], ['mensuelle', 15, 100]);
      expect(vers.nonArretee, isTrue);
      expect(vers.note, contains('16,4 %'));
      expect(vers.note, contains('3,6 %'));
      expect(vers.motifNonArret, contains('CNSS'), reason: 'le motif dit ce qu\'il faut confirmer, et auprès de qui');
      // un seul identifiant par ligne : aucun code ne disparaît (paie M11, alertes, jeu)
      expect(cfbCalendrierFiscal.where((o) => o.code.startsWith('CNSS')).map((o) => o.code), ['CNSS', 'CNSS-VERS']);
      expect(cfbCalendrierFiscal.where((o) => o.nonArretee).map((o) => o.code), ['CNSS-VERS'], reason: 'le reste du calendrier est confirmé');
    });

    test('la semence : la fiche du versement porte le statut non arrêté, celle de la déclaration n\'en porte aucun ; les deux ont la famille CNSS', () {
      final s = cfbSemenceObligations();
      final vers = s.firstWhere((f) => f['code'] == 'CNSS-VERS'), decl = s.firstWhere((f) => f['code'] == 'CNSS');
      expect(vers['statutArret'], 'non_arrete');
      expect(vers['dateArret'], isNull);
      expect(vers['decideurArret'], isNull);
      expect(cfbObligationNonArretee(vers), isTrue);
      expect(decl.containsKey('statutArret'), isFalse, reason: 'l\'absence du champ vaut « arrêtée » : le calendrier confirmé reste byte-identique');
      expect(cfbObligationNonArretee(decl), isFalse);
      expect([vers['famille'], decl['famille']], ['CNSS', 'CNSS']);
      // la fiche relue sur la forme du calendrier garde le marquage
      expect(cfbObligationDepuisFiche(vers).nonArretee, isTrue);
      expect(cfbObligationDepuisFiche(decl).nonArretee, isFalse);
    });

    test('un exercice engendre douze déclarations au 10 et douze versements au 15, jamais avancés : un week-end passe au jour ouvrable SUIVANT', () {
      final e = cfbGenEcheances(2026, obligationsFixes: cfbSemenceObligations(), aujourdhui: aujourdhui, sansReglement: true);
      final decl = e.where((x) => x['code'] == 'CNSS').toList(), vers = e.where((x) => x['code'] == 'CNSS-VERS').toList();
      expect([decl.length, vers.length, e.length], [12, 12, 75]);
      expect(decl.every((x) => '${x['echeanceTheorique']}'.endsWith('-${_obl('CNSS').jour}')), isTrue);
      expect(vers.every((x) => '${x['echeanceTheorique']}'.endsWith('-${_obl('CNSS-VERS').jour}')), isTrue);
      // 15/11/2026 est un dimanche : le versement d'octobre est dû le lundi 16/11 ; 15/08/2026 est un samedi : lundi 17/08
      final nov = vers.firstWhere((x) => x['echeanceTheorique'] == '2026-11-15');
      expect([nov['echeance'], nov['reportee']], ['2026-11-16', true]);
      final aout = vers.firstWhere((x) => x['echeanceTheorique'] == '2026-08-15');
      expect([aout['echeance'], aout['reportee']], ['2026-08-17', true]);
      for (final x in e) {
        expect(DateTime.parse('${x['echeance']}').isBefore(DateTime.parse('${x['echeanceTheorique']}')), isFalse, reason: '${x['code']} ne s\'avance jamais');
        expect(DateTime.parse('${x['echeance']}').weekday, lessThan(6), reason: '${x['code']} tombe un jour ouvrable');
      }
    });
  });

  group('arrêter la date (date et décideur)', () {
    List<M> magasin() => [...cfbSemenceObligations()];

    CfbEcritureObligation arreter(List<M> o, {String? role = 'direction', String? decideur = 'La Direction', Object? date, bool fileul = false, String code = 'CNSS-VERS'}) =>
        cfbArreterObligation(o, code: code, role: role, decideur: decideur, dateArret: date, acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui, fileul: fileul);

    test('refus nommés : rôle non habilité, fileul, obligation inconnue, déjà arrêtée, décideur absent, date future', () {
      final o = magasin();
      for (final role in ['comptable', 'aide_comptable', 'caissier', 'medecin', null]) {
        expect(arreter(o, role: role).refus!.code, 'VALIDATION_RESERVEE', reason: '$role');
      }
      expect(arreter(o, fileul: true).refus!.code, 'FILEUL_LECTURE_SEULE');
      expect(arreter(o, code: 'XXX').refus!.code, 'OBLIGATION_INCONNUE');
      expect(arreter(o, code: 'CNSS').refus!.code, 'ARRET_SANS_OBJET', reason: 'la déclaration unique est déjà arrêtée (confirmée) : rien à arrêter');
      expect(arreter(o, decideur: '  ').refus!.code, 'DECIDEUR_REQUIS');
      expect(arreter(o, date: '2026-12-01').refus!.code, 'DATE_ARRET_FUTURE');
      for (final role in cfbRolesValidation) {
        expect(arreter(o, role: role).ok, isTrue, reason: role);
      }
    });

    test('l\'arrêt écrit la date et le décideur, retire le marquage, et NE CHANGE ni le jour ni aucune échéance', () {
      final o = magasin();
      final r = arreter(o, date: '2026-11-09');
      expect(r.ok, isTrue);
      expect(r.historique, isNull, reason: 'arrêter n\'est pas une version datée : aucune copie à l\'historique');
      final f = r.fiche!;
      expect([f['statutArret'], f['dateArret'], f['decideurArret']], ['arrete', '2026-11-09', 'La Direction']);
      expect(f['jour'], _obl('CNSS-VERS').jour, reason: 'le jour reste celui de la donnée');
      expect(cfbObligationNonArretee(f), isFalse);
      appliquer(r, o, []);
      expect(o.where(cfbObligationNonArretee), isEmpty, reason: 'plus aucune date non arrêtée : le marquage disparaît');
      expect(cfbObligationDepuisFiche(o.firstWhere((x) => x['code'] == 'CNSS-VERS')).nonArretee, isFalse);
      // une seconde fois : refusée
      expect(arreter(o).refus!.code, 'ARRET_SANS_OBJET');
    });
  });

  group('modifier le jour avec date d\'effet : les échéances non payées sont régénérées, le marquage suit l\'arrêt', () {
    test('le jour passe de 15 à 16 au 01/12/2026 : novembre (payé) conservé, décembre régénéré ; la fiche reste NON ARRÊTÉE', () {
      final obl = <M>[...cfbSemenceObligations()], hist = <M>[];
      final ech = cfbGenEcheances(2026, obligationsFixes: cfbSemenceObligations(), aujourdhui: aujourdhui, sansReglement: true);
      final nov = ech.firstWhere((e) => e['code'] == 'CNSS-VERS' && e['echeanceTheorique'] == '2026-11-15');
      nov['paye'] = true;
      nov['reference'] = 'QUIT-CNSS-VERS-2026-11';
      final r = cfbModifierObligation(obl, code: 'CNSS-VERS', valeurs: {'jour': 16}, dateEffet: '2026-12-01', motif: 'La CNSS fixe le 16', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui);
      appliquer(r, obl, hist);
      final fiche = obl.firstWhere((o) => o['code'] == 'CNSS-VERS');
      expect([fiche['jour'], fiche['dateEffet'], fiche['valideLe']], [16, '2026-12-01', null]);
      expect(cfbObligationNonArretee(fiche), isTrue, reason: 'modifier le jour n\'arrête rien : la Direction n\'a rien décidé');
      expect(hist.single['jour'], 15, reason: 'la version sortante reste à l\'historique');
      final reg = cfbRegenererEcheances(ech, code: 'CNSS-VERS', dateEffet: '2026-12-01', auteur: acteur, maintenant: maintenant, obligations: obl, historique: hist);
      expect([reg.conservees, reg.archivees, reg.creees], [0, 1, 1], reason: 'novembre est antérieur à la date d\'effet : seul décembre est régénéré');
      expect(reg.avant, ['2026-12-15']);
      expect(reg.apres, ['2026-12-16']);
      expect(reg.echeances.firstWhere((e) => e['echeanceTheorique'] == '2026-11-15' && e['code'] == 'CNSS-VERS')['reference'], 'QUIT-CNSS-VERS-2026-11', reason: 'une quittance ne bouge jamais');
      // la déclaration unique n'est pas touchée
      expect(reg.echeances.where((e) => e['code'] == 'CNSS' && e['statut'] == 'archive'), isEmpty);
    });

    test('un jour ARRÊTÉ puis CHANGÉ perd son arrêt (la nouvelle valeur n\'a pas été décidée) ; un autre champ le laisse intact', () {
      final obl = <M>[...cfbSemenceObligations()], hist = <M>[];
      appliquer(cfbArreterObligation(obl, code: 'CNSS-VERS', role: 'da', decideur: 'La Direction', dateArret: '2026-11-09', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui), obl, hist);
      // une correction de la seule note : l'arrêt tient
      appliquer(cfbModifierObligation(obl, code: 'CNSS-VERS', valeurs: {'note': 'Part patronale 16,4 %, ouvrière 3,6 %.'}, dateEffet: '2026-11-09', motif: 'Précision', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui), obl, hist);
      expect(cfbObligationNonArretee(obl.firstWhere((o) => o['code'] == 'CNSS-VERS')), isFalse);
      expect(obl.firstWhere((o) => o['code'] == 'CNSS-VERS')['decideurArret'], 'La Direction');
      // le jour change : l'arrêt tombe, la date redevient « à valider », et le motif le dit
      appliquer(cfbModifierObligation(obl, code: 'CNSS-VERS', valeurs: {'jour': 20}, dateEffet: '2026-12-01', motif: 'Nouvelle date', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui), obl, hist);
      final f = obl.firstWhere((o) => o['code'] == 'CNSS-VERS');
      expect(cfbObligationNonArretee(f), isTrue);
      expect([f['dateArret'], f['decideurArret']], [null, null]);
      expect(f['motifNonArret'], contains('modifié'));
    });

    test('la déclaration unique (CNSS, arrêtée d\'origine) se modifie sans jamais devenir « non arrêtée »', () {
      final obl = <M>[...cfbSemenceObligations()], hist = <M>[];
      appliquer(cfbModifierObligation(obl, code: 'CNSS', valeurs: {'jour': 12}, dateEffet: '2026-11-09', motif: 'DGI', acteur: acteur, maintenant: maintenant, aujourdhui: aujourdhui), obl, hist);
      expect(cfbObligationNonArretee(obl.firstWhere((o) => o['code'] == 'CNSS')), isFalse);
    });
  });

  group('la validation de la liste couvre les deux lignes', () {
    test('valider les obligations vise vingt et une fiches actives (vingt obligations et les paramètres ORTB) et ne touche pas au marquage d\'arrêt (valider n\'est pas arrêter)', () {
      final obl = <M>[...cfbSemenceObligations()];
      final r = cfbValiderObligations(obl, role: 'da', acteur: acteur, maintenant: maintenant);
      expect(r.nombre, 21, reason: '20 obligations et la fiche des paramètres ORTB');
      for (var i = 0; i < obl.length; i++) {
        if (r.ids.contains('${obl[i]['id']}')) obl[i] = {...obl[i], ...r.patch};
      }
      expect(cfbObligationNonArretee(obl.firstWhere((o) => o['code'] == 'CNSS-VERS')), isTrue, reason: 'la validation de la liste n\'arrête pas une date');
    });
  });
}
