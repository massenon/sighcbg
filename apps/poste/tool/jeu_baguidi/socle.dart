// LE SOCLE DU JEU BAGUIDI : les référentiels qui ne dépendent d'aucun module (J7 à J9, décision du 08/11/2026) et ce que la clinique d'origine a laissé
// de GÉNÉRIQUE (rôles, matrice des droits, catalogues d'examens). Aucune activité ici : ni patient, ni facture, ni écriture.
//
// Ce qui est à Baguidi est ÉCRIT (plan comptable, actes de médecine du travail, assureurs, entreprises clientes, secteurs, postes) ; ce qui est générique
// est RECOPIÉ du jeu de référence ; tout le reste démarre vide et appartient à une étape suivante (`module_*.dart`).
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'contexte.dart';

/// Les collections recopiées du jeu de référence parce qu'elles ne portent aucune donnée d'une clinique : rôles, matrice, manifeste, catalogues cliniques
/// (analyses, imagerie, pathologies), barèmes réglementaires, modèles, formats. Les champs `_cree*` sont retirés à la lecture.
const List<String> collectionsGeneriques = [
  'rolesBase', 'modulesManifeste', 'rbac', 'modulesActifs',
  'naturesFacture', 'typesPiece', 'centresCouts',
  'examensLabo', 'unitesLabo', 'variablesLabo', 'plagesReactif',
  'examensImagerie', 'variablesImagerie', 'pathologies',
  'regimesTravail', 'grillePrimes', 'historiquePrimes', 'baremeNS131', 'historiqueBareme',
  'objectifsPilotage', 'obligationsFiscales', 'historiqueObligations',
  'modelesBadge', 'modelesMessage', 'enquetes', 'identiteLegale', 'tachesPlanifiees',
  // le répertoire des ambulances : neuf fiches fictives, marquées « Numéro fictif de démonstration », qui disent elles-mêmes qu'elles sont à remplacer
  'ambulances',
  // le barème de l'AIB par situation de l'acheteur (modèle de la maquette) : 5 % arrêté depuis le 07/09/2026 (décision de Baguidi), 1 % et 3 % non arrêtés et
  // marqués à valider ; versionné par date d'effet
  'situationsAib', 'baremeAib',
  // les PARAMÈTRES de l'AIB (base de la retenue, branchement IFU, taux de repli, longueur de l'IFU) : la graine, une version 1 par rubrique, à valider aux
  // Paramètres ; les validations ajoutent des versions datées, elles n'écrasent rien
  'parametresAib',
];

/// Les tarifs hérités du logiciel d'origine : aucun n'est une grille de Baguidi (J7). Le motif est écrit sur CHAQUE fiche.
const String motifTarifHerite = 'Tarif hérité du logiciel d’origine : grille Baguidi à fournir. Valeur d’attente, à corriger par la Direction.';
const String sourceTarifHerite = 'Hérité du logiciel d’origine, grille Baguidi à fournir';
const String dateMarquage = '2026-11-08';

/// Les sous-comptes à SIX chiffres que les moteurs de `packages/domaine` et les vecteurs emploient (571000 caisse, 706000 prestations, 411000 clients…)
/// et que le plan SYSCOHADA révisé, qui s'arrête à quatre chiffres, ne porte pas. Relevé figé par lecture du code et des vecteurs (08/11/2026) : on
/// n'ajoute pas un compte dont rien ne se sert, on ne modifie ni les moteurs ni les vecteurs. Chacun est rattaché au compte du plan dont il est le
/// préfixe le plus long (571000 sous 571) et marqué source « SIGH ».
const List<String> sousComptesSigh = [
  '101100', '104100', '130000', '131000', '139000', '162000', '211000', '213000', '229000', '231100',
  '235100', '241000', '244100', '244200', '245000', '245100', '275000', '281000', '31000', '311000',
  '312000', '401000', '401110', '401120', '401130', '408000', '411000', '411110', '411200', '422000',
  '423000', '428101', '428200', '431000', '431300', '441100', '442100', '443000', '447000', '449200',
  '521000', '521100', '521200', '521300', '571000', '601000', '601100', '602100', '603201', '603202',
  '604100', '604200', '604300', '604410', '604420', '604430', '604600', '604700', '605000', '605100',
  '605200', '605300', '605400', '605600', '605700', '605800', '605900', '605901', '608100', '612000',
  '616000', '618100', '618300', '622000', '622300', '622800', '624100', '624200', '624300', '625000',
  '625100', '625200', '625400', '625500', '627700', '628100', '628810', '631800', '631810', '631820',
  '631830', '632400', '632401', '632410', '632700', '634100', '635101', '637100', '638300', '638400',
  '638900', '641100', '641200', '641300', '645000', '646100', '646200', '646210', '646400', '646800',
  '647200', '648000', '651100', '658200', '658800', '661100', '664120', '671200', '701000', '706000',
  '706100', '706200',
];

