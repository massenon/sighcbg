import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_installation.dart';
import '../donnees/magasin.dart';
import '../import/droits_import.dart' show octetsMaxDe;
import '../import/port_magasin.dart';
import 'configuration_sync.dart' show collectionsConfiguration;
import 'pont_activite.dart' show collectionsActivite, collectionsDeLaMereSeule;

/// LA DEMANDE D'IMPORT AU POSTE (lot IMP-C, décision de la Direction du 12/11/2026, « option c »). La colle entre les règles pures de `packages/domaine/lib/src/import/demande_import.dart`
/// (rejouées sans poste par les tests du domaine et par le banc de synchronisation) et le magasin du poste. Aucune règle d'import ici.
///
/// Même forme que les décisions de droits (`ServiceDroits`) : une fiche descriptive que le fileul dépose, que la MÈRE juge et complète du verdict, et qui revient au fileul par le pont
/// d'activité (famille A, champ à champ, dans les deux sens). Un service par magasin.
///
///  * FILEUL rattaché : un jeu dont les cibles sont de la configuration de la mère s'écrit DIRECTEMENT ici (l'agent le voit aussitôt, les gardes « réglé sur la mère » étant levées pour ce
///    geste seul) et une demande part AUTOMATIQUEMENT à la mère ([importerEtDemander]). Quand le verdict revient, [reconcilierVerdicts] règle l'écriture locale : archivée si la mère
///    l'a retenue, marquée « non retenue par la mère » si elle l'a refusée — jamais disparue en silence — et une notification le dit.
///  * MÈRE : [demarrerMere] puis [traiterEnAttente] — elle REJOUE chaque demande sous le rôle et le nom de son AUTEUR, avec SA matrice en force, applique par le chemin de l'import local
///    ou refuse en nommant, journalise (RG-12) et écrit le verdict sur la même fiche. Le traitement est BRANCHÉ au démarrage de la mère (`main.dart`) : un test le prouve à travers le vrai
///    poste (`demandes_import_sync_test.dart`).
///
/// Un import fait AU POSTE DE LA MÈRE reste local et direct : aucune demande. Un jeu RESTREINT, ou qui écrit aussi de l'activité synchronisée, ne passe jamais par une demande.
class ServiceDemandesImport {
  ServiceDemandesImport._(this.magasin);
  static final Expando<ServiceDemandesImport> _instances = Expando('ServiceDemandesImport');
  static ServiceDemandesImport de(Magasin m) => _instances[m] ??= ServiceDemandesImport._(m);

  final Magasin magasin;

  /// Ce poste est-il un fileul rattaché à une clinique ? Par défaut : l'état d'installation du poste.
  bool Function()? fileulRattache;
  bool get estFileul => (fileulRattache ?? () => ServiceInstallation.de(magasin).rattache)();

  /// L'étiquette de ce poste (rend uniques les identifiants d'une demande et d'une écriture provisoire).
  String etiquette = 'P';

  /// La matrice EN FORCE chez celui qui juge : la mère la pose au démarrage (graine engendrée + décisions de droits superposées à chaud).
  MatriceDroits Function()? matriceEnForce;

  /// Les collections que la mère seule écrit, et celles de l'activité qu'un fileul peut pousser (celles que la mère seule écrit dans le pont en sont retirées : un fileul n'y envoie rien).
  RegimeDemandesImport get regime => RegimeDemandesImport(
        collectionsDeLaMere: collectionsConfiguration(),
        collectionsActivite: collectionsActivite.difference(collectionsDeLaMereSeule),
      );

  CollectionMagasin get demandes => magasin.collection(demandesImportCollection);

  /// Le jeu passe-t-il par une demande SUR CE POSTE ? Seulement sur un fileul rattaché.
  bool passeParUneDemande(JeuImport j) => estFileul && regime.exigeLaMere(j);

  /// Un jeu restreint qui écrit de la configuration ne s'importe qu'au poste de la mère : le fileul le dit.
  bool reserveALaMere(JeuImport j) => estFileul && regime.reserveALaMere(j);

