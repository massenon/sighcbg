/// LES SIX JEUX DU 11/11/2026 (décisions de la Direction) : référentiel produits, stock détail initial, transferts gros → détail, comptage d'inventaire,
/// emplacements, courriers. Ils prolongent les dix jeux de la maquette sans les modifier : même moteur, mêmes refus nommés.
///
/// Trois principes qui gouvernent ces jeux :
///  * un import qui TOUCHE un stock existant (stock détail initial, transfert) ne s'annule pas par son lot : il a déplacé des quantités que d'autres
///    gestes ont pu suivre ; la correction passe par un mouvement ou un inventaire (RG-03), pas par l'effacement d'une trace ;
///  * le COMPTAGE d'inventaire s'écrit à part (`comptagesInventaire`) : il n'est qu'une SAISIE de ce qui a été compté. La régularisation du stock reste un
///    geste humain posé à la feuille d'inventaire, jamais automatique ;
///  * « ignorer les existants » n'est offert que là où l'existant est une référence qu'on enrichit (produits, fournisseurs, emplacements, courriers).
part of 'jeux_import.dart';

List<ValeurListe> Function(dynamic) _categoriesProduit() => (_) => [for (final c in importCategoriesProduit) ValeurListe(c[0], c[1])];

/// Le dernier contrôle d'une dépendance commune : un produit écrit par le lot a-t-il déjà un mouvement autre que ceux du lot ?
DependanceImport? _mouvementPosterieur(FicheImport lot, PortImport port) {
  final ecrits = (lot['ecrits'] as List).cast<Map>();
  final ids = {for (final e in ecrits) if (e['collection'] == 'produits') e['id']};
  final propres = {for (final e in ecrits) if (e['collection'] == 'mouvements') e['id']};
  final autre = port.actives('mouvements').where((m) => ids.contains(m['produitId']) && !propres.contains(m['id'])).firstOrNull;
  return autre == null
      ? null
      : DependanceImport('MOUVEMENT_POSTERIEUR', 'l’article « ${autre['produit']} » a déjà un mouvement de stock (${autre['reference']}, ${autre['typeLabel']})',
          'Annulez d’abord ce mouvement, ou régularisez le stock par un inventaire : le lot ne peut pas être retiré sous un stock vivant (RG-03).');
}

// --- 11. RÉFÉRENTIEL PRODUITS ------------------------------------------------------------------------------------------------------

