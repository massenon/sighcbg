part of 'jeux_import.dart';

/// LES SEPT JEUX DE RÉFÉRENTIELS DU LOT « JEUX SUPPLÉMENTAIRES » : natures de facture, centres de coûts, unités de mesure du laboratoire, catalogue de l'imagerie, prestataires
/// externes, immobilisations, budgets. Portés de la clinique sœur (qui les a prouvés sur sa maquette) et ADAPTÉS aux champs réels des écrans de Baguidi : chaque jeu écrit la fiche que la saisie
/// à l'écran écrit, jamais à côté, et ne modifie JAMAIS une fiche tenue.
///
/// CLASSEMENT (voir `docs/architecture/ECARTS-MAQUETTE.md`) :
///  * DIRECT ET DEMANDE (non restreints, cible de configuration de la mère) : natures de facture, centres de coûts, unités du laboratoire, catalogue de l'imagerie. Sur un fileul rattaché, l'agent
///    voit son import aussitôt et une demande vérifiée part à la mère, qui reste l'autorité (`demande_import.dart`) ;
///  * DIRECT SEUL, RESTREINT : prestataires (tarif par acte = rémunération), immobilisations (patrimoine), budgets (prévisionnel financier). Leurs lignes ne voyagent jamais dans une demande (RG-13) ;
///  * RÉSERVÉ À LA MÈRE : aucun (il faudrait un jeu restreint qui écrive de la configuration).
///
/// « Ignorer les existants » reste réservé aux quatre jeux de la Direction (produits, fournisseurs, emplacements, courriers) : aucun de ces sept ne l'accorde, chacun étant le SUPPORT d'une pièce
/// émise (nature portée par une facture, centre porté par une écriture, unité d'un résultat, examen d'une demande, bien d'un amortissement, budget d'un réalisé).

/// Les secteurs d'activité proposés par l'écran « Natures de facture » (`referentiels.secteursActivite` du jeu du poste, test de concordance au domaine).
const List<String> importSecteursActivite = [
  'Médecine générale',
  'Chirurgie',
  'Maternité',
  'Imagerie médicale',
  'Laboratoire',
  'Accueil',
  'Soins et observation',
  'Pharmacie',
];

/// Les spécialités d'un prestataire externe : celles de l'écran, plus « Autre » qu'il propose aussi.
const List<String> importSpecialitesPrestataire = [...rhaSpecialitesPrestataire, 'Autre'];

ProblemeImport _avert(String colonne, Object? valeur, String code, String motif, String geste) => _p(colonne, valeur, code, importAvertissement, motif, geste);
ProblemeImport _refus(String colonne, Object? valeur, String code, String motif, String geste) => _p(colonne, valeur, code, importRefus, motif, geste);

Map<String, _V> _actifsParCode(PortImport port, String collection, String champ) =>
    {for (final x in port.toutes(collection)) if (x['statut'] != 'archive' && x[champ] != null) _n(x[champ]): x};

Iterable<Object?> _ecritsDe(FicheImport lot, String collection) => [for (final e in (lot['ecrits'] as List).cast<Map>()) if (e['collection'] == collection) e['id']];

// --- 17. NATURES DE FACTURE ---------------------------------------------------------------------------------------------------------

