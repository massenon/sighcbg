/// LE JEU « PRIX D'ACHAT DES PRODUITS » (`tarifs-produits`) : l'import du prix d'achat des articles par PROPOSITION, jamais par réécriture. Même fabrique que « Tarifs et prix », même chemin que
/// l'écran « Changer le prix d'achat » : chaque ligne passe par `tarProposerProduit` (famille PRODUIT : RG-02, contrôle d'usage, une proposition ouverte par article, date passée refusée, provenance
/// `import`), jamais par un second contrôle. Le prix en vigueur ne bouge jamais à l'import :
///   * Oui + geste de décider (matrice) : version VALIDÉE d'emblée, effective à sa date d'effet ;
///   * Oui sans ce geste, ou champ vide : PROPOSITION, soumise à la décision ;
///   * Non (motif obligatoire) : ligne NON appliquée, consignée avec son motif, AUCUNE version ;
///   * prix identique à celui en vigueur : « inchangée », comptée, jamais une version.
/// Les ERREURS refusent le fichier entier (tout ou rien) ; un tiret n'est pas un zéro, NC n'existe pas pour un prix d'achat, zéro est refusé, un article inconnu est refusé en le nommant.
///
/// RÉSERVÉ À LA MÈRE, comme « Tarifs et prix » : les versions de prix sont de la famille R (la mère seule écrit) ; un fileul propose à l'écran « Référentiel produits », la demande part à la mère.
/// Le droit d'importer est celui de l'écran du jeu (`imp-tarifs-produits`), accordé par la matrice (le gestionnaire de stock y a droit : décision de la Direction).
///
/// Le prix de VENTE n'est pas une colonne : il se DÉRIVE du prix d'achat d'un médicament (RG-02) ; un prix de vente propre hors médicament se règle à l'écran.
part of 'jeux_import.dart';

const String _ecranTarifsProduits = 'imp-tarifs-produits';

const Map<String, String> _colonneDuRefusProduit = {
  'MOTIF_REQUIS': 'Motif',
  'DATE_EFFET_REQUISE': 'Date d’effet',
  'DATE_PASSEE': 'Date d’effet',
  'DATE_PASSEE_RESERVEE': 'Date d’effet',
  'TARIF_DEJA_UTILISE': 'Date d’effet',
  'CHANGEMENT_EN_ATTENTE': 'Code article',
  'PRESTATION_INTROUVABLE': 'Code article',
  'PRODUIT_INTROUVABLE': 'Code article',
  'PRIX_ABSENT': 'Prix d’achat',
  'PRIX_ZERO': 'Prix d’achat',
  'PRIX_INVALIDE': 'Prix d’achat',
  'RG02_MARGE': 'Prix d’achat',
};

String _achatVente(num? achat) => achat == null ? 'absent' : nombre(achat);

class _CtxPrixProduits {
  _CtxPrixProduits(this.port)
      : peutDecider = port.profil.geste(gesteDeciderPrix),
        produits = {for (final x in port.actives('produits')) _n(x['code']): x};
  final PortImport port;
  final bool peutDecider;
  final Map<String, _V> produits;

  ReferentielTarifs get h => ReferentielTarifs(port.toutes(tarCollectionTarifs), port.toutes(tarCollectionVersions));

  /// Le droit est celui d'IMPORTER ce jeu (le moteur l'a contrôlé avant), jamais celui d'éditer « Tarifs et prix ».
  ContexteTarif cx(ReferentielTarifs ref) => ContexteTarif(
        referentiel: ref,
        aujourdhui: port.jour,
        role: port.profil.role,
        auteur: port.utilisateur,
        peutProposerProduit: port.profil.peutImporterEcran(_ecranTarifsProduits),
        peutDecider: peutDecider,
        peutDatePassee: false,
        produits: port.toutes('produits'),
        pieces: PiecesTarif(factures: port.toutes('factures'), demandesAnalyses: port.toutes('demandesAnalyses'), demandesImagerie: port.toutes('demandesImagerie')),
      );

  /// Un article que la prestation de prix ne porte pas encore reçoit sa version 1 de REPRISE avant la proposition (réparation de donnée, pas un geste de l'importateur) ; [ecrire] la pose au
  /// magasin, sinon le référentiel de la vérification la porte virtuellement.
  ReferentielTarifs avecReprise(_V produit, {EcrireFiche? ecrire}) {
    final h0 = h;
    if (h0.parCode['${produit['code']}'] != null) return h0;
    final m = tarMigrerProduits([produit], origine: 'reprise');
    if (m.tarifs.isEmpty) return h0;
    if (ecrire == null) return ReferentielTarifs([...h0.tarifs, ...m.tarifs], [...h0.versions, ...m.versions]);
    for (final t in m.tarifs) {
      ecrire(tarCollectionTarifs, {...t});
    }
    for (final v in m.versions) {
      ecrire(tarCollectionVersions, {...v});
    }
    return h;
  }
}

