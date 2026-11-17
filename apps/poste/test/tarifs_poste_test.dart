import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';

/// LE RÉFÉRENTIEL DE PRIX AU POSTE (lot T6, étape 2) : les deux collections du jeu, les gardes du magasin (une version est IMMUABLE, les listes de lecture ne
/// s'éditent plus pour un prix), la projection de lecture et sa garde de parité, la reprise d'un magasin d'AVANT le référentiel, et le circuit tenu sur le magasin
/// (mère : écrit ; fileul : dépose une demande, la mère applique sous le rôle de son auteur).
final auj = DateTime(2026, 10, 30, 10);
String plus(int n) => tarIso(auj.add(Duration(days: n)));

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

TarifsPoste poste(Magasin m, String role, {String nom = 'Agent', bool fileul = false, bool editer = true, String etiquette = 'P', DroitsGestes Function()? gestes}) => TarifsPoste(m,
    gestes: gestes,
    role: role,
    auteur: () => nom,
    fileul: fileul,
    peutEditerEcran: editer,
    // Décider et dater dans le passé sont des GESTES de la matrice (`DroitsGestes`, origine sans fiche) : aucun nom de rôle ici ni dans le moteur.
    libelles: const {'da': 'Directrice de l’Administration et des Finances (DAF)', 'direction': 'Direction / Gérance', 'admin': 'Administrateur système'},
    horloge: () => auj,
    etiquette: etiquette);

DemandeProposition prop(String code, num prix, {String? date, bool valider = false}) =>
    DemandeProposition(code: code, prixNonAssure: prix, etatAssure: 'unique', dateEffet: date ?? plus(3), motif: 'Test TAR', valider: valider);

/// Un code d'ACTE qu'aucune pièce du jeu livré ne porte, au sens du contrôle d'usage lui-même (le jeu est daté de novembre, après le jour fixé de ces tests).
String codeLibre(Magasin m, [int rang = 0]) {
  final h = TarifsPoste.lire(m);
  final pieces = TarifsPoste.pieces(m);
  return [
    for (final p in h.tarifs)
      if (p['codeActe'] != null && p['famille'] != 'HOSPITALISATION' && tarUsages(p, '2000-01-01', pieces, aujourdhui: '2026-10-30').isEmpty) '${p['code']}'
  ].elementAt(rang);
}

