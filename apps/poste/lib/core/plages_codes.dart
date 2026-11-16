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

  /// Demande une plage à la mère : `(nom, taille, minimum) -> (début, fin)`. Posée par `main` quand le poste est rattaché ou mère ; absente sinon.
  Future<(int, int)> Function(String nom, int taille, int minimum)? obtenir;

  static const int seuilRecharge = 10;
  static const int taillePlage = 50;
  final Set<String> _enCours = {};

  bool get actif => obtenir != null;

  List<Fiche> plages(String nom) => [
        for (final f in magasin.collection(PlagesCodes.collection).toutes)
          if (f['statut'] != 'archive' && f['nom'] == nom) f
      ]..sort((a, b) => (a['debut'] as num).compareTo(b['debut'] as num));

  int restants(String nom) => plages(nom).fold(0, (n, f) => n + ((f['fin'] as num).toInt() - (f['prochain'] as num).toInt() + 1).clamp(0, 1 << 30));

  /// [serie] : le code de la série au référentiel de numérotation (`achats.besoins`) ; [date] : la date de la pièce (l'année du numéro, la version de la série).
  Future<void> recharger(String nom, String serie, Iterable<Fiche> Function() fiches, {Object? date}) async {
    final demander = obtenir;
    if (demander == null || _enCours.contains(nom) || restants(nom) > seuilRecharge) return;
    _enCours.add(nom);
    try {
      final (debut, fin) = await demander(nom, taillePlage, rangMaximal(serie, date: date, existants: fiches()) + 1);
      magasin.collection(PlagesCodes.collection).ajouterSansJournal({'id': 'PLG-$nom-$debut', 'nom': nom, 'debut': debut, 'fin': fin, 'prochain': debut});
    } catch (_) {
      // Hors ligne ou mère arrêtée : on garde ce qu'on a.
    } finally {
      _enCours.remove(nom);
    }
  }

  /// La prochaine référence du carnet `nom`, numérotée par la série [serie] du référentiel de numérotation (lot 2, 16/11/2026 : plus aucun préfixe ni millésime
  /// écrit ici) : le numéro suivant de la plage détenue, formaté selon la version de la série en vigueur à [date] (l'année est celle de la pièce) ; plage épuisée,
  /// une référence PROVISOIRE de la série (`BEB-2026-PROV-…`) ; sans service de plage, la règle historique (plus grand rang de la série + 1).
  String reference(String nom, String serie, Iterable<Fiche> existantes, {required DateTime date}) {
    if (!actif) return numeroSuivant(serie, date: date, existants: existantes);
    final col = magasin.collection(PlagesCodes.collection);
    for (final p in plages(nom)) {
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
