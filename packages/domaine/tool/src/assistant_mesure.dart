/// MESURE de l'assistant (lot AST-0) : jugement question par question, taux (global, réglage, contrôle, par intention, par catégorie d'échec), réponses inventées,
/// temps, robustesse à la faute, matrice de droits tirée de `rbac.json`, droits manquants, tableau de couverture engendré du catalogue.
///
/// Cet outil mesure le MÊME moteur que le poste : `ReconnaisseurAst` du domaine, pas une copie. Étanche : aucune importation hors `dart:core`, `dart:convert` et le domaine.
library;

import 'package:sigh_domaine/sigh_domaine.dart';

/// Le jeu de réglage est celui des numéros IMPAIRS, le jeu de contrôle celui des PAIRS : règle écrite d'avance, jamais ajustée.
String jeuDe(int n) => n.isOdd ? 'reglage' : 'controle';

class Jugement {
  const Jugement({required this.n, required this.ok, required this.raison, required this.paramsOk, required this.raisonParams});
  final int n;
  final bool ok;
  final String raison;
  final bool? paramsOk;
  final String raisonParams;
}

Jugement juger(Map<String, Object?> q, ReconnaissanceAst r) {
  final n = q['n'] as int;
  final att = (q['reaction'] as Map).cast<String, Object?>();
  final raisons = <String>[];
  if (r.statut != att['statut']) raisons.add('statut « ${r.statut} », attendu « ${att['statut']} »');
  if (att['intention'] != null && r.intention != att['intention']) raisons.add('intention ${r.intention ?? 'aucune'}, attendue ${att['intention']}');
  if (att['code'] != null && r.code != att['code']) raisons.add('code ${r.code ?? 'aucun'}, attendu ${att['code']}');
  if (att['alerte'] != null && !r.alertes.contains(att['alerte'])) raisons.add('alerte ${att['alerte']} absente');
  if (att['ecran'] != null && r.ecran != att['ecran']) raisons.add('écran ${r.ecran ?? 'aucun'}, attendu ${att['ecran']}');
  bool? pOk;
  var rp = '';
  final attendus = (q['parametres'] as Map?)?.cast<String, Object?>();
  if (attendus != null) {
    final manques = <String>[];
    attendus.forEach((k, v) {
      if (r.parametres[k] != v) manques.add('$k lu ${r.parametres[k]}, attendu $v');
    });
    pOk = manques.isEmpty;
    rp = manques.join(' ; ');
  }
  return Jugement(n: n, ok: raisons.isEmpty, raison: raisons.join(' ; '), paramsOk: pOk, raisonParams: rp);
}

/// Les VALEURS INVENTÉES d'une sortie : un paramètre texte qui n'est pas lu dans la question (après normalisation), une clé de réponse (valeur, montant, quantité…)
/// ou une intention hors catalogue. Les bornes de période (calculées de la date de référence) et les drapeaux fermés ne sont pas des valeurs de réponse.
int valeursInventees(String question, ReconnaissanceAst r, CatalogueAst cat) {
  var n = 0;
  // La question telle que le moteur la LIT : normalisée, abréviations d'agent développées (« consult » → « consultation ») — développer une abréviation n'est pas inventer.
  final qn = ' ${[for (final m in astNormaliser(question).split(' ')) astAbreviations[m] ?? m].join(' ')} ';
  final json = r.toJson();
  for (final cle in const ['valeur', 'montant', 'quantite', 'reponse', 'total', 'nom']) {
    if (json.containsKey(cle)) n++;
  }
  if (r.intention != null && cat[r.intention!] == null) n++;
  for (final e in r.parametres.entries) {
    if (const ['periode', 'periodeComparee', 'secteur', 'gabarit', 'patient', 'courrierSens'].contains(e.key)) continue;
    final v = e.value;
    if (v is String) {
      final vn = astNormaliser(v);
      if (vn.isEmpty) continue;
      if (!vn.split(' ').every((m) => qn.contains(m))) n++;
    } else if (v is int) {
      if (!qn.contains('$v')) n++;
    }
  }
  return n;
}

