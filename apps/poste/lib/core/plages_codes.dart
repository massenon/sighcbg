import 'dart:async';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';

/// LES CODES DE DOSSIER NE SE CHEVAUCHENT JAMAIS ENTRE POSTES (RG-01 ; limite levée le 03/11/2026).
///
/// Chaque poste d'une clinique (la mère comme les fileuls) reçoit de la MÈRE des PLAGES de numéros : le poste ne tire un code que dans sa plage, hors ligne
/// comme en ligne, et deux postes ne peuvent donc plus attribuer le même numéro. La plage en cours vit au magasin (collection `plagesCodes`, locale au poste,
/// jamais synchronisée) : elle survit à un redémarrage. Quand il reste peu de numéros, le poste en redemande une, en tâche de fond.
///
/// Un poste SANS plage (autonome, mère pas encore activée) garde la règle historique (plus grand rang + 1) : rien ne change pour lui. Un poste rattaché dont la
/// plage est ÉPUISÉE hors ligne n'invente pas de numéro : il attribue un code PROVISOIRE (`PROV-…`), que la mère remplace à la première synchronisation.
class PlagesCodes {
  PlagesCodes._(this.magasin);
  final Magasin magasin;
  static final Expando<PlagesCodes> _par = Expando<PlagesCodes>();

  /// Le service du magasin donné (créé à la première demande).
  static PlagesCodes de(Magasin m) => _par[m] ??= PlagesCodes._(m);

  /// Demande une plage à la mère : `(taille, minimum, année) -> (début, fin)`. Posée par `main` quand le poste est rattaché ou mère ; absente sinon.
  /// SÉRIES ANNUELLES (RG-01, lot 0, E3830) : une plage appartient à UNE année et ne code que les dossiers créés cette année-là ; au changement d'année le poste
  /// demande une plage de la nouvelle série (qui repart à 1 chez la mère) et n'entame plus celles de l'année écoulée.
  Future<(int, int)> Function(int taille, int minimum, int annee)? obtenir;

  /// Combien de numéros il faut avoir devant soi avant d'en redemander.
  static const int seuilRecharge = 10;
  static const int taillePlage = 50;
  static const String collection = 'plagesCodes';

  bool _enCours = false;

  bool get actif => obtenir != null;

  /// Les plages détenues par ce poste, la plus ancienne d'abord ; avec [annee], celles de cette série seulement (une plage sans année n'appartient à aucune).
  List<Fiche> plagesDe([int? annee]) => [
        for (final f in magasin.collection(collection).toutes)
          if (f['statut'] != 'archive' && f['nom'] == null && (annee == null || f['annee'] == annee)) f
      ]..sort((a, b) => (a['debut'] as num).compareTo(b['debut'] as num));

  List<Fiche> get plages => plagesDe();

  /// Le numéro restant dans les plages détenues (de la série [annee] quand elle est donnée).
  int restantsDe([int? annee]) => plagesDe(annee).fold(0, (n, f) => n + ((f['fin'] as num).toInt() - (f['prochain'] as num).toInt() + 1).clamp(0, 1 << 30));

  int get restants => restantsDe();

  /// LES PLAGES D'AVANT LES SÉRIES ANNUELLES (reliquat de numérotation, 17/11/2026). Une plage reçue avant que les plages portent leur année n'appartient à aucune série ([plagesDe] la laisse de côté :
  /// elle ne code plus rien, un code provisoire plutôt qu'une année devinée). Elle est RATTACHÉE à l'année que ses codes DÉJÀ attribués désignent (le compteur d'alors était unique : le rang d'un code de la
  /// plage identifie son année), jamais à une année devinée : sans code attribué dans la plage, ou avec des codes de plusieurs années, elle reste sans année et se compte dans `sansAnnee`. Seule la plage
  /// reçoit son année : aucun code attribué n'est réécrit (RG-01). Idempotent. Rend le nombre de plages rattachées et celui des plages que rien ne permet de rattacher.
  ({int rattachees, int sansAnnee}) rattacherAnciennes({DateTime? maintenant}) {
    final col = magasin.collection(collection);
    final anciennes = [
      for (final f in col.toutes)
        if (f['statut'] != 'archive' && f['nom'] == null && f['annee'] == null) f
    ];
    if (anciennes.isEmpty) return (rattachees: 0, sansAnnee: 0);
    final r = rattacherPlagesAnciennes([for (final f in anciennes) PlageNumeros.depuis(f)!], [for (final p in magasin.collection('patients').toutes) p['code']],
        reference: maintenant ?? DateTime.now());
    for (final e in r.rattachees.entries) {
      col.appliquerDistante({...anciennes[e.key], 'annee': e.value});
    }
    return (rattachees: r.rattachees.length, sansAnnee: r.sansAnnee.length);
  }