final JeuImport jeuNaturesFacture = JeuImport(
  id: 'natures-facture',
  octetsMaxDefaut: octetsMaxImportCourt,
  ecran: 'imp-natures-facture',
  libelle: 'Importation des natures de facture',
  module: 'CFG',
  statut: 'supporte',
  description: 'Natures proposées à l’émission d’une facture : code, nature, secteur émetteur.',
  source: 'Écran « Natures de facture » (configuration) : la liste que la caisse propose à l’émission.',
  limite: 'Le secteur émetteur se choisit parmi les secteurs que propose l’écran « Natures de facture » (la même liste que la saisie). Une nature importée est proposée à la caisse dès l’import.',
  cibles: const ['naturesFacture'],
  fichierModele: 'modele-import-natures-facture',
  gesteExiste: 'Retirez la ligne : une nature tenue se modifie à l’écran « Natures de facture ».',
  colonnes: [
    _oblig('code', 'Code', 'texte',
        motif: RegExp(r'^[A-Za-z0-9]{2,8}$'), motifTexte: '2 à 8 lettres ou chiffres, sans espace', exemple: 'ORTH', aide: 'Quatre lettres en usage ; écrit en majuscules. Un code déjà tenu refuse le fichier.'),
    _oblig('libelle', 'Nature de la facture', 'texte', longueurMax: 80, exemple: 'Orthopédie', aide: 'Le libellé que la caisse choisit à l’émission : deux natures ne portent jamais le même.'),
    _oblig('secteur', 'Secteur émetteur', 'liste', liste: _fixe(importSecteursActivite), exemple: 'Chirurgie'),
    _col('source', 'Origine', 'texte', longueurMax: 120, exemple: 'Décision de la Direction'),
  ],
  contexte: (port) => {'codes': _actifsParCode(port, 'naturesFacture', 'code'), 'libelles': _actifsParCode(port, 'naturesFacture', 'libelle')},
  cle: (v) => [_n(v['code']), 'lib:${_n(v['libelle'])}'],
  existe: (v, ctx) {
    final a = (ctx['codes'] as Map)[_n(v['code'])] as _V?, b = (ctx['libelles'] as Map)[_n(v['libelle'])] as _V?;
    if (a != null) return 'la nature « ${a['code']} » existe déjà (${a['libelle']})';
    return b != null ? 'la nature « ${b['libelle']} » existe déjà sous le code ${b['code']}' : null;
  },
  regles: _aucun,
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('naturesFacture', {
        'code': '${v['code']}'.toUpperCase(),
        'libelle': v['libelle'],
        'secteur': v['secteur'],
        'ordre': port.toutes('naturesFacture').length + 1,
        if (v['source'] != null) 'source': v['source'],
      });
    }
  },
  dependances: (lot, port) {
    final libs = {for (final id in _ecritsDe(lot, 'naturesFacture')) port.parId('naturesFacture', id)?['libelle']}..remove(null);
    final f = port.actives('factures').where((x) => libs.contains(x['type'])).firstOrNull;
    return f == null
        ? null
        : DependanceImport('NATURE_UTILISEE', 'la facture ${f['numero'] ?? f['id']} porte déjà cette nature', 'Archivez la nature à l’écran « Natures de facture » (RG-14) plutôt que d’annuler son lot.');
  },
);

// --- 18. CENTRES DE COÛTS -----------------------------------------------------------------------------------------------------------

final JeuImport jeuCentresCouts = JeuImport(
  id: 'centres-couts',
  octetsMaxDefaut: octetsMaxImportCourt,
  ecran: 'imp-centres-couts',
  libelle: 'Importation des centres de coûts',
  module: 'M12',
  statut: 'supporte',
  description: 'Axes d’imputation analytique : code, intitulé, type, responsable.',
  source: 'Écran « Centres de coûts » : les six secteurs porteurs de recette plus la Direction (transverse), complétés par la clinique.',
  limite: 'Le code EST l’imputation que portent les écritures comptables : il ne se double jamais, majuscules et minuscules confondues, et un code tenu n’est jamais modifié.',
  cibles: const ['centresCouts'],
  fichierModele: 'modele-import-centres-couts',
  gesteExiste: 'Retirez la ligne : le code d’un centre ne se double jamais (les écritures le portent) ; un centre tenu se modifie à l’écran « Centres de coûts ».',
  colonnes: [
    _oblig('code', 'Code', 'texte',
        motif: RegExp(r'^[A-Za-z0-9_-]{2,24}$'), motifTexte: '2 à 24 lettres, chiffres, tiret ou souligné, sans espace', exemple: 'orthopedie', aide: 'L’imputation portée par les écritures. Écrit tel quel.'),
    _oblig('libelle', 'Intitulé du centre', 'texte', longueurMax: 80, exemple: 'Orthopédie'),
    _oblig('type', 'Type', 'liste', liste: (_) => const [ValeurListe('exploitation', 'Centre d’exploitation'), ValeurListe('support', 'Centre de support')], exemple: 'Centre d’exploitation'),
    _col('responsable', 'Responsable', 'texte', longueurMax: 80, exemple: ''),
    _col('source', 'Origine', 'texte', longueurMax: 120, exemple: 'Décision de la Direction'),
  ],
  contexte: (port) => {'codes': _actifsParCode(port, 'centresCouts', 'code'), 'libelles': _actifsParCode(port, 'centresCouts', 'libelle')},
  cle: (v) => [_n(v['code']), 'lib:${_n(v['libelle'])}'],
  existe: (v, ctx) {
    final a = (ctx['codes'] as Map)[_n(v['code'])] as _V?, b = (ctx['libelles'] as Map)[_n(v['libelle'])] as _V?;
    if (a != null) return 'le centre « ${a['code']} » existe déjà (${a['libelle']})';
    return b != null ? 'le centre « ${b['libelle']} » existe déjà sous le code ${b['code']}' : null;
  },
  regles: (v, ctx, sc, n) =>
      v['responsable'] != null ? const [] : [_avert('Responsable', '', 'SANS_RESPONSABLE', 'aucun responsable désigné', 'Il se désigne à l’écran « Centres de coûts ».')],
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('centresCouts', {'code': v['code'], 'libelle': v['libelle'], 'type': v['type'], 'responsable': v['responsable'], if (v['source'] != null) 'source': v['source']});
    }
  },
  dependances: (lot, port) {
    final codes = {for (final id in _ecritsDe(lot, 'centresCouts')) port.parId('centresCouts', id)?['code']}..remove(null);
    final ec = port.actives('ecritures').where((x) => codes.contains(x['centreCout'])).firstOrNull;
    if (ec != null) {
      return DependanceImport('CENTRE_IMPUTE', 'l’écriture ${ec['piece'] ?? ec['numero'] ?? ec['id']} est déjà imputée à ce centre', 'Archivez le centre à l’écran « Centres de coûts » (RG-14) plutôt que d’annuler son lot.');
    }
    final b = port.actives('budgets').where((x) => codes.contains(x['centreCout'])).firstOrNull;
    return b == null ? null : DependanceImport('CENTRE_BUDGETE', 'le budget ${b['reference']} porte déjà ce centre', 'Annulez d’abord le lot de budgets, ou archivez le centre.');
  },
);