final JeuImport jeuProduits = JeuImport(
  id: 'produits',
  ecran: 'imp-produits',
  libelle: 'Importation du référentiel produits',
  module: 'IMP',
  statut: 'supporte',
  description: 'Le référentiel des articles : code, désignation, famille, unité, prix d’achat et prix de vente. Aucune quantité : le stock s’importe à part (stock initial).',
  source: 'Catalogue des articles de la clinique ; le prix de vente suit RG-02 (le médicament se facture au prix d’achat, sans marge).',
  cibles: const ['produits'],
  ignorable: true,
  fichierModele: 'modele-import-produits',
  gesteExiste: 'Retirez la ligne, cochez « Ignorer les existants », ou corrigez la fiche à l’écran du référentiel. Un import ne modifie jamais un article déjà tenu.',
  colonnes: [
    _oblig('code', 'Code article', 'texte', longueurMax: 24, exemple: 'PARA500', aide: 'Un code désigne un seul article.'),
    _oblig('designation', 'Désignation', 'texte', longueurMax: 160, exemple: 'PARACETAMOL 500 MG CP B/100'),
    _oblig('categorie', 'Catégorie', 'liste', liste: _categoriesProduit(), exemple: 'Médicaments'),
    _col('unite', 'Unité', 'texte', longueurMax: 30, exemple: 'Boîte', aide: 'Vide : « Unité ».'),
    _col('prixAchat', 'Prix d’achat unitaire', 'entier', min: 0, exemple: 350, aide: 'En francs CFA. Vide : l’article est créé « à valoriser » et le dit (aucun prix n’est inventé).'),
    _col('prixVente', 'Prix de vente unitaire', 'entier',
        min: 0, exemple: 350, aide: 'En francs CFA. Vide : égal au prix d’achat. RG-02 : un médicament ne se vend pas au-dessus de son prix d’achat sans validation de la Direction.'),
    _col('seuil', 'Seuil d’alerte', 'entier', min: 0, exemple: 20, aide: 'Vide : proposé à 5, marqué « à valider ».'),
    _col('emplacement', 'Emplacement', 'texte', longueurMax: 60, exemple: 'Rayon A, Casier 3'),
    _col('fournisseur', 'Code fournisseur', 'texte', longueurMax: 24, exemple: 'SOBAPS', aide: 'Code d’un fournisseur connu. Un code inconnu est signalé, jamais refusé.'),
  ],
  contexte: (port) => {
    'produits': {for (final x in port.toutes('produits')) _n(x['code']): x},
    'fournisseurs': {for (final x in port.actives('fournisseurs')) _n(x['code']): true},
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) {
    final p = (ctx['produits'] as Map)[_n(v['code'])] as _V?;
    return p != null ? 'l’article « ${p['code']} » existe déjà dans le référentiel (${p['designation']})' : null;
  },
  regles: (v, ctx, sc, n) {
    final pb = <ProblemeImport>[];
    final achat = v['prixAchat'] as num?, vente = v['prixVente'] as num?;
    if (v['categorie'] == 'medicament' && achat != null && vente != null && vente > achat) {
      pb.add(_p('Prix de vente unitaire', vente, 'RG02_MARGE', importRefus, 'prix de vente ${vente} supérieur au prix d’achat $achat : un médicament se facture au prix d’achat, sans marge (RG-02)',
          'Alignez le prix de vente sur le prix d’achat, ou obtenez la validation tracée de la Direction avant l’import.'));
    }
    if (achat == null) {
      pb.add(_p('Prix d’achat unitaire', '', 'A_VALORISER', importAvertissement, 'prix d’achat absent : l’article sera créé « à valoriser »', 'Valorisez-le ensuite avec sa source ; aucun prix n’est inventé.'));
    }
    final f = v['fournisseur'];
    if (f != null && (ctx['fournisseurs'] as Map)[_n(f)] == null) {
      pb.add(_p('Code fournisseur', f, 'FOURNISSEUR_INCONNU', importAvertissement, 'aucun fournisseur « $f » au référentiel', 'Créez le fournisseur (jeu Fournisseurs) ou corrigez le code.'));
    }
    final ref = (sc['articles'] as Map<String, _V>)[_n(v['code'])];
    if (ref != null && (ref['designation'] != v['designation'])) {
      pb.add(_p('Désignation', v['designation'], 'ARTICLE_INCOHERENT', importRefus, 'le code « ${v['code']} » porte une autre désignation que la ligne ${ref['n']}', 'Un code désigne un seul article.'));
    } else {
      (sc['articles'] as Map<String, _V>)[_n(v['code'])] = {'n': n, 'designation': v['designation']};
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      final prix = v['prixAchat'] as num?;
      final vente = (v['prixVente'] as num?) ?? prix ?? 0;
      ecrireFiche('produits', {
        'code': v['code'],
        'designation': v['designation'],
        'unite': v['unite'] ?? 'Unité',
        'categorie': v['categorie'],
        'prixAchat': prix ?? 0,
        'prixVente': vente,
        'cump': prix ?? 0,
        'seuilAlerte': v['seuil'] ?? 5,
        'seuilAValider': v['seuil'] == null,
        'stockGros': 0,
        'stockDetail': 0,
        'stock': 0,
        'emplacement': v['emplacement'] ?? '',
        'fournisseur': v['fournisseur'] ?? '',
        'valoriseSage': false,
        if (prix == null || prix == 0) ...{'valorisationProvisoire': true, 'sourceValorisation': 'Prix d’achat absent du fichier d’import ${lot['reference']} : à valoriser'},
      });
    }
  },
  dependances: _mouvementPosterieur,
);