DemandeProduit _offreProduit(_V v, _V produit, String? lot, {required bool valider}) {
  final pa = v['prixAchat'] as Map;
  return DemandeProduit(
    code: '${produit['code']}',
    prixAchat: pa['etat'] == 'montant' ? pa['montant'] : null,
    dateEffet: '${v['dateEffet']}',
    motif: v['motif'] as String?,
    source: v['source'] as String?,
    valider: valider,
    importJeu: 'tarifs-produits',
    importLot: lot,
  );
}

/// Les contrôles de la proposition, puis l'écriture : Oui vaut « valider » seulement pour qui décide ; un refus de validation dégrade le Oui en proposition, jamais en erreur.
({ResultatTarif<PropositionTarif> resultat, bool valider}) _proposerLigneProduit(_CtxPrixProduits c, ReferentielTarifs h, _V v, _V produit, String? lot) {
  final cx = c.cx(h);
  final produits = c.port.toutes('produits');
  var valider = c.peutDecider && v['valider'] == 'oui';
  var r = tarProposerProduit(cx, _offreProduit(v, produit, lot, valider: valider), produits: produits);
  if (!r.ok && valider && (r.refus!.code == 'VALIDATION_RESERVEE' || r.refus!.code == 'CONFIGURATION_DE_LA_MERE')) {
    valider = false;
    r = tarProposerProduit(cx, _offreProduit(v, produit, lot, valider: false), produits: produits);
  }
  return (resultat: r, valider: valider);
}