// --- 19. UNITÉS DE MESURE DU LABORATOIRE --------------------------------------------------------------------------------------------

final JeuImport jeuUnitesLabo = JeuImport(
  id: 'unites-labo',
  octetsMaxDefaut: octetsMaxImportCourt,
  ecran: 'imp-unites-labo',
  libelle: 'Importation des unités de mesure',
  module: 'M5',
  statut: 'supporte',
  description: 'Unités dans lesquelles les résultats s’expriment : symbole tel que le laboratoire l’écrit, intitulé, domaine.',
  source: 'Fiche de résultats de la clinique et écran « Unités de mesure » : « G/l », « T/l », « g/dl », jamais les notations normalisées.',
  limite: 'Le symbole s’écrit comme le laboratoire le lit et ne se normalise JAMAIS : « G/l » (giga par litre) et « g/l » (gramme par litre) sont deux unités. Une unité importée naît « à confirmer » ; le biologiste médical la valide.',
  cibles: const ['unitesLabo'],
  fichierModele: 'modele-import-unites-labo',
  gesteExiste: 'Retirez la ligne : une unité tenue se modifie à l’écran « Unités de mesure ».',
  colonnes: [
    _oblig('symbole', 'Symbole', 'texte', longueurMax: 20, exemple: 'mmol/l', aide: 'Tel qu’il s’imprime sur la fiche de résultats. Les majuscules et minuscules comptent.'),
    _oblig('libelle', 'Intitulé complet', 'texte', longueurMax: 80, exemple: 'millimole par litre'),
    _oblig('domaine', 'Domaine', 'liste', liste: _fixe(catDomainesUnite), exemple: 'Biochimie'),
  ],
  // Le symbole ne se normalise jamais : la clé est le symbole TEL QUEL (la casse compte).
  contexte: (port) => {
        'unites': {for (final u in port.toutes('unitesLabo')) if (u['statut'] != 'archive') '${u['symbole']}': u}
      },
  cle: (v) => ['${v['symbole']}'],
  existe: (v, ctx) {
    final u = (ctx['unites'] as Map)['${v['symbole']}'] as _V?;
    return u != null ? 'l’unité « ${u['symbole']} » existe déjà (${u['libelle']})' : null;
  },
  regles: (v, ctx, sc, n) =>
      [_avert('Symbole', '', 'A_CONFIRMER', 'unité importée « à confirmer » jusqu’à sa validation par le biologiste médical', 'Le biologiste la valide à l’écran « Unités de mesure ».')],
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      ecrireFiche('unitesLabo', {'symbole': l.v['symbole'], 'libelle': l.v['libelle'], 'domaine': l.v['domaine'], 'aValider': true});
    }
  },
  dependances: (lot, port) {
    final cles = <Object?>{};
    for (final id in _ecritsDe(lot, 'unitesLabo')) {
      final u = port.parId('unitesLabo', id);
      if (u != null) cles..add(u['symbole'])..add(u['id']);
    }
    final v = port.actives('variablesLabo').where((x) => cles.contains(x['unite'])).firstOrNull;
    return v == null
        ? null
        : DependanceImport('UNITE_UTILISEE', 'la variable « ${v['libelle'] ?? v['code']} » s’exprime déjà dans cette unité', 'Archivez l’unité à l’écran « Unités de mesure » (RG-14) plutôt que d’annuler son lot.');
  },
);

// --- 20. CATALOGUE DE L'IMAGERIE ----------------------------------------------------------------------------------------------------

