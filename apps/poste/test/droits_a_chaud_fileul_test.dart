import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

import 'aide_polices.dart';

/// UN FILEUL OUVERT RECALCULE SES DROITS TOUT DE SUITE (10/11/2026) : la fiche `rbac` que la mère diffuse arrive par `ApplicateurConfiguration` (`appliquerDistante`, sans
/// journal ni garde) ; la coque, qui écoute la collection, recalcule le ruban, les accès rapides et les commandes d'écriture sans qu'on la relance. Une session ouverte
/// garde sa session mais PAS ses droits périmés.
final donnees = DonneesNavigation.depuisDossier();

Magasin poste() => Magasin.depuisDossier(['rbac', 'modulesActifs', 'audit', 'naissances', 'patients', 'deces', 'grossesses', 'accouchements', 'rolesBase']);

Future<void> monter(WidgetTester t, Magasin m, {required String role, String? ecran}) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role, nomPoste: 'Fileul'),
      magasin: m,
      ecranInitial: ecran,
      horloge: () => DateTime(2026, 11, 10, 10)));
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Ce que fait un fileul quand la mère diffuse une nouvelle version de la fiche d'un rôle.
void recevoir(Magasin m, String role, Map<String, Object?> Function(Map<String, Object?> fiche) transforme) {
  final f = m.collection('rbac').toutes.firstWhere((x) => x['role'] == role);
  m.collection('rbac').appliquerDistante(transforme({...f}));
}

Future<void> pomper(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(chargerPolices);

  testWidgets('une décision reçue retire la commande d’écriture sur l’écran OUVERT (lecture seule posée à chaud), puis la rend — sans relancer, session intacte', (t) async {
    final m = poste();
    await monter(t, m, role: 'sage_femme', ecran: 'm4-naissances');
    expect(find.widgetWithIcon(BoutonSigh, LucideIcons.plus).evaluate().length, greaterThan(0), reason: 'la maternité est son module : elle y écrit');
    expect(find.textContaining('Lecture seule : le profil'), findsNothing);
    recevoir(m, 'sage_femme', (f) => {...f, 'droits': {...(f['droits'] as Map), 'M4': {'voir': true, 'editer': false, 'annuler': false}}, 'version': 5});
    await pomper(t);
    expect(find.textContaining('Lecture seule : le profil'), findsOneWidget);
    expect(find.widgetWithIcon(BoutonSigh, LucideIcons.plus).evaluate().length, 0, reason: 'une commande sans droit est ABSENTE, pas grisée');
    expect(find.text('Tableau de bord — Responsable Maternité'), findsNothing, reason: 'elle reste sur son écran : le droit d’écrire a changé, pas celui de voir');
    recevoir(m, 'sage_femme', (f) => {...f, 'droits': {...(f['droits'] as Map), 'M4': {'voir': true, 'editer': true, 'annuler': true}}, 'version': 6});
    await pomper(t);
    expect(find.widgetWithIcon(BoutonSigh, LucideIcons.plus).evaluate().length, greaterThan(0));
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('un droit de VOIR retiré à l’écran ouvert : la coque ne le laisse pas, le dit, journalise l’accès retiré et ramène à l’accueil du rôle (session gardée)', (t) async {
    final m = poste();
    await monter(t, m, role: 'sage_femme', ecran: 'm4-naissances');
    expect(find.text('Registre des naissances'), findsWidgets);
    recevoir(m, 'sage_femme', (f) => {
          ...f,
          'droitsEcrans': {...(f['droitsEcrans'] as Map), 'm4-naissances': {'voir': false}},
          'version': 7
        });
    await pomper(t);
    await pomper(t);
    expect(find.textContaining('Vos droits ont changé'), findsOneWidget);
    expect(find.text('Tableau de bord — Responsable Maternité'), findsWidgets, reason: 'retombée sur l’accueil du rôle, qui reste son rôle : la session n’est pas fermée');
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Accès retiré à chaud' && a['reference'] == 'm4-naissances'), isTrue);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('le ruban et les accès rapides suivent : un module ouvert à distance paraît, refermé il disparaît', (t) async {
    final m = poste();
    await monter(t, m, role: 'sage_femme');
    Future<void> domaine(String nom) async {
      await t.tap(find.byKey(Key('domaine-$nom')));
      await t.pump();
      if (find.byKey(const Key('panneau-ruban')).evaluate().isEmpty) {
        await t.tap(find.byKey(Key('domaine-$nom')));
        await t.pump();
      }
    }

    expect(find.byKey(const Key('domaine-Financier')), findsNothing, reason: 'aucun module financier au départ');
    recevoir(m, 'sage_femme', (f) => {...f, 'droits': {...(f['droits'] as Map), 'M9': {'voir': true, 'editer': false, 'annuler': false}}, 'version': 8});
    await pomper(t);
    expect(find.byKey(const Key('domaine-Financier')), findsOneWidget, reason: 'le domaine paraît sans redémarrage');
    await domaine('Financier');
    expect(find.byKey(const Key('pastille-m9-assures')), findsOneWidget);
    recevoir(m, 'sage_femme', (f) => {...f, 'droits': {...(f['droits'] as Map), 'M9': {'voir': false, 'editer': false, 'annuler': false}}, 'version': 9});
    await pomper(t);
    expect(find.byKey(const Key('domaine-Financier')), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('un fileul rattaché ne peut pas écrire la fiche de droits lui-même (famille R) ; ce qu’il reçoit de la mère, lui, s’applique', (t) async {
    final m = poste();
    final appl = ApplicateurConfiguration(m, (c) async => const <PieceSync>[]);
    appl.demarrer(intervalle: const Duration(hours: 1));
    appl.arreter();
    final f = m.collection('rbac').toutes.firstWhere((x) => x['role'] == 'sage_femme');
    expect(() => m.collection('rbac').mettreAJour(f['id'], {'statut': 'archive'}), throwsA(isA<EcritureRefusee>()));
    recevoir(m, 'sage_femme', (x) => {...x, 'version': 11});
    expect(m.collection('rbac').parId(f['id'])!['version'], 11);
  });
}
