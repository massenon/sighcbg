/// LA DEMANDE D'IMPORT D'UN FILEUL À LA MÈRE (lot IMP-C, décision de la Direction du 12/11/2026, « option c »), reprise du lot IMP-D de la clinique sœur (identité commune des fiches,
/// restitution sur refus) puis du lot IMP-E (le Grand Stock chez le fileul, décision de la Direction du 13/11/2026).
///
/// Un référentiel de configuration (famille R : la mère seule en est l'autorité) importé à un poste FILEUL suit DEUX chemins à la fois, jamais l'un sans l'autre :
///
///  1. le fileul écrit DIRECTEMENT chez lui — l'agent voit son import tout de suite, la garde « réglé sur la mère » étant levée pour CE geste seulement — ; les fiches posées portent
///     l'IDENTITÉ COMMUNE de la demande ([identifiantDeDemande] : `<COL>-<demande>-<rang>`, jamais préfixée de l'étiquette du poste) et le marquage « en attente de la mère »
///     ([champEnAttenteMere]) ;
///  2. une DEMANDE vérifiée part automatiquement à la mère (fiche `demandesImport`, famille A : le fileul dépose, la mère complète du verdict). La mère reste la SEULE AUTORITÉ :
///     elle REJOUE l'analyse sous le rôle et le nom de l'auteur, avec sa propre matrice, ses propres données et ses propres bornes, exige le MÊME résultat que le fileul
///     ([resultatIdentique]) et applique par le MÊME chemin que l'import local, sous les MÊMES identifiants — ou refuse en NOMMANT le code, le motif et le geste.
///
/// Trois issues, aucune muette :
///  * la mère APPLIQUE : ses fiches portent les identifiants de celles du fileul, elles les REMPLACENT à l'arrivée (une fiche par code, jamais « provisoire + archivée ») ; le marquage tombe ;
///  * la mère REFUSE : le fileul RESTITUE son lot ([restituerLotDirect], archivage RG-14, jamais une suppression), sauf les fiches sur lesquelles une pièce émise s'appuie déjà : elles
///    restent, marquées [champRefuseeParMere], le verdict nomme le code, le motif et le geste ;
///  * la mère est INJOIGNABLE : la demande reste dans la file du fileul (famille A, hors ligne d'abord), ses fiches portent « en attente de la mère » et le libellé de la demande ne dit
///    JAMAIS « appliquée » avant la confirmation ([libelleEtatDemandeImport]). En cas de conflit, la MÈRE gagne, toujours.
///
/// LE GRAND STOCK (produits, lots, mouvements) passera par cette voie (le gestionnaire de stock est un FILEUL). Le double comptage que l'on craignait est MESURÉ
/// (`apps/poste/test/grand_stock_mesure_test.dart` à l'arbre d'avant) et levé : identité commune, valeur de DÉPART des compteurs ([champDepartCompteurs]), fiche PROPRE AU POSTE tant que la
/// mère n'a pas confirmé ([ficheLocaleAuPoste]), rejeu SANS EFFET ([appliquerDemande]).
///
/// UN JEU RESTREINT (patients, personnel, soldes, courriers, stock vivant, comptage d'inventaire) ne passe JAMAIS par une demande : ses lignes ne voyagent pas dans une fiche partagée
/// (RG-13). Le Personnel (identité et salaire) reste réservé à la mère : l'administrateur et la DAF le gèrent au module RH, au poste de la mère. La mère le REDIT à chaque demande :
/// une demande forgée par un fileul falsifié est refusée en le nommant.
///
/// Les lignes du fichier voyagent dans la demande EN CLAIR (la mère doit pouvoir rejouer) jusqu'au verdict, qui les EFFACE : elles sont lues, entre le dépôt et le verdict, par la mère et par
/// les postes qui reçoivent le journal des demandes (famille A) ; jamais par un téléphone, et le relais ne voit que du chiffré.
///
/// Ce fichier ne porte que les règles pures, rejouées sans poste (`PortImportMemoire`) par les tests et par le banc ; le poste y branche son magasin.
library;

import 'dart:convert';

import 'moteur_import.dart';
import 'profil_import.dart';

/// La collection des demandes (famille A de la synchronisation : champ à champ, dans les deux sens ; jamais vers un téléphone).
const String demandesImportCollection = 'demandesImport';

/// États d'une demande : `en_attente` (déposée, la mère n'a pas encore statué), `appliquee`, `refusee`, `retiree` (le fileul a annulé son lot avant la réponse : la mère ne la traite plus).
const String demandeImportEnAttente = 'en_attente', demandeImportAppliquee = 'appliquee', demandeImportRefusee = 'refusee', demandeImportRetiree = 'retiree';

/// Où en est la restitution du fileul après un refus de la mère (champ `restitution` de la demande, écrit par le fileul).
const String restitutionFaite = 'faite', restitutionPartielle = 'partielle';