final JeuImport jeuCatalogueImagerie = JeuImport(
  id: 'catalogue-imagerie',
  octetsMaxDefaut: octetsMaxImportCourt,
  ecran: 'imp-catalogue-imagerie',
  libelle: 'Importation du catalogue de l’imagerie',
  module: 'CFG',
  statut: 'supporte',
  description: 'Examens d’imagerie : code, libellé, modalité (échographie, radiographie, mammographie, scanner, IRM), voie d’abord, code tarifaire.',
  source: 'Écran « Catalogue de l’imagerie » : l’examen est un acte facturable, rangé dans le tableau de sa modalité.',
  limite: 'PROPOSITION À VALIDER : un examen importé naît « à valider » et le dit ; il ne porte AUCUNE variable de compte rendu (elles se définissent au catalogue). Le prix ne s’importe pas : il vit au référentiel tarifaire.',
  cibles: const ['examensImagerie'],
  fichierModele: 'modele-import-catalogue-imagerie',
  gesteExiste: 'Retirez la ligne : un examen tenu se modifie à l’écran « Catalogue de l’imagerie ».',
  colonnes: [
    _oblig('code', 'Code examen', 'texte',
        motif: RegExp(r'^[A-Za-z0-9_-]{2,40}$'), motifTexte: '2 à 40 lettres, chiffres, tiret ou souligné', exemple: 'IMG-RAD-THO', aide: 'Aligné sur le code du référentiel tarifaire : un examen est un acte facturable.'),
    _oblig('libelle', 'Intitulé', 'texte', longueurMax: 160, exemple: 'Radiographie du thorax'),
    _oblig('modalite', 'Modalité', 'liste',
        liste: (_) => [for (final m in modalitesImagerie) ValeurListe(m.code, m.label)], exemple: 'Radiographie', aide: 'Elle range l’examen dans SON tableau.'),
    _col('voie', 'Voie d’abord', 'texte', longueurMax: 60, exemple: 'sus-pubienne'),
    _col('tarifCode', 'Code tarifaire (si différent)', 'texte', longueurMax: 30, exemple: '', aide: 'Quand l’examen se facture comme un autre.'),
  ],
  contexte: (port) => {'examens': _actifsParCode(port, 'examensImagerie', 'code')},
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) {
    final x = (ctx['examens'] as Map)[_n(v['code'])] as _V?;
    return x != null ? 'l’examen « ${x['code']} » existe déjà (${x['label']})' : null;
  },
  regles: (v, ctx, sc, n) => [
    _avert('Code examen', '', 'A_VALIDER', 'examen importé en proposition : il porte la mention « à valider » jusqu’à la relecture du praticien de la famille',
        'L’échographiste ou le directeur médical le valide à l’écran « Catalogue de l’imagerie ».'),
    _avert('Code examen', '', 'SANS_VARIABLES', 'aucune variable de compte rendu n’est importée', 'Elles se définissent au catalogue (onglet « Variables »), jamais depuis un fichier.'),
  ],
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      final m = modaliteImagerie('${v['modalite']}');
      ecrireFiche('examensImagerie', {
        'code': v['code'],
        'label': v['libelle'],
        'icone': m?.icone ?? 'scan-line',
        'voie': v['voie'],
        'modalite': v['modalite'],
        'tarifCode': v['tarifCode'],
        'aValider': true,
      });
    }
  },
  dependances: (lot, port) {
    final codes = {for (final id in _ecritsDe(lot, 'examensImagerie')) port.parId('examensImagerie', id)?['code']}..remove(null);
    final d = port.actives('demandesImagerie').where((x) => codes.contains(x['examenCode'])).firstOrNull;
    return d == null
        ? null
        : DependanceImport('EXAMEN_DEMANDE', 'l’examen est déjà demandé (${d['reference'] ?? d['id']})', 'Archivez l’examen à l’écran « Catalogue de l’imagerie » (RG-14) plutôt que d’annuler son lot.');
  },
);

// --- 21. PRESTATAIRES EXTERNES (RESTREINT) ------------------------------------------------------------------------------------------

