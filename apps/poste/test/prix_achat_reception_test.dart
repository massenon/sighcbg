import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm7_achats_test.dart' show ouvrir, toucher, bouton, ecrire, cas, magasin, aujourdhui;

/// UNE RÉCEPTION D'ACHAT À UN AUTRE PRIX PROPOSE le changement du prix d'achat : une seule proposition ouverte par produit, jamais d'écriture directe du prix de la fiche, jamais de réception bloquée,
/// l'entrée en stock et le CUMP inchangés, le retour d'une annulation de réception qui retire la proposition, l'autorité de MODIFIER les réceptions (pas celle de « Référentiel produits »).
Map<String, Object?> commande(Magasin m, {num prix2 = 1100, num prix1 = 650}) => m.collection('commandes').inserer({
      'reference': 'BC-TEST-PRIX',
      'date': '2026-10-30',
      'fournisseur': 'CAME',
      'fournisseurNom': 'CAME',
      'statutCommande': 'validee',
      'valideePar': 'TACHEDI Arialu',
      'statut': 'actif',
      'lignes': [
        {'produitId': 'PRD0001', 'produit': 'ABAISSE LANGUE', 'unite': 'Unité', 'quantite': 20, 'prixUnitaire': prix1, 'montant': 20 * prix1},
        {'produitId': 'PRD0002', 'produit': 'ACCUZON', 'unite': 'Unité', 'quantite': 7, 'prixUnitaire': prix2, 'montant': 7 * prix2},
      ],
      'montant': 20 * prix1 + 7 * prix2,
    }, prefixe: 'COM').fiche;

Magasin monde({num prix2 = 1100, num prix1 = 650}) {
  final m = magasin();
  TarifsPoste.assurerProduits(m);
  commande(m, prix1: prix1, prix2: prix2);
  return m;
}

List<Map<String, Object?>> propositions(Magasin m, String code) => [for (final v in TarifsPoste.lire(m).versionsDe(code)) if (v['statut'] == 'propose') v];

Future<void> receptionner(WidgetTester t, Magasin m, {String role = 'stock', String bl = '26LNA00777'}) async {
  await ouvrir(t, m, 'm7-receptions', role: role);
  await toucher(t, bouton('Réceptionner').first);
  await ecrire(t, 'referenceBL', bl);
  await toucher(t, bouton('Valider la réception'));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  cas('la réception à un autre prix OUVRE une proposition (une seule, datée de la réception, motivée) : le prix et la fiche ne bougent pas, le stock et le CUMP bougent comme avant', (t) async {
    final m = monde();
    final p2 = {...m.collection('produits').parId('PRD0002')!};
    final achat = p2['prixAchat'] as num, cump = p2['cump'];
    expect(achat, 1000);
    await receptionner(t, m);
    // Le produit reçu à 650, identique : aucune proposition. Le produit reçu à 1100 : une.
    expect(propositions(m, 'ABA'), isEmpty);
    final ps = propositions(m, 'ACC');
    expect(ps.length, 1);
    expect([ps.single['prixNonAssure'], ps.single['version'], ps.single['origine'], ps.single['dateEffet'], ps.single['motif']], [1100, 2, 'ecran', '2026-10-30', 'prix constaté à la réception n° 26LNA00777']);
    expect(ps.single['source'], 'Réception 26LNA00777');
    final apres = m.collection('produits').parId('PRD0002')!;
    expect([apres['prixAchat'], apres['prixVente']], [achat, achat], reason: 'jamais d\'écriture directe du prix : il change au Oui');
    expect(apres['stockGros'], (p2['stockGros'] as num) + 7, reason: 'la réception n\'est pas bloquée');
    expect(apres['cump'], isNot(cump), reason: 'le CUMP suit l\'entrée, comme avant');
    expect(TarifsPoste.prixProduit(m, apres, aujourdhui: aujourdhui, date: '2026-10-30').achat, 1000);
    expect(find.textContaining('proposition(s) de changement du prix d’achat ouverte(s)'), findsOneWidget);
  });

  cas('une seule proposition ouverte par produit : une seconde réception à un autre prix n\'en ouvre pas une deuxième', (t) async {
    final m = monde();
    TarifsPoste(m, role: 'stock', auteur: () => 'Gestionnaire', peutProposerPrixAchat: true, horloge: () => aujourdhui)
        .proposerPrixAchat(DemandeProduit(code: 'ACC', prixAchat: 1050, dateEffet: tarIso(aujourdhui), motif: 'Déjà proposé'));
    await receptionner(t, m);
    expect(propositions(m, 'ACC').length, 1);
    expect(propositions(m, 'ACC').single['prixNonAssure'], 1050, reason: 'la proposition ouverte avant reste la seule');
    expect(find.textContaining('attend déjà sa décision pour ACC'), findsOneWidget);
  });

  cas('un prix de réception identique à celui en vigueur n\'ouvre rien', (t) async {
    final m = monde(prix2: 1000);
    await receptionner(t, m);
    expect(propositions(m, 'ACC'), isEmpty);
    expect(propositions(m, 'ABA'), isEmpty);
    expect(find.textContaining('proposition(s) de changement'), findsNothing);
  });

  cas('annuler la réception retire la proposition qu\'elle avait ouverte (elle reste lisible : RG-14) ; le stock revient', (t) async {
    final m = monde();
    final gros = m.collection('produits').parId('PRD0002')!['stockGros'];
    await receptionner(t, m);
    expect(propositions(m, 'ACC').length, 1);
    await toucher(t, find.text('Annuler').last);
    expect(propositions(m, 'ACC'), isEmpty);
    final v = TarifsPoste.lire(m).versionsDe('ACC').last;
    expect([v['statut'], v['version']], ['retire', 2], reason: 'la version reste au registre, retirée');
    expect(m.collection('produits').parId('PRD0002')!['stockGros'], gros);
  });

  cas('sans le droit de modifier « Réceptions & contrôles », aucune proposition : le moteur refuse en le disant et la réception n\'est pas bloquée', (t) async {
    final m = monde();
    // Le rôle « aide_comptable » modifie les réceptions mais pas « Référentiel produits » : l'autorité d'une réception est la sienne, pas l'autre.
    final r = TarifsPoste(m, role: 'x', auteur: () => 'X', peutProposerPrixAchat: true, peutProposerReception: false, horloge: () => aujourdhui)
        .proposerPrixReception(produit: m.collection('produits').parId('PRD0002')!, prixRecu: 1100, date: '2026-10-30', reference: 'BL');
    expect(r.issue.etat, 'refusee');
    expect(r.issue.refus!.code, 'PROPOSITION_RESERVEE');
    expect(propositions(m, 'ACC'), isEmpty);
    final ok = TarifsPoste(m, role: 'x', auteur: () => 'X', peutProposerPrixAchat: false, peutProposerReception: true, horloge: () => aujourdhui)
        .proposerPrixReception(produit: m.collection('produits').parId('PRD0002')!, prixRecu: 1100, date: '2026-10-30', reference: 'BL');
    expect(ok.issue.etat, 'ouverte', reason: 'modifier les réceptions suffit, sans modifier le référentiel produits');
  });
}
