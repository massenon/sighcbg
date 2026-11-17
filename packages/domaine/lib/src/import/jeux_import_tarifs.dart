/// LE JEU « TARIFS ET PRIX » (lot TAR, PRD-TARIFS T4) : l'import du référentiel de prix par PROPOSITION. Il remplace l'ancien jeu « catalogue des actes », qui écrivait des
/// prix dans une liste devenue simple projection de lecture : ce chemin est refusé par la garde du magasin (le prix en vigueur ne se réécrit jamais).
///
/// UN SEUL CHEMIN : chaque ligne passe par le MÊME moteur que l'écran « Tarifs et prix » (`tarProposer`), jamais par un second contrôle. Le prix en vigueur ne bouge jamais à l'import :
///   * Oui + geste de décider (matrice)  : version VALIDÉE d'emblée, effective à sa date d'effet ;
///   * Oui sans ce geste, ou champ vide  : PROPOSITION, soumise à la décision (vide = « à valider », décision T7 de la Direction) ;
///   * Non (motif obligatoire)           : ligne NON appliquée, consignée avec son motif, AUCUNE version, ni erreur ni refus du fichier ;
///   * prix identique à celui en vigueur : « inchangée », comptée, jamais une version.
/// Les ERREURS refusent le fichier entier (tout ou rien) ; les DÉCISIONS se prennent ligne à ligne. Un tiret n'est pas un zéro ; NC n'existe qu'en colonne assurée ; zéro est refusé.
///
/// RÉSERVÉ À LA MÈRE : la mère seule écrit le référentiel (famille R). Un fileul ne dépose pas un fichier : il propose à l'écran, la demande part à la mère (`propositionsTarif`).
part of 'jeux_import.dart';

const List<(String, String)> _famillesPrix = [
  ('CONSULTATION', 'Consultations'),
  ('ACTE', 'Actes'),
  ('HOSPITALISATION', 'Hospitalisation'),
  ('AMI', 'Actes médico-infirmiers'),
  ('GYNECO', 'Gynéco-obstétrique et kits'),
  ('CERTIFICAT', 'Certificats et attestations'),
  ('LABO', 'Analyses de laboratoire'),
  ('IMAGERIE', 'Imagerie médicale'),
];
const List<(String, String)> _couverturesPrix = [('toutes', 'Toutes compagnies'), ('sos', 'SOS seule'), ('non', 'Non couvert')];
const Map<String, Object> _assurableDe = {'toutes': true, 'sos': 'sos', 'non': false};
const Map<String, String> _colonneDuRefus = {
  'MOTIF_REQUIS': 'Motif',
  'DATE_EFFET_REQUISE': 'Date d’effet',
  'DATE_PASSEE': 'Date d’effet',
  'DATE_PASSEE_RESERVEE': 'Date d’effet',
  'TARIF_DEJA_UTILISE': 'Date d’effet',
  'CHANGEMENT_EN_ATTENTE': 'Code',
  'PRESTATION_INTROUVABLE': 'Code',
  'CODE_EXISTANT': 'Code',
  'IDENTITE_INCOMPLETE': 'Désignation',
  'PRIX_ABSENT': 'Prix non assuré',
  'PRIX_INVALIDE': 'Prix non assuré',
  'PRIX_ZERO': 'Prix non assuré',
};

/// Le contexte lu UNE fois par analyse : le référentiel, les pièces (contrôle d'usage), le jour et le droit de décider du profil qui importe.
class _CtxTarifs {
  _CtxTarifs(this.port)
      : jour = port.jour,
        peutDecider = port.profil.geste(gesteDeciderPrix),
        secteurs = <String>{...importSecteursActes};
  final PortImport port;
  final String jour;
  final bool peutDecider;
  final Set<String> secteurs;

  ReferentielTarifs get h => ReferentielTarifs(port.toutes(tarCollectionTarifs), port.toutes(tarCollectionVersions));

  ContexteTarif cx(ReferentielTarifs ref) => ContexteTarif(
        referentiel: ref,
        aujourdhui: jour,
        role: port.profil.role,
        auteur: port.utilisateur,
        // L'importateur a le droit d'importer ce jeu (le moteur l'a contrôlé avant) : il propose. Décider reste le geste réservé de la matrice.
        peutEditerEcran: true,
        peutDecider: peutDecider,
        peutDatePassee: false,
        pieces: PiecesTarif(factures: port.toutes('factures'), demandesAnalyses: port.toutes('demandesAnalyses'), demandesImagerie: port.toutes('demandesImagerie')),
      );
}