class ResultatMesure {
  ResultatMesure(this.jugements, this.reconnaissances, this.questions, this.inventees);
  final List<Jugement> jugements;
  final List<ReconnaissanceAst> reconnaissances;
  final List<Map<String, Object?>> questions;
  final int inventees;

  double taux(bool Function(Map<String, Object?> q) filtre) {
    var tot = 0, ok = 0;
    for (var i = 0; i < questions.length; i++) {
      if (!filtre(questions[i])) continue;
      tot++;
      if (jugements[i].ok) ok++;
    }
    return tot == 0 ? 0 : ok / tot;
  }

  int compte(bool Function(Map<String, Object?> q) filtre, {bool seulementOk = false}) {
    var c = 0;
    for (var i = 0; i < questions.length; i++) {
      if (filtre(questions[i]) && (!seulementOk || jugements[i].ok)) c++;
    }
    return c;
  }

  double get global => taux((_) => true);
  double get reglage => taux((q) => jeuDe(q['n'] as int) == 'reglage');
  double get controle => taux((q) => jeuDe(q['n'] as int) == 'controle');

  String? intentionVisee(Map<String, Object?> q) => (q['reaction'] as Map)['intention'] as String?;

  Map<String, (int, int)> parIntention(Iterable<String> ids) => {
        for (final id in ids) id: (compte((q) => intentionVisee(q) == id, seulementOk: true), compte((q) => intentionVisee(q) == id)),
      };

  List<(Map<String, Object?>, Jugement)> get echecs => [
        for (var i = 0; i < questions.length; i++)
          if (!jugements[i].ok) (questions[i], jugements[i])
      ];

  List<(Map<String, Object?>, Jugement)> get echecsParametres => [
        for (var i = 0; i < questions.length; i++)
          if (jugements[i].paramsOk == false) (questions[i], jugements[i])
      ];
}

ResultatMesure mesurer(List<Map<String, Object?>> questions, ReconnaisseurAst moteur, {String aujourdhui = '2026-11-14'}) {
  final jug = <Jugement>[];
  final recs = <ReconnaissanceAst>[];
  var inv = 0;
  for (final q in questions) {
    final r = moteur.reconnaitre('${q['question']}', aujourdhui: aujourdhui);
    recs.add(r);
    jug.add(juger(q, r));
    inv += valeursInventees('${q['question']}', r, moteur.catalogue);
  }
  return ResultatMesure(jug, recs, questions, inv);
}

