/// LA DEMANDE D'IMPORT D'UN FILEUL À LA MÈRE (lot IMP-C, décision de la Direction du 12/11/2026, « option c »).
///
/// Un référentiel de configuration (famille R : la mère seule en est l'autorité) importé à un poste FILEUL suit DEUX chemins à la fois, jamais l'un sans l'autre :
///
///  1. le fileul écrit DIRECTEMENT chez lui — l'agent voit son import tout de suite, la garde « réglé sur la mère » étant levée pour CE geste seulement — ; les fiches posées sont
///     marquées PROVISOIRES (`provisoireMere`, `demandeImport`) et portent un identifiant propre au poste : elles ne peuvent entrer en collision avec aucune fiche de la mère ;
///  2. une DEMANDE vérifiée part automatiquement à la mère (fiche `demandesImport`, famille A : le fileul dépose, la mère complète du verdict). La mère reste la SEULE AUTORITÉ :
///     elle REJOUE l'analyse sous le rôle et le nom de l'auteur, avec sa propre matrice, ses propres données et ses propres bornes, puis applique par le MÊME chemin que l'import
///     local, ou refuse en NOMMANT le code, le motif et le geste.
///
/// Le verdict revient au fileul par la même fiche. [reconcilierEcrituresLocales] règle alors l'écriture locale, sans rien laisser disparaître en silence (RG-14) :
///  * appliquée : la mère a ses fiches ; sa copie arrive par la configuration diffusée, et l'écriture provisoire locale est ARCHIVÉE (motif nommé, restaurable) une fois la copie
///    visible — jamais avant, pour que le fileul ne se retrouve pas sans rien entre les deux ;
///  * refusée : l'écriture locale RESTE, marquée « non retenue par la mère » (`nonRetenueMere`, avec le code, le motif et le geste), et une notification le dit au fileul ;
///  * écrasée par la synchronisation (la fiche locale a disparu ou a été remplacée avant le verdict) : comptée et DITE, jamais tue.
///
/// DEUX CHOSES NE PASSENT JAMAIS PAR UNE DEMANDE : un jeu RESTREINT (patients, personnel, soldes, stock vivant, courriers : ses lignes ne voyagent pas dans une fiche partagée,
/// RG-13) et un jeu qui écrit aussi de l'ACTIVITÉ (lots, mouvements : leurs règles de fusion sont propres, le double geste doublerait le stock, RG-03). Les données de volume local
/// pur (le comptage d'inventaire du poste) restent locales. La mère le REDIT à chaque demande : une demande forgée par un fileul falsifié est refusée en le nommant.
///
/// Ce fichier ne porte que les règles pures, rejouées sans poste (`PortImportMemoire`) par les tests et par le banc ; le poste y branche son magasin.
library;

import 'dart:convert';

import 'moteur_import.dart';

/// La collection des demandes (famille A de la synchronisation : champ à champ, dans les deux sens ; jamais vers un téléphone).
const String demandesImportCollection = 'demandesImport';

/// États d'une demande : `en_attente` (déposée, la mère n'a pas encore statué), `appliquee`, `refusee`.
const String demandeImportEnAttente = 'en_attente', demandeImportAppliquee = 'appliquee', demandeImportRefusee = 'refusee';

/// Les champs que SEULE la mère écrit sur une demande : le verdict et son horodatage. Un fileul qui en écrit un est refusé par le protocole (`refusDemandeImportDuFileul`).
const List<String> champsVerdictDemandeImport = ['resultatCode', 'resultatMotif', 'resultatGeste', 'resultatLot', 'resultatEcrits', 'traitePar', 'traiteLe'];

/// Une demande dont les lignes, une fois sérialisées, dépassent ce multiple de la borne de taille du jeu est refusée : la borne porte sur le FICHIER (un classeur compressé),
/// les lignes déployées en JSON pèsent beaucoup plus. Un fileul falsifié ne peut ainsi pas faire avaler à la mère plus que ce que le jeu accepte à un poste.
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

/// Les identifiants d'une demande et d'une écriture provisoire portent l'étiquette du poste : deux postes ne se rencontrent jamais.
String identifiantDemandeImport(String etiquette, DateTime maintenant, int rang) => 'DIM$etiquette${maintenant.microsecondsSinceEpoch.toRadixString(36)}$rang';

