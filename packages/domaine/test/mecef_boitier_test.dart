// LE MODÈLE DU BOÎTIER MECeF (décision de la Direction de Baguidi du 16/11/2026 : un ELTRADE CC300) : un réglage de clinique, semé, qui NOMME l'appareil — et
// n'invente aucun protocole : l'adaptateur reste non configuré et le dit.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  test('la définition du registre : famille mecef, texte, semée à « ELTRADE CC300 », jamais vers un téléphone, sourcée', () {
    final d = definitionsParametres.firstWhere((x) => x.cle == mecefCleModeleBoitier);
    expect(d.famille, 'mecef');
    expect(d.type, TypeParametre.texte);
    expect(d.defaut, 'ELTRADE CC300');
    expect(d.defaut, mecefModeleBoitierDefaut);
    expect(d.mobile, isFalse);
    expect(Parametres.autoriseMobile(Parametres.semer(d).toJson()), isFalse);
    expect(d.source, contains('16/11/2026'));
    expect(d.branche, isTrue);
  });

  test('le modèle en vigueur : texte nettoyé ; vide ou absent : non renseigné (jamais un modèle supposé)', () {
    expect(mecefModeleBoitierEnVigueur('  ELTRADE CC300 '), 'ELTRADE CC300');
    expect(mecefModeleBoitierEnVigueur(''), isNull);
    expect(mecefModeleBoitierEnVigueur(null), isNull);
    expect(mecefModeleBoitierEnVigueur(42), isNull);
  });

  test('mode boîtier : l’adaptateur reste NON CONFIGURÉ et nomme le modèle — « intégration à fournir par l’éditeur du boîtier »', () async {
    final a = adaptateurPourMode('boitier', modeleBoitier: 'ELTRADE CC300');
    expect(a.configure, isFalse);
    expect(a.refus!.code, mecefCodeNonConfigure);
    expect(a.refus!.motif, contains('Boîtier non configuré'));
    expect(a.refus!.motif, contains('adaptateur ELTRADE CC300 : intégration à fournir par l’éditeur du boîtier'));
    final r = await a.emettre(const DemandeCertification(cle: 'F1', total: 1000, base: 1000, aib: 10));
    expect(r.ok, isFalse);
    expect(r.numero, isNull, reason: 'aucun numéro n’est fabriqué');
    expect(mecefMentionAdaptateurBoitier(null), contains('modèle non renseigné'));
  });

  test('mode e-MECeF : le modèle du boîtier ne change rien au refus de la maquette', () {
    expect(adaptateurPourMode('emecef', modeleBoitier: 'ELTRADE CC300').refus!.motif, adaptateurPourMode('emecef').refus!.motif);
  });

  test('la pièce porte le modèle là où elle porte le mode : seulement en mode boîtier, et seulement s’il est renseigné', () {
    expect(champsAppareilMecef('boitier', 'ELTRADE CC300'), {'modeleBoitierMecef': 'ELTRADE CC300'});
    expect(champsAppareilMecef('emecef', 'ELTRADE CC300'), isEmpty);
    expect(champsAppareilMecef('boitier', null), isEmpty);
    // Les champs de la maquette (vecteurs) sont inchangés.
    final c = champsEnAttenteCertification(adaptateurPourMode('boitier', modeleBoitier: 'ELTRADE CC300').refus!, 'boitier');
    expect(c.keys.toSet(), {'statutMecef', 'codeRetour', 'motifRefusMecef', 'modeMecef'});
  });
}
