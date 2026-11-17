import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/facture_tiers_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/service_droits.dart';
import 'package:sigh_poste/impression/identite_poste.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m9/facture_tiers_piece.dart';

import 'aide_polices.dart';
import 'm9_aide.dart';

/// LA SUITE DE LA FACTURE À UNE ENTREPRISE, AU POSTE (Direction de Baguidi, 17/11/2026, point 2) : l'IMPRESSION (en-tête légal unique, acheteur, totaux calculés par somme, signataires du
/// RÉGLAGE), l'AVOIR par le moteur unique (rien réécrit, brouillon équilibré, cumul plafonné, filles libérées), la TRANSMISSION au circuit MECeF (en attente → certifiée / rejetée, refus nommés).
const ifu = '1201555000123';
final auj = DateTime(2026, 8, 16, 12);

Magasin monde() {
  final m = magasin();
  ServiceDroits.de(m).fileulRattache = () => false;
  m.collection('baremeAib').inserer({
    'id': 'BAI-TEST',
    'statut': 'actif',
    'situation': 'prestation_service',
    'taux': 5,
    'statutArret': 'arrete',
    'arrete': true,
    'aValider': false,
    'dateEffet': '2026-01-01',
    'dateArret': '2026-01-01',
    'decideurArret': 'Direction',
    'source': 'Texte de test',
    'motif': 'Version de test'
  });
  return m;
}

AssFilleMere ligne([String tag = '']) => AssFilleMere('Employeur de test')
  ..factures.addAll([
    {'id': 'F-T1$tag', 'numero': 'FN-2026-09001$tag', 'montantTTC': 10000, 'partAssurance': 8000, 'partPatient': 2000, 'date': '2026-08-10', 'lignes': [{}]},
    {'id': 'F-T2$tag', 'numero': 'FN-2026-09002$tag', 'montantTTC': 5000, 'partAssurance': 4000, 'partPatient': 1000, 'date': '2026-08-11', 'lignes': [{}]},
  ])
  ..assureur = 12000
  ..montant = 15000
  ..patient = 3000;

Fiche emise(Magasin m, {String role = 'comptable', String tag = ''}) {
  final r = emettreFactureTiers(m,
      role: role,
      maintenant: auj,
      acheteurIfu: ifu,
      acheteurNom: 'Entreprise de test',
      situationChoisie: 'prestation_service',
      compagnieCode: 'AFR',
      compagnieNom: 'AFRICAINE DES ASSURANCES',
      periode: 'mois',
      periodeLibelle: 'Mensuelle',
      depuis: '2026-07-17',
      ligne: ligne(tag));
  expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
  return r.fiche!;
}

class _Appareil implements AdaptateurMecef {
  _Appareil({this.numero, this.refusRendu});
  final String? numero;
  final RefusMecef? refusRendu;
  int appels = 0;
  @override
  String get mode => 'boitier';
  @override
  bool get configure => true;
  @override
  RefusMecef? get refus => null;
  @override
  Future<ReponseCertification> emettre(DemandeCertification d) async {
    appels++;
    return numero != null ? ReponseCertification.ok(numero!, '2026-08-16T12:00:05Z') : ReponseCertification.refus(refusRendu!);
  }
}

