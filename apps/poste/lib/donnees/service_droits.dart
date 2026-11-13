import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_installation.dart';
import 'magasin.dart';

/// LES DÉCISIONS DE DROITS AU POSTE (Direction, 10/11/2026) : la matrice des rôles n'est jamais figée.
///
/// Un droit se décide à TOUT moment, depuis la mère ou depuis un poste habilité, et chaque décision se propage à tous les postes de la clinique sans qu'aucun
/// ne redémarre. Le mécanisme tient en trois gestes :
///
///  * **le poste qui décide** écrit une DÉCISION (collection `decisionsDroits`, une fiche immuable : rôle, clés changées, ancien droit vu, motif, auteur, horodatage).
///    Sur la mère (ou un poste sans clinique) elle s'applique aussitôt à la fiche `rbac` du rôle ; sur un fileul rattaché, qui ne peut pas écrire `rbac` (famille R,
///    garde « réglé sur la mère »), elle part à la mère par le pont d'activité ;
///  * **la mère** juge chaque décision reçue (l'auteur doit pouvoir éditer « Rôles et permissions », motif obligatoire), l'applique clé par clé — la plus récente par
///    horodatage l'emporte, rien n'est écrasé en silence (`decisions_droits.dart`) —, journalise l'ancien et le nouveau droit, l'auteur et le motif (RG-12), puis marque
///    l'issue sur la décision ;
///  * **les fileuls** reçoivent la fiche `rbac` par la configuration diffusée de la mère (`ApplicateurConfiguration`) ; la coque recalcule alors ses droits à chaud.
///
/// Les décisions ne se suppriment jamais (RG-14) : « revenir au défaut d'origine » est une décision de plus.
class ServiceDroits {
  ServiceDroits._(this.magasin);
  static final Expando<ServiceDroits> _instances = Expando('ServiceDroits');
  static ServiceDroits de(Magasin m) => _instances[m] ??= ServiceDroits._(m);

  final Magasin magasin;

  /// Ce poste est-il un fileul rattaché à une clinique ? Ses décisions partent alors à la mère au lieu de s'appliquer ici. Par défaut : l'état d'installation du poste.
  bool Function()? fileulRattache;
  bool get estFileul => (fileulRattache ?? () => ServiceInstallation.de(magasin).rattache)();

  /// La matrice EN FORCE chez celui qui juge : `(rôle, écran) -> peut éditer`. La mère la pose au démarrage (`demarrerMere`).
  bool Function(String role, String ecran)? peutEditer;

  CollectionMagasin get _rbac => magasin.collection('rbac');
  CollectionMagasin get decisions => magasin.collection(drCollectionDecisions);

  Fiche? ficheDuRole(String role) => _rbac.toutes.where((f) => f['role'] == role).firstOrNull;

  final Random _alea = Random();
  int _serie = 0;
  String _nouvelId() => 'DDR-${magasin.horloge().toUtc().millisecondsSinceEpoch.toRadixString(36)}-${(++_serie).toRadixString(36)}-${_alea.nextInt(1 << 30).toRadixString(36)}';

  /// La graine de la fiche du rôle : la fiche du jeu livré avec le poste (`jeu/rbac.json`), jamais modifiée. `null` : rôle créé en exploitation, sans défaut d'origine.
  Fiche? graineDuRole(String role) {
    final f = ficheDuRole(role);
    if (f == null) return null;
    final g = magasin.ficheOrigine('rbac', '${f['id']}');
    return g != null && g['role'] == role ? g : null;
  }

  /// Le nombre de postes de la clinique vus cette semaine (battements `postesClinique`), la mère comprise ; `null` si ce poste n'en sait rien (aucune clinique).
  int? postesDeLaClinique() {
    final lim = magasin.horloge().subtract(const Duration(days: 7));
    final vus = magasin.collection('postesClinique').toutes;
    if (vus.isEmpty) return null;
    return vus.where((p) => (DateTime.tryParse('${p['vuLe'] ?? ''}') ?? DateTime(2000)).isAfter(lim)).length + 1;
  }