/// Les champs que SEULE la mère écrit sur une demande : le verdict et son horodatage. Un fileul qui en écrit un est refusé par le protocole (`refusDemandeImportDuFileul`).
const List<String> champsVerdictDemandeImport = ['resultatCode', 'resultatMotif', 'resultatGeste', 'resultatLot', 'resultatEcrits', 'traitePar', 'traiteLe'];

/// LOT IMP-E (reprise de la clinique sœur, décision de la Direction du 13/11/2026) : la demande dont une fiche est née. Une fiche écrite par une demande porte `serieDemande` (la série des
/// identifiants, la même chez le fileul et chez la mère) : c'est ce qui lui donne une IDENTITÉ COMMUNE à tous les postes (son identifiant, jamais préfixé par l'étiquette du poste) et qui
/// permet de reconnaître un rejeu.
const String champSerieDemande = 'serieDemande';

/// LOT IMP-E : la valeur de DÉPART de chaque compteur d'une fiche écrite par une demande (stock d'un produit, quantité restante d'un lot), posée à l'écriture. C'est le point de départ
/// COMMUN du compteur : le fileul et la mère écrivent la même valeur, aucun des deux ne la publie comme une variation (sinon elle s'additionnerait à celle de l'autre). Seules les sorties
/// et les entrées POSTÉRIEURES voyagent, comptées depuis ce départ.
const String champDepartCompteurs = 'departCompteurs';

/// LOT IMP-D/E : le marquage d'une fiche écrite chez un fileul que la mère n'a pas encore confirmée (valeur : l'identifiant de la demande). La fiche de la mère, qui la remplace à l'arrivée de
/// la configuration, ne le porte pas : le marquage tombe donc de lui-même à la confirmation.
const String champEnAttenteMere = 'enAttenteMere';

/// LOT IMP-D/E : une fiche que la mère a refusée mais qu'une pièce émise utilise déjà (valeur : le motif nommé). Elle reste en place, marquée, jamais réécrite.
const String champRefuseeParMere = 'refuseeParMere';

/// LOT IMP-E : une fiche écrite chez un fileul que la mère n'a pas confirmée (en attente) ou a refusée (gardée parce qu'une pièce s'appuie dessus) est PROPRE À CE POSTE : elle ne part
/// pas au journal, aucun autre poste ne la voit. Un stock ne se rend visible aux autres postes qu'une fois la mère d'accord (jamais de stock doublé par deux fileuls, jamais une
/// quantité que la mère refuserait ensuite).
bool ficheLocaleAuPoste(Map<String, Object?> f) => '${f[champEnAttenteMere] ?? ''}'.isNotEmpty || '${f[champRefuseeParMere] ?? ''}'.isNotEmpty;

/// Une demande dont les lignes, une fois sérialisées, dépassent ce multiple de la borne de taille du jeu est refusée : la borne porte sur le FICHIER (un classeur
/// compressé), les lignes déployées en JSON pèsent beaucoup plus. Un fileul falsifié ne peut ainsi pas faire avaler à la mère plus que ce que le jeu accepte à un poste.
const int facteurDeploiementLignesImport = 12;

/// Les deux familles de collections qui décident d'une demande : celles que la mère SEULE écrit (configuration), et celles de l'ACTIVITÉ que le pont synchronise.
class RegimeDemandesImport {
  const RegimeDemandesImport({required this.collectionsDeLaMere, required this.collectionsActivite});
  final Set<String> collectionsDeLaMere, collectionsActivite;

  /// Le jeu passe-t-il par une demande sur un fileul rattaché ? Non restreint, une collection cible que la mère seule écrit, aucune cible d'activité synchronisée.
  bool exigeLaMere(JeuImport j) => !j.restreint && j.cibles.any(collectionsDeLaMere.contains) && !j.cibles.any(collectionsActivite.contains);

  /// Un jeu RESTREINT qui écrit de la configuration ne s'importe qu'au poste de la mère : le fileul le dit au lieu de proposer un envoi.
  bool reserveALaMere(JeuImport j) => j.restreint && j.cibles.any(collectionsDeLaMere.contains);
}

/// Les identifiants d'une demande portent l'étiquette du poste : deux postes ne se rencontrent jamais.
String identifiantDemandeImport(String etiquette, DateTime maintenant, int rang) => 'DIM$etiquette${maintenant.microsecondsSinceEpoch.toRadixString(36)}$rang';

/// L'identifiant d'une fiche écrite par une demande d'import (lot IMP-D). Le fileul l'écrit chez lui et la mère le rejoue avec la MÊME formule : la fiche de la mère remplace donc celle du
/// fileul (même `id`) au lieu de la doubler. [rang] est le rang de la fiche dans sa collection au sein du geste (1, 2, …) ; il est le même des deux côtés parce que la mère n'applique que si
/// elle écrit exactement les mêmes lignes ([resultatIdentique]).
String identifiantDeDemande(String collection, String demandeId, int rang) {
  final p = collection.length < 3 ? collection : collection.substring(0, 3);
  return '${p.toUpperCase()}-$demandeId-$rang';
}