  DateTime get _maintenant => magasin.horloge();
  String get _jour {
    final d = _maintenant;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  int _serie = 0;

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // FILEUL : écrire directement ET déposer la demande
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  /// L'écriture directe puis le dépôt de la demande d'un fichier DÉJÀ vérifié. [profil] et [nomAgent] sont ceux de l'agent connecté (le moteur refuse selon son droit : rien n'est écrit
  /// ni déposé sans lui). Rend le résultat de l'écriture et l'identifiant de la demande.
  ({ResultatImport resultat, String? demande}) importerEtDemander(JeuImport jeu, AnalyseImport analyse, {required ProfilImport profil, required String nomAgent}) {
    final port = PortMagasin(magasin, aujourdhui: () => _maintenant, nomAgent: nomAgent, profil: profil, gardesLevees: true, etiquette: etiquette);
    final id = identifiantDemandeImport(etiquette, _maintenant, ++_serie);
    final r = importerDirectEtDemander(jeu: jeu, analyse: analyse, port: port, regime: regime, idDemande: id, poste: etiquette);
    if (!r.ok) return (resultat: r.refus!, demande: null);
    demandes.inserer(r.demande!);
    return (resultat: r.resultat!, demande: id);
  }

  /// Les demandes que CET agent a déposées, de la plus récente à la plus ancienne (le fileul voit l'état de chacune : en attente, appliquée, refusée avec son code, son motif, son geste).
  List<Fiche> sesDemandes(String agent, {String? jeu}) => [
        for (final d in demandes.toutes)
          if (d['statut'] != 'archive' && '${d['demandePar']}' == agent && (jeu == null || d['jeu'] == jeu)) d
      ]..sort((a, b) => '${b['demandeLe']}${b['id']}'.compareTo('${a['demandeLe']}${a['id']}'));

  Timer? _minuterieFileul;
  VoidCallback? _ecouteFileul;
  bool _reconciliation = false;

  /// Démarre, sur un fileul, la lecture des verdicts : à chaque changement des demandes, puis périodiquement (la copie de la mère arrive par la configuration diffusée, parfois après
  /// le verdict).
  void demarrerFileul({Duration intervalle = const Duration(seconds: 4)}) {
    if (_ecouteFileul != null) return;
    _ecouteFileul = () => scheduleMicrotask(reconcilierVerdicts);
    demandes.addListener(_ecouteFileul!);
    _minuterieFileul = Timer.periodic(intervalle, (_) => reconcilierVerdicts());
    reconcilierVerdicts();
  }

  /// Règle l'écriture locale de chaque demande de CE poste dont la mère a rendu son verdict. Idempotent. Rend le nombre de demandes réglées.
  int reconcilierVerdicts() {
    if (_reconciliation) return 0;
    _reconciliation = true;
    var n = 0;
    try {
      final port = PortMagasin(magasin, aujourdhui: () => _maintenant, nomAgent: 'Poste', profil: const ProfilImport.aucunDroit(), gardesLevees: true, etiquette: etiquette);
      for (final d in [for (final d in demandes.toutes) if (d['statut'] != 'archive' && '${d['demandePoste']}' == etiquette && (d['etat'] == demandeImportAppliquee || d['etat'] == demandeImportRefusee)) d]) {
        final r = reconcilierEcrituresLocales({...d}, port, copieDeLaMereVisible: _copieVisible);
        if (!r.aNotifier) continue;
        magasin.collection('notifications').inserer({
          'type': r.issue == 'retenue' ? 'import_retenu' : 'import_non_retenu',
          'poste': 'tous',
          'destinataire': d['demandePar'],
          'libelle': r.titre,
          'detail': r.detail,
          'priorite': r.issue == 'retenue' ? 'normale' : 'haute',
          'reference': d['id'],
          'lue': false,
          'creeLe': _maintenant.toIso8601String(),
          'statut': 'actif',
        }, prefixe: 'NOT');
        n++;
      }
    } finally {
      _reconciliation = false;
    }
    return n;
  }

  /// La copie de la mère est-elle arrivée ? Une fiche du lot de la mère, qui n'est pas une écriture locale (ni provisoire, ni non retenue), et active.
  bool _copieVisible(String collection, String lotMere) => magasin
      .collection(collection)
      .toutes
      .any((f) => f['lotImport'] == lotMere && f['demandeImport'] == null && f['nonRetenueMere'] != true && f['statut'] != 'archive');

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // MÈRE : juger, appliquer ou refuser
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  bool _traitement = false;
  VoidCallback? _ecoute;

  /// Nombre de demandes traitées depuis le démarrage, et la dernière erreur d'un tour.
  int traitees = 0;
  Object? derniereErreur;

  /// À la mère : traite les demandes en attente (au démarrage, puis à chaque demande reçue). [matrice] : la matrice EN FORCE de la mère, relue à chaque demande.
  void demarrerMere({required MatriceDroits Function() matrice}) {
    matriceEnForce = matrice;
    if (_ecoute != null) return;
    _ecoute = () => scheduleMicrotask(traiterEnAttente);
    demandes.addListener(_ecoute!);
    traiterEnAttente();
  }

  void arreter() {
    if (_ecoute != null) demandes.removeListener(_ecoute!);
    _ecoute = null;
    if (_ecouteFileul != null) demandes.removeListener(_ecouteFileul!);
    _ecouteFileul = null;
    _minuterieFileul?.cancel();
    _minuterieFileul = null;
  }

  /// Traite, dans l'ordre du dépôt, chaque demande `en_attente`. Chacune refait la MÊME analyse sous le rôle et le nom de son auteur (un bouton absent au fileul ne protège rien, et un
  /// autre poste a pu créer la même fiche) ; le verdict est écrit sur la demande et revient au fileul par le pont. Rend le nombre de demandes traitées dans ce tour.
  int traiterEnAttente() {
    final matrice = matriceEnForce;
    if (_traitement || matrice == null) return 0;
    _traitement = true;
    var n = 0;
    try {
      final m = matrice();
      final enAttente = [for (final d in demandes.toutes) if (d['statut'] != 'archive' && d['etat'] == demandeImportEnAttente && '${d['traiteLe'] ?? ''}'.isEmpty) d]
        ..sort((a, b) => '${a['demandeLe']}${a['id']}'.compareTo('${b['demandeLe']}${b['id']}'));
      for (final d in enAttente) {
        final role = '${d['demandeRole']}', auteur = '${d['demandePar']}';
        final port = PortMagasin(magasin,
            aujourdhui: () => _maintenant,
            nomAgent: auteur,
            profil: ProfilImport(role: role, libelleRole: m.libelle(role) ?? role, droitEcran: (e) => m.droit(role, e)));
        VerdictDemandeImport v;
        try {
          v = traiterDemandeImport({...d}, port, jeuImportParId, regime: regime, octetsMax: _borne('${d['jeu']}'));
        } catch (e) {
          // Jamais muet : une exception se nomme aussi, et la demande reste lisible du fileul.
          v = VerdictDemandeImport.refusee('ECRITURE_REFUSEE', '$e', 'Rien n’a été écrit. Corrigez la cause puis refaites la demande.');
        }
        demandes.mettreAJour(d['id'], v.versChamps(traitePar: 'Mère', traiteLe: _jour), journaliser: false);
        magasin.journaliser(v.appliquee ? 'Demande d’import appliquée' : 'Demande d’import refusée', 'IMP', 'DemandeImport', '${d['id']}', {'etat': demandeImportEnAttente},
            {'jeu': d['jeu'], 'par': auteur, 'role': role, 'code': v.code, 'lot': v.lot, 'poste': d['demandePoste']});
        n++;
      }
      derniereErreur = null;
    } catch (e) {
      derniereErreur = e;
    } finally {
      _traitement = false;
    }
    traitees += n;
    return n;
  }

  int? _borne(String jeuId) {
    final j = jeuImportParId(jeuId);
    return j == null ? null : octetsMaxDe(magasin, j);
  }
}