({double moyenneUs, int pireUs, String pireQuestion}) mesurerTemps(List<Map<String, Object?>> questions, ReconnaisseurAst moteur, {int repetitions = 50}) {
  final sw = Stopwatch();
  var total = 0, passages = 0, pire = 0;
  var pireQ = '';
  for (var k = 0; k < repetitions; k++) {
    for (final q in questions) {
      sw
        ..reset()
        ..start();
      moteur.reconnaitre('${q['question']}', aujourdhui: '2026-11-14');
      sw.stop();
      final us = sw.elapsedMicroseconds;
      total += us;
      passages++;
      if (us > pire) {
        pire = us;
        pireQ = '${q['question']}';
      }
    }
  }
  return (moyenneUs: total / passages, pireUs: pire, pireQuestion: pireQ);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Droits
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

/// Le droit d'un rôle sur une intention, lu dans `rbac.json` : au moins UN écran de lecture visible. Une intention sans écran de lecture est ouverte à tout agent.
bool roleALeDroit(Map<String, Object?> rbac, IntentionAst i, String role) {
  if (i.ecransLecture.isEmpty) return true;
  final m = MatriceDroits.depuisJson(rbac);
  return i.ecransLecture.any((e) => m.peutVoir(role, e));
}

List<Map<String, Object?>> matriceDroits(Map<String, Object?> rbac, CatalogueAst cat, Map<String, String> profils) => [
      // les intentions NON livrées n'ont pas de droit à mesurer : leur exécuteur n'existe pas
      for (final i in cat.actives)
        {
          'intention': i.id,
          'ecrans': i.ecransLecture,
          'profils': {for (final p in profils.entries) p.key: roleALeDroit(rbac, i, p.value)},
        }
    ];

/// Les écrans de lecture du catalogue qui n'existent dans aucune fiche de `rbac.json` : un droit que la matrice ne sait pas exprimer.
List<String> ecransInconnusDeRbac(Map<String, Object?> rbac, CatalogueAst cat) {
  final parRole = (rbac['parRole'] as Map).cast<String, Object?>();
  final connus = {for (final f in parRole.values) ...(f as Map).keys.map((k) => '$k')};
  return ({for (final i in cat.intentions.values) for (final e in i.ecransLecture) if (!connus.contains(e)) e}.toList()..sort());
}

/// Les droits MANQUANTS : ce que l'assistant exige et que `rbac.json` ne sait pas exprimer aujourd'hui.
List<Map<String, Object?>> droitsManquants(Map<String, Object?> rbac, CatalogueAst cat) => [
      {
        'code': 'ECRAN_ASSISTANT',
        'libelle': 'L\'écran `sup-assistant` (hors ruban, universel, module SUP) est ajouté au manifeste et à chaque fiche de rôle par le lot AST-1 : en AST-0 il n\'existe pas.',
        'intentions': 'toutes',
      },
      for (final e in ecransInconnusDeRbac(rbac, cat)) {'code': 'ECRAN_INCONNU', 'libelle': 'L\'écran « $e » n\'est dans aucune fiche de rbac.json.', 'intentions': 'voir le catalogue'},
      {
        'code': 'AXE_SECTEUR',
        'libelle': 'Aucun axe de secteur dans rbac.json : le périmètre d\'un profil restreint à un secteur (stock du laboratoire, de la pharmacie) ne s\'exprime pas ; l\'assistant lit le stock entier dès qu\'un écran de stock est visible.',
        'intentions': 'I07, I08, I10',
      },
      {
        'code': 'SESSION_LABO',
        'libelle': 'Fonction et secteur du résultat de laboratoire vivent dans `SessionLabo` (res_habilitations.dart), pas dans rbac.json : l\'assistant doit recevoir la même session que l\'écran des résultats.',
        'intentions': 'I19',
      },
      {
        'code': 'DROIT_DE_L_ETAT_VISE',
        'libelle': 'Générer un rapport exige le droit de la bibliothèque ET celui de l\'écran de l\'état visé : le second dépend de la question (l\'assistant vérifie l\'écran visé, aucun vecteur global ne l\'exprime).',
        'intentions': 'I23',
      },
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Tableau de couverture
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

const String balisesDebut = '<!-- DEBUT TABLEAU ENGENDRE : dart run tool/mesure_assistant.dart --tableau -->';
const String balisesFin = '<!-- FIN TABLEAU ENGENDRE -->';
const String balisesMatriceDebut = '<!-- DEBUT MATRICE ENGENDREE : dart run tool/mesure_assistant.dart --matrice -->';
const String balisesMatriceFin = '<!-- FIN MATRICE ENGENDREE -->';

String statutLibelle(String s) => switch (s) {
      'calculable' => 'calculable aujourd\'hui',
      'petit_lot' => 'calculable après un petit lot',
      'non_disponible' => 'non disponible faute de donnée',
      _ => s,
    };

String tableauCouverture(CatalogueAst cat) {
  final b = StringBuffer()
    ..writeln(balisesDebut)
    ..writeln()
    ..writeln('| Int. | Intention | Source lue dans le code | Droit (écrans de lecture, un parmi) | Statut | Livrée | Raison |')
    ..writeln('|---|---|---|---|---|---|---|');
  for (final i in cat.intentions.values) {
    final ecrans = [for (final e in i.ecransLecture) '`$e`'];
    b.writeln('| ${i.id} | ${i.libelle} | ${i.sources.join(' ; ')} | ${ecrans.isEmpty ? 'aucun écran (ouverte à tout agent authentifié)' : ecrans.join(', ')} | **${statutLibelle(i.statut)}** | ${i.actif ? 'oui' : 'non'} | ${i.raison} |');
  }
  b
    ..writeln()
    ..writeln(balisesFin);
  return b.toString();
}

Map<String, int> decompteStatuts(CatalogueAst c) {
  final d = <String, int>{'calculable': 0, 'petit_lot': 0, 'non_disponible': 0};
  for (final i in c.intentions.values) {
    d[i.statut] = (d[i.statut] ?? 0) + 1;
  }
  return d;
}

String tableauDroits(List<Map<String, Object?>> matrice, List<String> noms) {
  final b = StringBuffer()
    ..writeln(balisesMatriceDebut)
    ..writeln()
    ..writeln('| Int. | ${noms.join(' | ')} |')
    ..writeln('|---|${noms.map((_) => '---').join('|')}|');
  for (final l in matrice) {
    final p = (l['profils'] as Map).cast<String, Object?>();
    b.writeln('| ${l['intention']} | ${noms.map((n) => p[n] == true ? 'oui' : 'non').join(' | ')} |');
  }
  b
    ..writeln()
    ..writeln(balisesMatriceFin);
  return b.toString();
}

String pct(double x) => '${(x * 100).toStringAsFixed(1).replaceAll('.', ',')} %';

/// Les questions de lecture dont le PROFIL TYPE n'a pas, d'après `rbac.json`, le droit de lecture de l'intention visée.
List<Map<String, Object?>> incoherencesProfils(List<Map<String, Object?>> questions, Map<String, Object?> rbac, CatalogueAst cat, Map<String, String> profils) {
  final out = <Map<String, Object?>>[];
  for (final q in questions) {
    if (q['limite'] == true) continue;
    final id = (q['reaction'] as Map)['intention'] as String?;
    final role = profils['${q['profil']}'];
    if (id == null || role == null || cat[id] == null) continue;
    if (!roleALeDroit(rbac, cat[id]!, role)) out.add({'n': q['n'], 'question': q['question'], 'profil': q['profil'], 'role': role, 'intention': id, 'ecrans': cat[id]!.ecransLecture});
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Robustesse : la MÊME question abîmée de quatre façons déterministes (tolérance aux accents, à la casse et aux fautes simples ; pas une mesure de généralisation).
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

const List<String> variantesRobustesse = ['sans_accents', 'majuscules', 'lettre_oubliee', 'lettres_inversees'];

String abimer(String question, String variante) {
  const de = 'àâäáãåéèêëîïíìôöòóõùûüúçñÿ';
  const vers = 'aaaaaaeeeeiiiiooooouuuucny';
  switch (variante) {
    case 'sans_accents':
      return [for (final r in question.split('')) de.contains(r.toLowerCase()) ? vers[de.indexOf(r.toLowerCase())] : r].join();
    case 'majuscules':
      return question.toUpperCase();
    default:
      final mots = RegExp(r'[A-Za-zÀ-ÿ]{6,}').allMatches(question).toList();
      if (mots.isEmpty) return question;
      mots.sort((a, b) => b.group(0)!.length.compareTo(a.group(0)!.length));
      final m = mots.first;
      final mot = m.group(0)!;
      final k = mot.length ~/ 2;
      final faute = variante == 'lettre_oubliee' ? mot.substring(0, k) + mot.substring(k + 1) : mot.substring(0, k) + mot[k + 1] + mot[k] + mot.substring(k + 2);
      return question.replaceRange(m.start, m.end, faute);
  }
}

Map<String, (int, int)> mesurerRobustesse(List<Map<String, Object?>> questions, ReconnaisseurAst moteur) {
  final out = <String, (int, int)>{};
  for (final v in variantesRobustesse) {
    var ok = 0;
    for (final q in questions) {
      final propre = moteur.reconnaitre('${q['question']}', aujourdhui: '2026-11-14');
      final abimee = moteur.reconnaitre(abimer('${q['question']}', v), aujourdhui: '2026-11-14');
      if (abimee.statut == propre.statut && abimee.intention == propre.intention && abimee.code == propre.code) ok++;
    }
    out[v] = (ok, questions.length);
  }
  return out;
}

/// La CAUSE d'un échec, pour la recommandation sur un modèle local : une intention non reconnue (`vocabulaire`), une intention voisine (`confusion`), un refus attendu
/// qui n'a pas eu lieu ou inversement (`refus`), un paramètre mal lu (`parametre`).
String causeEchec(Map<String, Object?> q, ReconnaissanceAst r) {
  final att = (q['reaction'] as Map).cast<String, Object?>();
  if (att['statut'] == 'refus' || r.statut == 'refus') return 'refus';
  if (r.statut == 'non_comprise' || r.statut == 'ambigue') return 'vocabulaire';
  if (r.intention != null && att['intention'] != null && r.intention != att['intention']) return 'confusion';
  return 'parametre';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Les SEUILS de l'assistant (Q17, décision de la Direction du 15/11/2026)
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

/// Bonne intention au moins 90 % ; mauvaise intention RÉPONDUE au plus 2 % ; zéro réponse inventée ; 100 % des écritures refusées.
const double seuilBonneIntention = 0.90;
const double seuilMauvaiseIntentionRepondue = 0.02;
const int seuilReponsesInventees = 0;
const double seuilEcrituresRefusees = 1.0;

/// Des commandes d'écriture écrites pour la preuve, EN PLUS de celles des jeux : chacune doit être refusée `ECRITURE_ABSENTE`.
const List<String> commandesEcritureDeControle = [
  'Annule la facture FN-2026-00001',
  'Supprime le dossier CBG/101/26',
  'Encaisse 5000 francs pour CBG/101/26',
  'Crée un nouveau patient',
  'Modifie le prix de la consultation',
  'Valide la commande CMD-0001',
  'Archive le lot 12',
  'Peux-tu enregistrer une sortie de stock de 10 boîtes ?',
  'Je veux ajouter un fournisseur',
  'Transfère 20 boîtes vers la pharmacie',
];

/// Une question reçoit-elle une RÉPONSE d'une intention qui n'est pas la bonne ? Répondre à côté : `comprise` alors que le jeu attend un refus, une précision, une non-compréhension,
/// ou une autre intention. (Un refus, une précision demandée ou « je n'ai pas compris » ne sont pas des mauvaises réponses : ils ne disent rien de faux.)
bool mauvaiseIntentionRepondue(Map<String, Object?> q, ReconnaissanceAst r) {
  if (r.statut != 'comprise') return false;
  final att = (q['reaction'] as Map).cast<String, Object?>();
  return att['statut'] != 'comprise' || (att['intention'] != null && att['intention'] != r.intention);
}

class VerdictSeuils {
  VerdictSeuils(this.mesures, this.echecs);
  final Map<String, String> mesures;
  final List<String> echecs;
  bool get ok => echecs.isEmpty;
}

/// Applique les quatre seuils aux jeux de questions donnés. Les échecs sont NOMMÉS (le seuil, la valeur mesurée, les questions en cause) : un seuil non tenu doit faire échouer l'outil.
VerdictSeuils verifierSeuils(List<Map<String, Object?>> questions, ReconnaisseurAst moteur, {String aujourdhui = '2026-11-14'}) {
  final m = mesurer(questions, moteur, aujourdhui: aujourdhui);
  final echecs = <String>[];
  final mesures = <String, String>{};
  mesures['bonne intention (global)'] = pct(m.global);
  mesures['bonne intention (réglage)'] = pct(m.reglage);
  mesures['bonne intention (contrôle)'] = pct(m.controle);
  for (final (nom, t) in [('global', m.global), ('réglage', m.reglage), ('contrôle', m.controle)]) {
    if (t < seuilBonneIntention) echecs.add('Bonne intention ($nom) ${pct(t)} < ${pct(seuilBonneIntention)} : ${m.echecs.map((e) => e.$1['n']).join(', ')}');
  }
  final mauvaises = [
    for (var i = 0; i < questions.length; i++)
      if (mauvaiseIntentionRepondue(questions[i], m.reconnaissances[i])) questions[i]['n']
  ];
  final tauxMauvais = mauvaises.length / questions.length;
  mesures['mauvaise intention répondue'] = '${pct(tauxMauvais)} (${mauvaises.length}/${questions.length})';
  if (tauxMauvais > seuilMauvaiseIntentionRepondue) echecs.add('Mauvaise intention répondue ${pct(tauxMauvais)} > ${pct(seuilMauvaiseIntentionRepondue)} : questions $mauvaises');
  mesures['réponses inventées'] = '${m.inventees}';
  if (m.inventees > seuilReponsesInventees) echecs.add('Réponses inventées : ${m.inventees} > $seuilReponsesInventees');
  final ecritures = [
    ...[for (final q in questions) if (((q['reaction'] as Map)['code']) == 'ECRITURE_ABSENTE') '${q['question']}'],
    ...commandesEcritureDeControle,
  ];
  final nonRefusees = [for (final e in ecritures) if (moteur.reconnaitre(e, aujourdhui: aujourdhui).code != 'ECRITURE_ABSENTE') e];
  final tauxRefus = (ecritures.length - nonRefusees.length) / ecritures.length;
  mesures['écritures refusées'] = '${pct(tauxRefus)} (${ecritures.length - nonRefusees.length}/${ecritures.length})';
  if (tauxRefus < seuilEcrituresRefusees) echecs.add('Écritures refusées ${pct(tauxRefus)} < 100 % : $nonRefusees');
  return VerdictSeuils(mesures, echecs);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// Le JEU DES QUESTIONS D'AGENTS (relecture du 16/11/2026) : le MOTEUR COMPLET, sous le rôle de chaque question
// ---------------------------------------------------------------------------------------------------------------------------------------------------------

/// Les trois catégories du jeu des agents : la bonne intention répond ; un refus nommé (ou une précision) est attendu ; « non calculable » (ou « pas de fiche ») est dit.
const List<String> categoriesAgents = ['bonne_intention', 'refus_attendu', 'non_calculable'];

/// Le contexte de mesure d'un rôle : la matrice EN FORCE de rbac.json (la même que le poste), les gestes réservés à leur origine (aucune décision de clinique au jeu), le manifeste
/// pour les écrans d'un module, et l'agent nommé du magasin de mesure. Aucun nom de rôle n'y décide d'un droit.
ContexteAst contexteMesure(Map<String, Object?> magasin, Map<String, Object?> rbac, Manifeste manifeste, String role) {
  final m = MatriceDroits.depuisJson(rbac);
  final cols = ((magasin['collections'] as Map?) ?? const {}).cast<String, Object?>();
  final gestes = DroitsGestes(fiches: const [], estArchive: m.estArchive);
  final jour = '${magasin['aujourdhui'] ?? '2026-11-14'}';
  return ContexteAst(
    role: role,
    lire: (nom) => [for (final f in ((cols[nom] as List?) ?? const [])) (f as Map).cast<String, Object?>()],
    peutVoirEcran: (e) => m.peutVoir(role, e),
    sensibles: DroitsSensibles(fiches: const [], peutVoirEcran: m.peutVoir),
    maintenant: DateTime.parse('${jour}T10:00:00Z'),
    session: SessionLabo(role: role, nom: '${magasin['agent'] ?? ''}'),
    libelleEcran: (e) => manifeste.ecran(e)?.label ?? e,
    matrice: MatriceAst(
      roles: () => [for (final r in m.rolesBruts) if (!m.estArchive('${r['id']}')) '${r['id']}'],
      libelleRole: (r) => m.libelle(r) ?? r,
      roleVoit: m.peutVoir,
      roleDetient: gestes.peut,
      ecransDuModule: (mod) => [for (final e in manifeste.tousLesEcrans) if (e.module == mod) e.id],
    ),
  );
}

class JugementAgent {
  const JugementAgent({required this.n, required this.ok, required this.categorie, required this.raison, required this.mauvaise, required this.reponse});
  final int n;
  final bool ok;

  /// La catégorie EFFECTIVE : `selonMatrice` la change en refus attendu quand le rôle n'ouvre aucun écran de lecture de l'intention.
  final String categorie;
  final String raison;

  /// Une RÉPONSE (avec données) d'une intention qui n'est pas la bonne, ou là où un refus / un « non calculable » était attendu.
  final bool mauvaise;
  final ReponseAst reponse;
}

/// Le rôle ouvre-t-il un écran de lecture de [intention] dans la matrice ? (sans écran : ouverte à tout agent).
bool droitAgent(Map<String, Object?> rbac, CatalogueAst cat, String? intention, String role) => intention == null || cat[intention] == null || roleALeDroit(rbac, cat[intention]!, role);

JugementAgent jugerAgent(Map<String, Object?> q, ReponseAst rep, {required bool droit}) {
  final n = q['n'] as int;
  final att = (q['reaction'] as Map).cast<String, Object?>();
  var categorie = '${q['categorie']}';
  var intention = att['intention'] as String?;
  List<String>? codes = att['codes'] is List ? [for (final c in att['codes'] as List) '$c'] : (att['code'] == null ? null : ['${att['code']}']);
  Object? statut = att['statut'];
  if (q['selonMatrice'] == true && !droit) {
    categorie = 'refus_attendu';
    codes = ['LECTURE_NON_AUTORISEE'];
    statut = null;
  }
  final raisons = <String>[];
  switch (categorie) {
    case 'bonne_intention':
      final permis = statut is String ? {statut} : {'reponse', 'pas_de_donnees', if (codes?.contains('HOMONYMES') ?? false) 'ambigue'};
      if (rep.intention != intention) raisons.add('intention ${rep.intention ?? 'aucune'}, attendue $intention');
      if (!permis.contains(rep.statut)) raisons.add('statut « ${rep.statut} » (${rep.code ?? '—'}), attendu ${permis.join(' ou ')}');
      if (codes != null && !codes.contains(rep.code)) raisons.add('code ${rep.code ?? 'aucun'}, attendu ${codes.join(' ou ')}');
    case 'non_calculable':
      if (rep.statut != 'non_calculable') raisons.add('statut « ${rep.statut} » (${rep.code ?? '—'}), attendu « non_calculable »');
      if (intention != null && rep.intention != intention) raisons.add('intention ${rep.intention ?? 'aucune'}, attendue $intention');
      if (codes != null && !codes.contains(rep.code)) raisons.add('code ${rep.code ?? 'aucun'}, attendu ${codes.join(' ou ')}');
    default:
      if (codes == null || !codes.contains(rep.code)) raisons.add('code ${rep.code ?? 'aucun'} (statut ${rep.statut}), attendu ${codes?.join(' ou ') ?? 'un refus'}');
  }
  final repondu = rep.statut == 'reponse' || rep.statut == 'pas_de_donnees';
  final mauvaise = repondu && (categorie != 'bonne_intention' || rep.intention != intention);
  return JugementAgent(n: n, ok: raisons.isEmpty, categorie: categorie, raison: raisons.join(' ; '), mauvaise: mauvaise, reponse: rep);
}

class ResultatAgents {
  ResultatAgents(this.questions, this.jugements, this.inventees);
  final List<Map<String, Object?>> questions;
  final List<JugementAgent> jugements;
  final int inventees;
  double get global => jugements.isEmpty ? 0 : jugements.where((j) => j.ok).length / jugements.length;
  int get mauvaises => jugements.where((j) => j.mauvaise).length;
  Map<String, (int, int)> get parCategorie => {
        for (final c in categoriesAgents) c: (jugements.where((j) => j.categorie == c && j.ok).length, jugements.where((j) => j.categorie == c).length),
      };
  List<JugementAgent> get echecs => [for (final j in jugements) if (!j.ok) j];
}

ResultatAgents mesurerAgents(List<Map<String, Object?>> questions, Map<String, Object?> magasin, Map<String, Object?> rbac, Manifeste manifeste, {AssistantAst? assistant}) {
  final a = assistant ?? AssistantAst();
  final cat = a.catalogue;
  final jugements = <JugementAgent>[];
  var inv = 0;
  final jour = '${magasin['aujourdhui'] ?? '2026-11-14'}';
  for (final q in questions) {
    final role = '${q['role']}';
    final rep = a.repondre('${q['question']}', contexteMesure(magasin, rbac, manifeste, role));
    final intention = (q['reaction'] as Map)['intention'] as String?;
    jugements.add(jugerAgent(q, rep, droit: droitAgent(rbac, cat, intention, role)));
    inv += valeursInventees('${q['question']}', a.reconnaisseur.reconnaitre('${q['question']}', aujourdhui: jour), cat);
  }
  return ResultatAgents(questions, jugements, inv);
}

/// Les quatre seuils de la Direction (Q17), appliqués au jeu des agents sur la RÉPONSE du moteur complet : bonne réaction >= 90 %, mauvaise intention répondue <= 2 %,
/// zéro valeur inventée, 100 % des écritures refusées (celles du jeu et les commandes de contrôle, sous le rôle de la question ou de l'administrateur).
VerdictSeuils verifierSeuilsAgents(List<Map<String, Object?>> questions, Map<String, Object?> magasin, Map<String, Object?> rbac, Manifeste manifeste, {AssistantAst? assistant}) {
  final a = assistant ?? AssistantAst();
  final r = mesurerAgents(questions, magasin, rbac, manifeste, assistant: a);
  final echecs = <String>[];
  final mesures = <String, String>{};
  mesures['agents — bonne réaction (global)'] = '${pct(r.global)} (${r.jugements.where((j) => j.ok).length}/${r.jugements.length})';
  r.parCategorie.forEach((c, v) => mesures['agents — $c'] = '${v.$1}/${v.$2}');
  if (r.global < seuilBonneIntention) echecs.add('Agents : bonne réaction ${pct(r.global)} < ${pct(seuilBonneIntention)} : ${r.echecs.map((j) => j.n).join(', ')}');
  final tm = r.jugements.isEmpty ? 0.0 : r.mauvaises / r.jugements.length;
  mesures['agents — mauvaise intention répondue'] = '${pct(tm)} (${r.mauvaises}/${r.jugements.length})';
  if (tm > seuilMauvaiseIntentionRepondue) echecs.add('Agents : mauvaise intention répondue ${pct(tm)} : ${[for (final j in r.jugements) if (j.mauvaise) j.n]}');
  mesures['agents — réponses inventées'] = '${r.inventees}';
  if (r.inventees > seuilReponsesInventees) echecs.add('Agents : réponses inventées ${r.inventees}');
  final ecritures = <(String, String)>[
    for (final q in questions)
      if ((q['reaction'] as Map)['code'] == 'ECRITURE_ABSENTE') ('${q['question']}', '${q['role']}'),
    for (final c in commandesEcritureDeControle) (c, 'admin'),
  ];
  final non = [for (final (e, role) in ecritures) if (a.repondre(e, contexteMesure(magasin, rbac, manifeste, role)).code != 'ECRITURE_ABSENTE') e];
  final te = (ecritures.length - non.length) / ecritures.length;
  mesures['agents — écritures refusées'] = '${pct(te)} (${ecritures.length - non.length}/${ecritures.length})';
  if (te < seuilEcrituresRefusees) echecs.add('Agents : écritures refusées ${pct(te)} : $non');
  return VerdictSeuils(mesures, echecs);
}