/// Le PORT d'une demande d'import : décore le port d'un poste pour que les fiches écrites reçoivent leur identifiant de demande ([identifiantDeDemande]) au lieu du « plus un » du poste.
/// Le fileul le pose avec [marquerEnAttente] (ses fiches portent [champEnAttenteMere] jusqu'à la confirmation de la mère) ; la mère le pose sans marquage.
class PortDemandeImport extends PortImport {
  /// [compteurs] : les champs compteurs de chaque collection (stock d'un produit, quantité restante d'un lot), dont la valeur d'écriture est posée comme DÉPART ([champDepartCompteurs]).
  PortDemandeImport(this.base, {required this.demandeId, this.marquerEnAttente = false, this.compteurs = const {}});
  final PortImport base;
  final String demandeId;
  final bool marquerEnAttente;
  final Map<String, Set<String>> compteurs;
  final Map<String, int> _rangs = {};

  @override
  ProfilImport get profil => base.profil;
  @override
  List<FicheImport> toutes(String collection) => base.toutes(collection);
  @override
  String get jour => base.jour;
  @override
  String get utilisateur => base.utilisateur;

  /// Écrit la fiche sous l'identifiant `(demande, collection, rang)`. C'est IDEMPOTENT : une fiche de cette demande qui existe déjà à ce rang (rejeu de la demande, reprise du journal,
  /// redémarrage) est rendue telle quelle, sans écriture ni ligne de journal : une demande ne compte jamais deux fois la même fiche. La fiche porte la série de sa demande
  /// ([champSerieDemande]) et, pour un compteur, sa valeur de DÉPART ([champDepartCompteurs]).
  @override
  FicheImport inserer(String collection, FicheImport fiche) {
    final rang = _rangs.update(collection, (n) => n + 1, ifAbsent: () => 1);
    final id = fiche['id'] ?? identifiantDeDemande(collection, demandeId, rang);
    final deja = base.parId(collection, id);
    if (deja != null && deja[champSerieDemande] == demandeId) return deja;
    final champs = compteurs[collection] ?? const <String>{};
    final depart = {for (final k in champs) if (fiche[k] is num) k: fiche[k]};
    return base.inserer(collection, {
      ...fiche,
      'id': id,
      champSerieDemande: demandeId,
      if (depart.isNotEmpty) champDepartCompteurs: depart,
      if (marquerEnAttente && collection != collectionLots) champEnAttenteMere: demandeId,
    });
  }

  @override
  void retirer(String collection, Object? id) => base.retirer(collection, id);
  @override
  bool archiver(String collection, Object? id, String motif) => base.archiver(collection, id, motif);
  @override
  void restaurer(String collection, Object? id) => base.restaurer(collection, id);
  @override
  void mettreAJour(String collection, Object? id, FicheImport patch) => base.mettreAJour(collection, id, patch);
  @override
  void journaliser(String action, String module, String entite, String reference, Object? avant, Object? apres) =>
      base.journaliser(action, module, entite, reference, avant, apres);
}

/// Le lot d'import déjà écrit par cette demande (il porte la série de la demande), ou `null`. Sert de preuve qu'un rejeu n'a rien à écrire.
FicheImport? lotDeLaDemande(PortImport port, String demandeId) =>
    port.toutes(collectionLots).where((l) => l[champSerieDemande] == demandeId && l['etat'] == 'applique').firstOrNull;

/// Applique la demande, UNE SEULE fois. Si le lot de cette demande existe déjà (rejeu de la demande, redémarrage entre l'écriture et le verdict, reprise du journal), c'est un NO-OP :
/// aucune fiche, aucun lot, aucune ligne de journal de plus ; le lot déjà écrit est rendu. Sinon, c'est `appliquer`, sous les identifiants de la demande.
ResultatImport appliquerDemande(JeuImport j, AnalyseImport analyse, PortDemandeImport port) {
  final deja = lotDeLaDemande(port, port.demandeId);
  if (deja != null) return ResultatImport.ok(lot: deja, ecrits: (deja['ecrits'] as List? ?? const []).length);
  return appliquer(j, analyse, port);
}

/// Les rangs (numéros de ligne du fichier) qu'une analyse ÉCRIRAIT : ni refusés, ni ignorés.
List<int> rangsAEcrire(AnalyseImport a) => [for (final l in a.lignes) if (!l.ignoree && l.etat != 'refus') l.n];