String _prixAffiche(num? na, String etatA, num? pa) {
  final a = etatA == 'montant' ? '$pa' : (etatA == 'nc' ? 'NC' : (etatA == 'unique' ? 'unique' : 'absent'));
  return '${na ?? 'absent'} / $a';
}

/// Ce que la ligne propose, dans la forme que `tarProposer` attend.
DemandeProposition _offreDeLigne(_V v, ReferentielTarifs h, {required bool valider}) {
  final na = v['prixNonAssure'] as Map, pa = v['prixAssure'] as Map;
  final unique = v['prixUnique'] == 'oui';
  final etatA = unique ? 'unique' : '${pa['etat']}';
  final p = h.parCode['${v['code']}'];
  return DemandeProposition(
    code: '${v['code']}',
    prixNonAssure: na['etat'] == 'montant' ? na['montant'] : null,
    prixAssure: etatA == 'montant' ? pa['montant'] : null,
    etatAssure: etatA,
    dateEffet: v['dateEffet'] as String?,
    motif: v['motif'] as String?,
    valider: valider,
    creation: p != null
        ? null
        : {
            'libelle': v['designation'],
            'famille': v['famille'],
            if (v['secteur'] != null && '${v['secteur']}'.isNotEmpty) 'secteur': v['secteur'],
            if (v['source'] != null && '${v['source']}'.isNotEmpty) 'source': v['source'],
          },
    assurable: p != null ? null : (v['couverture'] != null && '${v['couverture']}'.isNotEmpty ? _assurableDe[v['couverture']] : (etatA == 'nc' ? false : null)),
  );
}

