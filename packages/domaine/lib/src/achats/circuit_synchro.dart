// LES CIRCUITS D'ACHAT QUI TRAVERSENT LES POSTES (Direction de Baguidi, 16/11/2026) : le BESOIN exprimé sur un fileul doit arriver à la DAF, qui arbitre depuis SON poste ;
// la COMMANDE aussi (RG-04). Ce fichier porte les règles PURES, partagées par le poste (qui contrôle à blanc), la mère (qui applique et refuse) et la fusion du pont :
//
//  * l'ÉTAT d'un bon ne RÉGRESSE jamais : `besoins.etape` et `commandes.statutCommande` ont un rang ; un bon accordé ne redevient pas soumis par une fusion tardive ;
//  * l'arbitrage (accorder, rejeter, demander un complément) et la validation d'une commande sont RÉSERVÉS : un fileul ne les écrit pas, il les DÉPOSE
//    (collection `validationsDeposees`, genre [valGenreCircuitAchat] — le mécanisme de la continuité des validations, pas un second) ; la mère les applique sous le rôle de leur
//    auteur en refaisant les contrôles. Premier dépôt appliqué = décision ; un second dépôt contradictoire est refusé en nommant l'arbitre ;
//  * un état en aval de l'arbitrage (préparation, livraison…) ne s'écrit que si la mère détient déjà l'arbitrage.
//
// Écarts de la maquette : docs/architecture/ECARTS-MAQUETTE.md, E2850 à E2879.
library;

import '../validation/validation.dart' show RefusValidation, valInstant;
import '../validation/validation_deposee.dart';
import 'besoins.dart';
import 'commandes.dart';

/// Le genre de dépôt des circuits d'achat (à côté de `referentiel`).
const String valGenreCircuitAchat = 'circuit_achat';

/// Les deux familles de gestes déposables.
const String circuitBesoinArbitrage = 'besoin_arbitrage';
const String circuitCommandeValidation = 'commande_validation';

/// Les collections dont l'état est protégé contre la régression.
const Set<String> collectionsCircuitAchat = {'besoins', 'commandes'};

/// Le champ qui porte l'état dans chaque collection.
String champEtatCircuit(String collection) => collection == 'commandes' ? 'statutCommande' : 'etape';

/// Les rangs. `accorde`, `rejete` et `complement` sont trois DÉCISIONS de même rang (l'une exclut les autres) ; `distribue` et `livre` sont deux fins.
const Map<String, int> _rangBesoin = {
  'brouillon': 0,
  'soumis': 1,
  'controle_stock': 2,
  'validation_da': 3,
  'accorde': 4,
  'rejete': 4,
  'complement': 4,
  'prepare': 5,
  'livre': 6,
  'distribue': 6,
  'cloture': 7,
};
const Map<String, int> _rangCommande = {
  'brouillon': 0,
  'attente_validation': 1,
  'validee': 2,
  'transmise': 3,
  'livree': 4,
  'soldee': 5,
};

/// Le rang d'un état, `null` s'il est inconnu (jamais deviné : une fusion qui ne connaît pas l'état ne tranche pas).
int? rangCircuit(String collection, Object? etat) => (collection == 'commandes' ? _rangCommande : _rangBesoin)['$etat'];

/// Les états que SEULE la mère écrit (par l'application d'un dépôt) : un fileul qui les écrit lui-même est refusé en le nommant.
const Map<String, Set<String>> circuitEtatsReserves = {
  'besoins': {'accorde', 'rejete', 'complement'},
  'commandes': {'validee'},
};

/// Les états qui supposent que l'arbitrage est déjà détenu par la mère.
const Map<String, Set<String>> _enAval = {
  'besoins': {'prepare', 'livre', 'distribue', 'cloture'},
  'commandes': {'transmise', 'livree', 'soldee'},
};

/// Les états qui valent « arbitrage détenu ».
const Map<String, Set<String>> _arbitrageDetenu = {
  'besoins': {'accorde', 'prepare', 'livre', 'distribue', 'cloture'},
  'commandes': {'validee', 'transmise', 'livree', 'soldee'},
};

/// L'état le plus avancé d'un bon à la création qu'un fileul peut écrire : tout ce qui précède l'arbitrage.
const Map<String, int> _rangMaxCreation = {'besoins': 3, 'commandes': 1};

/// Un refus de la mère : code, motif, geste (les trois champs d'un refus nommé du protocole).
typedef RefusCircuit = ({String code, String motif, String geste});