/// La mère ne confirme que le MÊME résultat que celui que le fileul a écrit. Rend `null` si les lignes écrites sont identiques, sinon le constat nommé : les lignes que la mère
/// n'écrirait pas (déjà tenues chez elle) et celles qu'elle écrirait en plus.
({String motif, String geste})? resultatIdentique(List<int> ecritsParLeFileul, List<int> ecritsParLaMere) {
  final a = ecritsParLeFileul.toSet(), b = ecritsParLaMere.toSet();
  if (a.length == b.length && a.containsAll(b)) return null;
  String liste(Iterable<int> n) {
    final l = (n.toList()..sort());
    return l.length <= 10 ? l.join(', ') : '${l.take(10).join(', ')} et ${l.length - 10} autre(s)';
  }

  final enMoins = a.difference(b), enPlus = b.difference(a);
  return (
    motif: 'la mère ne produirait pas le même résultat que chez vous${enMoins.isEmpty ? '' : ' : elle n’écrirait pas la ligne ${liste(enMoins)} (déjà tenue chez elle)'}${enPlus.isEmpty ? '' : '${enMoins.isEmpty ? ' :' : ','} elle écrirait en plus la ligne ${liste(enPlus)}'}',
    geste: 'Votre écriture locale est restituée. Les fiches de la mère vous arrivent par la configuration : refaites l’import avec le fichier à jour.',
  );
}

/// La fiche déposée par le fileul. [analyse] est celle qu'il a faite lui-même (acceptée, au moins une ligne à écrire) : un fichier refusé ne part jamais.
///
/// [lotLocal] et [lotLocalId] disent que le fileul a DÉJÀ écrit le fichier chez lui ; `rangsEcrits` est ce qu'il a écrit, que la mère doit reproduire à l'identique. `serieIdentifiants`
/// porte la série des identifiants de fiche : la demande est RENOMMÉE par le pont en arrivant à la mère (l'étiquette du poste préfixe son identifiant de synchronisation), la série ne
/// doit pas l'être.
Map<String, Object?> composerDemandeImport({
  required String id,
  required JeuImport jeu,
  required AnalyseImport analyse,
  required String role,
  required String par,
  required String jour,
  required String poste,
  String? lotLocal,
  Object? lotLocalId,
}) {
  assert(analyse.accepte && analyse.aEcrire > 0, 'une demande ne part que d\'un fichier vérifié');
  assert(!jeu.restreint, 'un jeu restreint ne passe jamais par une demande');
  return {
    'id': id,
    'statut': 'actif',
    'jeu': jeu.id,
    'jeuLibelle': jeu.libelle,
    'fichier': analyse.fichier,
    'empreinte': analyse.empreinte,
    'lignes': [for (final l in analyse.lignesBrutes) [for (final c in l) c]],
    'ignorerExistants': analyse.options.ignorerExistants,
    'nbLignes': analyse.nbLignes,
    'aEcrire': analyse.aEcrire,
    'nbAvertissements': analyse.compte.avertissements,
    'etat': demandeImportEnAttente,
    'demandePar': par,
    'demandeRole': role,
    'demandePoste': poste,
    'demandeLe': jour,
    if (lotLocal != null) ...{
      'ecritureDirecte': true,
      'serieIdentifiants': id,
      'lotLocal': lotLocal,
      'lotLocalId': lotLocalId,
      'rangsEcrits': rangsAEcrire(analyse),
    },
  };
}

/// Ce que fait le FILEUL d'un fichier vérifié : l'écriture directe, puis le dépôt de la demande. [port] est le port LOCAL du fileul (gardes levées pour ce geste) : le moteur y refuse
/// toujours selon le droit du rôle, et un échec d'écriture ne dépose RIEN. Rend soit la demande déposée, soit le refus nommé du moteur.
class ImportDirectEtDemande {
  const ImportDirectEtDemande.depose(this.demande, this.resultat) : refus = null;
  const ImportDirectEtDemande.refuse(ResultatImport r)
      : demande = null,
        resultat = null,
        refus = r;
  final Map<String, Object?>? demande;
  final ResultatImport? resultat;
  final ResultatImport? refus;
  bool get ok => demande != null;
}

ImportDirectEtDemande importerDirectEtDemander({
  required JeuImport jeu,
  required AnalyseImport analyse,
  required PortImport port,
  required RegimeDemandesImport regime,
  required String idDemande,
  required String poste,
  Map<String, Set<String>> compteurs = const {},
}) {
  if (!regime.exigeLaMere(jeu)) {
    return ImportDirectEtDemande.refuse(ResultatImport.refus(
        'JEU_NON_DEMANDABLE', 'le jeu « ${jeu.libelle} » ne passe pas par une demande à la mère', 'Importez-le par la voie ordinaire du poste, ou au poste de la mère s’il est réservé.'));
  }
  if (!analyse.accepte || analyse.aEcrire == 0) {
    return ImportDirectEtDemande.refuse(
        const ResultatImport.refus('ANALYSE_REFUSEE', 'le fichier n’a pas passé l’analyse, ou n’a rien à écrire', 'Corrigez les refus listés, puis téléversez de nouveau.'));
  }
  // L'ÉCRITURE DIRECTE : le même chemin que tout import (droit, rejeu de l'analyse, atomicité, lot consigné), sous les identifiants de la demande (la mère les rejouera à l'identique) et
  // le marquage « en attente de la mère ». Refusée, rien n'est déposé.
  final r = appliquerDemande(jeu, analyse, PortDemandeImport(port, demandeId: idDemande, marquerEnAttente: true, compteurs: compteurs));
  if (!r.ok) return ImportDirectEtDemande.refuse(r);
  final lot = r.lot!;
  final demande = composerDemandeImport(
      id: idDemande, jeu: jeu, analyse: analyse, role: port.profil.role, par: port.utilisateur, jour: port.jour, poste: poste, lotLocal: '${lot['reference']}', lotLocalId: lot['id']);
  port.journaliser('Demande d’import déposée à la mère', 'IMP', 'DemandeImport', idDemande, null, {'jeu': jeu.id, 'fichier': analyse.fichier, 'lignes': analyse.nbLignes, 'lotLocal': lot['reference'], 'role': port.profil.role});
  return ImportDirectEtDemande.depose(demande, r);
}