  int _plusGrandRang(Iterable<Fiche> patients, int annee) {
    final suffixe = '$annee'.substring('$annee'.length - 2);
    // Tous les sigles se relisent (`lireCodePatient`) : un code attribué sous un sigle antérieur garde son rang (RG-01, jamais réutilisé).
    var max = 0;
    for (final p in patients) {
      final c = lireCodePatient(p['code']);
      if (c != null && c.annee == suffixe && c.rang > max) max = c.rang;
    }
    return max;
  }

  /// Demande une plage si le stock de numéros est bas. Sans effet hors ligne : l'échec est silencieux ICI (la plage restante sert) et se redit au tirage
  /// suivant ; le seul cas qui se voit est l'épuisement, qui donne un code provisoire.
  Future<void> recharger({DateTime? maintenant}) async {
    final demander = obtenir;
    final annee = (maintenant ?? DateTime.now()).year;
    if (demander == null || _enCours || restantsDe(annee) > seuilRecharge) return;
    _enCours = true;
    try {
      final minimum = _plusGrandRang(magasin.collection('patients').toutes, annee) + 1;
      final (debut, fin) = await demander(taillePlage, minimum, annee);
      // L'identifiant porte l'année : la série repart à 1 chaque année, deux plages de deux années peuvent commencer au même rang.
      magasin.collection(collection).ajouterSansJournal({'id': 'PLG$annee-$debut', 'debut': debut, 'fin': fin, 'prochain': debut, 'annee': annee});
    } catch (_) {
      // Hors ligne ou mère arrêtée : on garde ce qu'on a.
    } finally {
      _enCours = false;
    }
  }

  /// Le prochain code de dossier, pour un dossier créé à [maintenant]. Plage de CETTE ANNÉE détenue : le numéro suivant de la plage. Plage de l'année épuisée (ou
  /// seules des plages d'une autre année) : un code PROVISOIRE, que la mère remplace en lisant la date de création. Aucun service de plage : la règle historique.
  String prochainCode(Iterable<Fiche> patients, DateTime maintenant) {
    if (!actif) return patProchainCode(patients, maintenant);
    final col = magasin.collection(collection);
    for (final p in plagesDe(maintenant.year)) {
      final n = (p['prochain'] as num).toInt();
      if (n <= (p['fin'] as num).toInt()) {
        // La plage avance DÈS la réservation : l'écran de saisie peut rester ouvert, et un second guichet ne reçoit pas le même numéro.
        col.appliquerDistante({...p, 'prochain': n + 1});
        unawaited(recharger(maintenant: maintenant));
        return codePatient(n, maintenant.year);
      }
    }
    unawaited(recharger(maintenant: maintenant));
    return 'PROV-${maintenant.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
  }
}


/// LES NUMÉROS DE BONS NE SE CHEVAUCHENT JAMAIS ENTRE POSTES (Direction, 16/11/2026) : même mécanisme que les codes de dossier (plages reçues de la mère, un carnet PAR SÉRIE : `besoins`,
/// `commandes`), mêmes règles. Deux fileuls hors ligne qui exprimaient chacun « le plus grand rang + 1 » produisaient deux `BEB-2026-0004` : avec une plage, chacun tire dans la sienne.
/// Plage épuisée hors ligne : une référence PROVISOIRE (`BEB-2026-PROV-…`), unique par poste et par instant, qui ne ressemble à aucun numéro de série et que personne ne confondra ;
/// elle n'est PAS renumérotée par la mère (un bon n'est pas une pièce certifiante ; la renuméroter romprait le lien avec le papier déjà remis au service). Les plages vivent dans la
/// même collection locale que celles des dossiers, distinguées par le champ `nom`.
class PlagesNumeros {
  PlagesNumeros._(this.magasin);
  final Magasin magasin;
  static final Expando<PlagesNumeros> _par = Expando<PlagesNumeros>();
  static PlagesNumeros de(Magasin m) => _par[m] ??= PlagesNumeros._(m);

  /// Demande une plage à la mère : `(nom, taille, minimum, annee) -> (début, fin)`. Posée par `main` quand le poste est rattaché ou mère ; absente sinon. [annee] : l'année de la plage, donnée
  /// pour une série À REMISE ANNUELLE (la série repart à 1, un rang d'une plage 2026 ne numérote jamais une pièce de 2027) ; absente pour une série qui ne se remet pas à 1.
  Future<(int, int)> Function(String nom, int taille, int minimum, {int? annee})? obtenir;