void generer(Contexte ctx) {
  _conserverLesGeneriques(ctx);
  _planComptable(ctx);
  _actesEtTarifs(ctx);
  _assureursEtEntreprises(ctx);
  _organisation(ctx);
  _calendrierFiscal(ctx);
  _caisse(ctx);
}

// --- Génériques --------------------------------------------------------------------------------------------------------------------------------

void _conserverLesGeneriques(Contexte ctx) {
  for (final n in collectionsGeneriques) {
    ctx.remplacer(n, ctx.reference(n));
  }
  // Une fiche de la matrice peut citer, dans son motif, l'agent pour qui le compte avait été demandé : le nom d'une personne d'une autre clinique ne se livre
  // pas (même pseudonymisé).
  ctx.remplacer('rbac', [
    for (final f in ctx.fiches('rbac'))
      {
        ...f,
        if ('${f['motif'] ?? ''}'.startsWith('Compte demandé par la Direction')) 'motif': 'Compte demandé par la Direction.',
      }
  ]);
  ctx.note('socle : ${collectionsGeneriques.length} collections génériques recopiées du jeu de référence');
}

// --- Plan comptable (J9) -----------------------------------------------------------------------------------------------------------------------

String _journalDe(String num) {
  if (RegExp(r'^40').hasMatch(num)) return 'ACH';
  if (RegExp(r'^41').hasMatch(num)) return 'VTE';
  if (RegExp(r'^4[23]').hasMatch(num) || RegExp(r'^66').hasMatch(num)) return 'SAL';
  if (RegExp(r'^631').hasMatch(num) || RegExp(r'^52').hasMatch(num)) return 'BQ';
  if (RegExp(r'^57').hasMatch(num)) return 'CAI';
  if (num.startsWith('2')) return 'IMM';
  if (num.startsWith('6')) return 'ACH';
  if (num.startsWith('7')) return 'VTE';
  return 'OD';
}