final JeuImport jeuPrestataires = JeuImport(
  id: 'prestataires',
  restreint: true,
  octetsMaxDefaut: octetsMaxImportCourt,
  ecran: 'imp-prestataires',
  libelle: 'Importation des prestataires externes',
  module: 'M10',
  statut: 'supporte',
  description: 'Intervenants extérieurs rémunérés à l’acte : nom, spécialité, téléphone, tarif par acte, IFU, facture normalisée.',
  source: 'Écran « Prestataires externes » (circoncision, hydrotubation, accouchement, analyses, chirurgie, échographie, anesthésie).',
  limite: 'Les actes réalisés ne s’importent pas : c’est un compteur d’activité du mois, il part de zéro. Le numéro (PE-NNNN) est attribué par le logiciel, jamais lu du fichier.',
  cibles: const ['prestataires'],
  fichierModele: 'modele-import-prestataires',
  gesteExiste: 'Retirez la ligne : un prestataire tenu se modifie à l’écran « Prestataires externes ».',
  colonnesRetirees: const [
    ColonneRetiree('Actes réalisés', 'les actes réalisés sont un compteur d’activité du mois : ils ne s’importent pas et partent de zéro'),
    ColonneRetiree('N°', 'le numéro PE-NNNN est attribué par le logiciel, jamais lu d’un fichier'),
  ],
  colonnes: [
    _oblig('nom', 'Nom du prestataire', 'texte', longueurMax: 120, exemple: 'Dr EXEMPLE Alpha'),
    _oblig('specialite', 'Spécialité / type d’acte', 'liste', liste: _fixe(importSpecialitesPrestataire), exemple: 'Chirurgie'),
    _col('telephone', 'Téléphone', 'texte', longueurMax: 30, exemple: '0197000000'),
    _oblig('tarifActe', 'Tarif par acte (FCFA)', 'entier', min: 0, exemple: 25000, aide: 'Montant entier en francs. Un tiret n’est pas un zéro : il est refusé ; zéro est signalé.'),
    _col('ifu', 'IFU du prestataire', 'texte', motif: RegExp(r'^\d{13}$'), motifTexte: '13 chiffres', exemple: '3202112446712'),
    _col('factureNormalisee', 'Facture normalisée fournie', 'liste',
        liste: (_) => const [ValeurListe('oui', 'Oui'), ValeurListe('non', 'Non')], exemple: 'Non', aide: 'Vide : « Non » (comme l’écran).'),
  ],
  contexte: (port) {
    final n = <String, _V>{}, f = <String, _V>{};
    for (final p in port.toutes('prestataires')) {
      if (p['statut'] == 'archive') continue;
      n[_n(p['nom'])] = p;
      if (p['ifu'] != null && '${p['ifu']}'.isNotEmpty) f['${p['ifu']}'] = p;
    }
    return {'noms': n, 'ifus': f};
  },
  cle: (v) => [_n(v['nom']), if (v['ifu'] != null) 'ifu:${v['ifu']}'],
  existe: (v, ctx) {
    final a = v['ifu'] != null ? (ctx['ifus'] as Map)['${v['ifu']}'] as _V? : null, b = (ctx['noms'] as Map)[_n(v['nom'])] as _V?;
    if (a != null) return 'un prestataire porte déjà cet IFU (${a['nom']})';
    return b != null ? 'le prestataire « ${b['nom']} » existe déjà' : null;
  },
  regles: (v, ctx, sc, n) => [
    if (v['ifu'] == null) _avert('IFU du prestataire', '', 'IFU_ABSENT', 'IFU absent : la charge n’est pas déductible', 'Renseignez-le dès que le prestataire le fournit.'),
    if (v['factureNormalisee'] != 'oui')
      _avert('Facture normalisée fournie', '', 'FACTURE_NORMALISEE_ABSENTE', 'pas de facture normalisée : la dépense reste hors du circuit MECeF', 'Le prestataire doit la fournir ; la case se coche à l’écran.'),
    if (v['tarifActe'] == 0)
      _avert('Tarif par acte (FCFA)', 0, 'TARIF_NUL', 'tarif de zéro : un acte à zéro franc n’est pas un tarif', 'Saisissez le tarif remis par la Direction ; à défaut, l’écran le marque « à fournir ».'),
  ],
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('prestataires', {
        'reference': admReferenceSuivante('PE-', 4, port.toutes('prestataires')),
        'nom': v['nom'],
        'specialite': v['specialite'],
        'telephone': v['telephone'],
        'tarifActe': v['tarifActe'],
        'actesRealises': 0,
        'ifu': v['ifu'],
        'factureNormalisee': v['factureNormalisee'] == 'oui',
      });
    }
  },
  dependances: (lot, port) {
    final p = [for (final id in _ecritsDe(lot, 'prestataires')) port.parId('prestataires', id)].where((x) => x != null && ((x['actesRealises'] as num?) ?? 0) > 0).firstOrNull;
    return p == null
        ? null
        : DependanceImport('PRESTATAIRE_EN_ACTIVITE', 'le prestataire « ${p['nom']} » a déjà ${p['actesRealises']} acte(s) réalisé(s) ce mois', 'Archivez-le à l’écran « Prestataires externes » (RG-14).');
  },
);

// --- 22. IMMOBILISATIONS (RESTREINT) ------------------------------------------------------------------------------------------------

/// Les comptes d'immobilisation : classes 21 à 27 (la 28 porte les amortissements, la 29 les dépréciations).
final RegExp _compteImmobilisation = RegExp(r'^2[1-7]');

String _cleBien(_V v) => '${_n(v['designation'])}|${v['dateAcquisition']}|${v['valeur']}';

