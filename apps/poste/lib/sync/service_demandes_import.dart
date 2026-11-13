import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_installation.dart';
import '../donnees/magasin.dart';
import '../import/droits_import.dart' show octetsMaxDe;
import '../import/port_magasin.dart';
import 'configuration_sync.dart' show collectionsConfiguration;
import 'fusion_activite.dart' show champsCompteurs;
import 'pont_activite.dart' show collectionsActivite, collectionsDeLaMereSeule;

/// LA DEMANDE D'IMPORT AU POSTE (lot IMP-C, décision de la Direction du 12/11/2026, « option c »). La colle entre les règles pures de `packages/domaine/lib/src/import/demande_import.dart`
/// (rejouées sans poste par les tests du domaine et par le banc de synchronisation) et le magasin du poste. Aucune règle d'import ici.
///
/// Même forme que les décisions de droits (`ServiceDroits`) : une fiche descriptive que le fileul dépose, que la MÈRE juge et complète du verdict, et qui revient au fileul par le pont
/// d'activité (famille A, champ à champ, dans les deux sens). Un service par magasin.
///
///  * FILEUL rattaché : un jeu dont les cibles sont de la configuration de la mère s'écrit DIRECTEMENT ici (l'agent le voit aussitôt, les gardes « réglé sur la mère » étant levées pour ce
///    geste seul) et une demande part AUTOMATIQUEMENT à la mère ([importerEtDemander]). Les fiches portent l'IDENTITÉ de la demande (la même chez la mère : une fiche par code) et le marquage
///    « en attente de la mère ». Quand le verdict revient, [reconcilierVerdicts] en donne la suite : confirmé, le marquage tombe (la fiche de la mère a remplacé la sienne) ; refusé, le lot
///    est RESTITUÉ (archivé, RG-14 ; une fiche qu'une pièce émise utilise reste, marquée « refusée par la mère ») — jamais disparu en silence — et une notification le dit. Mère
///    injoignable : la demande attend dans la file du fileul, jamais dite « appliquée » avant la confirmation.
///  * MÈRE : [demarrerMere] puis [traiterEnAttente] — elle REJOUE chaque demande sous le rôle et le nom de son AUTEUR, avec SA matrice en force, applique par le chemin de l'import local
///    ou refuse en nommant, journalise (RG-12) et écrit le verdict sur la même fiche. Le traitement est BRANCHÉ au démarrage de la mère (`main.dart`) : un test le prouve à travers le vrai
///    poste (`demandes_import_sync_test.dart`).
///
/// Un import fait AU POSTE DE LA MÈRE reste local et direct : aucune demande. Un jeu RESTREINT ne passe jamais par une demande.
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

  /// Les collections que la mère seule écrit. Une cible d'ACTIVITÉ (lots, mouvements) n'exclut plus un jeu : le Grand Stock passe par la demande (lot IMP-E).
  RegimeDemandesImport get regime => RegimeDemandesImport(collectionsDeLaMere: collectionsConfiguration());

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
    final r = importerDirectEtDemander(jeu: jeu, analyse: analyse, port: port, regime: regime, idDemande: id, poste: etiquette, compteurs: champsCompteurs);
    if (!r.ok) return (resultat: r.refus!, demande: null);
    try {
      demandes.inserer(r.demande!);
    } catch (e) {
      // Jamais une écriture sans demande : si le dépôt échoue, l'écriture est restituée.
      restituerLotDirect(jeuImportParId, r.resultat!.lot!['id'], codeRefus: 'DEMANDE_NON_DEPOSEE', motifRefus: '$e', port: port);
      return (
        resultat: ResultatImport.refus('DEMANDE_NON_DEPOSEE', 'la demande à la mère n’a pas pu être déposée : $e', 'Rien n’est resté écrit chez vous : l’écriture a été restituée. Refaites l’import.'),
        demande: null
      );
    }
    return (resultat: r.resultat!, demande: id);
  }

  /// La demande dont CE poste a écrit le lot [lotId] chez lui, ou `null`.
  Fiche? demandeDuLot(Object? lotId) => [for (final d in demandes.toutes) if (d['statut'] != 'archive' && d['lotLocalId'] == lotId) d].firstOrNull;

  /// FILEUL : annule un lot écrit chez lui. Tant que la mère n'a pas statué, le lot s'annule comme tout lot (droit d'annuler, archivage RG-14) ET la demande est retirée (la mère ne la
  /// traite plus). Confirmé ou refusé par la mère, le lot ne s'annule plus ici : refus nommé (elle détient les mêmes fiches ; un lot refusé se restitue tout seul).
  ResultatImport annulerLotDuFileul(Object? lotId, {required ProfilImport profil, required String nomAgent, String? motif}) {
    final demande = demandeDuLot(lotId);
    final refus = refusAnnulationLotDirect(demande);
    if (refus != null) return ResultatImport.refus(refus.code, refus.motif, refus.geste);
    final port = PortMagasin(magasin, aujourdhui: () => _maintenant, nomAgent: nomAgent, profil: profil, gardesLevees: true, etiquette: etiquette);
    final r = annulerLot(jeuImportParId, lotId, motif, port);
    if (r.ok && demande != null && demande['etat'] == demandeImportEnAttente) {
      demandes.mettreAJour(demande['id'], champsRetraitDemande(par: nomAgent, jour: _jour), journaliser: false);
      magasin.journaliser('Demande d’import retirée (lot annulé)', 'IMP', 'DemandeImport', '${demande['id']}', {'etat': demandeImportEnAttente}, {'etat': demandeImportRetiree});
    }
    return r;
  }

  /// Les demandes que CET agent a déposées, de la plus récente à la plus ancienne (le fileul voit l'état de chacune : en attente, appliquée, refusée avec son code, son motif, son geste).
  List<Fiche> sesDemandes(String agent, {String? jeu}) => [
        for (final d in demandes.toutes)
          // Décision du 13/11/2026 : sur un fileul, jamais la demande d'un autre poste (la synchronisation ne la livre déjà pas ; ce filtre est la seconde porte).
          if (d['statut'] != 'archive' && '${d['demandePar']}' == agent && (jeu == null || d['jeu'] == jeu) && (!estFileul || '${d['demandePoste'] ?? etiquette}' == etiquette)) d
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

  /// Donne la SUITE du verdict de chaque demande de CE poste, une fois. Refusée : le lot local est RESTITUÉ (archivage, jamais une suppression ; les fiches qu'une pièce émise utilise restent,
  /// marquées) et la demande le dit. Appliquée : le marquage « en attente de la mère » est levé des fiches que la configuration de la mère n'a pas encore remplacées ; pour une collection
  /// que le pont synchronise (stock, lots, mouvements), la confirmation est l'ARRIVÉE de la fiche de la mère (le pont lève alors le marquage) : lever avant ferait partir au journal la
  /// version du fileul avant celle de la mère. Idempotent (les champs `restitution` et `marquageLeve` de la demande en gardent la mémoire). Rend le nombre de demandes suivies.
  int reconcilierVerdicts() {
    if (_reconciliation) return 0;
    _reconciliation = true;
    var n = 0;
    try {
      for (final d in [for (final d in demandes.toutes) if (d['statut'] != 'archive' && d['ecritureDirecte'] == true && '${d['demandePoste']}' == etiquette) d]) {
        final lot = magasin.collection(collectionLots).parId(d['lotLocalId']);
        if (lot == null) continue;
        final ecrits = ((lot['ecrits'] as List?) ?? const []).cast<Map>();
        switch (suiteDuVerdict(d)) {
          case SuiteDuVerdict.aucune:
            break;
          case SuiteDuVerdict.restituer:
            final port = PortMagasin(magasin, aujourdhui: () => _maintenant, nomAgent: '${d['demandePar']}', profil: const ProfilImport.aucunDroit(), gardesLevees: true, etiquette: etiquette);
            final r = restituerLotDirect(jeuImportParId, d['lotLocalId'], codeRefus: '${d['resultatCode']}', motifRefus: '${d['resultatMotif']}', port: port);
            // Un lot déjà annulé à la main n'a rien à restituer : la demande le dit comme restitué.
            final dejaFait = !r.ok && r.code == 'LOT_NON_APPLIQUE';
            if (r.ok || dejaFait) {
              demandes.mettreAJour(d['id'], {
                'restitution': dejaFait ? restitutionFaite : r.etat,
                'restitutionLe': _jour,
                'restitutionArchives': r.archives,
                'restitutionGardees': [for (final g in r.gardees) {'collection': g['collection'], 'id': g['id'], 'code': g['code'], 'motif': g['motif']}],
              }, journaliser: false);
              _notifier(d, 'import_non_retenu', 'Import refusé par la mère, écriture restituée',
                  'La mère a refusé « ${d['jeuLibelle'] ?? d['jeu']} » (${d['fichier'] ?? ''}) : ${d['resultatCode']} : ${d['resultatMotif']}. ${r.archives} fiche(s) restituée(s) (archivées, RG-14)'
                  '${r.gardees.isEmpty ? '' : ', ${r.gardees.length} gardée(s) parce qu’une pièce émise s’appuie dessus (marquées « refusée par la mère »)'}. ${d['resultatGeste'] ?? ''}');
              n++;
            }
          case SuiteDuVerdict.leverLeMarquage:
            var attendues = 0;
            for (final e in ecrits) {
              final c = '${e['collection']}';
              final f = magasin.collection(c).parId(e['id']);
              if (f == null || f[champEnAttenteMere] != d['id']) continue;
              if (collectionsActivite.contains(c)) {
                attendues++;
              } else {
                magasin.collection(c).retirerChamp(e['id'], champEnAttenteMere);
              }
            }
            if (attendues == 0) {
              demandes.mettreAJour(d['id'], {'marquageLeve': true}, journaliser: false);
              _notifier(d, 'import_retenu', 'Import confirmé par la mère',
                  'La mère a appliqué « ${d['jeuLibelle'] ?? d['jeu']} » (${d['fichier'] ?? ''}, lot ${d['resultatLot']}) : ses fiches portent les mêmes identifiants que les vôtres et les ont remplacées, sans doublon.');
              n++;
            }
        }
      }
    } finally {
      _reconciliation = false;
    }
    return n;
  }

  void _notifier(Fiche d, String type, String libelle, String detail) => magasin.collection('notifications').inserer({
        'type': type,
        'poste': 'tous',
        'destinataire': d['demandePar'],
        'libelle': libelle,
        'detail': detail,
        'priorite': type == 'import_retenu' ? 'normale' : 'haute',
        'reference': d['id'],
        'lue': false,
        'creeLe': _maintenant.toIso8601String(),
        'statut': 'actif',
      }, prefixe: 'NOT');

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
          v = traiterDemandeImport({...d}, port, jeuImportParId, regime: regime, octetsMax: _borne('${d['jeu']}'), compteurs: champsCompteurs);
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