// --- 12. STOCK DÉTAIL INITIAL ------------------------------------------------------------------------------------------------------

final JeuImport jeuStockDetail = JeuImport(
  id: 'stock-detail',
  ecran: 'imp-stock-detail',
  libelle: 'Importation du stock détail initial',
  module: 'IMP',
  statut: 'supporte',
  description: 'La situation de départ de la pharmacie (stock détail), article par article. Légitime UNE seule fois par article, tant qu’aucun mouvement n’existe au stock détail.',
  source: 'Comptage de départ de la pharmacie d’urgence ; ensuite, le stock détail ne bouge que par transfert, délivrance, perte ou inventaire.',
  cibles: const ['mouvements'],
  fichierModele: 'modele-import-stock-detail',
  gesteExiste: 'Retirez la ligne.',
  colonnes: [
    _oblig('code', 'Code article', 'texte', longueurMax: 24, exemple: 'PARA500', aide: 'Code d’un article du référentiel produits.'),
    _oblig('quantite', 'Quantité', 'entier',
        min: 0,
        exemple: 40,
        aide: 'Quantité de départ au stock détail. Jamais négative (RG-03).',
        sousMin: const SousMinImport('RG03_STOCK_NEGATIF', 'quantité négative : le stock ne peut jamais être négatif (RG-03)', 'Saisissez la quantité réellement comptée, zéro ou plus.')),
  ],
  contexte: (port) => {
    'produits': {for (final x in port.actives('produits')) _n(x['code']): x},
    'mouvements': port.actives('mouvements'),
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final p = (ctx['produits'] as Map)[_n(v['code'])] as _V?;
    if (p == null) {
      return [_p('Code article', v['code'], 'PRODUIT_INCONNU', importRefus, 'aucun article « ${v['code']} » au référentiel produits', 'Importez d’abord le référentiel produits, ou corrigez le code.')];
    }
    final mvt = (ctx['mouvements'] as List).cast<_V>().where((m) => m['produitId'] == p['id'] && m['stockType'] == 'detail').firstOrNull;
    if (mvt != null) {
      return [
        _p('Code article', v['code'], 'STOCK_DETAIL_DEJA_ALIMENTE', importRefus,
            'l’article « ${p['designation']} » a déjà un mouvement au stock détail (${mvt['reference']}, ${mvt['typeLabel']}) : le stock initial ne s’importe qu’une fois, tant qu’aucun mouvement n’existe',
            'Retirez la ligne. Pour corriger le stock détail, passez un mouvement ou un inventaire : jamais un second stock initial.')
      ];
    }
    if (_num(p['stockDetail']) != 0) {
      return [
        _p('Code article', v['code'], 'STOCK_DETAIL_NON_NUL', importRefus, 'l’article « ${p['designation']} » porte déjà ${_num(p['stockDetail'])} au stock détail',
            'Retirez la ligne : le stock détail n’est pas vide, le régulariser relève d’un inventaire.')
      ];
    }
    return const [];
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    final jour = port.jour;
    final mouvs = <_V>[...port.toutes('mouvements')];
    for (final l in lignes) {
      final p = (ctx['produits'] as Map)[_n(l.v['code'])] as _V;
      final q = _num(l.v['quantite']);
      final ref = _referenceMouvement(mouvs);
      mouvs.add({'reference': ref});
      ecrireFiche('mouvements', {
        'reference': ref,
        'date': jour,
        'produitId': p['id'],
        'produit': p['designation'],
        'type': 'entree',
        'typeLabel': 'Entrée',
        'quantite': q,
        'stockType': 'detail',
        'justificatif': 'Import ${lot['reference']} (stock détail initial)',
        'utilisateur': port.utilisateur,
      });
      port.mettreAJour('produits', p['id'], {'stockDetail': q, 'stock': _num(p['stockGros']) + q});
    }
  },
  // Le lot a posé du stock au détail : il ne s'efface pas, il se corrige par un mouvement ou un inventaire.
  dependances: (lot, port) => const DependanceImport('STOCK_POSE', 'ce lot a posé le stock détail initial des articles : d’autres gestes ont pu s’appuyer dessus',
      'Corrigez le stock détail par un mouvement de stock ou un inventaire (RG-03), jamais en effaçant le stock initial.'),
);