  static const int seuilRecharge = 10;
  static const int taillePlage = 50;
  final Set<String> _enCours = {};

  bool get actif => obtenir != null;

  /// Les plages du carnet [nom] utilisables pour l'année [annee] : celles de CETTE année d'abord, puis celles d'avant les séries annuelles (sans année : tolérées tant qu'elles servent, comme avant) ;
  /// sans [annee], toutes. Une plage d'une AUTRE année ne sert jamais.
  List<Fiche> plages(String nom, {int? annee}) => [
        for (final f in magasin.collection(PlagesCodes.collection).toutes)
          if (f['statut'] != 'archive' && f['nom'] == nom && (annee == null || f['annee'] == null || f['annee'] == annee)) f
      ]..sort((a, b) {
          // Celles de l'année demandée avant les anciennes, puis par rang.
          final pa = a['annee'] == null ? 1 : 0, pb = b['annee'] == null ? 1 : 0;
          return pa != pb ? pa.compareTo(pb) : (a['debut'] as num).compareTo(b['debut'] as num);
        });

  int restants(String nom, {int? annee}) =>
      plages(nom, annee: annee).fold(0, (n, f) => n + ((f['fin'] as num).toInt() - (f['prochain'] as num).toInt() + 1).clamp(0, 1 << 30));

  /// L'année à demander pour la série [serie] à [date] : l'année de la PIÈCE si la série repart à 1 chaque année, sinon aucune (carnet unique).
  static int? anneeDemandee(String serie, Object? date) {
    final s = Numerotation.serie(serie, date: date);
    return s.remiseAnnuelle ? anneeDePiece(date) : null;
  }

  /// [serie] : le code de la série au référentiel de numérotation (`achats.besoins`) ; [date] : la date de la pièce (l'année du numéro, la version de la série).
  Future<void> recharger(String nom, String serie, Iterable<Fiche> Function() fiches, {Object? date}) async {
    final demander = obtenir;
    final annee = anneeDemandee(serie, date);
    final cleEnCours = annee == null ? nom : '$nom/$annee';
    if (demander == null || _enCours.contains(cleEnCours) || restants(nom, annee: annee) > seuilRecharge) return;
    _enCours.add(cleEnCours);
    try {
      final (debut, fin) = await demander(nom, taillePlage, rangMaximal(serie, date: date, existants: fiches()) + 1, annee: annee);
      magasin.collection(PlagesCodes.collection).ajouterSansJournal({
        'id': annee == null ? 'PLG-$nom-$debut' : 'PLG-$nom-$annee-$debut',
        'nom': nom,
        'debut': debut,
        'fin': fin,
        'prochain': debut,
        if (annee != null) 'annee': annee,
      });
    } catch (_) {
      // Hors ligne ou mère arrêtée : on garde ce qu'on a (un refus nommé de la mère, chevauchement compris, ne crée AUCUNE plage).
    } finally {
      _enCours.remove(cleEnCours);
    }
  }

  /// La prochaine référence du carnet `nom`, numérotée par la série [serie] du référentiel de numérotation (lot 2, 16/11/2026 : plus aucun préfixe ni millésime
  /// écrit ici) : le numéro suivant de la plage détenue, formaté selon la version de la série en vigueur à [date] (l'année est celle de la pièce) ; plage épuisée,
  /// une référence PROVISOIRE de la série (`BEB-2026-PROV-…`) ; sans service de plage, la règle historique (plus grand rang de la série + 1).
  String reference(String nom, String serie, Iterable<Fiche> existantes, {required DateTime date}) {
    if (!actif) return numeroSuivant(serie, date: date, existants: existantes);
    final col = magasin.collection(PlagesCodes.collection);
    for (final p in plages(nom, annee: anneeDemandee(serie, date))) {
      final n = (p['prochain'] as num).toInt();
      if (n <= (p['fin'] as num).toInt()) {
        col.appliquerDistante({...p, 'prochain': n + 1});
        unawaited(recharger(nom, serie, () => magasin.collection(nom).toutes, date: date));
        return numeroFormate(serie, date: date, rang: n);
      }
    }
    unawaited(recharger(nom, serie, () => magasin.collection(nom).toutes, date: date));
    return numeroProvisoire(serie, date: date, suffixe: date.millisecondsSinceEpoch.toRadixString(36).toUpperCase());
  }
}