void main() {
  group('le jeu livré porte le référentiel', () {
    test('206 prestations, 206 versions 1 ; l\'accesseur lit les trois espaces de codes', () {
      final m = jeu();
      final h = TarifsPoste.lire(m);
      expect([h.tarifs.length, h.versions.length], [206, 206]);
      expect(h.versions.every((v) => v['statut'] == 'valide' && v['version'] == 1), isTrue, reason: 'la valeur facturée aujourd\'hui est la version 1 : aucune proposition inventée (aucune grille imprimée)');
      expect(TarifsPoste.prix(m, 'SIV', null, false, aujourdhui: auj).montant, TarifsPoste.prix(m, 'SO02', null, false, aujourdhui: auj).montant, reason: 'SIV est l\'alias de grille de SO02');
      expect(TarifsPoste.prix(m, 'CERT-APT', null, false, aujourdhui: auj).montant, 7000, reason: 'le doublon de code de grille : la première ligne, seule lue jusqu\'ici');
      expect(TarifsPoste.prixAnalyse(m, 'L01', aujourdhui: auj), 2000);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, assure: true), 3000);
      expect(TarifsPoste.prixGrille(m, 'IMG-ECHO-PEL', aujourdhui: auj, assure: false).montant, 9000);
      final actes = TarifsPoste.actes(m, aujourdhui: auj);
      expect(actes.length, 78, reason: 'les 78 actes du jeu livré');
      expect(actes.firstWhere((a) => a['code'] == 'MG01')['prix'], 5000);
    });

    test('la projection de lecture : 39 lignes LABO au démarrage (la grille héritée, fusionnée avec ses analyses), puis 0 écart de parité ; aucune ligne de journal', () {
      final m = jeu();
      final avant = m.collection('audit').toutes.length;
      expect(TarifsPoste.parites(m, auj).length, 39, reason: 'les 39 lignes LABO de la grille héritée, fusionnées avec leur analyse');
      expect(TarifsPoste.projeter(m, auj), 39);
      expect(TarifsPoste.parites(m, auj), isEmpty, reason: 'garde de parité : la projection dit ce que le référentiel dit');
      expect(TarifsPoste.projeter(m, auj), 0, reason: 'idempotente');
      expect(m.collection('audit').toutes.length, avant, reason: 'ce n\'est pas un geste : aucune ligne de journal');
      expect(m.collection('catalogueTarifs').actives.firstWhere((t) => t['code'] == 'LAB-AKOP')['prixNonAssure'], 2000);
    });

    test('la projection suit le jour : une version à venir bascule le jour dit, sans tâche de minuit', () {
      final m = jeu();
      final t = poste(m, 'da', nom: 'DAF');
      expect(t.proposer(prop('MG01', 5500, date: plus(2), valider: true)).ok, isTrue);
      expect(m.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01')['prix'], 5000, reason: 'à venir : le prix d\'aujourd\'hui ne bouge pas');
      expect(TarifsPoste.projeterSiNouveauJour(m, auj), 0);
      expect(TarifsPoste.projeterSiNouveauJour(m, auj.add(const Duration(days: 2))), greaterThan(0));
      expect(m.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01')['prix'], 5500);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: plus(1)), 5000);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: plus(2)), 5500);
    });
  });

  group('les lecteurs en LISTE résolvent à la date de la PIÈCE, jamais à celle de l\'horloge (sonde de la mutation « prix d\'aujourd\'hui »)', () {
    test('actes, analyses, types de chambre, entrée de grille et grille : l\'ancien prix la veille de la date d\'effet, le nouveau le jour dit', () {
      final m = jeu();
      final t = poste(m, 'da', nom: 'DAF');
      final h = TarifsPoste.lire(m);
      // Un acte, une chambre et une ligne de grille : des versions validées à venir (J+5).
      final grilleEcho = '${h.parGrille['IMG-ECHO-PEL']!['code']}';
      for (final code in ['MG01', 'HO01', grilleEcho]) {
        expect(t.proposer(prop(code, 77777, date: plus(5), valider: true)).ok, isTrue, reason: code);
      }
      // Une analyse : une version validée à J+5 (aucune grille imprimée n'existe : aucune proposition n'attend au départ).
      expect(h.versionsDe('L01').length, 1, reason: 'aucune proposition inventée');
      expect(t.proposer(prop('L01', 2600, date: plus(5), valider: true)).ok, isTrue);
      final nouveauL01 = TarifsPoste.lire(m).versionsDe('L01').last['prixNonAssure'];
      expect(nouveauL01, 2600);
      for (final (jour, attendu) in [(plus(4), false), (plus(5), true)]) {
        final nom = attendu ? 'le jour dit' : 'la veille';
        expect(TarifsPoste.actes(m, aujourdhui: auj, date: jour).firstWhere((a) => a['code'] == 'MG01')['prix'], attendu ? 77777 : 5000, reason: 'actes, $nom');
        expect(TarifsPoste.analyses(m, aujourdhui: auj, date: jour).firstWhere((a) => a['code'] == 'L01')['prix'], attendu ? nouveauL01 : 2000, reason: 'analyses, $nom');
        expect(TarifsPoste.typesChambre(m, aujourdhui: auj, date: jour).first['tarif'], attendu ? 77777 : isNot(77777), reason: 'chambres, $nom');
        expect(TarifsPoste.entreeGrille(m, 'IMG-ECHO-PEL', aujourdhui: auj, date: jour)!['prixNonAssure'], attendu ? 77777 : 9000, reason: 'entrée de grille, $nom');
        expect(TarifsPoste.grille(m, aujourdhui: auj, date: jour, famille: 'IMAGERIE').firstWhere((e) => e['code'] == 'IMG-ECHO-PEL')['prixNonAssure'], attendu ? 77777 : 9000, reason: 'grille, $nom');
      }
      // Sans date : le jour de l'horloge fournie (le 30/10), donc l'ancien prix.
      expect(TarifsPoste.actes(m, aujourdhui: auj).firstWhere((a) => a['code'] == 'MG01')['prix'], 5000);
    });
  });

  group('les gardes du magasin tiennent la règle AU MOTEUR (masquer un bouton ne protège rien)', () {
    test('une version est IMMUABLE : le prix, l\'archivage et le retrait d\'une version valide sont refusés', () {
      final m = jeu();
      final col = m.collection('versionsTarif');
      expect(() => col.mettreAJour('SO12@origine@1', {'prixNonAssure': 1}), throwsA(isA<EcritureRefusee>()));
      expect(() => col.archiver('SO12@origine@1'), throwsA(isA<EcritureRefusee>()));
      expect(() => col.mettreAJour('SO12@origine@1', {'statut': 'retire'}), throwsA(isA<EcritureRefusee>()));
      expect(() => col.inserer({'id': 'SO12@origine@1', 'code': 'SO12', 'version': 1}), throwsA(isA<EcritureRefusee>()), reason: 'une version ne se réécrit pas par une insertion');
      final prop1 = poste(m, 'da', nom: 'DAF').proposer(prop('SO12', 1111, date: plus(4)));
      final id = prop1.version!['id'];
      expect(() => col.mettreAJour(id, {'statut': 'refuse', 'motifDecision': 'x'}), returnsNormally, reason: 'seule une proposition se décide');
      expect(() => col.mettreAJour(id, {'statut': 'valide'}), throwsA(isA<EcritureRefusee>()), reason: 'une version refusée ne redevient pas valide');
      expect(m.collection('audit').toutes.where((a) => a['action'] == 'Écriture refusée').length, greaterThanOrEqualTo(5), reason: 'RG-12 : chaque refus est journalisé');
    });

    test('`actes`, `analyses` et `catalogueTarifs` ne s\'éditent plus pour un prix ; le libellé reste libre', () {
      final m = jeu();
      final acte = m.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01');
      expect(() => m.collection('actes').mettreAJour(acte['id'], {'prix': 9999}), throwsA(isA<EcritureRefusee>()));
      expect(() => m.collection('actes').mettreAJour(acte['id'], {'secteur': 'Autre secteur'}), returnsNormally);
      final ana = m.collection('analyses').actives.first;
      expect(() => m.collection('analyses').mettreAJour(ana['id'], {'prix': 1}), throwsA(isA<EcritureRefusee>()));
      final t = m.collection('catalogueTarifs').actives.first;
      expect(() => m.collection('catalogueTarifs').mettreAJour(t['id'], {'prixNonAssure': 1}), throwsA(isA<EcritureRefusee>()));
      try {
        m.collection('actes').mettreAJour(acte['id'], {'prix': 9999});
      } on EcritureRefusee catch (e) {
        expect(e.motif, contains('Tarifs et prix'));
      }
    });
  });

  group('le circuit tenu sur le magasin de la mère', () {
    test('propose, décide, journalise une ligne par transition, projette ; le retour part à l\'auteur', () {
      final m = jeu();
      final comptable = poste(m, 'comptable', nom: 'Un comptable');
      final r = comptable.proposer(prop('MG01', 5200, date: plus(1)));
      expect(r.ok, isTrue);
      final id = r.version!['id'] as String;
      expect(r.version!['proposeRole'], 'comptable');
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: plus(1)), 5000, reason: 'une proposition ne change RIEN');
      expect(poste(m, 'comptable').decider(id, 'oui').refus!.code, 'VALIDATION_RESERVEE');
      final daf = poste(m, 'da', nom: 'La DAF');
      expect(daf.decider(id, 'non', motif: '').refus!.code, 'MOTIF_REQUIS');
      final oui = daf.decider(id, 'oui');
      expect(oui.ok, isTrue);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: plus(1)), 5200);
      final lignes = m.collection('audit').toutes.where((a) => '${a['action']}'.startsWith('Changement de prix')).map((a) => a['action']).toList();
      expect(lignes, containsAll(['Changement de prix : proposition', 'Changement de prix : validation']));
      // Le retour à l'auteur : une notification adressée au poste du comptable.
      final n = m.collection('notifications').toutes.where((x) => x['type'] == 'prix_decide').toList();
      expect(n.length, 1);
      expect([n.first['poste'], n.first['destinataire']], ['comptable', 'Un comptable']);
      expect(n.first['libelle'], 'Votre changement de prix MG01 a été accepté');
    });

    test('« Valider » en un geste lève le marquage « tarif d\'attente » (version et fiche de l\'analyse) et projette', () {
      final m = jeu();
      // L05 : une analyse SANS ligne de grille (donc sans proposition en attente), au tarif d'attente de la collection `analyses`.
      final fiche = m.collection('analyses').actives.firstWhere((a) => a['code'] == 'L05');
      expect(fiche['tarifProvisoire'], true);
      final prix = (fiche['prix'] as num).toInt();
      final daf = poste(m, 'da', nom: 'La DAF');
      final r = daf.proposer(prop('L05', prix + 100, date: plus(0), valider: true));
      expect(r.ok, isTrue, reason: '${r.refus}');
      expect(r.valideeEnUnGeste, isTrue);
      expect(m.collection('analyses').parId(fiche['id'])!['prix'], prix + 100, reason: 'la projection est refaite à la décision');
      final versions = TarifsPoste.lire(m).versionsDe('L05');
      expect(versions.first['provisoire'], false, reason: 'le Oui arrête le marquage porté par la version 1');
      expect(versions.first['arretePar'], 'La DAF');
      expect(m.collection('analyses').parId(fiche['id'])!['validePar'], 'La DAF', reason: 'la fiche de la famille du centre des validations est validée du même geste');
    });

    test('la durée de validité d\'une pro-forma : 30 jours par défaut, réglage en base, journalisé, réservé', () {
      final m = jeu();
      final daf = poste(m, 'da', nom: 'DAF');
      expect(daf.validiteProformaJours(), 30);
      expect(poste(m, 'caissier').definirValiditeProforma(10).refus!.code, 'REGLAGE_RESERVE');
      expect(daf.definirValiditeProforma('x').refus!.code, 'DUREE_INVALIDE');
      final r = daf.definirValiditeProforma(10, motif: 'test');
      expect([r.ok, r.valeur!.avant], [true, 30]);
      expect(daf.validiteProformaJours(), 10);
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Validité d’une pro-forma'), isTrue);
    });
  });

  group('un fileul ne peut pas écrire une version : il dépose, la mère applique', () {
    test('la proposition d\'un fileul : aucune version écrite localement, une demande déposée ; la mère l\'applique sous le rôle de son auteur', () {
      final mere = jeu(), fileul = jeu();
      final f = poste(fileul, 'direction', nom: 'La Direction', fileul: true, etiquette: 'F');
      final avant = fileul.collection('versionsTarif').toutes.length;
      final r = f.proposer(prop('MG01', 5300, date: plus(2)));
      expect(r.ok && r.depose, isTrue, reason: '${r.refus}');
      expect(fileul.collection('versionsTarif').toutes.length, avant, reason: 'famille R : la mère seule écrit une version');
      final dem = fileul.collection('propositionsTarif').toutes.single;
      expect([dem['genre'], dem['etat'], dem['demandeRole'], dem['demandePar']], ['proposition', 'deposee', 'direction', 'La Direction']);
      // Le fileul qui tenterait d'écrire quand même est refusé (garde « réglé sur la mère » posée par l'application de la configuration).
      // La demande voyage (le pont) ; la mère l'applique.
      mere.collection('propositionsTarif').appliquerDistante({...dem});
      final m = poste(mere, 'admin', nom: 'Poste mère', etiquette: 'M');
      expect(m.appliquerDemandes(), 1);
      final traitee = mere.collection('propositionsTarif').toutes.single;
      expect([traitee['etat'], traitee['traitePar']], ['appliquee', 'Poste mère']);
      final v = mere.collection('versionsTarif').toutes.firstWhere((x) => x['id'] == traitee['versionId']);
      expect([v['statut'], v['proposePar'], v['proposeRole']], ['propose', 'La Direction', 'direction']);
      expect(m.appliquerDemandes(), 0, reason: 'une demande n\'est appliquée qu\'une fois');
      // La décision de la Direction (fileul) est elle aussi une demande, appliquée par la mère sous le rôle `direction`.
      mere.collection('versionsTarif').toutes; // la mère porte la version ; le fileul la reçoit par la configuration
      fileul.collection('versionsTarif').appliquerDistante({...v});
      final d = f.decider('${v['id']}', 'oui');
      expect(d.ok && d.depose, isTrue, reason: '${d.refus}');
      expect(fileul.collection('versionsTarif').parId(v['id'])!['statut'], 'propose', reason: 'rien n\'est décidé localement');
      final demD = fileul.collection('propositionsTarif').toutes.firstWhere((x) => x['genre'] == 'decision');
      mere.collection('propositionsTarif').appliquerDistante({...demD});
      expect(m.appliquerDemandes(), 1);
      expect(mere.collection('versionsTarif').parId(v['id'])!['statut'], 'valide');
      expect(mere.collection('versionsTarif').parId(v['id'])!['roleDecision'], 'direction');
      expect(TarifsPoste.prixActe(mere, 'MG01', aujourdhui: auj, date: plus(2)), 5300);
    });

    test('la mère REFAIT les contrôles : une demande qui ne passe pas est REFUSÉE avec son code, et le dit au fileul', () {
      final mere = jeu();
      mere.collection('propositionsTarif').appliquerDistante({
        'id': 'DTF1', 'statut': 'actif', 'genre': 'proposition', 'etat': 'deposee', 'demandePar': 'Un caissier', 'demandeRole': 'caissier', 'demandeLe': plus(0),
        'code': 'MG01', 'prixNonAssure': 5400, 'etatAssure': 'unique', 'dateEffet': plus(2), 'motif': 'x',
      });
      mere.collection('propositionsTarif').appliquerDistante({
        'id': 'DTF2', 'statut': 'actif', 'genre': 'proposition', 'etat': 'deposee', 'demandePar': 'Un autre', 'demandeRole': 'comptable', 'demandeLe': plus(0),
        'code': 'MG02', 'prixNonAssure': 0, 'etatAssure': 'unique', 'dateEffet': plus(2), 'motif': 'x', 'valider': true,
      });
      // La mère n'accorde le droit d'éditer qu'aux rôles qu'elle connaît : un caissier, un comptable ne proposent pas, même si la demande le dit.
      final m = TarifsPoste(mere, role: 'admin', auteur: () => 'Poste mère', peutEditerPour: (r) => r == 'comptable', horloge: () => auj);
      expect(m.appliquerDemandes(), 2);
      expect(mere.collection('propositionsTarif').parId('DTF1')!['resultatCode'], 'PROPOSITION_RESERVEE');
      expect(mere.collection('propositionsTarif').parId('DTF2')!['resultatCode'], 'VALIDATION_RESERVEE', reason: 'valider en un geste n\'est pas modifier la fiche');
      expect(mere.collection('versionsTarif').toutes.length, 206, reason: 'aucune version écrite');
    });

    test('sur un fileul, « Oui à tout » dépose une demande par ligne : jamais sans la comparaison affichée', () {
      final fileul = jeu();
      final f = poste(fileul, 'direction', nom: 'La Direction', fileul: true, etiquette: 'F');
      expect(f.deciderTous(comparaisonAffichee: false).refus!.code, 'COMPARAISON_REQUISE');
      // Trois propositions en attente (reçues de la mère avec la configuration).
      for (final (i, code) in ['MG01', 'MG02', 'MG03'].indexed) {
        fileul.collection('versionsTarif').appliquerDistante({
          'id': '$code@a-dater@${i + 2}', 'code': code, 'version': i + 2, 'prixNonAssure': 20000 + i, 'etatAssure': 'unique', 'origine': 'ecran', 'statut': 'propose',
          'aDater': true, 'proposePar': 'Un agent', 'proposeRole': 'da', 'proposeLe': plus(0), 'motif': 'Test TAR',
        });
      }
      final ids = [for (final v in fileul.collection('versionsTarif').toutes.where((v) => v['statut'] == 'propose')) '${v['id']}'];
      final r = f.deciderTous(comparaisonAffichee: true, ids: ids, dateEffet: plus(5));
      expect(r.ok, isTrue);
      expect(fileul.collection('propositionsTarif').toutes.length, 3);
      expect(fileul.collection('versionsTarif').toutes.where((v) => v['statut'] == 'valide' && v['origine'] == 'ecran').length, 0, reason: 'rien n\'est décidé localement');
      expect(poste(fileul, 'caissier', fileul: true, editer: false).deciderTous(comparaisonAffichee: true, ids: ids).refus!.code, 'VALIDATION_RESERVEE');
    });
  });

  group('deux droits distincts, tenus par la MATRICE (aucun nom de rôle en dur)', () {
    DroitsGestes avecFiches(Magasin m) => DroitsGestes(fiches: m.collection('rbac').actives);

    test('proposer = éditer l\'écran ; décider = le geste « tarif_decider » : une fiche de rôle l\'accorde ou le retire, à chaud', () {
      final m = jeu();
      final p = poste(m, 'stock', nom: 'Un gestionnaire', gestes: () => avecFiches(m)).proposer(prop('MG03', 11000, date: plus(60)));
      expect(p.ok, isTrue, reason: 'qui édite propose');
      final id = p.version!['id'] as String;
      expect(poste(m, 'stock', gestes: () => avecFiches(m)).decider(id, 'oui').refus!.code, 'VALIDATION_RESERVEE', reason: 'éditer ne suffit pas à décider');
      // La clinique accorde le geste au gestionnaire de stock et le retire à la DAF : la fiche de rôle, rien d'autre.
      m.collection('rbac').inserer({'id': 'RBAC-S', 'role': 'stock', 'statut': 'actif', 'droitsGestes': {gesteDeciderPrix: true}});
      m.collection('rbac').inserer({'id': 'RBAC-D', 'role': 'da', 'statut': 'actif', 'droitsGestes': {gesteDeciderPrix: false}});
      expect(poste(m, 'da', gestes: () => avecFiches(m)).decider(id, 'oui').refus!.code, 'VALIDATION_RESERVEE', reason: 'la fiche retire le geste à la DAF');
      expect(poste(m, 'stock', gestes: () => avecFiches(m)).decider(id, 'oui').ok, isTrue, reason: 'la fiche accorde le geste au gestionnaire de stock');
    });

    test('l\'info-bulle de la date passée nomme les rôles que la MATRICE désigne (la DAF et la Direction d\'origine, pas l\'administrateur) et suit une fiche', () {
      final m = jeu();
      final t = poste(m, 'caissier', gestes: () => avecFiches(m));
      expect(t.profilsDatePassee, ['Directrice de l’Administration et des Finances (DAF)', 'Direction / Gérance']);
      m.collection('rbac').inserer({'id': 'RBAC-A', 'role': 'admin', 'statut': 'actif', 'droitsGestes': {gesteDaterPrixPasse: true}});
      expect(t.profilsDatePassee, contains('Administrateur système'));
      expect(t.profilsDecider, contains('Administrateur système'));
    });

    test('date passée : refusée sans la case ou pour un rôle sans le geste, permise à la DAF avec la case et le motif, refusée dès qu\'une pièce a utilisé la prestation', () {
      final m = jeu();
      final libre = codeLibre(m), libre2 = codeLibre(m, 1);
      final daf = poste(m, 'da', nom: 'La DAF');
      DemandeProposition passee(String code, num prix, {bool case_ = true}) =>
          DemandeProposition(code: code, prixNonAssure: prix, etatAssure: 'unique', dateEffet: plus(-1), motif: 'Erreur de saisie constatée', datePassee: case_);
      expect(daf.proposer(passee(libre, 10500, case_: false)).refus!.code, 'DATE_PASSEE');
      expect(poste(m, 'admin').proposer(passee(libre, 10500)).refus!.code, 'DATE_PASSEE_RESERVEE', reason: 'l\'administrateur décide mais ne date pas dans le passé');
      final ok = daf.proposer(passee(libre, 10500));
      expect(ok.ok, isTrue, reason: '${ok.refus}');
      m.collection('factures').inserer({
        'statut': 'actif', 'numero': 'FC-9', 'date': '${plus(-1)}T09:00:00', 'lignes': [{'acteCode': libre2, 'prixUnitaire': 1000, 'quantite': 1, 'statutPaiement': 'du'}]
      });
      expect(daf.proposer(passee(libre2, 31000)).refus!.code, 'TARIF_DEJA_UTILISE');
    });

    test('la ligne IMPAYÉE est figée à la prescription : une pièce du jour qui porte la prestation ferme la date d\'effet d\'aujourd\'hui', () {
      final m = jeu();
      final c = codeLibre(m, 2);
      final avant = TarifsPoste.prixActe(m, c, aujourdhui: auj)!;
      m.collection('factures').inserer({
        'statut': 'actif', 'numero': 'FC-10', 'date': '${plus(0)}T09:00:00', 'lignes': [{'acteCode': c, 'prixUnitaire': avant, 'quantite': 1, 'statutPaiement': 'du'}]
      });
      final daf = poste(m, 'da', nom: 'La DAF');
      expect(daf.proposer(prop(c, avant + 500, date: plus(0))).refus!.code, 'TARIF_DEJA_UTILISE');
      final suite = daf.proposer(prop(c, avant + 500, date: plus(1)));
      expect(suite.ok, isTrue, reason: '${suite.refus?.code} ${suite.refus?.motif}');
      expect(TarifsPoste.prixActe(m, c, aujourdhui: auj, date: plus(0)), avant, reason: 'le patient informé garde son prix');
    });
  });

  group('T12 : la journée d\'hospitalisation vient du référentiel de prix', () {
    test('trois types de chambre au prix en vigueur à la date ; une version validée à venir ne bascule que le jour dit', () {
      final m = jeu();
      expect(TarifsPoste.tarifsJournee(m, aujourdhui: auj), {'standard': 5000, 'vip': 15000, 'vvip': 25000});
      expect(poste(m, 'da', nom: 'La DAF').proposer(prop('HO02', 16000, date: plus(3), valider: true)).ok, isTrue);
      expect(TarifsPoste.tarifsJournee(m, aujourdhui: auj, date: plus(2))['vip'], 15000);
      expect(TarifsPoste.tarifsJournee(m, aujourdhui: auj, date: plus(3))['vip'], 16000);
    });
  });

  group('la reprise d\'un magasin d\'AVANT le référentiel', () {
    test('le prix facturé hier (collection `actes` relue du disque) devient la version 1 ; les éditions du catalogue sont listées, jamais appliquées', () async {
      final dossier = Directory.systemTemp.createTempSync('tarifs-reprise');
      addTearDown(() => dossier.deleteSync(recursive: true));
      final disque = PersistanceFichiers(dossier.path);
      final m0 = jeu();
      // Le poste d'avant : un acte dont la clinique avait corrigé le prix (la caisse le lisait), une ligne du catalogue éditée (que personne ne lisait).
      final actes = [for (final a in m0.collection('actes').toutes) {...a, if (a['code'] == 'MG01') 'prix': 5700, if (a['code'] == 'MG01') 'prixNonAssure': 5700}];
      await disque.ecrire('actes', actes);
      final cat = [for (final a in m0.collection('catalogueTarifs').toutes) {...a, if (a['code'] == 'IMG-ECHO-PEL') 'prixNonAssure': 9100}];
      await disque.ecrire('catalogueTarifs', cat);
      final m = jeu();
      await m.brancherPersistance(disque);
      expect(m.collectionsLuesDuDisque, containsAll(['actes', 'catalogueTarifs']));
      expect(m.collectionsLuesDuDisque.contains('tarifs'), isFalse);
      final mg = TarifsPoste.reprendre(m, horloge: () => auj);
      expect(mg, isNotNull);
      expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj), 5700, reason: 'le prix facturé hier est la version 1 : une facture émise ne bouge pas');
      expect(TarifsPoste.lire(m).versionsDe('MG01').first['origine'], 'migration');
      expect(TarifsPoste.prixGrille(m, 'IMG-ECHO-PEL', aujourdhui: auj).montant, 9000, reason: 'l\'édition du catalogue, que personne ne lisait, n\'est pas reprise');
      expect(mg!.ecarts.any((e) => e['type'] == 'catalogue-grille' && e['code'] == 'IMG-ECHO-PEL'), isTrue, reason: 'elle est LISTÉE');
      expect(m.collection('audit').toutes.any((a) => '${a['action']}'.startsWith('Reprise des prix')), isTrue);
      expect(TarifsPoste.parites(m, auj), isEmpty);
      // Une seconde reprise (les collections viennent maintenant du disque) ne refait rien.
      await m.ecrireMaintenant();
      final m2 = jeu();
      await m2.brancherPersistance(PersistanceFichiers(dossier.path));
      expect(TarifsPoste.reprendre(m2, horloge: () => auj), isNull);
      expect(TarifsPoste.prixActe(m2, 'MG01', aujourdhui: auj), 5700);
    });

    test('un magasin sans rien sur disque garde le jeu livré ; un fileul ne projette pas (il reçoit les collections de lecture avec la configuration)', () {
      final m = jeu();
      expect(TarifsPoste.reprendre(m, horloge: () => auj), isNull);
      expect(TarifsPoste.parites(m, auj), isEmpty, reason: 'la mère a projeté les 39 lignes LABO');
      final f = jeu();
      expect(TarifsPoste.reprendre(f, horloge: () => auj, fileul: true), isNull);
      expect(TarifsPoste.parites(f, auj).length, 39, reason: 'un fileul ne projette pas : seule la mère réécrit les collections de lecture');
    });
  });
}