// --- 13. TRANSFERTS GROS → DÉTAIL --------------------------------------------------------------------------------------------------

final JeuImport jeuTransferts = JeuImport(
  id: 'transferts',
  ecran: 'imp-transferts',
  libelle: 'Importation d’un transfert gros → détail',
  module: 'IMP',
  statut: 'supporte',
  description: 'Un bon de transfert du magasin vers la pharmacie, article par article. RG-03 est contrôlé ligne par ligne (le stock du magasin ne devient jamais négatif) ; un seul justificatif pour tout le fichier.',
  source: 'Bon papier du magasinier : une ligne par article transféré.',
  cibles: const ['transferts', 'mouvements'],
  fichierModele: 'modele-import-transferts',
  gesteExiste: 'Retirez la ligne.',
  colonnes: [
    _oblig('code', 'Code article', 'texte', longueurMax: 24, exemple: 'PARA500', aide: 'Code d’un article du référentiel produits.'),
    _oblig('quantite', 'Quantité', 'entier',
        min: 1,
        exemple: 20,
        aide: 'Quantité transférée du magasin (stock gros) vers la pharmacie (stock détail). Au moins 1.',
        sousMin: const SousMinImport('RG03_STOCK_NEGATIF', 'quantité nulle ou négative : un transfert déplace au moins une unité (RG-03)', 'Saisissez une quantité d’au moins 1.')),
    _oblig('justificatif', 'Justificatif', 'texte', longueurMax: 120, exemple: 'Bon de besoin pharmacie n° 12', aide: 'La pièce qui motive le transfert : la MÊME valeur sur toutes les lignes (un fichier = un bon).'),
  ],
  contexte: (port) => {
    'produits': {for (final x in port.actives('produits')) _n(x['code']): x},
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final p = (ctx['produits'] as Map)[_n(v['code'])] as _V?;
    if (p == null) {
      return [_p('Code article', v['code'], 'PRODUIT_INCONNU', importRefus, 'aucun article « ${v['code']} » au référentiel produits', 'Importez d’abord le référentiel produits, ou corrigez le code.')];
    }
    // RG-03 ligne par ligne : le stock du magasin ne couvre pas la quantité. Le refus NOMME l'article.
    final dispo = _num(p['stockGros']);
    final q = _num(v['quantite']);
    if (q > dispo) {
      return [
        _p('Quantité', q, 'RG03_STOCK_INSUFFISANT', importRefus, 'RG-03 — « ${p['designation']} » : ${dispo.toInt()} ${p['unite'] ?? ''} disponible(s) au magasin, $q demandé(s)',
            'Réduisez la quantité à ${dispo.toInt()} au plus : le stock du magasin ne peut jamais devenir négatif.')
      ];
    }
    return const [];
  },
  reglesLot: (lignes, ctx) {
    final justifs = <String>{for (final l in lignes) _n(l.v['justificatif'])};
    if (justifs.length > 1) {
      return [
        _p('Justificatif', '', 'JUSTIFICATIF_UNIQUE', importRefus, 'le fichier porte ${justifs.length} justificatifs différents : un fichier est UN bon de transfert, donc un seul justificatif',
            'Alignez la colonne « Justificatif » sur une seule valeur, ou scindez le fichier en un bon par justificatif.')
      ];
    }
    return const [];
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    final produits = [for (final x in port.actives('produits')) x];
    final bons = port.toutes('transferts');
    final justificatif = '${lignes.first.v['justificatif']}';
    final bonLignes = <_V>[];
    for (final l in lignes) {
      final p = (ctx['produits'] as Map)[_n(l.v['code'])] as _V;
      bonLignes.add({
        'produitId': p['id'],
        'code': p['code'],
        'produit': p['designation'],
        'categorie': p['categorie'],
        'unite': p['unite'],
        'cump': p['cump'],
        'quantite': l.v['quantite'],
      });
    }
    // Dernier contrôle RG-03 avant écriture (le stock a pu bouger entre l'analyse et la confirmation : l'engine rejoue l'analyse, ici on le redit).
    controlerBonAvantEcriture(bonLignes, produits);
    final emis = emettreTransfert(
        date: port.jour,
        demandeur: port.utilisateur,
        motif: 'Import ${lot['reference']} : $justificatif',
        lignes: bonLignes,
        produits: produits,
        bons: bons,
        utilisateur: port.utilisateur);
    ecrireFiche('transferts', {...emis.bon, 'justificatifImport': justificatif});
    for (final m in emis.mouvements) {
      ecrireFiche('mouvements', {...m, 'justificatif': '${m['justificatif']} — $justificatif'});
    }
    for (final x in emis.produits) {
      final p = produits.firstWhere((e) => '${e['id']}' == x.id);
      port.mettreAJour('produits', p['id'], {...x.patch, 'stock': _num(x.patch['stockGros']) + _num(x.patch['stockDetail'])});
    }
  },
  dependances: (lot, port) => const DependanceImport('TRANSFERT_EMIS', 'ce lot a émis un bon de transfert qui a déjà déplacé le stock du magasin vers la pharmacie',
      'Corrigez par un transfert inverse ou un inventaire : deux mouvements symétriques ont été écrits, les effacer laisserait les deux stocks faux (RG-03).'),
);