  /// Une décision d'un agent : `valeurs` est ce que l'écran écrit (la forme de la fiche `rbac`). Rend ce qui s'est passé et l'ANNULATION, qui est une décision de plus
  /// (visible, journalisée, datée) et non un retour en arrière silencieux.
  ResultatPoseDroits decider({
    required String role,
    required Map<String, Object?> valeurs,
    required String journal,
    required String motif,
    String? auteurRole,
    String genre = 'modification',
  }) {
    final avant = ficheDuRole(role);
    final changements = drDiff(avant, valeurs);
    return _poser(role, changements, journal: journal, motif: motif, auteurRole: auteurRole, genre: genre);
  }

  /// « Revenir au défaut d'origine » : réapplique la graine du rôle en nouvelle version. L'historique reste entier.
  ResultatPoseDroits? revenirAuDefaut({required String role, required String motif, String? auteurRole}) {
    final g = graineDuRole(role);
    if (g == null) return null;
    final ch = drChangementsVersGraine(ficheDuRole(role), g);
    return _poser(role, ch, journal: 'Retour des droits au défaut d’origine', motif: motif, auteurRole: auteurRole, genre: 'defaut_origine');
  }

  ResultatPoseDroits _poser(String role, Map<String, Object?> changements,
      {required String journal, required String motif, String? auteurRole, required String genre}) {
    final avant = ficheDuRole(role);
    final vu = drAplatir(avant);
    if (changements.isEmpty) {
      // Rien ne change : aucune décision à consigner, et l'annulation n'a rien à défaire.
      return ResultatPoseDroits(transmise: false, issue: 'sans_effet', decisionId: '', annuler: () {});
    }
    final id = _nouvelId();
    final dec = drDecision(
        id: id,
        role: role,
        changements: changements,
        avant: vu,
        motif: motif,
        auteur: magasin.utilisateur,
        auteurRole: auteurRole,
        auteurId: magasin.acteur?.utilisateurId,
        poste: magasin.poste,
        decideLe: magasin.horloge(),
        baseVersion: (avant?['version'] as num?)?.toInt() ?? 0,
        genre: genre,
        journal: journal);
    VoidCallback annuler() => () {
          if (changements.isEmpty) return;
          _poser(role, {for (final k in changements.keys) k: vu[k]},
              journal: 'Annulation : $journal', motif: 'Annulation de la décision du ${dateFR(magasin.horloge())} (« $motif »)', auteurRole: auteurRole, genre: 'annulation');
        };
    if (estFileul) {
      // Un fileul ne peut pas écrire `rbac` : la décision part à la mère, qui la jugera, l'appliquera et la diffusera à tous les postes.
      decisions.ajouterSansJournal({...dec, 'id': id}, enTete: true);
      magasin.journaliser('Décision de droits transmise à la mère', 'M14', 'Rôle', role,
          {for (final e in changements.entries) drLibelleCle(e.key): drLibelleValeur(e.key, vu[e.key])},
          {for (final e in changements.entries) drLibelleCle(e.key): drLibelleValeur(e.key, e.value), 'motif': motif, 'décision': id});
      return ResultatPoseDroits(transmise: true, issue: 'en_attente', decisionId: id, annuler: annuler());
    }
    final res = _appliquer(dec, id, journal: journal);
    return ResultatPoseDroits(transmise: false, issue: res.issue, decisionId: id, resultat: res, annuler: annuler());
  }

  /// Applique une décision à la fiche du rôle de CE poste (la mère, ou un poste isolé), journalise (RG-12) et range la décision, traitée, au journal des décisions.
  ResultatDecisionDroits _appliquer(FicheDr dec, String idFiche, {required String journal, Fiche? ficheDecision}) {
    final role = '${dec['role']}';
    final avant = ficheDuRole(role);
    final res = drAppliquer(avant, dec);
    final apresFiche = res.fiche;
    if (apresFiche != null) {
      if (avant != null) {
        final reel = <String, Object?>{for (final e in apresFiche.entries) if (e.key != 'id' && _different(avant[e.key], e.value)) e.key: e.value};
        if (reel.isNotEmpty) _rbac.mettreAJour(avant['id'], reel, journaliser: false);
      } else {
        _rbac.inserer({...apresFiche}, prefixe: 'RBAC');
      }
    }
    final traite = <String, Object?>{
      'statutDemande': res.issue,
      'traiteLe': magasin.horloge().toUtc().toIso8601String(),
      'lignes': [for (final l in res.lignes) l.toJson()],
      'versionApres': (apresFiche ?? avant)?['version'],
    };
    if (ficheDecision != null) {
      decisions.mettreAJour(ficheDecision['id'], traite, journaliser: false);
    } else {
      decisions.ajouterSansJournal({...dec, 'id': idFiche, ...traite}, enTete: true);
    }
    if (res.lignes.isNotEmpty || res.issue == 'refusee') {
      magasin.journaliser(journal, 'M14', 'Rôle', role, res.avantJournal, {
        ...res.apresJournal,
        'motif': dec['motif'],
        'auteur': dec['auteur'],
        'décision': dec['ident'] ?? idFiche,
        'issue': res.issue,
        if (res.ecartees.isNotEmpty) 'écartées (décision plus récente en vigueur)': [for (final l in res.ecartees) drLibelleCle(l.cle)],
        if (res.concurrentes.isNotEmpty)
          'concurrentes': [for (final l in res.concurrentes) '${drLibelleCle(l.cle)} (remplace la décision de ${l.remplaceeParAuteur ?? 'un autre poste'} : « ${l.remplaceeParMotif ?? ''} »)'],
      });
    }
    return res;
  }

