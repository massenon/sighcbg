/// MECeF, lot M1 : les contrôles qui précèdent la normalisation d'une vente, et les règles de retransmission.
///
/// Port de `normaliserVente` et `retransmettreMecef` (`prototype_html/assets/js/parcours.js`, E2299), SANS leur appareil : la maquette y simule un
/// boîtier, le poste n'en a aucun de branché et n'invente ni protocole ni adresse. Ce qui est porté, c'est la DÉCISION (refus nommés, acheteur,
/// montants entiers) ; l'émission d'un numéro reste un geste de l'appareil, simulé et marqué comme tel par l'appelant.
/// Les fonctions de montants et d'acheteur sont rejouées sur `mecef_montants.json` ; celles-ci sont éprouvées par `mecef_normalisation_test.dart`.
library;

import '../droits/gestes_reserves.dart';
import 'etats.dart';
import 'montants.dart';

/// Ce que la normalisation retient d'une pièce, ou le refus nommé.
class PreparationNormalisation {
  const PreparationNormalisation.ok(AcheteurMecef this.acheteur, MontantsMecef this.montants) : refus = null, ignore = false;
  const PreparationNormalisation.refus(RefusMecef this.refus)
      : acheteur = null,
        montants = null,
        ignore = false;
  const PreparationNormalisation.ignoree()
      : acheteur = null,
        montants = null,
        refus = null,
        ignore = true;
  final AcheteurMecef? acheteur;
  final MontantsMecef? montants;
  final RefusMecef? refus;

  /// Mode « Désactivé » (démonstration) : aucune normalisation.
  final bool ignore;
  bool get ok => acheteur != null;
}