/// Le verdict de la mère sur une demande.
class VerdictDemandeImport {
  const VerdictDemandeImport.appliquee({required this.lot, required this.ecrits})
      : appliquee = true,
        code = null,
        motif = null,
        geste = null;
  const VerdictDemandeImport.refusee(String this.code, String this.motif, String this.geste, {this.lot})
      : appliquee = false,
        ecrits = 0;
  final bool appliquee;
  final String? code, motif, geste;

  /// La référence du lot écrit (appliquée) ou du fichier consigné refusé (refusée, si le moteur en a consigné un).
  final String? lot;
  final int ecrits;

  /// Les champs que la mère écrit sur la demande : l'état, le verdict nommé, le lot ; les lignes du fichier sont EFFACÉES (aucune valeur de cellule ne reste à la demande).
  Map<String, Object?> versChamps({required String traitePar, required String traiteLe}) => {
        'etat': appliquee ? demandeImportAppliquee : demandeImportRefusee,
        'resultatCode': code ?? '',
        'resultatMotif': motif ?? '',
        'resultatGeste': geste ?? '',
        'resultatLot': lot ?? '',
        'resultatEcrits': ecrits,
        'traitePar': traitePar,
        'traiteLe': traiteLe,
        'lignes': <Object?>[],
      };
}