// --- 14. COMPTAGE D'INVENTAIRE -----------------------------------------------------------------------------------------------------

final JeuImport jeuInventaire = JeuImport(
  id: 'inventaire',
  ecran: 'imp-inventaire',
  libelle: 'Importation d’un comptage d’inventaire',
  module: 'IMP',
  statut: 'supporte',
  description: 'La feuille de comptage (jusqu’à 200 articles) : la quantité comptée par article pour UN magasin. Le comptage est une saisie ; la régularisation du stock reste un geste humain, à la feuille d’inventaire.',
  source: 'Feuille de comptage papier du magasinier ou de la pharmacie.',
  cibles: const ['comptagesInventaire'],
  fichierModele: 'modele-import-inventaire',
  gesteExiste: 'Retirez la ligne.',
  colonnes: [
    _oblig('magasin', 'Magasin', 'liste', liste: _fixe(['gros', 'detail']), exemple: 'gros', aide: 'gros = magasin central, detail = pharmacie. Un fichier compte UN seul magasin.'),
    _oblig('code', 'Code article', 'texte', longueurMax: 24, exemple: 'PARA500', aide: 'Code d’un article du référentiel produits.'),
    _oblig('physique', 'Quantité comptée', 'entier', min: 0, exemple: 118, aide: 'Ce que vous avez compté sur le rayon. Jamais négatif.'),
    _col('date', 'Date du comptage', 'date', exemple: '2026-11-10', aide: 'Vide : date du jour.'),
  ],
  contexte: (port) => {
    'produits': {for (final x in port.actives('produits')) _n(x['code']): x},
    'jour': port.jour,
  },
  cle: (v) => ['${_n(v['magasin'])}|${_n(v['code'])}'],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final p = (ctx['produits'] as Map)[_n(v['code'])] as _V?;
    final pb = <ProblemeImport>[];
    if (p == null) {
      pb.add(_p('Code article', v['code'], 'PRODUIT_INCONNU', importRefus, 'aucun article « ${v['code']} » au référentiel produits', 'Importez d’abord le référentiel produits, ou corrigez le code.'));
    }
    final d = v['date'] as String?;
    if (d != null && d.compareTo(ctx['jour'] as String) > 0) {
      pb.add(_p('Date du comptage', d, 'DATE_FUTURE', importRefus, 'la date du comptage est dans le futur', 'Saisissez la date réelle du comptage, ou laissez la colonne vide.'));
    }
    return pb;
  },
  reglesLot: (lignes, ctx) {
    final mag = <Object?>{for (final l in lignes) l.v['magasin']};
    if (mag.length > 1) {
      return [
        _p('Magasin', '', 'MAGASIN_UNIQUE', importRefus, 'le fichier compte ${mag.length} magasins : une feuille d’inventaire porte sur UN magasin nommé',
            'Scindez le fichier : un comptage par magasin, jamais le total des deux (la régularisation ne concerne que le magasin compté).')
      ];
    }
    return const [];
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final p = (ctx['produits'] as Map)[_n(l.v['code'])] as _V;
      final mag = '${l.v['magasin']}';
      ecrireFiche('comptagesInventaire', {
        'lot': lot['reference'],
        'magasin': mag,
        'produitId': p['id'],
        'code': p['code'],
        'designation': p['designation'],
        'physique': l.v['physique'],
        'theoriqueAuComptage': _num(mag == 'detail' ? p['stockDetail'] : p['stockGros']),
        'dateComptage': l.v['date'] ?? port.jour,
        'regularise': false,
      });
    }
  },
  dependances: (lot, port) {
    final ids = {for (final e in (lot['ecrits'] as List).cast<Map>()) e['id']};
    final r = port.actives('comptagesInventaire').where((c) => ids.contains(c['id']) && c['regularise'] == true).firstOrNull;
    return r == null ? null : DependanceImport('COMPTAGE_REGULARISE', 'le comptage de « ${r['designation']} » a déjà servi à une régularisation', 'Un comptage régularisé reste la trace de l’inventaire : il ne s’annule pas.');
  },
);