num _num(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// L'acheteur d'une pièce : ce que la fenêtre a saisi, sinon ce que la pièce porte déjà, sinon les défauts (particulier, AIB par défaut).
({AcheteurMecef? acheteur, RefusMecef? refus}) acheteurDePiece(
    Map<String, Object?> fac,
    {Map<String, Object?>? saisi,
    int? aibParDefaut,
    int? longueurIfu}) {
  final s = saisi ?? const {};
  return validerAcheteurMecef(
    ifu: s.containsKey('ifu') ? s['ifu'] : fac['ifuClient'],
    nom: s.containsKey('nom') ? s['nom'] : fac['acheteurNom'],
    aibTaux: s.containsKey('aibTaux') ? s['aibTaux'] : fac['aibTaux'],
    aibSituation: s.containsKey('aibTaux') ? s['aibSituation'] : fac['aibSituation'],
    aibRepli: s.containsKey('aibTaux') ? s['aibRepli'] == true : fac['aibRepli'] == true,
    aibParDefaut: aibParDefaut,
    longueurIfu: longueurIfu,
  );
}

/// L'entrée de la fonction des montants pour une pièce de caisse (la pièce garde ses montants).
List<Map<String, Object?>> lignesMontantsPiece(Map<String, Object?> fac) {
  final ls = fac['lignes'];
  if (ls is List && ls.isNotEmpty) {
    return [for (final l in ls) ligneVersMecef((l as Map).cast<String, Object?>())];
  }
  return [
    {
      'designation': 'Prestation',
      'quantite': 1,
      'montantBrut': fac['montantTTC'],
      'prixUnitaire': fac['montantTTC'],
      'partAssureur': fac['partAssurance'] ?? 0,
      'partPersonnel': fac['partPersonnel'] ?? 0,
    }
  ];
}

/// Les contrôles de la normalisation d'une vente, dans l'ordre de la maquette : pro-forma, règlement, mode, déjà normalisée, acheteur, montants.
/// Un refus des montants est rendu avec ses données : l'appelant écrit alors la pièce `refusee` en nommant le code.
PreparationNormalisation preparerNormalisation(
  Map<String, Object?> fac, {
  Map<String, Object?>? acheteurSaisi,
  bool modeDesactive = false,
  int? aibParDefaut,
  int? longueurIfu,
  num tauxTvaCourant = 0,
}) {
  final num_ = '${fac['numero'] ?? fac['id']}';
  if (fac['proforma'] == true) {
    return const PreparationNormalisation.refus(RefusMecef(
        'PROFORMA',
        'Une pro-forma n’est pas une vente : elle ne se normalise pas.',
        'Émettre la facture de vente.'));
  }
  if (!(_num(fac['montantPaye']) > 0)) {
    return PreparationNormalisation.refus(RefusMecef(
        'VENTE_NON_ENCAISSEE',
        'La facture $num_ n’a encaissé aucun règlement : une vente se normalise à l’encaissement.',
        'Encaisser la vente à la caisse.'));
  }
  if (modeDesactive) return const PreparationNormalisation.ignoree();
  if (porteBlocFiscal(fac)) {
    return PreparationNormalisation.refus(RefusMecef(
        'DEJA_NORMALISEE',
        'La facture $num_ est déjà normalisée (${fac['numeroMecef']}) : elle ne se renormalise jamais.',
        'La corriger par un avoir.'));
  }
  // Une ligne « prix à valoriser » n'a pas de montant : la pièce ne se normalise pas tant qu'elle attend (elle n'est d'ailleurs jamais soldée). Refus nommé, rien n'est écrit.
  final enAttente = [
    for (final l in (fac['lignes'] as List? ?? const []))
      if (l is Map && l['prixAValoriser'] == true && l['montant'] == null) l['designation']
  ];
  if (enAttente.isNotEmpty) {
    return PreparationNormalisation.refus(RefusMecef(
        'PRIX_A_VALORISER',
        'La facture $num_ porte ${enAttente.length} ligne(s) au prix à valoriser (${enAttente.join(', ')}) : une vente ne se normalise qu’avec tous ses montants.',
        'Fixer le prix d’achat de l’article, encaisser la ligne, puis normaliser.'));
  }
  final ach = acheteurDePiece(fac, saisi: acheteurSaisi, aibParDefaut: aibParDefaut, longueurIfu: longueurIfu);
  if (ach.refus != null) return PreparationNormalisation.refus(ach.refus!);
  final m = mecefMontants(
    lignes: lignesMontantsPiece(fac),
    totalAttendu: _num(fac['montantTTC']),
    aibTaux: ach.acheteur!.aibTaux,
    tauxTvaCourant: tauxTvaCourant,
  );
  if (!m.ok) return PreparationNormalisation.refus(m.refus!);
  return PreparationNormalisation.ok(ach.acheteur!, m.montants!);
}

/// Un numéro simulé jamais déjà porté : le tirage, avancé d'un cran tant qu'il est pris.
String numeroMecefLibre(int tire, Set<String> pris) {
  var n = tire;
  while (pris.contains('MECEF$n')) {
    n++;
  }
  return 'MECEF$n';
}

/// Qui peut retransmettre une pièce (PRD section 7, Q7) : le geste réservé [gesteMecefRetransmettre] (une fois), puis [gesteMecefRetransmettreSansLimite] ; jamais une
/// vente normalisée ; une vente « à vérifier » se reprend, elle ne se retransmet pas. Null quand c'est permis. AUCUN nom de rôle ici (Direction, 16/11/2026) : l'origine des deux gestes
/// reprend la règle d'avant (le caissier une fois, la DAF et l'administrateur sans limite), et une fiche de rôle accorde ou retire. [gestes] : les droits EN FORCE (fiches `rbac`,
/// matrice) ; absent, l'origine du référentiel s'applique (un test nu).
RefusMecef? refusRetransmission(Map<String, Object?> fac, String role, {DroitsGestes? gestes}) {
  final g = gestes ?? DroitsGestes(fiches: const []);
  final num_ = '${fac['numero'] ?? fac['id']}';
  final etat = etatMecefDe(fac)?.id;
  if (etat == 'normalisee') {
    return RefusMecef(
        'DEJA_NORMALISEE',
        'La facture $num_ est déjà normalisée (${fac['numeroMecef']}) : elle ne se retransmet jamais.',
        'La corriger par un avoir.');
  }
  if (!const ['refusee', 'expiree', 'en_attente'].contains(etat)) {
    return RefusMecef(
        'PAS_RETRANSMISSIBLE',
        'La facture $num_ est à vérifier : elle se reprend sans doubler, elle ne se retransmet pas.',
        'Utiliser « Reprendre sans doubler ».');
  }
  final deja = _num(fac['retransmissions']).toInt();
  final unePremiere = g.peut(role, gesteMecefRetransmettre), sansLimite = g.peut(role, gesteMecefRetransmettreSansLimite);
  if (!unePremiere && !sansLimite) {
    return const RefusMecef(
        'RETRANSMISSION_INTERDITE',
        'La retransmission est un geste réservé de la matrice des droits (« retransmettre une pièce à la MECeF ») : votre profil ne le détient pas.',
        'Demander à un profil qui le détient (d’origine : la caisse, une fois, et la Directrice Administrative).');
  }
  if (!sansLimite && deja >= 1) {
    return RefusMecef(
        'RETRANSMISSION_RESERVEE',
        'Votre profil ne retransmet qu’une fois : la facture $num_ l’a déjà été.',
        'Demander la retransmission à un profil qui détient « retransmettre sans limite » (d’origine : la Directrice Administrative).');
  }
  return null;
}