void _planComptable(Contexte ctx) {
  final lignes = File('tool/donnees/plan-comptable-syscohada-revise.csv').readAsStringSync().split('\n').skip(1);
  final plan = <String, String>{};
  for (final l in lignes) {
    final t = l.trimRight();
    if (t.isEmpty) continue;
    final i = t.indexOf(';');
    plan[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  if (plan.length != 1332) throw StateError('Le plan SYSCOHADA révisé doit compter 1 332 comptes, il en compte ${plan.length}.');
  final ajouts = <String, ({String libelle, String parent})>{};
  for (final num in sousComptesSigh) {
    if (plan.containsKey(num)) continue;
    String? parent;
    for (var n = num.length - 1; n >= 1; n--) {
      if (plan.containsKey(num.substring(0, n))) {
        parent = num.substring(0, n);
        break;
      }
    }
    if (parent == null) throw StateError('Le sous-compte $num n\'a aucun compte parent dans le plan.');
    ajouts[num] = (libelle: '${plan[parent]} (sous-compte SIGH)', parent: parent);
  }
  final tous = <String, Fiche>{
    for (final e in plan.entries)
      e.key: {
        'statut': 'actif',
        'num': e.key,
        'libelle': e.value,
        'classe': int.parse(e.key[0]),
        'journal': _journalDe(e.key),
        'source': 'SYSCOHADA révisé',
      },
    for (final e in ajouts.entries)
      e.key: {
        'statut': 'actif',
        'num': e.key,
        'libelle': e.value.libelle,
        'classe': int.parse(e.key[0]),
        'journal': _journalDe(e.key),
        'source': 'SIGH',
        'parent': e.value.parent,
        'imputable': true,
      },
  };
  final nums = tous.keys.toList()..sort();
  var i = 0;
  ctx.remplacer('comptes', [
    for (final n in nums) {'id': 'CPT${(++i).toString().padLeft(4, '0')}', ...tous[n]!}
  ]);
  ctx.note('socle : plan comptable ${plan.length} comptes SYSCOHADA révisé + ${ajouts.length} sous-comptes SIGH');
}

// --- Actes et tarifs (J7) ----------------------------------------------------------------------------------------------------------------------

/// Remet une fiche tarifaire au statut de valeur d'attente : provisoire, motif, source, plus aucune mention d'un arrêté de la Direction d'origine.
Fiche _provisoire(Fiche f) {
  final r = {...f};
  r['tarifProvisoire'] = true;
  r.remove('tarifArreteLe');
  r.remove('aArbitrer');
  r.remove('arbitrage');
  if (r.containsKey('prixAValider')) r['prixAValider'] = true;
  // Un motif propre à la fiche (acte décliné par la grille : « choisir une variante à la place de la clinique facturerait le mauvais tarif ») est gardé
  // quand il ne parle ni d'un arrêté ni de la clinique d'origine.
  final ancien = '${f['motifPrix'] ?? ''}';
  final propre = ancien.isNotEmpty && !RegExp('arrêté|Direction|NASSIERA|Nassiera').hasMatch(ancien);
  r['motifPrix'] = propre ? '$motifTarifHerite $ancien' : motifTarifHerite;
  r['source'] = sourceTarifHerite;
  r['marqueLe'] = dateMarquage;
  // Les variantes d'une grille déclinée portent leur propre source (nom de la clinique d'origine) : même remise à l'état de valeur d'attente.
  if (r['variantesGrille'] is List) {
    r['variantesGrille'] = [
      for (final v in (r['variantesGrille'] as List))
        if (v is Map) ({...v.cast<String, Object?>()..remove('tarifArreteLe'), 'tarifProvisoire': true, 'source': sourceTarifHerite}) else v
    ];
  }
  return r;
}

void _actesEtTarifs(Contexte ctx) {
  final actes = [for (final a in ctx.reference('actes')) _provisoire(a)];
  final tarifs = [for (final t in ctx.reference('catalogueTarifs')) _provisoire(t)];
  // Actes de médecine du travail : tarifs d'ATTENTE proposés (10 000, 8 000, 8 000, 5 000, 5 000 non assuré), à corriger par la Direction. L'assuré paie 60 %
  // (la règle de la grille, vérifiée sur la consultation : 5 000 non assuré, 3 000 assuré). Les deux pièces d'aptitude sont des certificats : comme tous les
  // certificats de la grille, elles ne sont couvertes que par SOS et leur tarif est le même assuré ou non.
  const mt = [
    ('MT01', 'MT-EMB', 'Visite médicale d’embauche', 10000, 'CONSULTATION', true),
    ('MT02', 'MT-PER', 'Visite médicale périodique', 8000, 'CONSULTATION', true),
    ('MT03', 'MT-REP', 'Visite médicale de reprise', 8000, 'CONSULTATION', true),
    ('MT04', 'MT-FAP', 'Fiche d’aptitude', 5000, 'CERTIFICAT', false),
    ('MT05', 'CERT-APT', 'Certificat d’aptitude', 5000, 'CERTIFICAT', false),
  ];
  var n = tarifs.length;
  for (final (code, codeTarif, libelle, prix, famille, assurable) in mt) {
    final assure = assurable ? (prix * 6 ~/ 10) : prix;
    const motif = 'Tarif d’attente proposé le 08/11/2026 pour la médecine du travail : à corriger par la Direction.';
    actes.add({
      'id': 'ACT-$code',
      'code': code,
      'libelle': libelle,
      'secteur': 'Médecine du travail',
      'prix': prix,
      'prixNonAssure': prix,
      'prixAssure': assure,
      'nonCouvert': false,
      'assurable': assurable ? true : 'sos',
      'codeTarif': codeTarif,
      'tarifProvisoire': true,
      'motifPrix': motif,
      'source': 'Proposition du 08/11/2026 (aucune grille Baguidi remise)',
      'marqueLe': dateMarquage,
      'rapprochement': 'acte propre à Baguidi',
      'statut': 'actif',
    });
    tarifs.add({
      'id': 'TAR${(++n).toString().padLeft(3, '0')}',
      'code': codeTarif,
      'libelle': libelle,
      'famille': famille,
      'prixNonAssure': prix,
      'prixAssure': assure,
      'nonCouvert': false,
      'assurable': assurable ? true : 'sos',
      'prixAValider': true,
      'tarifProvisoire': true,
      'motifPrix': motif,
      'source': 'Proposition du 08/11/2026 (aucune grille Baguidi remise)',
      'marqueLe': dateMarquage,
      'statut': 'actif',
    });
  }
  ctx.remplacer('actes', actes);
  ctx.remplacer('catalogueTarifs', tarifs);

  // Catalogue des analyses (collection ET référentiel statique : les deux listes doivent rester identiques) et tarifs journaliers des chambres.
  final analyses = [for (final a in ctx.reference('analyses')) _provisoire(a)];
  ctx.remplacer('analyses', analyses);
  ctx.referentiels['analyses'] = analyses;
  ctx.referentiels['typesChambre'] = [
    for (final t in (ctx.referentiels['typesChambre'] as List).cast<Map>())
      {...t.cast<String, Object?>(), 'tarifProvisoire': true, 'motifPrix': motifTarifHerite}
  ];
  ctx.note('socle : ${actes.length} actes (dont 5 de médecine du travail), ${tarifs.length} tarifs de catalogue, ${analyses.length} analyses, tous marqués tarifProvisoire');
}

// --- Assureurs et entreprises clientes (J6, J8) ------------------------------------------------------------------------------------------------

/// Les trois compagnies avec lesquelles la démonstration porte une convention FICTIVE.
const List<String> compagniesConventionnees = ['NSIA', 'SUNU', 'SANLAM'];

void _assureursEtEntreprises(Contexte ctx) {
  final assureurs = <Fiche>[];
  for (final a in ctx.reference('assureurs')) {
    final signee = compagniesConventionnees.contains(a['code']);
    assureurs.add({
      ...a,
      'convention': signee ? 'Signée' : 'Aucune',
      'assures': 0,
      if (signee) ...{
        'conventionFictive': true,
        'dateConvention': '2026-08-01',
        'noteConvention': 'Convention fictive de démonstration : à remplacer par la convention réellement signée.',
      }
    });
  }
  ctx.remplacer('assureurs', assureurs);
  ctx.remplacer('garanties', const []);

  // Les six entreprises clientes de la médecine du travail : souscripteurs (employeurs), FICTIVES. Aucun numéro de téléphone n'est inventé.
  const entreprises = [
    ('Société Cotonnière du Borgou', 'NSIA', 60, 25),
    ('Huilerie de Parakou', 'NSIA', 45, 28),
    ('Transports Okpara', 'SUNU', 38, 30),
    ('Brasserie des Collines', 'SUNU', 30, 26),
    ('BTP Alafia', 'SANLAM', 25, 29),
    ('Imprimerie Gurma', 'SANLAM', 20, 27),
  ];
  final noms = {for (final a in assureurs) '${a['code']}': '${a['nom']}'};
  var i = 0;
  ctx.remplacer('souscripteurs', [
    for (final (nom, code, effectif, jour) in entreprises)
      {
        'id': 'SOU${(++i).toString().padLeft(3, '0')}',
        'statut': 'actif',
        'nom': nom,
        'categorie': 'entreprise',
        'assureur': code,
        'assureurNom': noms[code],
        'police': '$code/2026/${(200 + i).toString().padLeft(4, '0')}',
        'effectif': effectif,
        'contact': 'Contact fictif : responsable du personnel',
        'dateDebut': '2026-08-01',
        'periodiciteFacturation': 'mensuelle',
        'jourFacturation': jour,
        'conventionVisites': true,
        'grilleSaisie': false,
        'actesExclus': const <String>[],
        'produitsExclus': const <String>[],
        'accordPrealable': const <String>[],
        'fictif': true,
        'source': 'Entreprise fictive de démonstration (convention de visites de médecine du travail)',
      }
  ]);
  ctx.note('socle : 13 assureurs conservés (3 conventions fictives : ${compagniesConventionnees.join(', ')}), 6 entreprises fictives souscriptrices');
}

// --- Secteurs, postes, organigramme (J3, décision du 08/11/2026) ------------------------------------------------------------------------------

/// Les six secteurs que portent les neuf personnes. Rien n'est repris de l'organigramme de la clinique d'origine. Le responsable n'est nommé que lorsqu'il
/// est la seule personne du secteur : désigner l'un des deux comptables ou l'un des deux responsables RH serait inventer une hiérarchie.
void _organisation(Contexte ctx) {
  const source = 'Organisation de la Clinique Baguidi limitée aux neuf personnes de la démonstration : à compléter par la Direction';
  const secteurs = [
    ('DIR', 'DIRECTION', 'BAGUIDI Rafiou', 'Directeur Général', 'direction'),
    ('CPT', 'COMPTABILITÉ', '', 'Comptable', 'comptable'),
    ('RHU', 'RESSOURCES HUMAINES', '', 'Responsable des ressources humaines', 'rh'),
    ('MGE', 'MÉDECINE GÉNÉRALE', 'IDOHOU Abraham', 'Médecin', 'medecin'),
    ('SOI', 'SOINS INFIRMIERS', 'AKONDE Octave', 'Infirmier', 'infirmier'),
    ('ADM', 'ADMINISTRATION', '', 'Direction', 'direction'),
  ];
  var i = 0;
  ctx.remplacer('secteurs', [
    for (final (code, libelle, responsable, qualification, role) in secteurs)
      {
        'id': 'SEC${(++i).toString().padLeft(2, '0')}',
        'statut': 'actif',
        'ordre': i,
        'code': code,
        'libelle': libelle,
        'responsable': responsable,
        'qualification': qualification,
        'role': role,
        'source': source,
      }
  ]);
  const postes = [
    ('Directeur Général', 1, 'BAGUIDI Rafiou', 'direction', null),
    ('Direction', 1, 'SOKOU Peace', 'direction', 1),
    ('Comptables', 2, 'SANOUSSI Adamon', 'comptable', 1),
    ('Responsables des ressources humaines', 2, 'MABOUDOU Nawal', 'rh', 1),
    ('Médecin', 1, 'IDOHOU Abraham', 'medecin', 1),
    ('Infirmier', 1, 'AKONDE Octave', 'infirmier', 1),
  ];
  var p = 0;
  ctx.remplacer('postes', [
    for (final (poste, effectif, titulaire, role, parent) in postes)
      {
        'id': 'PST${(++p).toString().padLeft(3, '0')}',
        'statut': 'actif',
        if (parent != null) 'parentId': 'PST${parent.toString().padLeft(3, '0')}',
        'poste': poste,
        'effectif': effectif,
        'titulaire': titulaire,
        'chef': false,
        'role': role,
        'source': source,
      }
  ]);
  ctx.note('socle : 6 secteurs et 6 postes limités aux neuf personnes');
}

// --- Calendrier fiscal (décisions du 06/11/2026 et du 09/11/2026) -----------------------------------------------------------------------------

/// La CNSS se SÉPARE en deux obligations (Direction, 09/11/2026), toutes deux lues dans le calendrier du domaine — le jour n'est écrit nulle part ici :
///  - `CNSS` (identifiant technique historique) devient la « Déclaration unique (ITS, VPS, déclaration CNSS) », au jour de la donnée (le 10) ;
///  - `CNSS-VERS`, nouvelle, est le versement des cotisations (le 15), MARQUÉE NON ARRÊTÉE : la Direction l'arrêtera après confirmation auprès de la CNSS.
/// Les autres échéances héritées sont GARDÉES : le régime d'imposition de Baguidi est à revoir par le comptable, et chaque fiche le dit.
void _calendrierFiscal(Contexte ctx) {
  final declaration = d.cfbCalendrierFiscal.firstWhere((o) => o.code == 'CNSS');
  final versement = d.cfbCalendrierFiscal.firstWhere((o) => o.code == 'CNSS-VERS');
  final fiches = <Fiche>[];
  for (final o in ctx.fiches('obligationsFiscales')) {
    if (o['type'] != 'obligation') {
      fiches.add(o);
      continue;
    }
    if (o['code'] == 'CNSS') {
      fiches.add({
        ...o,
        'libelle': declaration.libelle,
        'jour': declaration.jour,
        'part': declaration.part,
        'declaration': declaration.declaration,
        'note': declaration.note,
        'source': declaration.source,
      });
    } else {
      fiches.add({
        ...o,
        'aRevoir': true,
        'noteRegime': 'Échéance héritée du calendrier d’origine : le régime d’imposition de la Clinique Baguidi est à revoir par le comptable (décision du 06/11/2026).',
        'source': 'Calendrier hérité du logiciel d’origine ; régime d’imposition à revoir par le comptable de la clinique',
      });
    }
  }
  // Le versement est inséré APRÈS la dernière obligation (avant la fiche des paramètres ORTB) : aucun identifiant FIS existant ne bouge.
  final rang = fiches.lastIndexWhere((f) => f['type'] == 'obligation') + 1;
  final n = fiches.where((f) => f['type'] == 'obligation').length + 1;
  fiches.insert(rang, d.cfbFicheDepuisObligation(versement, id: 'FIS${n.toString().padLeft(2, '0')}'));
  ctx.remplacer('obligationsFiscales', fiches);
  ctx.note('socle : CNSS scindée (déclaration unique au ${declaration.jour}, versement au ${versement.jour} non arrêté), ${fiches.where((f) => f['aRevoir'] == true).length} autres échéances gardées et marquées à revoir');
}

// --- Caisse ------------------------------------------------------------------------------------------------------------------------------------

/// Le seul compte de trésorerie qu'une démonstration sans banque connaît : la caisse (571000). Les comptes bancaires de la clinique d'origine portaient
/// des numéros de compte réels : ils ne sont pas repris.
void _caisse(Contexte ctx) {
  ctx.remplacer('banques', [
    for (final b in ctx.reference('banques'))
      if (b['nature'] == 'caisse') b
  ]);
}