final JeuImport jeuTarifsProduits = JeuImport(
  id: 'tarifs-produits',
  ecran: _ecranTarifsProduits,
  libelle: 'Importation des prix d’achat',
  module: 'IMP',
  statut: 'supporte',
  description:
      'Le prix d’achat des articles du référentiel produits, avec une date d’effet et la décision Oui ou Non : chaque ligne qui change un prix devient une proposition (version ajoutée), jamais une réécriture de la fiche. Le prix de vente d’un médicament suit son prix d’achat (RG-02).',
  source: 'Aucun tarif fournisseur n’a été remis : les prix du fichier font foi, aucun n’est complété ni inventé par le logiciel.',
  limite:
      'Un import de prix d’achat ne change jamais le prix en vigueur par lui-même : la ligne devient une proposition soumise à la décision (Oui ou Non), sauf si votre rôle détient le geste de décider et que la ligne dit Oui. Réservé au poste principal : un poste rattaché propose à l’écran « Référentiel produits ».',
  cibles: const [tarCollectionTarifs, tarCollectionVersions],
  fichierModele: 'modele-import-tarifs-produits',
  restreint: true,
  gesteExiste: 'Un article se change par une nouvelle version : donnez-lui une date d’effet, le prix en vigueur n’est jamais réécrit.',
  colonnes: [
    _oblig('code', 'Code article', 'texte', longueurMax: 24, exemple: 'PARA500', aide: 'Code d’un article du référentiel produits (un article inconnu est refusé : créez-le d’abord, jeu « Importation du référentiel produits »).'),
    _oblig('prixAchat', 'Prix d’achat', 'tarif', exemple: 350, aide: 'Montant entier strictement positif en FCFA. NC n’existe pas pour un prix d’achat ; un tiret n’est pas un zéro : une ligne sans prix est refusée.'),
    _oblig('dateEffet', 'Date d’effet', 'date', exemple: '2027-01-01', aide: 'Obligatoire : le prix en vigueur ne change qu’à cette date. Une date passée est refusée (elle se propose à l’écran, avec sa case et son motif).'),
    _col('valider', 'Valider (Oui/Non)', 'liste',
        liste: _fixe(['oui', 'non']), exemple: 'oui', aide: 'Oui : le prix s’applique (validé d’emblée si votre rôle décide, sinon il devient une proposition). Non : ligne non appliquée, motif obligatoire. Vide : à valider.'),
    _col('motif', 'Motif', 'texte', longueurMax: 160, exemple: 'Nouveau tarif fournisseur', aide: 'Obligatoire pour toute ligne qui change un prix et pour tout Non.'),
    _col('source', 'Source', 'texte', longueurMax: 160, exemple: 'Facture fournisseur du 01/12/2026'),
  ],
  contexte: (port) => _CtxPrixProduits(port),
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) => null,
  regles: (v, ctx0, sc, n) {
    final c = ctx0 as _CtxPrixProduits;
    final pb = <ProblemeImport>[];
    final produit = c.produits[_n(v['code'])];
    if (produit == null) {
      return [_p('Code article', v['code'], 'ARTICLE_INCONNU', importRefus, 'aucun article « ${v['code']} » au référentiel produits', 'Créez l’article (jeu « Importation du référentiel produits ») ou corrigez le code.')];
    }
    final h = c.avecReprise(produit);
    final p = h.parCode['${produit['code']}'];
    final na = v['prixAchat'] as Map;
    // Un NON est la décision de l'importateur : ni version, ni erreur. Son motif est obligatoire.
    if (v['valider'] == 'non') {
      if ('${v['motif'] ?? ''}'.isEmpty) {
        pb.add(_p('Motif', '', 'MOTIF_REQUIS', importRefus, 'une ligne « Non » se motive : sans motif, on ne sait pas pourquoi le prix d’achat n’est pas appliqué', 'Saisissez le motif de la ligne $n.'));
      } else {
        sc['sansEcritureLigne'] = 'non';
        pb.add(_p('Valider (Oui/Non)', 'Non', 'LIGNE_NON_APPLIQUEE', importAvertissement, 'ligne non appliquée sur décision de l’importateur (motif : ${v['motif']})', 'Rien à faire : aucune version n’est créée, le motif est consigné.'));
      }
      return pb;
    }
    if (na['etat'] == 'nc') {
      pb.add(_p('Prix d’achat', 'NC', 'NC_INTERDIT', importRefus, 'NC n’existe pas pour un prix d’achat (un article n’a pas de colonne assurée)', 'Saisissez le prix d’achat en francs.'));
    } else if (na['etat'] == 'manquant') {
      pb.add(_p('Prix d’achat', '-', 'PRIX_ABSENT', importRefus, 'un tiret n’est pas un zéro, et un prix d’achat absent n’est pas un prix : l’article ne se facturerait pas', 'Saisissez le prix d’achat, ou retirez la ligne.'));
    }
    if (pb.any((x) => x.estRefus)) return pb;
    // LE MÊME CHEMIN QUE L'ÉCRAN : tous les contrôles de la proposition, sans rien écrire.
    final e = _proposerLigneProduit(c, h, v, produit, null);
    final r = e.resultat;
    if (!r.ok && r.refus!.code == 'PRIX_INCHANGE') {
      sc['sansEcritureLigne'] = 'inchange';
      pb.add(_p('Prix d’achat', '', 'PRIX_INCHANGE', importAvertissement, 'ce prix d’achat est déjà celui en vigueur à cette date : aucune version, la ligne est comptée', 'Rien à faire.'));
      return pb;
    }
    if (!r.ok) {
      pb.add(_p(_colonneDuRefusProduit[r.refus!.code] ?? 'Prix d’achat', '', r.refus!.code, importRefus, r.refus!.motif, r.refus!.geste));
      return pb;
    }
    if (!e.valider && v['valider'] == 'oui') {
      pb.add(_p('Valider (Oui/Non)', 'Oui', 'OUI_VAUT_PROPOSITION', importAvertissement,
          'votre rôle ne détient pas le geste de décider un prix : le Oui vaut proposition, la décision revient aux rôles que la matrice désigne', 'Rien à faire : la proposition attend la décision.'));
    }
    final s = p == null ? null : h.instantane(p, '${v['dateEffet']}');
    if (s != null && s.na != null && na['etat'] == 'montant') {
      pb.add(_p('Prix d’achat', _achatVente(na['montant'] as num?), 'VARIATION', importAvertissement,
          'en vigueur à cette date : ${_achatVente(s.na)} ; proposé : ${_achatVente(na['montant'] as num?)}', 'Vérifier la variation avant de confirmer.'));
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    final c = ctx as _CtxPrixProduits;
    for (final l in lignes) {
      final v = l.v;
      final produit = c.produits[_n(v['code'])]!;
      final h = c.avecReprise(produit, ecrire: ecrireFiche);
      final e = _proposerLigneProduit(c, h, v, produit, '${lot['reference']}');
      final r = e.resultat;
      if (!r.ok) throw StateError('ligne ${l.n} (${v['code']}) : ${r.refus!.motif}');
      final prop = r.valeur!;
      ecrireFiche(tarCollectionVersions, {...prop.version, 'import': {'jeu': 'tarifs-produits', 'lot': lot['reference']}});
      if (prop.valideeEnUnGeste) {
        for (final (id, patch) in tarLeverProvisoire(c.h, '${produit['code']}', qui: port.utilisateur, jour: port.jour)) {
          port.mettreAJour(tarCollectionVersions, id, patch);
        }
      }
    }
  },
  // Un lot de prix d'achat s'annule en RETIRANT ses propositions (RG-14, rien ne se supprime) ; une version déjà validée se remplace par une nouvelle version, elle ne s'efface pas.
  dependances: (lot, port) {
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      if (e['collection'] != tarCollectionVersions) continue;
      final v = port.parId(tarCollectionVersions, e['id']);
      if (v != null && v['statut'] == 'valide') {
        return DependanceImport('VERSION_DEJA_VALIDEE', 'la version ${v['id']} est déjà validée : une décision se remplace par une nouvelle version, elle ne s’efface pas',
            'Proposez une nouvelle version à l’écran « Référentiel produits » (Changer le prix d’achat) ; seules les propositions encore en attente se retirent avec leur lot.');
      }
    }
    return null;
  },
);