/// Le contrôle que la MÈRE refait sur chaque écriture d'un poste (hors mère) dans `besoins` ou `commandes`. [type] : `creer` ou `modifier`. [champs] : ce que l'opération écrit.
/// [etatActuel] : l'état que la mère détient (`null` à la création). `null` rendu : l'écriture est acceptable.
RefusCircuit? refusCircuitAchat(String collection, String type, Map<String, Object?> champs, {Object? etatActuel}) {
  if (!collectionsCircuitAchat.contains(collection)) return null;
  final champ = champEtatCircuit(collection);
  final nouveau = champs[champ];
  final quoi = collection == 'commandes' ? 'une commande' : 'un bon de besoins';
  if (type == 'creer') {
    if (nouveau == null) return null;
    final r = rangCircuit(collection, nouveau);
    if (r == null) return (code: 'etat_inconnu', motif: 'État inconnu : $nouveau.', geste: 'Choisir un état du circuit');
    if (r > _rangMaxCreation[collection]!) {
      return (
        code: 'arbitrage_requis',
        motif: 'Un poste ne crée pas $quoi déjà décidé (« $nouveau ») : l’arbitrage ne s’écrit que par le dépôt du validateur, appliqué par la mère.',
        geste: 'Créer le bon, puis le soumettre à l’arbitrage'
      );
    }
    return null;
  }
  if (nouveau == null || '$nouveau' == '$etatActuel') return null;
  final rn = rangCircuit(collection, nouveau), ra = rangCircuit(collection, etatActuel);
  if (rn == null) return (code: 'etat_inconnu', motif: 'État inconnu : $nouveau.', geste: 'Choisir un état du circuit');
  if (ra != null && rn < ra) {
    return (
      code: 'etat_regressif',
      motif: '$quoi ne revient jamais en arrière : il est « $etatActuel », il ne repasse pas à « $nouveau » (un état déjà posé ne se défait pas par une fusion tardive).',
      geste: 'Établir un nouveau bon plutôt que de faire reculer celui-ci'
    );
  }
  if (circuitEtatsReserves[collection]!.contains('$nouveau')) {
    return (
      code: 'arbitrage_reserve',
      motif: 'L’état « $nouveau » est le fait du validateur : il se DÉPOSE depuis son poste et la mère l’applique sous son rôle ; un poste ne l’écrit pas lui-même.',
      geste: 'Déposer l’arbitrage depuis l’écran du circuit'
    );
  }
  if (_enAval[collection]!.contains('$nouveau') && !_arbitrageDetenu[collection]!.contains('$etatActuel')) {
    return (
      code: 'arbitrage_requis',
      motif: 'L’état « $nouveau » suppose l’arbitrage, que la mère ne détient pas encore (état actuel : « $etatActuel »).',
      geste: 'Attendre la confirmation de la mère, puis reprendre'
    );
  }
  return null;
}