final JeuImport jeuTarifs = JeuImport(
  id: 'tarifs',
  ecran: 'imp-actes',
  libelle: 'Importation des tarifs et prix',
  module: 'IMP',
  statut: 'supporte',
  description:
      'Prix des prestations (consultations, actes, soins, analyses, imagerie, certificats) à deux colonnes, avec les trois états de la colonne assurée, une date d’effet et la décision Oui ou Non : chaque ligne qui change un prix devient une proposition, jamais une réécriture.',
  source: 'Aucune grille imprimée de la clinique n’a été remise : les prix du fichier font foi, aucun n’est complété ni inventé par le logiciel.',
  limite:
      'Un import de prix ne change jamais le prix en vigueur par lui-même : la ligne devient une proposition soumise à la décision (Oui ou Non), sauf si votre rôle détient le geste de décider et que la ligne dit Oui. Réservé au poste principal : un poste rattaché propose à l’écran « Tarifs et prix ».',
  cibles: const [tarCollectionTarifs, tarCollectionVersions],
  fichierModele: 'modele-import-tarifs',
  restreint: true,
  gesteExiste: 'Une prestation connue se change par une nouvelle version : donnez-lui une date d’effet, le prix en vigueur n’est jamais réécrit.',
  colonnes: [
    _oblig('code', 'Code', 'texte',
        longueurMax: 30, exemple: 'MG01', aide: 'Code d’une prestation connue (changement de prix) ou d’une prestation nouvelle (création : désignation et famille obligatoires).'),
    _col('designation', 'Désignation', 'texte', longueurMax: 160, exemple: 'Consultation généraliste', aide: 'Libellé de facturation. Obligatoire pour créer une prestation ; jamais appliqué à une prestation connue.'),
    _col('famille', 'Famille', 'liste', liste: (_) => [for (final f in _famillesPrix) ValeurListe(f.$1, f.$2)], exemple: 'Actes', aide: 'Obligatoire pour créer une prestation.'),
    _col('secteur', 'Secteur', 'liste', liste: (ctx) => [for (final s in ((ctx as _CtxTarifs).secteurs.toList()..sort())) ValeurListe(s)], exemple: 'Médecine générale'),
    _oblig('prixNonAssure', 'Prix non assuré', 'tarif',
        exemple: 5000, aide: 'Montant entier strictement positif en FCFA. NC n’existe pas dans cette colonne ; un tiret n’est pas un zéro : une ligne sans prix non assuré est refusée.'),
    _oblig('prixAssure', 'Prix assuré', 'tarif',
        exemple: 3000, aide: 'Montant, NC (aucune compagnie ne couvre l’acte : l’assuré paie le prix non assuré) ou un tiret (valeur manquante : ne se facture pas aux assurés). Voir « Prix unique ».'),
    _col('prixUnique', 'Prix unique', 'liste', liste: _fixe(['oui', 'non']), exemple: 'non', aide: 'Oui : le prix assuré vaut le prix non assuré (la cellule « Prix assuré » est alors ignorée).'),
    _col('couverture', 'Couverture', 'liste',
        liste: (_) => [for (final c in _couverturesPrix) ValeurListe(c.$1, c.$2)], exemple: 'Toutes compagnies', aide: 'Pour une création seulement ; vide : toutes les compagnies.'),
    _oblig('dateEffet', 'Date d’effet', 'date',
        exemple: '2027-01-01', aide: 'Obligatoire : le prix en vigueur ne change qu’à cette date. Une date passée est refusée (elle se propose à l’écran, avec sa case et son motif).'),
    _col('valider', 'Valider (Oui/Non)', 'liste',
        liste: _fixe(['oui', 'non']), exemple: 'oui', aide: 'Oui : le prix s’applique (validé d’emblée si votre rôle décide, sinon il devient une proposition). Non : ligne non appliquée, motif obligatoire. Vide : à valider.'),
    _col('motif', 'Motif', 'texte', longueurMax: 160, exemple: 'Nouvelle grille tarifaire', aide: 'Obligatoire pour toute ligne qui change un prix et pour tout Non.'),
    _col('source', 'Source', 'texte', longueurMax: 160, exemple: 'Grille du 01/12/2026'),
  ],
  contexte: (port) {
    final c = _CtxTarifs(port);
    for (final p in port.actives(tarCollectionTarifs)) {
      if (p['secteur'] != null && '${p['secteur']}'.isNotEmpty) c.secteurs.add('${p['secteur']}');
    }
    return c;
  },
  cle: (v) => [_n(v['code'])],
  existe: (v, ctx) => null,
  regles: (v, ctx, sc, n) {
    final c = ctx as _CtxTarifs;
    final pb = <ProblemeImport>[];
    void p(String col, Object? val, String code, String niveau, String motif, String geste) => pb.add(_p(col, val, code, niveau, motif, geste));
    final h = c.h;
    final prest = h.parCode['${v['code']}'];
    if (prest != null && prest['famille'] == 'PRODUIT') {
      p('Code', v['code'], 'CODE_PRODUIT', importRefus, 'le code « ${v['code']} » est celui d’un produit : son prix d’achat se change à part', 'Placez ce code dans le fichier des produits.');
      return pb;
    }
    final na = v['prixNonAssure'] as Map, pa = v['prixAssure'] as Map;
    final unique = v['prixUnique'] == 'oui';
    final etatA = unique ? 'unique' : '${pa['etat']}';
    // Un NON est la décision de l'importateur : ni version, ni erreur. Son motif est obligatoire et se lit au rapport.
    if (v['valider'] == 'non') {
      if ('${v['motif'] ?? ''}'.isEmpty) {
        p('Motif', '', 'MOTIF_REQUIS', importRefus, 'une ligne « Non » se motive : sans motif, on ne sait pas pourquoi le prix n’est pas appliqué', 'Saisissez le motif de la ligne $n.');
      } else {
        sc['sansEcritureLigne'] = 'non';
        p('Valider (Oui/Non)', 'Non', 'LIGNE_NON_APPLIQUEE', importAvertissement, 'ligne non appliquée sur décision de l’importateur (motif : ${v['motif']})', 'Rien à faire : aucune version n’est créée, le motif est consigné.');
      }
      return pb;
    }
    if (na['etat'] == 'nc') {
      p('Prix non assuré', 'NC', 'NC_INTERDIT', importRefus, 'NC n’a de sens que dans la colonne assurée', 'Saisissez le prix de guichet en francs.');
    } else if (na['etat'] == 'manquant') {
      p('Prix non assuré', '-', 'PRIX_ABSENT', importRefus, 'un tiret n’est pas un zéro, et un prix non assuré absent n’est pas un tarif : la ligne ne se facturerait pas', 'Saisissez le prix non assuré en francs.');
    } else if (etatA == 'manquant') {
      p('Prix assuré', '-', 'PRIX_MANQUANT', importAvertissement, 'prix assuré manquant : la ligne ne se facturera pas aux assurés (un tiret n’est pas un zéro)', 'Saisissez le prix assuré dès qu’il est connu.');
    }
    if (prest == null) {
      if ('${v['designation'] ?? ''}'.isEmpty) {
        p('Désignation', '', 'IDENTITE_INCOMPLETE', importRefus, 'le code « ${v['code']} » est inconnu : une nouvelle prestation porte une désignation', 'Renseignez la désignation et la famille, ou corrigez le code.');
      } else if ('${v['famille'] ?? ''}'.isEmpty) {
        p('Famille', '', 'IDENTITE_INCOMPLETE', importRefus, 'le code « ${v['code']} » est inconnu : une nouvelle prestation porte une famille', 'Renseignez la famille, ou corrigez le code.');
      }
    }
    if (pb.any((x) => x.estRefus)) return pb;
    // LE MÊME CHEMIN QUE L'ÉCRAN : tous les contrôles de la proposition, sans rien écrire.
    final valider = c.peutDecider && v['valider'] == 'oui';
    var r = tarProposer(c.cx(h), _offreDeLigne(v, h, valider: valider));
    if (!r.ok && valider && (r.refus!.code == 'VALIDATION_RESERVEE' || r.refus!.code == 'CONFIGURATION_DE_LA_MERE')) {
      r = tarProposer(c.cx(h), _offreDeLigne(v, h, valider: false));
    }
    if (!r.ok && r.refus!.code == 'PRIX_INCHANGE') {
      sc['sansEcritureLigne'] = 'inchange';
      p('Prix non assuré', '', 'PRIX_INCHANGE', importAvertissement, 'ce prix est déjà celui en vigueur à cette date : aucune version, la ligne est comptée', 'Rien à faire.');
      return pb;
    }
    if (!r.ok) {
      p(_colonneDuRefus[r.refus!.code] ?? 'Prix non assuré', '', r.refus!.code, importRefus, r.refus!.motif, r.refus!.geste);
      return pb;
    }
    if (!valider && v['valider'] == 'oui') {
      p('Valider (Oui/Non)', 'Oui', 'OUI_VAUT_PROPOSITION', importAvertissement,
          'votre rôle ne détient pas le geste de décider un prix : le Oui vaut proposition, la décision revient aux rôles que la matrice désigne', 'Rien à faire : la proposition attend la décision.');
    }
    if (prest != null && na['etat'] == 'montant') {
      final s = h.instantane(prest, '${v['dateEffet']}');
      if (s != null) {
        final suivi = _prixAffiche(s.na, s.etatAssure, s.pa);
        final propose = _prixAffiche(na['montant'] as num?, etatA, etatA == 'montant' ? pa['montant'] as num? : null);
        p('Prix non assuré', propose, 'VARIATION', importAvertissement, 'en vigueur à cette date : $suivi ; proposé : $propose', 'Vérifier la variation avant de confirmer.');
      }
    }
    return pb;
  },
  ecrire: (lignes, ecrireFiche, lot, ctx, port) {
    final c = ctx as _CtxTarifs;
    for (final l in lignes) {
      final v = l.v;
      final h = c.h;
      final valider = c.peutDecider && v['valider'] == 'oui';
      var r = tarProposer(c.cx(h), _offreDeLigne(v, h, valider: valider));
      if (!r.ok && valider && (r.refus!.code == 'VALIDATION_RESERVEE' || r.refus!.code == 'CONFIGURATION_DE_LA_MERE')) {
        r = tarProposer(c.cx(h), _offreDeLigne(v, h, valider: false));
      }
      if (!r.ok) throw StateError('ligne ${l.n} (${v['code']}) : ${r.refus!.motif}');
      final prop = r.valeur!;
      if (prop.identite != null) ecrireFiche(tarCollectionTarifs, {...prop.identite!});
      ecrireFiche(tarCollectionVersions, {...prop.version, 'import': {'jeu': 'tarifs', 'lot': lot['reference']}});
      if (prop.valideeEnUnGeste) {
        // Une version validée à l'import arrête le marquage « tarif d'attente » de la prestation, comme un Oui à l'écran.
        for (final (id, patch) in tarLeverProvisoire(c.h, '${v['code']}', qui: port.utilisateur, jour: c.jour)) {
          port.mettreAJour(tarCollectionVersions, id, patch);
        }
      }
    }
  },
  // Un lot de prix s'annule en RETIRANT ses propositions (RG-14, rien ne se supprime) ; une version déjà validée se remplace par une nouvelle version, elle ne s'efface pas.
  dependances: (lot, port) {
    for (final e in (lot['ecrits'] as List).cast<Map>()) {
      if (e['collection'] != tarCollectionVersions) continue;
      final v = port.parId(tarCollectionVersions, e['id']);
      if (v != null && v['statut'] == 'valide') {
        return DependanceImport('VERSION_DEJA_VALIDEE', 'la version ${v['id']} est déjà validée : une décision se remplace par une nouvelle version, elle ne s’efface pas',
            'Proposez une nouvelle version à l’écran « Tarifs et prix » ; seules les propositions encore en attente se retirent avec leur lot.');
      }
    }
    return null;
  },
);