/// La fiche déposée par le fileul. [analyse] est celle qu'il a faite lui-même (acceptée, au moins une ligne à écrire) : un fichier refusé ne part jamais.
Map<String, Object?> composerDemandeImport({
  required String id,
  required JeuImport jeu,
  required AnalyseImport analyse,
  required String role,
  required String par,
  required String jour,
  required String poste,
  String? lotLocal,
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
    if (lotLocal != null) 'lotLocal': lotLocal,
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
}) {
  if (!regime.exigeLaMere(jeu)) {
    return ImportDirectEtDemande.refuse(ResultatImport.refus(
        'JEU_NON_DEMANDABLE', 'le jeu « ${jeu.libelle} » ne passe pas par une demande à la mère', 'Importez-le par la voie ordinaire du poste, ou au poste de la mère s’il est réservé.'));
  }
  if (!analyse.accepte || analyse.aEcrire == 0) {
    return ImportDirectEtDemande.refuse(
        const ResultatImport.refus('ANALYSE_REFUSEE', 'le fichier n’a pas passé l’analyse, ou n’a rien à écrire', 'Corrigez les refus listés, puis téléversez de nouveau.'));
  }
  // L'ÉCRITURE DIRECTE : le même chemin que tout import (droit, rejeu de l'analyse, atomicité, lot consigné). Refusée, rien n'est déposé.
  final r = appliquer(jeu, analyse, port);
  if (!r.ok) return ImportDirectEtDemande.refuse(r);
  final lot = r.lot!;
  // Les fiches posées sont PROVISOIRES : la mère reste l'autorité, elle décide si elles sont retenues.
  for (final e in ((lot['ecrits'] as List?) ?? const []).cast<Map>()) {
    port.mettreAJour('${e['collection']}', e['id'], {'provisoireMere': true, 'demandeImport': idDemande});
  }
  port.mettreAJour(collectionLots, lot['id'], {'etatMere': 'en_attente', 'demandeImport': idDemande});
  final demande = composerDemandeImport(
      id: idDemande, jeu: jeu, analyse: analyse, role: port.profil.role, par: port.utilisateur, jour: port.jour, poste: poste, lotLocal: '${lot['reference']}');
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
/// ICI) ; `FICHIER_TROP_GROS` ; le code du premier refus de l'analyse REJOUÉE (`DOUBLON_MAGASIN`, quand un autre poste a créé la même fiche entre-temps…) ; `ECRITURE_REFUSEE`.
VerdictDemandeImport traiterDemandeImport(
  FicheImport demande,
  PortImport port,
  JeuImport? Function(String id) jeuParId, {
  required RegimeDemandesImport regime,
  int? octetsMax,
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
  final r = appliquer(j, a, port);
  if (r.ok) return VerdictDemandeImport.appliquee(lot: '${r.lot!['reference']}', ecrits: r.ecrits);
  return VerdictDemandeImport.refusee(r.code ?? 'ECRITURE_REFUSEE', r.motif ?? 'l’écriture a été refusée', r.geste ?? 'Rien n’a été écrit.', lot: r.lot == null ? null : '${r.lot!['reference']}');
}

/// LE PROTOCOLE : ce qu'un poste qui n'est PAS la mère n'a pas le droit d'écrire sur une demande. Rend `null` quand l'opération est permise, sinon [code, motif, geste].
/// [type] : `creer` ou `modifier`. Le dépôt d'une demande est un AJOUT : à la création, l'état est `en_attente` et aucun champ de verdict n'est présent ; ensuite ni l'état ni le
/// verdict ne se réécrivent par un fileul (sans cela, un fileul falsifié se délivrerait lui-même un verdict, ou remettrait en attente une demande traitée pour la faire rejouer).
List<String>? refusDemandeImportDuFileul(String type, Map<String, Object?> champs) {
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
  if (verdict.isNotEmpty || champs.containsKey('etat')) {
    return const [
      'verdict_reserve_a_la_mere',
      'Une demande déposée ne se réécrit pas : son état et son verdict ne se modifient que par la mère.',
      'Déposer une nouvelle demande si le fichier a changé'
    ];
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Côté fileul : régler l'écriture locale quand le verdict est revenu
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce qu'a fait [reconcilierEcrituresLocales] : l'issue, et ce qu'il faut dire au fileul.
class ReconciliationImport {
  const ReconciliationImport(this.issue, {this.archivees = 0, this.marquees = 0, this.ecrasees = 0, this.titre = '', this.detail = ''});

  /// `retenue` (appliquée à la mère, écriture locale archivée) · `non_retenue` (refusée, écriture locale marquée) · `attente_copie` (appliquée, copie de la mère pas encore visible : on
  /// réessaie) · `sans_objet` (déjà réglée, ou pas de lot local) · `en_attente` (aucun verdict).
  final String issue;
  final int archivees, marquees, ecrasees;
  final String titre, detail;

  /// Il y a quelque chose à dire à l'agent (notification) : un verdict est tombé.
  bool get aNotifier => issue == 'retenue' || issue == 'non_retenue';
}

/// Règle l'écriture LOCALE d'une demande dont la mère a rendu son verdict. [port] est le port local du fileul (gardes levées). [copieDeLaMereVisible] dit si la mère a diffusé ses
/// fiches du lot [lotMere] pour [collection] (la configuration arrive par un autre canal que la demande, parfois après elle). Idempotent : l'état du lot local garde la mémoire.
ReconciliationImport reconcilierEcrituresLocales(
  FicheImport demande,
  PortImport port, {
  required bool Function(String collection, String lotMere) copieDeLaMereVisible,
}) {
  final etat = demande['etat'];
  if (etat != demandeImportAppliquee && etat != demandeImportRefusee) return const ReconciliationImport('en_attente');
  final lot = port.toutes(collectionLots).where((l) => l['reference'] == demande['lotLocal'] && l['demandeImport'] == demande['id']).firstOrNull;
  if (lot == null || lot['etatMere'] != 'en_attente') return const ReconciliationImport('sans_objet');
  final ecrits = ((lot['ecrits'] as List?) ?? const []).cast<Map>();
  // Une fiche provisoire encore là et encore marquée ; une fiche archivée par l'agent depuis (annulation du lot) n'est ni écrasée ni à régler ; le reste a été ÉCRASÉ par la synchronisation.
  final provisoires = <Map<String, Object?>>[];
  var ecrasees = 0;
  for (final e in ecrits) {
    final f = port.parId('${e['collection']}', e['id']);
    if (f == null || f['provisoireMere'] != true || f['demandeImport'] != demande['id']) {
      ecrasees++;
    } else if (f['statut'] != 'archive') {
      provisoires.add({'collection': e['collection'], 'id': e['id']});
    }
  }
  final libelle = '${demande['jeuLibelle'] ?? demande['jeu']}';
  final fichier = '${demande['fichier'] ?? ''}';
  final dit = ecrasees == 0 ? '' : ' $ecrasees fiche(s) provisoire(s) avaient déjà été remplacées par la synchronisation avant le verdict.';
  if (etat == demandeImportAppliquee) {
    final lotMere = '${demande['resultatLot']}';
    // La copie de la mère arrive par la configuration diffusée : tant qu'elle n'est pas là, l'écriture provisoire reste visible.
    final collections = {for (final p in provisoires) '${p['collection']}'};
    if (collections.any((c) => !copieDeLaMereVisible(c, lotMere))) return ReconciliationImport('attente_copie', ecrasees: ecrasees);
    var n = 0;
    for (final p in provisoires) {
      if (port.archiver('${p['collection']}', p['id'], 'Retenue par la mère (lot $lotMere) : sa copie remplace l’écriture provisoire de ce poste')) n++;
    }
    port.mettreAJour(collectionLots, lot['id'], {'etatMere': 'retenue', 'lotMere': lotMere, 'verdictLe': port.jour});
    port.journaliser('Import retenu par la mère', 'IMP', 'DemandeImport', '${demande['id']}', {'etatMere': 'en_attente'}, {'lotMere': lotMere, 'archivees': n, 'ecrasees': ecrasees});
    return ReconciliationImport('retenue',
        archivees: n,
        ecrasees: ecrasees,
        titre: 'Import retenu par la mère',
        detail: 'La mère a appliqué « $libelle » ($fichier, lot $lotMere) : sa copie remplace votre écriture provisoire.$dit');
  }
  final motif = '${demande['resultatCode']} : ${demande['resultatMotif']}';
  var m = 0;
  for (final p in provisoires) {
    port.mettreAJour('${p['collection']}', p['id'], {
      'provisoireMere': false,
      'nonRetenueMere': true,
      'motifNonRetenue': motif,
      'gesteNonRetenue': '${demande['resultatGeste'] ?? ''}',
      'nonRetenueLe': port.jour,
    });
    m++;
  }
  port.mettreAJour(collectionLots, lot['id'], {'etatMere': 'non_retenue', 'motifMere': motif, 'verdictLe': port.jour});
  port.journaliser('Import non retenu par la mère', 'IMP', 'DemandeImport', '${demande['id']}', {'etatMere': 'en_attente'}, {'code': demande['resultatCode'], 'marquees': m, 'ecrasees': ecrasees});
  return ReconciliationImport('non_retenue',
      marquees: m,
      ecrasees: ecrasees,
      titre: 'Import non retenu par la mère',
      detail:
          'La mère a refusé « $libelle » ($fichier) : $motif. $m fiche(s) écrite(s) chez vous restent visibles, marquées « non retenue par la mère » ; ${demande['resultatGeste'] ?? ''}$dit');
}
