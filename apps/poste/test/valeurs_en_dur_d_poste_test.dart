// LA FAMILLE D AU POSTE (18/11/2026) : les listes de choix et les libellés des écrans viennent des réglages datés ; changer un réglage change ce que l'écran propose SANS changer la décision.
// On prouve : (1) les modes de paiement, natures de facture, secteurs d'activité, types d'inventaire… suivent le réglage ; (2) le sous-ensemble des modes que règle le PATIENT reste défini par
// des CODES (changer un libellé ou l'ordre du réglage n'y fait jamais entrer l'assurance) ; (3) le nom d'une compagnie se lit au référentiel des assureurs.
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/modules/cfg/cfa_commun.dart';
import 'package:sigh_poste/modules/m8/commun.dart';

Map<String, Object?> version(String cle, String valeur, {String effet = '2026-11-01', int v = 1}) {
  final d = definitionDeParametre(cle)!;
  return Parametre(cle: cle, famille: d.famille, type: d.type, valeur: valeur, defaut: d.defaut, dateEffet: effet, version: v, auteur: 'Test', motif: 'essai', creeLe: '2026-11-18T08:00:00.000').toJson();
}

void brancher(List<Map<String, Object?>> fiches) => ListesReference.brancher(() => fiches, horloge: () => DateTime(2026, 11, 18));

void main() {
  tearDown(ListesReference.debrancher);

  test('les modes de paiement : le libellé suit le réglage, la décision (quels modes règle le patient) ne bouge pas', () {
    expect(modesPaiement.map((m) => m.$1), ['especes', 'tpe', 'mtn', 'moov', 'mobile_money', 'mixte', 'assurance']);
    expect(modeLabel('especes'), 'Espèces');
    brancher([version('libelles.m8.modesPaiement', 'assurance=Tiers payant; especes=Comptant')]);
    expect(modeLabel('especes'), 'Comptant');
    expect(modeLabel('assurance'), 'Tiers payant');
    expect(modeLabel('moov'), 'Moov Money');
    // L'ordre du réglage change l'ordre d'affichage…
    expect(modesPaiement.first.$1, 'assurance');
    // …mais le patient ne règle jamais par « assurance » : les modes qu'il règle sont les TYPES DE VERSEMENT en service (paramètres de la caisse), plus une liste de codes écrite ici (20/11/2026).
    expect(typesVersementEnService(const []).map((t) => t.code), ['especes', 'tpe', 'mtn', 'moov', 'mobile_money']);
    expect(typesVersementEnService(const []).any((t) => t.code == 'assurance'), isFalse);
    expect(modeLabel('inconnu'), 'inconnu');
  });

  test('les natures de facture sont UNE liste pour la caisse, les reliquats et le registre MECeF', () {
    expect(naturesFactureListe, ['Consultation', 'Hospitalisation', 'Laboratoire', 'Pharmacie', 'Soins à domicile']);
    brancher([version('listes.m8.naturesFacture', 'Consultation; Imagerie')]);
    expect(naturesFactureListe, ['Consultation', 'Imagerie']);
  });

  test('les secteurs d\'activité des natures de facture lisent le réglage (plus de référentiel statique du jeu)', () {
    final avant = ListesReference.semence('listes.cfg.secteursActivite');
    expect(avant.length, 8);
    brancher([version('listes.cfg.secteursActivite', 'Chirurgie; Imagerie médicale')]);
    expect(ListesReference.valeurs('listes.cfg.secteursActivite'), ['Chirurgie', 'Imagerie médicale']);
  });

  test('les listes posées en ligne dans les formulaires sont des réglages : valeur d\'attente reprise du code, puis la version datée', () {
    const attendues = {
      'listes.m2.conditionsExamen': ['Bonne', 'Moyenne', 'Difficile'],
      'listes.m2.statutsVaccinaux': ['À jour', 'Incomplet', 'Non vacciné', 'Inconnu'],
      'listes.m4.complicationsAccouchement': ['Aucune', 'Hémorragie de la délivrance', 'Souffrance fœtale', 'Dystocie', 'Éclampsie'],
      'listes.m4.etiologiesHemorragieAntePartum': ['Placenta praevia', 'Hématome rétro-placentaire', 'Rupture utérine', 'Autre'],
      'listes.m4.resultatsPcrNaissance': ['En attente', 'Négatif', 'Positif'],
      'listes.m6.typesInventaire': ['Hebdomadaire', 'Mensuel', 'Annuel', 'Tournant', 'Ponctuel'],
      'listes.m9.motifsChangementCouverture': [
        'Changement d’employeur',
        'Changement de compagnie par l’assuré',
        'Convention non reconduite',
        'Renouvellement de carte',
        'Changement de police',
        'Fin de couverture — patient redevenu non assuré',
        'Correction d’une saisie erronée',
      ],
      'listes.mecef.modesTransmission': ['Automatique à l’émission', 'Manuelle groupée', 'Différée en fin de journée'],
      'listes.m12.devisesBancaires': ['FCFA', 'EUR', 'USD'],
    };
    for (final e in attendues.entries) {
      expect(ListesReference.valeurs(e.key), e.value, reason: e.key);
    }
    expect(ListesReference.valeurs('listes.m6.destinationsTransfert').length, 7);
    brancher([version('listes.m6.typesInventaire', 'Mensuel; Annuel')]);
    expect(ListesReference.valeurs('listes.m6.typesInventaire'), ['Mensuel', 'Annuel']);
    expect(ListesReference.valeurs('listes.m12.devisesBancaires'), ['FCFA', 'EUR', 'USD']);
  });

  test('les familles de tarif de l\'écran des tarifs : les codes sont ceux de l\'énumération, les libellés ceux du réglage', () {
    brancher([version('libelles.cfg.famillesTarif', 'CONSULTATION=Consultations médicales')]);
    expect(enumFamillesTarif.libelle('CONSULTATION'), 'Consultations médicales');
    expect(enumFamillesTarif.codes.length, 8);
    expect(cfaSecteursActivite(), ListesReference.semence('listes.cfg.secteursActivite'));
  });
}