/// Ce que la MÈRE fait d'une demande. [port] porte le profil de l'AUTEUR (son rôle, lu de la matrice EN FORCE à la mère : elle ne lui prête pas ses propres droits), son nom, et les données
/// de la mère. Ne rien faire d'une demande déjà traitée est l'affaire de l'appelant (`etat != en_attente`), mais la règle est redite ici : un verdict n'est jamais écrit deux fois.
///
/// Refus nommés, dans l'ordre : `DEMANDE_DEJA_TRAITEE` ; `JEU_INCONNU` ; `JEU_RESTREINT` ; `JEU_NON_DEMANDABLE` ; `DROIT_IMPORT_REFUSE` (le rôle de l'auteur ne détient plus le droit, relu
/// ICI) ; `FICHIER_TROP_GROS` ; le code du premier refus de l'analyse REJOUÉE (`DOUBLON_MAGASIN`, quand un autre poste a créé la même fiche entre-temps…) ; `RESULTAT_DIFFERENT` (la
/// mère n'écrirait pas les mêmes lignes que le fileul) ; `ECRITURE_REFUSEE`.
///
/// Une demande dont le fileul a écrit le lot chez lui n'est confirmée que si la mère écrit EXACTEMENT les mêmes lignes ; ses fiches reçoivent les identifiants de la demande (ceux du fileul)
/// pour le remplacer au lieu de le doubler. Une demande que la mère a DÉJÀ appliquée (redémarrage entre l'écriture et le verdict, demande reçue deux fois) rend le même verdict sans
/// rien réécrire : sans cette preuve, la seconde analyse refuserait le fichier comme un doublon de ce que la mère vient elle-même d'écrire.
VerdictDemandeImport traiterDemandeImport(
  FicheImport demande,
  PortImport port,
  JeuImport? Function(String id) jeuParId, {
  required RegimeDemandesImport regime,
  int? octetsMax,
  Map<String, Set<String>> compteurs = const {},
}) {
  if (demande['etat'] != demandeImportEnAttente || '${demande['traiteLe'] ?? ''}'.isNotEmpty) {
    return const VerdictDemandeImport.refusee('DEMANDE_DEJA_TRAITEE', 'cette demande a déjà reçu son verdict', 'Aucune action : la mère ne statue qu’une fois.');
  }
  final j = jeuParId('${demande['jeu']}');
  if (j == null) {
    return VerdictDemandeImport.refusee('JEU_INCONNU', 'le jeu « ${demande['jeu']} » n’existe pas à la mère', 'Refaire la demande depuis la page du jeu, avec une version à jour du poste.');
  }
  if (j.restreint) {
    return VerdictDemandeImport.refusee('JEU_RESTREINT', 'le jeu « ${j.libelle} » porte des données restreintes : il ne passe jamais par une demande', 'Importez ce jeu au poste de la mère, par un profil qui en détient le droit.');
  }
  if (!regime.exigeLaMere(j)) {
    return VerdictDemandeImport.refusee('JEU_NON_DEMANDABLE', 'le jeu « ${j.libelle} » n’est pas un référentiel que la mère seule écrit : il ne passe pas par une demande', 'Importez-le par la voie ordinaire du poste.');
  }
  final rd = refusDroitImport(j, 'importer', port);
  if (rd != null) return VerdictDemandeImport.refusee(rd.code!, rd.motif!, rd.geste!);
  final directe = demande['ecritureDirecte'] == true;
  final serie = '${demande['serieIdentifiants'] ?? demande['id']}';
  if (directe) {
    final deja = lotDeLaDemande(port, serie);
    if (deja != null) return VerdictDemandeImport.appliquee(lot: '${deja['reference']}', ecrits: (deja['ecrits'] as List? ?? const []).length);
  }
  final lignes = [
    for (final l in (demande['lignes'] as List? ?? const [])) [for (final c in (l as List)) c]
  ];
  final borne = octetsMax ?? j.octetsMaxDefaut;
  final taille = utf8.encode(jsonEncode(lignes)).length;
  if (taille > borne * facteurDeploiementLignesImport) {
    return VerdictDemandeImport.refusee('FICHIER_TROP_GROS', 'les lignes de la demande dépassent ce que le jeu « ${j.libelle} » accepte (borne de ${(borne / 1024).round()} Ko pour le fichier)',
        'Scindez le fichier en plusieurs lots, ou faites relever la borne du jeu par un administrateur.');
  }
  final options = OptionsImport(
    ignorerExistants: demande['ignorerExistants'] == true,
    colonnesAccordees: port.profil.aLeDroitPaie ? {...j.colonnesReservees} : const {},
  );
  final a = analyserLignes(j, lignes, '${demande['fichier'] ?? ''}', port, options: options)..empreinte = demande['empreinte'] as String?;
  if (!a.accepte) {
    // Rejoué à la mère, le fichier ne passe plus (un autre poste a pu écrire la même fiche) : refusé en NOMMANT la première cause, consigné à l'historique de la mère.
    final premier = [for (final p in a.problemes) if (p.estRefus) p].firstOrNull;
    final lot = consigner(j, a, port);
    return VerdictDemandeImport.refusee(
        premier?.code ?? 'ANALYSE_REFUSEE',
        premier == null
            ? 'le fichier ne passe plus l’analyse à la mère'
            : 'rejoué à la mère, le fichier est refusé${premier.n > 0 ? ' (ligne ${premier.n}, ${premier.colonne})' : ''} : ${premier.motif}',
        premier?.geste ?? 'Corrigez le fichier puis refaites la demande.',
        lot: lot == null ? null : '${lot['reference']}');
  }
  if (directe && demande['rangsEcrits'] is List) {
    final diff = resultatIdentique([for (final n in (demande['rangsEcrits'] as List)) (n as num).toInt()], rangsAEcrire(a));
    if (diff != null) return VerdictDemandeImport.refusee('RESULTAT_DIFFERENT', diff.motif, diff.geste);
  }
  final r = directe ? appliquerDemande(j, a, PortDemandeImport(port, demandeId: serie, compteurs: compteurs)) : appliquer(j, a, port);
  if (r.ok) return VerdictDemandeImport.appliquee(lot: '${r.lot!['reference']}', ecrits: r.ecrits);
  return VerdictDemandeImport.refusee(r.code ?? 'ECRITURE_REFUSEE', r.motif ?? 'l’écriture a été refusée', r.geste ?? 'Rien n’a été écrit.', lot: r.lot == null ? null : '${r.lot!['reference']}');
}