final JeuImport jeuImmobilisations = JeuImport(
  id: 'immobilisations',
  restreint: true,
  octetsMaxDefaut: octetsMaxImportCourt,
  ecran: 'imp-immobilisations',
  libelle: 'Importation des immobilisations',
  module: 'M12',
  statut: 'supporte',
  description: 'Registre des biens : désignation, catégorie, date d’acquisition, valeur, durée d’amortissement, compte SYSCOHADA.',
  source: 'Écran « Immobilisations & amortissements » : les biens du patrimoine de la clinique.',
  limite:
      'L’amortissement SEMESTRIEL se CALCULE à la lecture, de la date d’acquisition à aujourd’hui : il ne s’importe jamais, et aucune écriture comptable n’est écrite. Un bien cédé ne s’importe pas (la cession se déclare à l’écran). Le numéro IM-NNN est attribué par le logiciel quand la colonne Référence est vide.',
  cibles: const ['immobilisations'],
  fichierModele: 'modele-import-immobilisations',
  gesteExiste: 'Retirez la ligne : un bien tenu se modifie à l’écran « Immobilisations & amortissements » ; son numéro n’est jamais réécrit.',
  colonnesRetirees: const [
    ColonneRetiree('Date de cession', 'une cession se déclare à l’écran « Immobilisations & amortissements » : un bien déjà cédé ne s’importe pas'),
    ColonneRetiree('Prix de cession', 'une cession se déclare à l’écran : un bien déjà cédé ne s’importe pas'),
    ColonneRetiree('Motif de la sortie', 'une sortie du patrimoine se déclare à l’écran : un bien déjà sorti ne s’importe pas'),
    ColonneRetiree('Amortissement cumulé', 'l’amortissement se calcule à la lecture, jamais importé'),
    ColonneRetiree('Valeur nette comptable', 'la valeur nette se calcule à la lecture, jamais importée'),
    ColonneRetiree('Dotation', 'la dotation se calcule à la lecture, jamais importée'),
  ],
  colonnes: [
    _col('reference', 'Référence', 'texte',
        motif: RegExp(r'^[A-Za-z0-9-]{2,20}$'), motifTexte: '2 à 20 lettres, chiffres ou tirets', exemple: 'IM-050', aide: 'Vide : numéro IM-NNN attribué par le logiciel. Renseignée, elle ne doit pas déjà exister.'),
    _oblig('designation', 'Désignation du bien', 'texte', longueurMax: 160, exemple: 'Moniteur multiparamétrique'),
    _oblig('categorie', 'Catégorie', 'liste', liste: _fixe(cpbCategoriesImmobilisation), exemple: 'Matériel médical'),
    _oblig('dateAcquisition', 'Date d’acquisition', 'date', exemple: '2026-03-15', aide: 'Jamais dans le futur.'),
    _oblig('valeur', 'Valeur d’acquisition (FCFA)', 'entier',
        min: 1,
        exemple: 1800000,
        aide: 'Montant entier strictement positif. Un tiret n’est pas un zéro.',
        sousMin: const SousMinImport('VALEUR_NULLE', 'la valeur d’acquisition doit être strictement positive : un bien sans valeur n’est pas une immobilisation', 'Saisissez la valeur d’acquisition en francs, ou retirez la ligne.')),
    _oblig('duree', 'Durée d’amortissement (années)', 'entier', min: 1, max: 30, exemple: 5),
    _oblig('compte', 'Compte d’immobilisation', 'texte',
        motif: RegExp(r'^\d{3,8}$'), motifTexte: 'numéro de compte SYSCOHADA de 3 à 8 chiffres', exemple: '241000', aide: 'Un compte d’immobilisation (classe 21 à 27) connu du plan comptable.'),
    _col('fournisseur', 'Fournisseur', 'texte', longueurMax: 120, exemple: ''),
    _col('etat', 'État', 'liste', liste: _fixe(cpbEtatsImmobilisation), exemple: 'En service', aide: 'Vide : « En service ». « Cédé » est refusé : un bien déjà cédé ne s’importe pas.'),
  ],
  contexte: (port) {
    final refs = <String, _V>{}, ids = <String, _V>{}, comptes = <String, _V>{};
    for (final i in port.toutes('immobilisations')) {
      if (i['statut'] == 'archive') continue;
      if (i['reference'] != null) refs[_n(i['reference'])] = i;
      ids['${_n(i['designation'])}|${i['dateAcquisition']}|${i['valeurAcquisition']}'] = i;
    }
    for (final c in port.toutes('comptes')) {
      if (c['statut'] != 'archive') comptes['${c['num']}'] = c;
    }
    return {'refs': refs, 'ids': ids, 'comptes': comptes, 'jour': port.jour, 'exercices': port.toutes('exercices')};
  },
  cle: (v) => [if (v['reference'] != null) 'ref:${_n(v['reference'])}', _cleBien(v)],
  existe: (v, ctx) {
    final a = v['reference'] != null ? (ctx['refs'] as Map)[_n(v['reference'])] as _V? : null, b = (ctx['ids'] as Map)[_cleBien(v)] as _V?;
    if (a != null) return 'le bien « ${a['reference']} » existe déjà (${a['designation']})';
    return b != null ? 'un bien identique existe déjà (${b['reference']})' : null;
  },
  regles: (v, ctx, sc, n) {
    final pb = <ProblemeImport>[];
    final d = '${v['dateAcquisition']}';
    if (d.compareTo(ctx['jour'] as String) > 0) {
      pb.add(_refus('Date d’acquisition', d, 'DATE_FUTURE', 'la date d’acquisition est dans le futur', 'Saisissez la date réelle d’acquisition (un bien ne s’amortit pas avant d’exister).'));
    } else {
      // L'exercice de la date : un bien ancien est précisément ce qu'on REPREND. L'import n'écrit aucune écriture (l'amortissement se calcule à la lecture) : la garde d'exercice clos
      // ne refuse donc pas, elle DIT que le bien entre aux états calculés de cet exercice et pas à la liasse déposée.
      final etat = cpcEtatExercice(ctx['exercices'] as List<Map<String, Object?>>, int.parse(d.substring(0, 4)));
      if (etat != 'ouvert') {
        pb.add(_avert('Date d’acquisition', d, 'EXERCICE_NON_OUVERT', 'l’exercice ${d.substring(0, 4)} est ${etat == 'clos' ? 'clos' : 'en clôture'} : le bien entre au registre et aux états calculés, pas à la liasse déjà déposée',
            'Vérifiez la date ; aucune écriture n’est posée sur cet exercice.'));
      }
    }
    if (v['etat'] == 'Cédé') {
      pb.add(_refus('État', v['etat'], 'BIEN_CEDE', 'un bien déjà cédé ne s’importe pas : il sort du patrimoine par la déclaration de cession à l’écran', 'Retirez la ligne.'));
    }
    final compte = '${v['compte']}';
    if ((ctx['comptes'] as Map)[compte] == null) {
      pb.add(_refus('Compte d’immobilisation', compte, 'COMPTE_INCONNU', 'le compte $compte n’existe pas au plan comptable', 'Importez-le d’abord (jeu « Importation du plan comptable ») ou corrigez le numéro.'));
    } else if (!_compteImmobilisation.hasMatch(compte)) {
      pb.add(_refus('Compte d’immobilisation', compte, 'COMPTE_NON_IMMOBILISATION', 'le compte $compte n’est pas un compte d’immobilisation (classes 21 à 27)', 'Choisissez un compte d’immobilisation.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    // Les numéros EXPLICITES d'abord : un numéro automatique ne prend jamais un numéro que le fichier porte plus bas.
    final ordre = [...lignes.where((l) => l.v['reference'] != null), ...lignes.where((l) => l.v['reference'] == null)];
    for (final l in ordre) {
      final v = l.v;
      ecrireFiche('immobilisations', {
        'reference': v['reference'] ?? cpbReferenceSuivante('IM-', 3, port.toutes('immobilisations')),
        'designation': v['designation'],
        'categorie': v['categorie'],
        'dateAcquisition': v['dateAcquisition'],
        'valeurAcquisition': v['valeur'],
        'dureeAmortissement': v['duree'],
        'compte': '${v['compte']}',
        'fournisseur': v['fournisseur'] ?? '',
        'etat': v['etat'] ?? 'En service',
        'dateCession': '',
        'valeurCession': null,
        'motifSortie': '',
      });
    }
  },
  dependances: (lot, port) {
    final b = [for (final id in _ecritsDe(lot, 'immobilisations')) port.parId('immobilisations', id)]
        .where((x) => x != null && (('${x['dateCession'] ?? ''}').isNotEmpty || x['etat'] == 'Cédé'))
        .firstOrNull;
    return b == null
        ? null
        : DependanceImport('BIEN_CEDE_DEPUIS', 'le bien ${b['reference']} a été cédé ou sorti du patrimoine depuis l’import', 'Un bien sorti se traite à l’écran « Immobilisations & amortissements » : sa fiche reste au registre.');
  },
);

// --- 23. BUDGETS (RESTREINT, exercice OUVERT seulement) -----------------------------------------------------------------------------

String _cleBudget(_V v) => '${v['exercice']}|${v['centre']}|${_n(v['nature'])}';

final JeuImport jeuBudgets = JeuImport(
  id: 'budgets',
  restreint: true,
  octetsMaxDefaut: octetsMaxImportCourt,
  ecran: 'imp-budgets',
  libelle: 'Importation des budgets',
  module: 'M12',
  statut: 'supporte',
  description: 'Budget prévisionnel par exercice, centre de coûts et nature budgétaire.',
  source: 'Écran « Budgets » : un budget par exercice, centre et nature ; le réalisé se lit des écritures.',
  limite:
      'Seul un exercice OUVERT reçoit un budget : un exercice en clôture ou clos est refusé en le nommant (la garde des clos est au magasin, l’écran la subit comme le fichier). Le réalisé n’est jamais importé : il se lit des écritures. Le numéro BG-AAAA-NNN est attribué par le logiciel.',
  cibles: const ['budgets'],
  fichierModele: 'modele-import-budgets',
  gesteExiste: 'Retirez la ligne : un budget tenu se modifie à l’écran « Budgets » ; son numéro n’est jamais réécrit.',
  colonnesRetirees: const [
    ColonneRetiree('Réalisé', 'le réalisé n’est jamais importé : il se lit des écritures de l’exercice'),
    ColonneRetiree('Disponible', 'le disponible se calcule (prévu moins réalisé), jamais importé'),
  ],
  colonnes: [
    _oblig('exercice', 'Exercice', 'entier', min: 2000, max: 2100, exemple: 2027, aide: 'L’année de l’exercice, qui doit être ouvert.'),
    _oblig('centre', 'Centre de coûts', 'liste',
        liste: (ctx) => [for (final c in (ctx['centresListe'] as List<ValeurListe>)) c], exemple: 'Laboratoire', aide: 'Le code ou l’intitulé d’un centre connu : importez-le d’abord au besoin.'),
    _oblig('nature', 'Nature budgétaire', 'liste', liste: _fixe(cpbNaturesBudget), exemple: 'Charges de fonctionnement'),
    _oblig('prevu', 'Montant prévisionnel (FCFA)', 'entier', min: 0, exemple: 5000000, aide: 'Montant entier, zéro ou plus. Un tiret n’est pas un zéro : il est refusé.'),
  ],
  contexte: (port) {
    final centres = <ValeurListe>[], lib = <String, String>{}, b = <String, _V>{};
    for (final c in port.toutes('centresCouts')) {
      if (c['statut'] == 'archive') continue;
      centres.add(ValeurListe('${c['code']}', '${c['libelle']}'));
      lib['${c['code']}'] = '${c['libelle']}';
    }
    for (final x in port.toutes('budgets')) {
      if (x['statut'] != 'archive') b['${x['exercice']}|${x['centreCout']}|${_n(x['nature'])}'] = x;
    }
    return {'centresListe': centres, 'libelles': lib, 'budgets': b, 'exercices': port.toutes('exercices')};
  },
  cle: (v) => [_cleBudget(v)],
  existe: (v, ctx) {
    final x = (ctx['budgets'] as Map)[_cleBudget(v)] as _V?;
    return x != null ? 'le budget ${x['reference']} existe déjà pour cet exercice, ce centre et cette nature' : null;
  },
  regles: (v, ctx, sc, n) {
    final a = (v['exercice'] as num).toInt();
    final e = cpcEtatExercice(ctx['exercices'] as List<Map<String, Object?>>, a);
    if (e == 'clos') {
      return [_refus('Exercice', a, 'EXERCICE_CLOS', 'l’exercice $a est clos : lecture seule', 'Seul un exercice ouvert reçoit un budget : rouvrez l’exercice (comptable, motif obligatoire) ou datez le budget de l’exercice ouvert.')];
    }
    if (e != 'ouvert') {
      return [_refus('Exercice', a, 'EXERCICE_EN_CLOTURE', 'l’exercice $a est en clôture : les modules n’y écrivent plus', 'Terminez ou reprenez la clôture, ou datez le budget de l’exercice ouvert.')];
    }
    return const [];
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      final exercice = (v['exercice'] as num).toInt();
      ecrireFiche('budgets', {
        'reference': cpbReferenceSuivante('BG-$exercice-', 3, port.toutes('budgets')),
        'exercice': exercice,
        'centreCout': v['centre'],
        'centre': (ctx['libelles'] as Map)['${v['centre']}'] ?? v['centre'],
        'nature': v['nature'],
        'prevu': v['prevu'],
      });
    }
  },
  dependances: (lot, port) {
    final exercices = port.toutes('exercices');
    final b = [for (final id in _ecritsDe(lot, 'budgets')) port.parId('budgets', id)].where((x) => x != null && cpcEtatExercice(exercices, int.tryParse('${x['exercice']}') ?? 0) == 'clos').firstOrNull;
    return b == null
        ? null
        : DependanceImport('EXERCICE_CLOS', 'l’exercice ${b['exercice']} a été clos depuis l’import : le budget ${b['reference']} est en lecture seule', 'Rouvrez l’exercice (comptable, motif obligatoire) pour corriger.');
  },
);