// --- 15. EMPLACEMENTS --------------------------------------------------------------------------------------------------------------

final JeuImport jeuEmplacements = JeuImport(
  id: 'emplacements',
  ecran: 'imp-emplacements',
  libelle: 'Importation des emplacements',
  module: 'IMP',
  statut: 'supporte',
  description: 'Les casiers du plan des rayons : code court et stable (celui de l’étiquette), intitulé, zone, conservation, capacité.',
  source: 'Plan des rayons du magasin et de la pharmacie.',
  cibles: const ['emplacements'],
  ignorable: true,
  fichierModele: 'modele-import-emplacements',
  gesteExiste: 'Retirez la ligne, cochez « Ignorer les existants », ou corrigez le casier à l’écran Étiquetage & emplacements.',
  colonnes: [
    _oblig('code', 'Code du casier', 'texte', longueurMax: 30, exemple: 'A2', aide: 'Court et stable : c’est lui qui figure sur l’étiquette.'),
    _oblig('libelle', 'Intitulé', 'texte', longueurMax: 100, exemple: 'Rayon A, casier 2'),
    _oblig('zone', 'Zone', 'liste', liste: _fixe(zonesEmplacement), exemple: 'Rayonnage sec'),
    _col('temperature', 'Température de conservation', 'liste', liste: _fixe(temperaturesConservation), exemple: 'Ambiante'),
    _col('capacite', 'Capacité (références)', 'entier', min: 0, exemple: 30),
  ],
  contexte: (port) => {'emplacements': {for (final x in port.toutes('emplacements')) _n(x['code']): x}},
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) {
    final e = (ctx['emplacements'] as Map)[_n(v['code'])] as _V?;
    return e != null ? 'le casier « ${e['code']} » existe déjà (${e['libelle']})' : null;
  },
  regles: _aucun,
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    for (final l in lignes) {
      final v = l.v;
      ecrireFiche('emplacements', {
        'code': v['code'],
        'libelle': v['libelle'],
        'zone': v['zone'],
        'temperature': v['temperature'] ?? 'Ambiante',
        'capacite': v['capacite'] ?? 0,
      });
    }
  },
  dependances: (lot, port) {
    final codes = <Object?>{};
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      final a = port.parId('${e['collection']}', e['id']);
      if (a != null) codes.add(a['code']);
    }
    final u = port.actives('produits').where((p) => codes.contains(p['emplacement'])).firstOrNull;
    return u == null ? null : DependanceImport('CASIER_UTILISE', 'l’article « ${u['designation']} » est rangé dans le casier « ${u['emplacement']} »', 'Déplacez l’article avant d’annuler le lot.');
  },
);