/// FUSION d'un bon que deux postes ont modifié : l'état ne régresse jamais. [fusion] est la fusion champ à champ déjà faite ; la fonction la corrige. Quand les deux versions portent
/// une décision de même rang et différente, la PLUS ANCIENNE l'emporte (le même résultat partout : la fusion converge), et la décision perdante est nommée (`arbitrageConcurrent`),
/// jamais effacée en silence. [refusLocal] : la mère a refusé l'écriture locale de l'état ; elle ne doit pas l'emporter. [posteFileul] : ce poste n'est pas la mère ; un état RÉSERVÉ
/// (accordé, rejeté, complément, validée) que le journal ne porte pas n'a pas pu être posé légitimement ici (il ne naît que du dépôt appliqué par la mère, qui revient par le journal) :
/// la mère l'a refusé ou ne l'a pas encore, et la version du journal l'emporte. Sans cette règle, le refus de la mère — qui arrive de façon asynchrone, par la file du fileul —
/// laisserait pour toujours au poste un arbitrage que personne n'a rendu.
Map<String, Object?> fusionnerCircuitAchat(String collection, Map<String, Object?> fusion, Map<String, Object?> local, Map<String, Object?> recu, {bool refusLocal = false, bool posteFileul = false}) {
  final champ = champEtatCircuit(collection);
  final el = local[champ], er = recu[champ];
  if (er == null || '$el' == '$er') return fusion;
  final rl = rangCircuit(collection, el), rr = rangCircuit(collection, er);
  if (rr == null) return fusion;
  final inventeIci = posteFileul && circuitEtatsReserves[collection]!.contains('$el');
  var gagneRecu = rl == null || rr > rl || refusLocal || inventeIci;
  if (!gagneRecu && rl == rr && !inventeIci) {
    // Deux décisions de même rang : la plus ancienne l'emporte, à défaut l'ordre alphabétique (déterministe).
    final dl = '${local['arbitreLe'] ?? ''}', dr = '${recu['arbitreLe'] ?? ''}';
    gagneRecu = dr.isNotEmpty && (dl.isEmpty || dr.compareTo(dl) < 0 || (dr == dl && '$er'.compareTo('$el') < 0));
    final perdant = gagneRecu ? local : recu;
    final gagnant = gagneRecu ? recu : local;
    if (collection == 'besoins') {
      fusion['arbitrageConcurrent'] = {'etat': perdant[champ], 'par': perdant['arbitrePar'], 'le': perdant['arbitreLe'], 'retenu': gagnant['arbitrePar']};
    }
  }
  if (gagneRecu) {
    fusion[champ] = er;
    if (collection == 'besoins') {
      for (final k in const ['arbitreLe', 'arbitrePar', 'motifArbitrage', 'valideePar']) {
        if (recu.containsKey(k)) {
          fusion[k] = recu[k];
        } else {
          fusion.remove(k);
        }
      }
    } else {
      for (final k in const ['valideePar', 'dateValidation', 'valideeParAgent']) {
        if (recu.containsKey(k)) {
          fusion[k] = recu[k];
        }
      }
    }
  } else {
    fusion[champ] = el;
  }
  return fusion;
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// LE DÉPÔT D'UN ARBITRAGE OU D'UNE VALIDATION DE COMMANDE
// ---------------------------------------------------------------------------------------------------------------------------------------

/// Les décisions déposables sur un besoin ; une commande n'a que `valider`.
const List<String> circuitDecisions = ['valider', 'rejeter', 'complement'];

Arbitrage _arbitrage(String d) => switch (d) {
      'rejeter' => Arbitrage.rejeter,
      'complement' => Arbitrage.complement,
      _ => Arbitrage.valider,
    };

/// L'identité d'un bon d'un poste à l'autre : l'identité de synchronisation, à défaut l'identifiant (un poste non rattaché).
String cleCircuit(Map<String, Object?> bon) => '${bon['idSync'] ?? bon['id']}';

Map<String, Object?>? _trouver(Iterable<Map<String, Object?>> fiches, String cible) {
  for (final f in fiches) {
    if (f['statut'] == 'archive') continue;
    if ('${f['idSync']}' == cible || '${f['id']}' == cible) return f;
  }
  return null;
}

/// Le contrôle UNIQUE des deux circuits (poste à blanc, mère à l'application). Rend `null` si le geste est recevable, sinon un refus NOMMÉ. `sansEffet` : rendu quand le bon est
/// DÉJÀ dans l'état voulu (rejouable sans effet double).
({RefusValidation? refus, bool sansEffet, Map<String, Object?>? bon}) _controler({
  required String famille,
  required String cible,
  required String decision,
  required String motif,
  required String role,
  required Iterable<Map<String, Object?>> besoins,
  required Iterable<Map<String, Object?>> commandes,
  Iterable<String>? validateurs,
}) {
  RefusValidation r(String c, String m, String? g) => RefusValidation(c, m, g);
  if (famille != circuitBesoinArbitrage && famille != circuitCommandeValidation) {
    return (refus: r('FAMILLE_INCONNUE', 'Circuit inconnu : $famille.', null), sansEffet: false, bon: null);
  }
  if (!estArbitre(role, validateurs: validateurs)) {
    return (
      refus: r('VALIDATION_RESERVEE', 'Arbitrer un besoin ou valider une commande (RG-04) revient aux rôles réglés comme validateurs par la clinique (d’origine : la Directrice Administrative) : le rôle « $role » ne le peut pas.', 'Demander au validateur des commandes de la clinique'),
      sansEffet: false,
      bon: null
    );
  }
  if (!circuitDecisions.contains(decision) || (famille == circuitCommandeValidation && decision != 'valider')) {
    return (refus: r('DECISION_INCONNUE', 'Décision inconnue : $decision.', null), sansEffet: false, bon: null);
  }
  final bon = _trouver(famille == circuitBesoinArbitrage ? besoins : commandes, cible);
  if (bon == null) {
    return (refus: r('INTROUVABLE', 'Le bon ${famille == circuitBesoinArbitrage ? 'de besoins' : 'de commande'} $cible est introuvable ou archivé.', 'Rafraîchir le poste'), sansEffet: false, bon: null);
  }
  if (famille == circuitBesoinArbitrage) {
    if (decision != 'valider' && motif.trim().isEmpty) {
      return (refus: r('MOTIF_OBLIGATOIRE', 'Le motif est obligatoire.', 'Saisir le motif du refus ou du complément demandé'), sansEffet: false, bon: bon);
    }
    final voulue = switch (decision) { 'rejeter' => 'rejete', 'complement' => 'complement', _ => 'accorde' };
    final etape = '${bon['etape']}';
    if (etape == voulue) return (refus: null, sansEffet: true, bon: bon);
    if (!const ['soumis', 'controle_stock', 'validation_da'].contains(etape)) {
      final deja = (rangCircuit('besoins', etape) ?? 0) >= 4;
      return (
        refus: r(deja ? 'DEJA_ARBITRE' : 'PAS_SOUMIS',
            deja
                ? 'Ce besoin est déjà « ${etatBesoin(etape).libelle.toLowerCase()} »${bon['arbitrePar'] == null ? '' : ' par ${bon['arbitrePar']}'} : le premier arbitrage fait foi.'
                : 'Ce besoin n’est pas soumis à l’arbitrage (état : ${etatBesoin(etape).libelle.toLowerCase()}).',
            deja ? 'Aucun' : 'Attendre que le service soumette son bon'),
        sansEffet: false,
        bon: bon
      );
    }
    return (refus: null, sansEffet: false, bon: bon);
  }
  final s = '${bon['statutCommande']}';
  if (s == 'validee' || (rangCircuit('commandes', s) ?? 0) >= 2) return (refus: null, sansEffet: true, bon: bon);
  if (s != 'attente_validation') {
    return (refus: r('PAS_SOUMISE', 'Cette commande n’est pas en attente de validation (état : ${libelleCommande(s).toLowerCase()}).', 'Attendre qu’elle soit soumise'), sansEffet: false, bon: bon);
  }
  return (refus: null, sansEffet: false, bon: bon);
}

/// DÉPOSE l'arbitrage d'un besoin ou la validation d'une commande depuis un poste rattaché. Les contrôles sont ceux de l'application, à blanc : un refus se NOMME dès le poste, avant tout
/// dépôt. Un dépôt identique qui attend déjà la mère n'est pas doublé.
VerdictDepot circuitDeposer({
  required String famille,
  required Map<String, Object?> bon,
  String decision = 'valider',
  String motif = '',
  required String role,
  required String acteur,
  required String poste,
  required DateTime maintenant,
  required Iterable<Map<String, Object?>> besoins,
  required Iterable<Map<String, Object?>> commandes,
  required List<Map<String, Object?>> depots,
  required String Function() nouvelId,
  Iterable<String>? validateurs,
}) {
  final cible = cleCircuit(bon);
  final c = _controler(famille: famille, cible: cible, decision: decision, motif: motif, role: role, besoins: besoins, commandes: commandes, validateurs: validateurs);
  if (c.refus != null) return VerdictDepot.refus(c.refus!);
  for (final d in depots) {
    if (d['statut'] != 'archive' && d['etat'] == valDepotDeposee && d['genre'] == valGenreCircuitAchat && d['famille'] == famille && d['cible'] == cible) {
      return VerdictDepot.ok(d, dejaDepose: true);
    }
  }
  final ref = '${c.bon!['reference'] ?? cible}';
  return VerdictDepot.ok({
    'id': nouvelId(),
    'statut': 'actif',
    'genre': valGenreCircuitAchat,
    'famille': famille,
    'cible': cible,
    'decision': decision,
    'libelle': famille == circuitBesoinArbitrage ? 'Arbitrage du besoin $ref' : 'Validation de la commande $ref',
    'etat': valDepotDeposee,
    'demandeRole': role,
    'demandePar': acteur,
    'demandePoste': poste,
    'demandeLe': valInstant(maintenant),
    if (motif.trim().isNotEmpty) 'motif': motif.trim(),
  });
}

/// Ce que la mère écrit quand un dépôt de circuit s'applique : la collection, la fiche, le patch, et la ligne de journal (RG-12).
class EcritureCircuit {
  const EcritureCircuit({required this.collection, required this.ficheId, required this.patch, required this.action, required this.entite, required this.reference, required this.apres});
  final String collection;
  final String ficheId;
  final Map<String, Object?> patch;
  final String action;
  final String entite;
  final String reference;
  final Map<String, Object?> apres;
}

/// Le verdict d'un dépôt de circuit : l'état à écrire sur la fiche, le refus éventuel, l'écriture à faire.
class ApplicationCircuit {
  const ApplicationCircuit({required this.etat, this.code, this.motif, this.geste, this.ecriture});
  final String etat;
  final String? code;
  final String? motif;
  final String? geste;
  final EcritureCircuit? ecriture;
}

/// APPLIQUE un dépôt de circuit sur la mère, sous le RÔLE et le NOM de son auteur, tous les contrôles refaits avec les données de la mère. La date est celle du GESTE (`demandeLe`).
/// `null` : rien à faire (déjà traité, ou autre genre). Rejouable : un bon déjà dans l'état voulu rend `sans_effet`.
ApplicationCircuit? circuitAppliquer(
  Map<String, Object?> depot, {
  required Iterable<Map<String, Object?>> besoins,
  required Iterable<Map<String, Object?>> commandes,
  required DateTime maintenant,
  Iterable<String>? validateurs,
  String libelleValidateur = directriceAdministrative,
}) {
  if (depot['genre'] != valGenreCircuitAchat || depot['etat'] != valDepotDeposee || depot['statut'] == 'archive') return null;
  final famille = '${depot['famille']}';
  final decision = '${depot['decision'] ?? 'valider'}';
  final motif = '${depot['motif'] ?? ''}';
  final quand = DateTime.tryParse('${depot['demandeLe'] ?? ''}') ?? maintenant;
  final c = _controler(
      famille: famille, cible: '${depot['cible']}', decision: decision, motif: motif, role: '${depot['demandeRole']}', besoins: besoins, commandes: commandes, validateurs: validateurs);
  if (c.refus != null) {
    return ApplicationCircuit(etat: valDepotRefusee, code: c.refus!.code, motif: c.refus!.motif, geste: c.refus!.geste);
  }
  final bon = c.bon!;
  if (c.sansEffet) {
    return ApplicationCircuit(
        etat: valDepotSansEffet,
        code: famille == circuitBesoinArbitrage ? 'DEJA_ARBITRE' : 'DEJA_VALIDE',
        motif: famille == circuitBesoinArbitrage
            ? 'Ce besoin a déjà reçu cette décision${bon['arbitrePar'] == null ? '' : ' (${bon['arbitrePar']})'} : rien n’est écrit une seconde fois.'
            : 'Cette commande est déjà validée${bon['valideePar'] == null ? '' : ' (${bon['valideePar']})'} : rien n’est écrit une seconde fois.');
  }
  final acteur = '${depot['demandePar']}';
  if (famille == circuitBesoinArbitrage) {
    final a = arbitrerBon(bon: bon, quoi: _arbitrage(decision), motif: motif, utilisateur: acteur, maintenant: valInstant(quand));
    return ApplicationCircuit(
        etat: valDepotAppliquee,
        ecriture: EcritureCircuit(
            collection: 'besoins',
            ficheId: '${bon['id']}',
            patch: a.patch,
            action: 'Arbitrage du besoin',
            entite: 'Besoin',
            reference: '${bon['reference']}',
            apres: {'décision': decision, 'étape': a.patch['etape'], if (motif.trim().isNotEmpty) 'motif': motif.trim()}));
  }
  final jour = '${quand.year.toString().padLeft(4, '0')}-${quand.month.toString().padLeft(2, '0')}-${quand.day.toString().padLeft(2, '0')}';
  final patch = {...validationCommande(jour: jour, validateur: libelleValidateur), 'valideeParAgent': acteur};
  return ApplicationCircuit(
      etat: valDepotAppliquee,
      ecriture: EcritureCircuit(
          collection: 'commandes',
          ficheId: '${bon['id']}',
          patch: patch,
          action: 'Validation de la commande (RG-04)',
          entite: 'Commande',
          reference: '${bon['reference']}',
          apres: {'statut': 'validee', 'validée par': acteur}));
}

/// Les notifications de poste que le verdict d'un arbitrage fait naître (le comptable ET le gestionnaire de stock) : celles de `arbitrerBon`, reconstruites depuis l'ÉTAT DU BON — donc
/// lisibles sur TOUT poste qui détient le bon accordé, et pas seulement celui où le geste a été fait. [bon] doit être accordé (ou au-delà).
List<Map<String, Object?>> notificationsDeBesoinAccorde(Map<String, Object?> bon) {
  if ((rangCircuit('besoins', bon['etape']) ?? 0) < 4 || const ['rejete', 'complement'].contains('${bon['etape']}')) return const [];
  final a = arbitrerBon(bon: bon, quoi: Arbitrage.valider, motif: '${bon['motifArbitrage'] ?? ''}', utilisateur: '${bon['arbitrePar'] ?? ''}', maintenant: '${bon['arbitreLe'] ?? ''}');
  return a.notifications;
}