String texteDe(PieceA4 p) {
  final out = StringBuffer();
  for (final c in p.cartouche) {
    out.writeln('${c.$1} ${c.$2}');
  }
  for (final b in p.blocs) {
    if (b is BlocTexte) out.writeln(b.texte);
    if (b is BlocTableau) {
      for (final col in b.tableau.colonnes) {
        out.write('[${col.libelle}] ');
      }
      for (final l in b.tableau.lignes) {
        for (final col in b.tableau.colonnes) {
          out.write('${col.valeur(l)} | ');
        }
        out.writeln();
      }
    }
  }
  return out.toString();
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('l\'impression : la pièce de la facture à une entreprise', () {
    test('en-tête légal unique de la date de la pièce, acheteur, totaux calculés depuis les lignes, AIB au taux du barème, en lettres ; bandeau tant que non certifiée', () {
      final m = monde();
      final f = emise(m);
      final p = pieceFactureTiers(f,
          signatures: signatairesPieceFactureTiers(m, auj), utilisateur: 'Essai', edite: auj, reference: 'CBG-20260816-0001', identite: identiteImprimeeDe(m, datePiece(f, auj)));
      final t = texteDe(p);
      expect(p.titre, 'Facture à une entreprise — normalisée');
      expect(p.identite, isNotNull);
      expect(t, contains('Entreprise de test'));
      expect(t, contains(ifu));
      expect(t, contains('Employeur de test'));
      // Les lignes : un tableau dont le total est refait par `somme`.
      final tableau = p.blocs.whereType<BlocTableau>().first.tableau;
      expect(tableau.libelleTotal, 'TOTAL');
      expect(tableau.colonnes.where((c) => c.somme != null).length, 2, reason: 'quantité et montant se totalisent ; le prix unitaire jamais');
      // Les montants : 12 000 F, AIB 5 % du hors taxes (exonéré) = 600, net = 12 600.
      expect(sp(t), contains('NET À PAYER (hors taxes + AIB)'));
      expect(sp(t).replaceAll(RegExp(r'\s'), ''), allOf(contains('12000'), contains('600'), contains('12600')));
      expect(t, contains('AIB 5 %'));
      expect(t, contains('Base normalisée MECeF'));
      // Non certifiée : le bandeau DEMO, jamais un faux code.
      expect(t, contains('DEMO : pièce non normalisée'));
      expect(t, isNot(contains('MECeF NIM')));
      expect(p.signatures.last.role, 'Pour l’entreprise');
    });

    test('certifiée : le bloc fiscal (NIM, code, compteurs) paraît ; MECeF fermé : aucun bloc ni bandeau ni base', () {
      final m = monde();
      final f = {...emise(m), 'statutMecef': 'valide', 'numeroMecef': 'CC300-000042'};
      PieceA4 piece({bool mecef = true}) => pieceFactureTiers(f, mecefActif: mecef, signatures: const [], utilisateur: 'Essai', edite: auj, reference: 'R');
      expect(texteDe(piece()), allOf(contains('MECeF NIM : CC300-000042'), contains('MECeF Compteurs'), contains('Code MECeF / DGI')));
      expect(piece().sousTitre, contains('CC300-000042'));
      final ferme = texteDe(piece(mecef: false));
      expect(ferme, isNot(contains('MECeF')));
      expect(ferme, isNot(contains('DEMO')));
      expect(piece(mecef: false).titre, 'Facture à une entreprise');
    });

    test('les avoirs portés figurent à la pièce avec leur total, et le reste facturé', () {
      final m = monde();
      final f = emise(m);
      final a = emettreAvoirTiers(m, role: 'comptable', maintenant: auj, factureId: '${f['id']}', motif: 'Erreur de période', montant: 5000);
      expect(a.ok, isTrue, reason: '${a.refus?.code} ${a.refus?.motif}');
      final f2 = m.collection(colFacturesTiers).parId(f['id'])!;
      final p = pieceFactureTiers(f2, avoirs: m.collection(colAvoirsTiers).actives, signatures: const [], utilisateur: 'Essai', edite: auj, reference: 'R');
      final t = texteDe(p);
      expect(t, contains(a.fiche!['reference'] as String));
      expect(t, contains('Erreur de période'));
      expect(sp(t).replaceAll(RegExp(r'\s'), ''), contains('Restefacturéaprèsavoirs:7000'));
      final tab = p.blocs.whereType<BlocTableau>().firstWhere((b) => b.tableau.libelleTotal == 'TOTAL DES AVOIRS').tableau;
      expect(tab.colonnes.where((c) => c.somme != null).length, 1);
    });

    test('les signataires sont LUS au réglage puis à l\'organigramme : aucun nom ni intitulé dans le code', () {
      final m = monde();
      final postes = m.collection('postes').actives;
      expect(postes, isNotEmpty, reason: 'le jeu porte l\'organigramme');
      final racine = signatairesPieceFactureTiers(m, auj).single;
      final attendu = postes.firstWhere((p) => '${p['parentId'] ?? ''}'.isEmpty);
      expect([racine.role, racine.nom], ['${attendu['poste']}', attendu['titulaire'] == null || '${attendu['titulaire']}'.trim().isEmpty ? null : '${attendu['titulaire']}'.trim()], reason: 'sans réglage, le poste qui coiffe l\'organigramme signe');
      final autres = postes.where((p) => '${p['parentId'] ?? ''}'.isNotEmpty).take(2).toList();
      final s = serviceParametres(m, auteur: () => 'Essai', horloge: () => auj)..semerDefauts();
      expect(s.regler(factureTiersCleSignataires, '${autres[0]['poste']};${autres[1]['poste']}', '2026-08-01', motif: 'Essai').ok, isTrue);
      final deux = signatairesPieceFactureTiers(m, auj);
      expect([for (final x in deux) x.role], ['${autres[0]['poste']}', '${autres[1]['poste']}'], reason: 'les postes nommés par le réglage, dans son ordre, par intitulé');
      // Avant la date d'effet du réglage : le poste qui coiffe l'organigramme.
      expect(signatairesPieceFactureTiers(m, DateTime(2026, 7, 1)).single.role, '${attendu['poste']}');
    });
  });

  group('l\'avoir : moteur unique, pièce émise jamais réécrite', () {
    test('avoir partiel : numéro de la série, brouillon ÉQUILIBRÉ, cumul porté par la pièce, journal ; un refus n\'écrit rien', () {
      final m = monde();
      final f = emise(m);
      final ecrituresAvant = m.collection('ecritures').toutes.length;
      expect(emettreAvoirTiers(m, role: 'caissier', maintenant: auj, factureId: '${f['id']}', motif: 'x').refus!.code, 'TIERS_PAYEUR_RESERVE');
      expect(emettreAvoirTiers(m, role: 'comptable', maintenant: auj, factureId: '${f['id']}', motif: ' ').refus!.code, 'MOTIF_AVOIR_REQUIS');
      expect(emettreAvoirTiers(m, role: 'comptable', maintenant: auj, factureId: '${f['id']}', motif: 'x', fileul: true).refus!.code, 'FILEUL_LECTURE_SEULE');
      expect(m.collection(colAvoirsTiers).toutes, isEmpty, reason: 'un refus n\'écrit rien');
      expect(m.collection('ecritures').toutes.length, ecrituresAvant);
      final r = emettreAvoirTiers(m, role: 'comptable', maintenant: auj, factureId: '${f['id']}', motif: 'Erreur de période', montant: 5000);
      expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
      final a = r.fiche!;
      expect([a['montant'], a['factureNumero'], a['acheteurNom'], a['type']], [5000, f['numero'], 'Entreprise de test', typeAvoirFactureTiers]);
      final nouvelles = [for (final e in m.collection('ecritures').toutes) if (e['pieceNumero'] == a['reference']) e];
      expect(nouvelles, hasLength(2));
      expect(nouvelles.fold<num>(0, (s, e) => s + (e['debit'] as num)), nouvelles.fold<num>(0, (s, e) => s + (e['credit'] as num)), reason: 'RG-10');
      expect(nouvelles.every((e) => e['statut'] == 'brouillon'), isTrue);
      final porteuse = m.collection(colFacturesTiers).parId(f['id'])!;
      expect([porteuse['montantAvoirs'], porteuse['montantTTC'], porteuse['avoirIds']], [5000, f['montantTTC'], [a['id']]], reason: 'la pièce PORTE son avoir, elle n\'est pas réécrite');
      expect(m.collection('audit').toutes.any((x) => x['action'] == 'Avoir sur une facture à une entreprise émis'), isTrue, reason: 'RG-12');
      // Plafond cumulé.
      final trop = emettreAvoirTiers(m, role: 'comptable', maintenant: auj, factureId: '${f['id']}', motif: 'x', montant: 8000);
      expect(trop.refus!.code, 'AVOIR_REFUSE');
      expect(trop.refus!.motif, contains('Le cumul des avoirs'));
      // La série de numéros est celle de `avoirs` : aucun doublon avec la caisse.
      expect(a['reference'], matches(RegExp(r'^AV-2026-\d{4}$')));
    });

    test('un avoir TOTAL libère les factures patients : la ligne du relevé se réclame de nouveau ; « Annuler » archive l\'avoir et défait le cumul', () {
      final m = monde();
      final f = emise(m);
      final r = emettreAvoirTiers(m, role: 'comptable', maintenant: auj, factureId: '${f['id']}', motif: 'Pièce erronée');
      expect(r.ok, isTrue);
      expect(m.collection(colFacturesTiers).parId(f['id'])!['montantAvoirs'], f['montantTTC']);
      final reclamees = fillesDejaReclamees(facturesTiers: m.collection(colFacturesTiers).actives);
      expect(reclamees, isEmpty, reason: 'contre-passée en totalité : plus rien n\'est réclamé');
      // Refus de transmettre une pièce contre-passée.
      expect(preparerCertificationFactureTiers(m.collection(colFacturesTiers).parId(f['id'])!).refus!.code, 'PIECE_CONTRE_PASSEE');
      r.annuler();
      expect(m.collection(colAvoirsTiers).actives, isEmpty);
      expect(m.collection(colAvoirsTiers).toutes, hasLength(1), reason: 'archivé, jamais supprimé (RG-14)');
    });

    test('la ligne du relevé est de nouveau offerte après un avoir total (même moteur que l\'écran)', () {
      final m = monde();
      final f = emise(m);
      emettreAvoirTiers(m, role: 'comptable', maintenant: auj, factureId: '${f['id']}', motif: 'Pièce erronée');
      final rel = ligneReleveFactureTiers(m, compagnieCode: 'AFR', periode: 'annee', souscripteur: 'Employeur de test', maintenant: auj);
      expect(rel.compagnieNom, isNotEmpty);
      expect(rel.depuis, '2025-08-16');
    });
  });

  group('la transmission : circuit MECeF des autres ventes', () {
    test('sans appareil : la pièce reste EN ATTENTE avec le refus nommé, le compte de retransmission avance, le journal le dit', () async {
      final m = monde();
      final f = emise(m);
      expect(f['statutMecef'], 'en_attente');
      final r = await transmettreFactureTiers(m, '${f['id']}', role: 'comptable', maintenant: auj);
      expect(r.enAttente, isTrue);
      expect(r.refus!.code, mecefCodeNonConfigure);
      expect(m.collection(colFacturesTiers).parId(f['id'])!['numeroMecef'], isNull, reason: 'aucun numéro fabriqué');
      expect(m.collection('audit').toutes.any((x) => x['action'] == 'Facture à une entreprise : transmission MECeF'), isTrue);
    });

    test('un appareil répond : CERTIFIÉE, identifiant et AIB portés, jamais rappelé ensuite ; il refuse : REJETÉE avec code et motif', () async {
      final m = monde();
      final f = emise(m);
      final appareil = _Appareil(numero: 'CC300-000042');
      final r = await transmettreFactureTiers(m, '${f['id']}', role: 'comptable', maintenant: auj, adaptateur: appareil);
      expect(r.certifiee, isTrue);
      final p = m.collection(colFacturesTiers).parId(f['id'])!;
      expect([p['statutMecef'], p['numeroMecef'], p['aibMontant'], p['dateTransmission']], ['valide', 'CC300-000042', 600, '2026-08-16T12:00:05Z']);
      expect(p['montantTTC'], f['montantTTC'], reason: 'la certification n\'écrit pas les montants');
      final encore = await transmettreFactureTiers(m, '${f['id']}', role: 'comptable', maintenant: auj, adaptateur: appareil);
      expect(encore.sansEffet, isTrue);
      expect(appareil.appels, 1, reason: 'une pièce normalisée ne rappelle jamais l\'appareil');
      final g = emise(m, role: 'da', tag: 'B');
      final rejet = await transmettreFactureTiers(m, '${g['id']}', role: 'da', maintenant: auj, adaptateur: _Appareil(refusRendu: const RefusMecef('E-12', 'IFU inconnu du dispositif.', 'Corriger')));
      expect(rejet.etat, transmissionTiersRejetee);
      final pg = m.collection(colFacturesTiers).parId(g['id'])!;
      expect([pg['statutMecef'], pg['codeRetour']], ['rejete', 'E-12']);
    });

    test('refus nommés : fileul, droit, module MECeF fermé, pièce introuvable', () async {
      final m = monde();
      final f = emise(m);
      expect((await transmettreFactureTiers(m, '${f['id']}', role: 'comptable', maintenant: auj, fileul: true)).refus!.code, 'FILEUL_LECTURE_SEULE');
      expect((await transmettreFactureTiers(m, '${f['id']}', role: 'infirmier', maintenant: auj)).refus!.code, 'RETRANSMISSION_INTERDITE');
      expect((await transmettreFactureTiers(m, 'ZZ', role: 'comptable', maintenant: auj)).refus!.code, 'FACTURE_TIERS_INTROUVABLE');
      m.collection('modulesActifs').inserer({'id': 'MA-TEST', 'statut': 'actif', 'module': 'MECEF', 'actif': false, 'motif': 'Essai'});
      expect((await transmettreFactureTiers(m, '${f['id']}', role: 'comptable', maintenant: auj)).refus!.code, 'MECEF_FERME');
    });
  });

  cas('l\'onglet : « Aperçu et impression » ouvre la pièce avec l\'acheteur ; « Émettre un avoir » ouvre la modale, refuse sans motif puis écrit l\'avoir ; « Transmettre » dit l\'attente nommée', (t) async {
    final m = monde();
    await ouvrir(t, m, 'm9-facture-mere', role: 'comptable');
    t.view.physicalSize = const Size(1600, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pump(const Duration(milliseconds: 300));
    await toucher(t, find.text('Factures à une entreprise').first);
    await t.pump(const Duration(milliseconds: 300));
    await saisir(t, 'ifu', ifu);
    await saisir(t, 'nom', 'Université de Parakou');
    await choisir(t, 'situation', 'Prestation de service retenue par le payeur');
    await toucher(t, find.byKey(const Key('tiers:emettre')));
    await t.pump(const Duration(milliseconds: 500));
    final f = m.collection(colFacturesTiers).toutes.single;
    // Aperçu / impression.
    await toucher(t, find.byKey(Key('tiers:imprimer:${f['id']}')));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Facture à une entreprise — normalisée'), findsWidgets);
    expect(find.textContaining('Université de Parakou'), findsWidgets);
    final fermer = find.text('Fermer');
    if (fermer.evaluate().isNotEmpty) await toucher(t, fermer.first);
    await t.pump(const Duration(milliseconds: 400));
    // Transmission : aucun appareil, l'attente est nommée et rien n'est fabriqué.
    await toucher(t, find.byKey(Key('tiers:transmettre:${f['id']}')));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining(mecefCodeNonConfigure), findsWidgets);
    expect(m.collection(colFacturesTiers).parId(f['id'])!['numeroMecef'], isNull);
    ToastsSigh.viderPourTests();
    // Avoir : sans motif, refusé par le formulaire ; avec motif, écrit.
    await toucher(t, find.byKey(Key('tiers:avoir:${f['id']}')));
    await t.pump(const Duration(milliseconds: 400));
    await toucher(t, find.byKey(const Key('tiers:avoir-valider')));
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection(colAvoirsTiers).toutes, isEmpty);
    await saisir(t, 'motif', 'Erreur de période');
    await saisir(t, 'montant', '4000');
    await toucher(t, find.byKey(const Key('tiers:avoir-valider')));
    await t.pump(const Duration(milliseconds: 600));
    final a = m.collection(colAvoirsTiers).toutes.single;
    expect([a['montant'], a['motif']], [4000, 'Erreur de période']);
    expect(m.collection(colFacturesTiers).parId(f['id'])!['montantAvoirs'], 4000);
    // La facture du patient n'est pas touchée : aucun avoir de la caisse n'est né.
    expect(m.collection('avoirs').toutes.where((x) => x['origine'] == 'facture_tiers'), isEmpty);
  });
}