/// LE PROTOCOLE : ce qu'un poste qui n'est PAS la mère n'a pas le droit d'écrire sur une demande. Rend `null` quand l'opération est permise, sinon [code, motif, geste].
/// [type] : `creer` ou `modifier`. Le dépôt d'une demande est un AJOUT : à la création, l'état est `en_attente` et aucun champ de verdict n'est présent ; ensuite ni le verdict ni l'état ne se
/// réécrivent par un fileul (sans cela, un fileul falsifié se délivrerait lui-même un verdict, ou remettrait en attente une demande traitée pour la faire rejouer), à UNE exception : il
/// RETIRE sa propre demande ([demandeImportRetiree]) tant que la mère n'a pas statué — [etatActuel] est l'état que la mère détient (`null` : demande inconnue, ou le contrôle ne le sait pas).
/// Les champs de SUIVI du fileul (`restitution…`, `marquageLeve`) lui appartiennent : ils s'écrivent champ à champ à côté du verdict, sans jamais le détruire.
List<String>? refusDemandeImportDuFileul(String type, Map<String, Object?> champs, {String? etatActuel}) {
  final verdict = [for (final k in champsVerdictDemandeImport) if (champs.containsKey(k)) k];
  final etat = champs['etat'];
  if (type == 'creer') {
    if (verdict.isNotEmpty || (etat != null && etat != demandeImportEnAttente)) {
      return const [
        'verdict_reserve_a_la_mere',
        'Le verdict d’une demande d’import n’appartient qu’à la mère : un fileul dépose sa demande « en attente », sans verdict.',
        'Déposer la demande à l’état « en attente » et attendre la réponse de la mère'
      ];
    }
    return null;
  }
  if (verdict.isEmpty && etat == demandeImportRetiree && (etatActuel == null || etatActuel == demandeImportEnAttente || etatActuel == demandeImportRetiree)) return null;
  if (verdict.isNotEmpty || champs.containsKey('etat')) {
    return const [
      'verdict_reserve_a_la_mere',
      'Une demande déposée ne se réécrit pas : son état et son verdict ne se modifient que par la mère (le fileul peut seulement la RETIRER tant qu’elle attend).',
      'Déposer une nouvelle demande si le fichier a changé'
    ];
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Côté fileul : ce que le verdict de la mère commande
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le résultat d'une RESTITUTION : les fiches archivées et celles que le fileul GARDE parce qu'une pièce émise s'appuie déjà dessus (une pièce émise ne se réécrit jamais).
class ResultatRestitution {
  const ResultatRestitution.ok({required this.archives, this.gardees = const []})
      : ok = true,
        code = null,
        motif = null,
        geste = null;
  const ResultatRestitution.refus(String this.code, String this.motif, String this.geste)
      : ok = false,
        archives = 0,
        gardees = const [];
  final bool ok;
  final int archives;

  /// Les fiches conservées : `{collection, id, code, motif}` (le motif dit la pièce qui s'appuie dessus).
  final List<Map<String, Object?>> gardees;
  final String? code, motif, geste;

  /// `faite` quand tout est archivé, `partielle` quand une fiche a dû rester.
  String get etat => gardees.isEmpty ? restitutionFaite : restitutionPartielle;
}

/// RESTITUE le lot qu'un fileul a écrit chez lui quand la mère refuse ([codeRefus], [motifRefus] : le verdict, recopié au lot). Ce n'est pas une suppression (RG-14) : les fiches sont
/// ARCHIVÉES, comme à l'annulation d'un lot (`annulerLot`), les MODIFICATIONS du lot sont restituées dans l'ordre inverse.
///
/// Ce n'est pas le geste d'un agent mais la suite d'une décision de la mère : le droit d'annuler n'est donc PAS relu (un agent qui peut importer sans pouvoir annuler voit quand même
/// son écriture restituée). La règle de sûreté est ailleurs : une fiche qu'une pièce émise utilise déjà (la dépendance du jeu, relue FICHE PAR FICHE) n'est pas archivée ; elle reste,
/// marquée [champRefuseeParMere] avec le motif de la mère, et le verdict le dit. Un jeu qui porte des quantités (le Grand Stock) restitue à sa façon ([JeuImport.restituer]).
/// Idempotent : un lot déjà restitué ne se restitue pas deux fois.
ResultatRestitution restituerLotDirect(JeuImport? Function(String id) jeu, Object? lotId, {required String codeRefus, required String motifRefus, required PortImport port}) {
  final lot = port.parId(collectionLots, lotId);
  if (lot == null) return const ResultatRestitution.refus('LOT_INCONNU', 'le lot écrit chez vous est introuvable', 'Actualisez l’historique des lots.');
  if (lot['etat'] == 'restitue') return const ResultatRestitution.ok(archives: 0);
  if (lot['etat'] != 'applique') {
    return ResultatRestitution.refus('LOT_NON_APPLIQUE', 'seul un lot appliqué se restitue (état actuel : ${lot['etat']})', 'Aucune action : ce lot a déjà été annulé.');
  }
  final j = jeu('${lot['jeu']}');
  final ecrits = (lot['ecrits'] as List).cast<Map>().map((e) => e.cast<String, Object?>()).toList();
  final libelleMotif = 'Restitution du lot ${lot['reference']} : refusé par la mère ($codeRefus)';
  final motifMarque = '$codeRefus : $motifRefus';
  final gardees = <Map<String, Object?>>[];
  var archives = 0;
  if (j?.restituer != null) {
    final r = j!.restituer!(lot, libelleMotif, motifMarque, port);
    archives = r.archives;
    gardees.addAll(r.gardees);
  } else {
    for (final e in ecrits) {
      final f = port.parId('${e['collection']}', e['id']);
      if (f == null || f['statut'] == 'archive') continue;
      // Une pièce émise s'appuie-t-elle sur CETTE fiche ? La dépendance du jeu est relue sur un lot d'une seule fiche.
      final dep = j?.dependances({'reference': lot['reference'], 'jeu': lot['jeu'], 'ecrits': [e]}, port);
      if (dep != null) {
        port.mettreAJour('${e['collection']}', e['id'], {champRefuseeParMere: motifMarque});
        gardees.add({'collection': e['collection'], 'id': e['id'], 'code': dep.code, 'motif': dep.motif});
        continue;
      }
      if (port.archiver('${e['collection']}', e['id'], libelleMotif)) {
        archives++;
      } else {
        port.mettreAJour('${e['collection']}', e['id'], {champRefuseeParMere: motifMarque});
        gardees.add({'collection': e['collection'], 'id': e['id'], 'code': 'ARCHIVAGE_REFUSE', 'motif': 'le moteur a refusé d’archiver la fiche (garde ou exercice clos)'});
      }
    }
  }
  port.mettreAJour(collectionLots, lot['id'], {
    'etat': 'restitue',
    'restitueLe': port.jour,
    'motifRestitution': motifMarque,
    'restitueGardees': gardees.length,
  });
  port.journaliser('Import restitué (refusé par la mère)', 'IMP', 'LotImport', '${lot['reference']}', {'etat': 'applique'}, {'etat': 'restitue', 'code': codeRefus, 'fiches': archives, 'gardees': gardees.length});
  return ResultatRestitution.ok(archives: archives, gardees: gardees);
}

/// Un lot écrit chez un fileul s'annule tant que la mère n'a pas statué. Une fois confirmé par elle, il ne s'annule plus ICI (la mère détient les mêmes fiches : l'annuler chez le fileul seul
/// ferait diverger les deux), et un lot déjà refusé se restitue tout seul. Rend le refus nommé, ou `null` quand l'annulation est permise ([demande] `null` : lot sans demande).
({String code, String motif, String geste})? refusAnnulationLotDirect(FicheImport? demande) {
  if (demande == null || demande['ecritureDirecte'] != true) return null;
  switch (demande['etat']) {
    case demandeImportAppliquee:
      return (
        code: 'LOT_CONFIRME_PAR_LA_MERE',
        motif: 'la mère a confirmé ce lot${demande['resultatLot'] == null || '${demande['resultatLot']}'.isEmpty ? '' : ' (lot ${demande['resultatLot']} chez elle)'} : elle détient les mêmes fiches et décide de la configuration',
        geste: 'Demandez l’annulation du lot à la mère, sur le poste principal : les fiches vous reviennent par la configuration.',
      );
    case demandeImportRefusee:
      return (
        code: 'RESTITUTION_PAR_LA_MERE',
        motif: 'la mère a refusé ce lot : votre écriture locale est restituée automatiquement',
        geste: 'Rien à faire : lisez le motif sur la demande.',
      );
  }
  return null;
}

/// Les champs qui RETIRENT une demande que le fileul annule avant la réponse de la mère (elle ne la traite plus ; les lignes du fichier sont effacées).
Map<String, Object?> champsRetraitDemande({required String par, required String jour}) =>
    {'etat': demandeImportRetiree, 'retireePar': par, 'retireeLe': jour, 'lignes': <Object?>[]};

/// Ce que le fileul doit faire d'une demande dont il a écrit le lot chez lui, d'après son état.
enum SuiteDuVerdict {
  /// Rien : la demande attend la mère, ou tout est déjà fait.
  aucune,

  /// La mère a refusé : restituer le lot local.
  restituer,

  /// La mère a confirmé : lever le marquage « en attente de la mère » des fiches qu'elle n'a pas encore remplacées.
  leverLeMarquage,
}

SuiteDuVerdict suiteDuVerdict(FicheImport demande) {
  if (demande['ecritureDirecte'] != true) return SuiteDuVerdict.aucune;
  switch (demande['etat']) {
    case demandeImportRefusee:
      return demande['restitution'] == restitutionFaite || demande['restitution'] == restitutionPartielle ? SuiteDuVerdict.aucune : SuiteDuVerdict.restituer;
    case demandeImportAppliquee:
      return demande['marquageLeve'] == true ? SuiteDuVerdict.aucune : SuiteDuVerdict.leverLeMarquage;
  }
  return SuiteDuVerdict.aucune;
}

/// L'état d'une demande tel que le fileul le LIT : libellé et ton (`attention`, `succes`, `danger`, `neutre`). Un lot écrit chez le fileul n'est JAMAIS dit « appliqué » avant que la mère
/// l'ait confirmé : tant que la demande attend, le libellé dit « écrit chez vous, en attente de la mère ».
({String libelle, String ton}) libelleEtatDemandeImport(FicheImport demande) {
  final directe = demande['ecritureDirecte'] == true;
  switch (demande['etat']) {
    case demandeImportAppliquee:
      return (libelle: 'Appliquée par la mère', ton: 'succes');
    case demandeImportRefusee:
      final r = demande['restitution'];
      if (!directe) return (libelle: 'Refusée par la mère', ton: 'danger');
      if (r == restitutionFaite) return (libelle: 'Refusée par la mère, écriture restituée', ton: 'danger');
      if (r == restitutionPartielle) return (libelle: 'Refusée par la mère, restitution partielle', ton: 'danger');
      return (libelle: 'Refusée par la mère, restitution en cours', ton: 'danger');
    case demandeImportRetiree:
      return (libelle: 'Retirée par vous', ton: 'neutre');
    case demandeImportEnAttente:
      return directe ? (libelle: 'Écrit chez vous, en attente de la mère', ton: 'attention') : (libelle: 'En attente de la mère', ton: 'attention');
  }
  return (libelle: '${demande['etat']}', ton: 'neutre');
}