// --- 16. COURRIERS -----------------------------------------------------------------------------------------------------------------

String _cleCourrier(_V v) => '${_n(v['sens'])}|${v['date']}|${_n(v['correspondant'])}|${_n(v['objet'])}';

final JeuImport jeuCourriers = JeuImport(
  id: 'courriers',
  ecran: 'imp-courriers',
  libelle: 'Importation du registre des courriers',
  module: 'IMP',
  statut: 'supporte',
  description: 'Le registre du courrier départ et arrivée : sens, date, correspondant, objet, nature, service destinataire. Le numéro d’ordre est attribué par le logiciel (série annuelle).',
  source: 'Registre papier du courrier administratif.',
  cibles: const ['courriers'],
  ignorable: true,
  fichierModele: 'modele-import-courriers',
  gesteExiste: 'Retirez la ligne ou cochez « Ignorer les existants » : un courrier déjà enregistré ne se saisit pas deux fois.',
  colonnes: [
    _oblig('sens', 'Sens', 'liste', liste: (_) => const [ValeurListe('arrivee', 'Arrivée'), ValeurListe('depart', 'Départ')], exemple: 'Arrivée'),
    _oblig('date', 'Date', 'date', exemple: '2026-11-03'),
    _oblig('correspondant', 'Correspondant', 'texte', longueurMax: 120, exemple: 'Direction départementale de la santé'),
    _oblig('objet', 'Objet', 'texte', longueurMax: 200, exemple: 'Convocation à la réunion trimestrielle'),
    _col('nature', 'Nature', 'liste', liste: _fixe(admNaturesCourrier), exemple: 'Lettre', aide: 'Vide : « Lettre ».'),
    _oblig('affecteA', 'Service destinataire', 'liste', liste: _fixe(admServicesCourrier), exemple: 'Direction Administrative'),
    _col('traitement', 'État du traitement', 'liste',
        liste: (_) => [for (final e in admTraitementsCourrier.entries) ValeurListe(e.key, e.value.$1)], exemple: 'En attente', aide: 'Vide : « En attente ».'),
  ],
  contexte: (port) => {'cles': <String, _V>{for (final c in port.toutes('courriers')) _cleCourrier({...c, 'sens': c['sens']}): c}},
  cle: (v) => [_cleCourrier(v)],
  existe: (v, ctx) {
    final c = (ctx['cles'] as Map)[_cleCourrier(v)] as _V?;
    return c != null ? 'le courrier ${c['reference']} (${c['objet']}) est déjà enregistré' : null;
  },
  regles: (v, ctx, sc, n) {
    final d = v['date'] as String?;
    if (d != null && d.length >= 4 && int.parse(d.substring(0, 4)) < 2000) {
      return [_p('Date', d, 'DATE_INVRAISEMBLABLE', importAvertissement, 'date antérieure à 2000', 'Vérifiez l’année saisie.')];
    }
    return const [];
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    final posees = <_V>[...port.toutes('courriers')];
    for (final l in lignes) {
      final v = l.v;
      final ref = admReferenceCourrier(v['sens'], v['date'], posees);
      posees.add({'reference': ref});
      ecrireFiche('courriers', {
        'reference': ref,
        'sens': v['sens'],
        'date': v['date'],
        'correspondant': v['correspondant'],
        'objet': v['objet'],
        'nature': v['nature'] ?? 'Lettre',
        'affecteA': v['affecteA'],
        'traitement': v['traitement'] ?? 'en_attente',
        'accuseReception': false,
        'numerise': false,
      });
    }
  },
  dependances: (lot, port) => null,
);