  static bool _different(Object? a, Object? b) => '${_canon(a)}' != '${_canon(b)}';
  static Object? _canon(Object? v) => v is Map ? (v.entries.toList()..sort((a, b) => '${a.key}'.compareTo('${b.key}'))).map((e) => '${e.key}=${_canon(e.value)}').join(',') : v;

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // LA MÈRE : juger et appliquer les décisions que les postes lui ont envoyées
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  bool _traitement = false;
  VoidCallback? _ecoute;

  /// À la mère : traite les décisions en attente (au démarrage, puis à chaque décision reçue). [peutEditerEnForce] : la matrice EN FORCE de la mère.
  void demarrerMere({required bool Function(String role, String ecran) peutEditerEnForce}) {
    peutEditer = peutEditerEnForce;
    if (_ecoute != null) return;
    _ecoute = () => scheduleMicrotask(traiterEnAttente);
    decisions.addListener(_ecoute!);
    traiterEnAttente();
  }

  void arreter() {
    if (_ecoute != null) decisions.removeListener(_ecoute!);
    _ecoute = null;
  }

  /// Traite, dans l'ordre des horodatages de décision, chaque décision `en_attente`. Rend le nombre de décisions traitées.
  int traiterEnAttente() {
    if (_traitement) return 0;
    _traitement = true;
    var n = 0;
    try {
      final attente = [
        for (final d in decisions.toutes)
          if (d['statutDemande'] == 'en_attente' && d['statut'] != 'archive') d
      ]..sort((a, b) {
          final c = '${a['decideLe']}'.compareTo('${b['decideLe']}');
          return c != 0 ? c : '${a['ident'] ?? a['id']}'.compareTo('${b['ident'] ?? b['id']}');
        });
      for (final d in attente) {
        final dec = <String, Object?>{...d};
        final jugement = peutEditer == null ? null : drRefusDecision(dec, peutEditer: peutEditer!);
        if (jugement != null || peutEditer == null) {
          final refus = jugement ?? 'La mère ne sait pas encore juger cette décision (matrice des droits non chargée).';
          if (peutEditer == null) continue; // pas de verdict sans matrice : la décision attend
          decisions.mettreAJour(d['id'], {'statutDemande': 'refusee', 'motifRefus': refus, 'traiteLe': magasin.horloge().toUtc().toIso8601String()}, journaliser: false);
          magasin.journaliser('Décision de droits refusée', 'M14', 'Rôle', '${d['role']}', null,
              {'motif': d['motif'], 'auteur': d['auteur'], 'refus': refus, 'décision': d['ident'] ?? d['id']});
          n++;
          continue;
        }
        _appliquer(dec, '${d['id']}', journal: '${d['journal'] ?? 'Décision de droits'}', ficheDecision: d);
        n++;
      }
    } finally {
      _traitement = false;
    }
    return n;
  }
}

class ResultatPoseDroits {
  const ResultatPoseDroits({required this.transmise, required this.issue, required this.decisionId, required this.annuler, this.resultat});

  /// Vrai : le poste est un fileul, la décision est partie à la mère et n'est pas encore appliquée.
  final bool transmise;

  /// `appliquee` · `partielle` · `ecartee` · `sans_effet` · `en_attente` (fileul).
  final String issue;
  final String decisionId;
  final ResultatDecisionDroits? resultat;
  final VoidCallback annuler;
}
