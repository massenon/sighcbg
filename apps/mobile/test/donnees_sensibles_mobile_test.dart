// LES DONNÉES SENSIBLES SUR LE TÉLÉPHONE (Direction, 11/11/2026) : le MÊME calcul que le poste (`DroitsSensibles`, packages/domaine) sur les fiches que la mère livre.
// Le masquage se fait AU SERVICE, avant que l'écran reçoive la donnée : un champ retiré ne peut pas réapparaître par un autre chemin de l'écran.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/main.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

import 'aide_mobile.dart';
import 'aide_suite.dart';

typedef Fiche = Map<String, Object?>;

Fiche decision(String role, Map<String, bool> cats) => {'id': 'RBACS-$role', 'role': role, 'statut': 'actif', 'donneesSensibles': cats, 'definiLe': '2026-11-11'};

void livrer(FauxMoteur m, [List<Fiche> decisions = const []]) =>
    m.droits.appliquer(rbac: [...m.droits.graine.rbacLivre, ...decisions], modulesActifs: const [], majLe: DateTime(2026, 11, 11, 9));

void main() {
  test('sans décision, le défaut suit la matrice : un médecin lit tout le dossier, rien n’est masqué', () async {
    final m = FauxMoteur(fonction: 'medecin')..profil = ProfilMobile.soignant;
    final d = await m.soignant!.dossier('p1');
    expect(d.masques, isEmpty);
    expect(d.fiche['telephone'], '97 11 22 33');
    expect(d.resume.allergies, ['Pénicilline']);
  });

  test('une décision livrée par la mère retire la catégorie AVANT l’écran, à chaud, sans réappairage ; la retirer la rend', () async {
    final m = FauxMoteur(fonction: 'medecin')..profil = ProfilMobile.soignant;
    final s = m.soignant!;
    livrer(m, [decision('medecin', {'coordonnees': false, 'allergies_traitements': false})]);
    var d = await s.dossier('p1');
    expect(d.masques, containsAll(['coordonnees', 'allergies_traitements']));
    expect(d.fiche.containsKey('telephone'), isFalse);
    expect(d.fiche.containsKey('quartier'), isFalse);
    expect(d.resume.telephone, isNull);
    expect(d.resume.quartier, isNull);
    expect(d.resume.allergies, isEmpty, reason: 'la liste est vidée ; l’écran dit « réservé » grâce à `masques`, jamais « aucune allergie »');
    expect(d.fiche['nom'], 'DULOUNE', reason: 'l’identification minimale reste');
    livrer(m);
    d = await s.dossier('p1');
    expect(d.masques, isEmpty);
    expect(d.fiche['telephone'], '97 11 22 33');
  });

  test('le diagnostic et les notes obéissent à leur catégorie : retirées du résumé, pas seulement cachées à l’écran', () async {
    final m = FauxMoteur(fonction: 'medecin')..profil = ProfilMobile.soignant;
    final s = m.soignant!;
    await s.enregistrerNote('p1', {'motif': 'Toux', 'diagnostic': 'Hypertension artérielle'});
    var d = await s.dossier('p1');
    expect(d.resume.notes.single['diagnostic'], 'Hypertension artérielle');
    livrer(m, [decision('medecin', {'diagnostic_pathologie': false})]);
    d = await s.dossier('p1');
    expect(d.resume.notes.single.containsKey('diagnostic'), isFalse);
    expect(d.masques, contains('diagnostic_pathologie'));
    expect((await m.source.liste('notes')).single.data['diagnostic'], 'Hypertension artérielle', reason: 'le lot du téléphone n’est jamais modifié par le masquage : seule la lecture est filtrée');
    livrer(m, [decision('medecin', {'notes_consultation': false})]);
    d = await s.dossier('p1');
    expect(d.resume.notes, isEmpty);
    expect(d.resume.prescriptions, isEmpty);
  });

  test('la décision porte sur UN rôle : la sage-femme garde ce qu’on retire au médecin', () async {
    final sf = FauxMoteur(fonction: 'sage_femme')..profil = ProfilMobile.soignant;
    livrer(sf, [decision('medecin', {'coordonnees': false})]);
    expect((await sf.soignant!.dossier('p1')).masques, isEmpty);
  });

  testWidgets('À L’ÉCRAN : le dossier dit « Information réservée » à la place de la valeur retirée', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final m = FauxMoteurSuite(fonction: 'medecin', agent: 'Agent de test', source: lotSageFemme())..profil = ProfilMobile.soignant;
    livrer(m, [decision('medecin', {'coordonnees': false})]);
    await t.pumpWidget(SighMobile(moteur: m));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('onglet-dossiers')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('patient-p4')));
    await t.pumpAndSettle();
    expect(find.textContaining('Winké'), findsNothing);
    expect(find.textContaining(mentionReservee('coordonnees')), findsWidgets);
  });

  test('AGENDA : le motif d’un rendez-vous suit « notes et dossier de consultation » — masqué au service, rendu à chaud, jamais recopié dans une saisie', () async {
    final m = FauxMoteur(fonction: 'medecin')..profil = ProfilMobile.soignant;
    final s = m.soignant!;
    var a = await s.agenda();
    final motif = a.duJour.first.motif;
    expect(motif, isNotEmpty);
    expect(a.duJour.first.motifMasque, isFalse);
    livrer(m, [decision('medecin', {'notes_consultation': false})]);
    a = await s.agenda();
    for (final l in [...a.duJour, ...a.enSouffrance]) {
      expect(l.motif, mentionReservee('notes_consultation'), reason: 'le motif ne sort pas du service : l\'écran ne peut pas le montrer par un autre chemin');
      expect(l.motifMasque, isTrue);
    }
    expect(a.duJour.first.patient, isNotEmpty, reason: 'l\'identification minimale reste');
    livrer(m);
    a = await s.agenda();
    expect(a.duJour.first.motif, motif, reason: 'droit rendu à chaud, sans réappairage');
  });
}
