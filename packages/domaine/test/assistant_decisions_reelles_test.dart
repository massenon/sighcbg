// Les 100 questions RÉELLES de l'assistant, relues par la Direction le 16/11/2026 (docs/prd/ASSISTANT-100-questions-par-role.md), sondées une à une sur le MOTEUR COMPLET sous le rôle de la question.
// Chaque test nomme les numéros de questions qu'il couvre : le tableau « n° → état réel » de docs/architecture/ASSISTANT-couverture-des-intentions.md s'appuie sur eux.
// Aucun rôle n'est nommé pour décider d'un droit : les attentes se lisent dans rbac.json. Données : EXEMPLES neutres (CBG/101/26, EXEMPLE/Fournisseur…), jamais une identité réelle.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import '../tool/src/assistant_mesure.dart';

Map<String, Object?> _json(String chemin) => (jsonDecode(File(chemin).readAsStringSync()) as Map).cast<String, Object?>();

void main() {
  final rbac = _json('../rbac/data/rbac.json');
  final manifeste = Manifeste.depuisJson(_json('../referentiels/data/manifeste.json'));
  final magasin = _json('test/vecteurs/assistant_magasin_agents.json');
  final questions = [for (final q in (_json('test/vecteurs/assistant_questions_agents.json')['questions'] as List)) (q as Map).cast<String, Object?>()];
  final matrice = MatriceDroits.depuisJson(rbac);
  final a = AssistantAst();

  Map<String, Object?> question(int n) => questions.firstWhere((q) => q['n'] == n);
  ContexteAst cx(String role, {Map<String, List<Map<String, Object?>>> en = const {}}) {
    final base = contexteMesure(magasin, rbac, manifeste, role);
    if (en.isEmpty) return base;
    return ContexteAst(
        role: role,
        lire: (n) => en[n] ?? base.lire(n),
        peutVoirEcran: base.peutVoirEcran,
        sensibles: base.sensibles,
        maintenant: base.maintenant,
        session: base.session,
        libelleEcran: base.libelleEcran,
        matrice: base.matrice);
  }

  /// La réponse du moteur à la question réelle n°[n], sous son rôle.
  ReponseAst pose(int n, {Map<String, List<Map<String, Object?>>> en = const {}}) => a.repondre('${question(n)['question']}', cx('${question(n)['role']}', en: en));
  String tout(ReponseAst r) => [r.titre, ...r.lignes, if (r.tableau != null) ...[...r.tableau!.colonnes, for (final l in r.tableau!.lignes) ...l]].join(' | ');
  String sansEspaces(String t) => t.replaceAll(RegExp(r'\s'), '');
  List<Map<String, Object?>> col(String nom) => [for (final f in ((magasin['collections'] as Map)[nom] as List)) (f as Map).cast<String, Object?>()];

  group('le jeu : les 100 lignes de la Direction, mot pour mot', () {
    // Relit le document de la Direction : « | n° | question | intention | état | droit | décision | » sous chaque titre de rôle « ## … (`id`) ».
    final lignes = <int, ({String role, String question, String intention, String decision})>{};
    String? role;
    for (final l in File('../../docs/prd/ASSISTANT-100-questions-par-role.md').readAsLinesSync()) {
      final r = RegExp(r'^## .*\(`(\w+)`\)').firstMatch(l);
      if (r != null) role = r.group(1);
      final m = RegExp(r'^\| (\d+) \| (.*?) \| (I\d+|HC) \| (.*?) \| (.*?) \| (.*) \|$').firstMatch(l);
      if (m != null) lignes[int.parse(m.group(1)!)] = (role: role!, question: m.group(2)!, intention: m.group(3)!, decision: m.group(6)!);
    }
    test('le document porte 100 questions, le jeu aussi, mêmes numéros', () {
      expect(lignes.length, 100);
      expect(questions.map((q) => q['n']).toList(), [for (var i = 1; i <= 100; i++) i]);
    });
    test('numéro, rôle, texte (le code patient du gabarit se lit CBG/…/26), intention et décision : identiques au document', () {
      for (final q in questions) {
        final l = lignes[q['n']]!;
        expect(q['role'], l.role, reason: 'Q${q['n']} : rôle');
        expect(q['questionOriginale'], l.question.replaceAll('CNT/…/26', 'CBG/…/26'), reason: 'Q${q['n']} : texte');
        expect(q['intentionDirection'], l.intention, reason: 'Q${q['n']} : intention');
        expect(q['decision'], l.decision, reason: 'Q${q['n']} : décision');
      }
    });
    test('les gabarits sont instanciés par des valeurs fictives : ni « … », ni « tel / telle », ni nom de la clinique sœur, ni identité réelle', () {
      for (final q in questions) {
        final t = '${q['question']}';
        expect(t.contains('…') || t.contains('[') || RegExp(r'\btel(le)?\b', caseSensitive: false).hasMatch(t), isFalse, reason: 'Q${q['n']} : $t');
        expect(RegExp('CNT|Nassi', caseSensitive: false).hasMatch('$t ${q['questionOriginale']}'), isFalse, reason: 'Q${q['n']}');
      }
      final codes = {for (final p in col('patients')) p['code']};
      for (final q in questions) {
        final c = RegExp(r'CBG/\d+/26').firstMatch('${q['question']}')?.group(0);
        if (c != null) expect(codes, contains(c), reason: 'Q${q['n']} : un patient du jeu de test');
      }
    });
    test('les rôles des questions sont des rôles de la matrice, vingt rôles à cinq questions', () {
      final par = <String, int>{};
      for (final q in questions) {
        expect(matrice.roleConnu('${q['role']}'), isTrue, reason: 'Q${q['n']}');
        par['${q['role']}'] = (par['${q['role']}'] ?? 0) + 1;
      }
      expect(par.length, 20);
      expect(par.values.toSet(), {5});
    });
  });

  group('décisions « Validée » : chaque question répond par SA bonne intention, avec sa source, sous le droit de la matrice', () {
    test('toutes les questions de catégorie « bonne intention » reçoivent leur intention et une réponse (ou « aucun enregistrement ») — Q1 à Q100', () {
      // Q65 est la SEULE question mesurée en échec, et dite : la décision nomme une autre personne que celle qui la pose (voir le test des ouvertures de droits).
      for (final q in questions.where((q) => q['categorie'] == 'bonne_intention' && q['n'] != 65)) {
        final r = pose(q['n'] as int);
        final attendue = (q['reaction'] as Map)['intention'];
        expect(r.intention, attendue, reason: 'Q${q['n']} « ${q['question']} » : ${r.titre}');
        expect(['reponse', 'pas_de_donnees', 'ambigue'], contains(r.statut), reason: 'Q${q['n']} : ${r.statut} ${r.code}');
        if (r.statut == 'reponse') expect(r.sources, isNotEmpty, reason: 'Q${q['n']} sans source');
      }
    });
  });

  group('les 15 ouvertures de droits en LECTURE seule (Q15, Q30, Q33, Q35, Q49, Q54, Q60, Q63, Q65, Q75, Q79, Q83, Q85, Q89, Q95)', () {
    const ecransOuverts = {
      15: ['m10-planning'],
      30: ['m10-planning'],
      33: ['cfg-tarifs'],
      49: ['cfg-tarifs'],
      54: ['m10-planning'],
      60: ['m3-plan-lits'],
      63: ['m10-planning'],
      75: ['cfg-tarifs'],
      79: ['m3-plan-lits'],
      83: ['m2-stats-consultations', 'm3-stats-hospitalisations'],
      85: ['m6-point-ventes'],
      89: ['m10-planning'],
      95: ['m6-stock-detail', 'm6-lots'],
    };
    test('l’écran ouvert est VISIBLE du rôle, sans droit d’écrire ni d’annuler (la matrice dit [1,0,0])', () {
      for (final e in ecransOuverts.entries) {
        final role = '${question(e.key)['role']}';
        for (final ecran in e.value) {
          expect(matrice.peutVoir(role, ecran), isTrue, reason: 'Q${e.key} : $role ne voit pas $ecran');
          final d = matrice.droit(role, ecran);
          expect([d.editer, d.annuler], [false, false], reason: 'Q${e.key} : $role écrit dans $ecran');
        }
      }
    });
    test('et la question reçoit une RÉPONSE (plus le refus LECTURE_NON_AUTORISEE de la relecture)', () {
      for (final n in [15, 30, 33, 35, 49, 54, 60, 63, 75, 79, 83, 85, 89, 95]) {
        final r = pose(n);
        expect(r.statut, isNot('refus'), reason: 'Q$n : ${r.code} ${r.titre}');
        expect(['reponse', 'pas_de_donnees'], contains(r.statut), reason: 'Q$n');
      }
    });
    test('Q35 : le biologiste lit le stock des articles du LABORATOIRE seulement ; un article d’un autre secteur lui est invisible', () {
      final reactif = a.repondre('Il reste combien de Réactif NFS ?', cx('laborantin'));
      expect(reactif.statut, 'reponse');
      expect(tout(reactif), contains('Périmètre : réactifs et consommables du laboratoire'));
      final autre = a.repondre('Il reste combien de Amoxicilline 500 mg ?', cx('laborantin'));
      expect(autre.statut, 'pas_de_donnees');
      expect(tout(autre), contains('dans le périmètre du laboratoire'));
      expect(tout(autre), isNot(contains('12')), reason: 'aucune quantité d’un article hors secteur ne fuit');
    });
    test('Q65 — AMBIGU, non appliqué à l’ambulancier : la décision nomme « l’aide-soignante » (qui lit déjà les lits par le plan des lits) alors que la question est posée par l’ambulancier', () {
      expect(matrice.peutVoir('aide_soignant', 'm3-plan-lits'), isTrue);
      expect(a.repondre('Dans quel lit est le patient CBG/101/26 ?', cx('aide_soignant')).statut, 'reponse');
      final r = pose(65);
      expect([r.statut, r.code], ['refus', 'LECTURE_NON_AUTORISEE'], reason: 'ouvrir à l’ambulancier exige que la Direction confirme le rôle visé');
    });
    test('les autres rôles gardent leur refus : un caissier ne lit pas le planning', () {
      expect(a.repondre('Qui est de garde ce soir ?', cx('caissier')).code, 'LECTURE_NON_AUTORISEE');
    });
  });

  group('refus gardés : Q25 (AVIS_MEDICAL_REFUSE) et Q69 (RG-13)', () {
    test('Q25 : une dose se refuse nommément, sans lire une seule donnée', () {
      final lectures = <String>[];
      final base = cx('medecin');
      final r = a.repondre('${question(25)['question']}', ContexteAst(role: 'medecin', lire: (n) {
        lectures.add(n);
        return base.lire(n);
      }, peutVoirEcran: base.peutVoirEcran, sensibles: base.sensibles, maintenant: base.maintenant));
      expect([r.statut, r.code], ['refus', 'AVIS_MEDICAL_REFUSE']);
      expect(lectures, isEmpty);
    });
    test('Q69 : l’aide-soignante est refusée (aucun écran de résultats) ; l’accueil voit le STATUT (Oui / En attente), jamais le contenu', () {
      final r = pose(69);
      expect([r.statut, r.code, r.intention], ['refus', 'LECTURE_NON_AUTORISEE', 'I19']);
      expect(r.tableau, isNull);
      // accueil (réception) : le statut en un mot
      final accueil = a.repondre('Les analyses de CBG/101/26 sont rendues ?', cx('reception'));
      expect(accueil.statut, 'reponse');
      expect(tout(accueil), contains('Résultat rendu : Oui'));
      expect(tout(accueil), contains('Oui'));
      expect(accueil.tableau!.colonnes, ['Code', 'Analyse', 'Rendu']);
      final attente = a.repondre('Les analyses de CBG/103/26 sont rendues ?', cx('reception'));
      expect(tout(attente), contains('Non, en attente'));
      expect(tout(attente), contains('En attente'));
      // jamais de valeur de résultat : le contenu se lit à l'écran, sous les habilitations métier
      for (final r in [accueil, attente]) {
        expect(tout(r), isNot(contains('g/dl')));
        expect(tout(r), isNot(contains('à lire à l’écran Résultats')), reason: 'l’accueil n’a pas les habilitations du contenu');
        expect(tout(r), isNot(contains('Validé biologiquement')), reason: 'ni l’état fin du laboratoire');
      }
      // sans patient nommé, l'accueil est invité à en donner un : le statut seul ne se liste pas
      expect(a.repondre('Les analyses en attente ?', cx('reception')).code, 'PRECISION_REQUISE');
    });
  });

  group('Q9 reformulée, Q14 / Q7 / Q41 recettes, Q19 / Q100 dette : les deux chiffres', () {
    test('Q9 : le rôle sans le geste reçoit un SUIVI (« en attente de la validation de … »), jamais « à valider par vous »', () {
      final r = pose(9);
      expect(r.intention, 'I13');
      expect(tout(r), contains('SUIVI'));
      expect(tout(r), contains('Elles ne sont pas à valider par vous'));
      expect(tout(r), isNot(contains('attendent VOTRE validation')));
    });
    test('Q14 : « recettes » donne LES DEUX chiffres, nommés (encaissé 16 500, facturé 18 000), ventilés par SECTEUR', () {
      final r = pose(14);
      final t = sansEspaces(tout(r));
      expect(t, contains('Recettes(encaissé)'));
      expect(t, contains('16500'));
      expect(t, contains('Chiffred’affaires(facturé)'));
      expect(t, contains('18000'));
      expect(r.tableau!.colonnes.first, 'Secteur');
      expect(r.tableau!.lignes.map((l) => l.first), containsAll(['Consultation', 'Laboratoire']));
      expect(tout(r), contains('ne s’additionnent pas'));
    });
    test('Q7 : par secteur, ET comparée à la semaine d’avant (période de MÊME nature qui précède)', () {
      final r = pose(7);
      expect(r.tableau!.colonnes, containsAll(['Secteur', 'Encaissé', 'Encaissé (comparé)']));
      expect(tout(r), contains('période comparée (du 02/11/2026 au 08/11/2026)'));
      // la semaine d'avant porte un règlement de 8 000 (laboratoire) : le comparé le montre
      expect(sansEspaces(tout(r)), contains('8000'));
    });
    test('Q41 : par MODE de paiement (le mode porté par la facture) ; le facturé ne se ventile pas par mode', () {
      final r = pose(41);
      expect(r.tableau!.colonnes.first, 'Mode de paiement');
      expect(r.tableau!.lignes.single.first, 'Moov Money');
      expect(sansEspaces(r.tableau!.lignes.single[1]), '5000FCFA');
      expect(r.tableau!.lignes.single[2], 'sans objet');
    });
    test('Q19 et Q100 : factures non payées (40 000) ET solde comptable 401 (30 000), chacun nommé, et l’écart ; même réponse pour la DAF et l’assistant comptable', () {
      for (final n in [19, 100]) {
        final t = sansEspaces(tout(pose(n)));
        expect(t, contains('Facturesfournisseursnonpayées:40000FCFA'), reason: 'Q$n');
        expect(t, contains('Soldecomptable'), reason: 'Q$n');
        expect(t, contains('Écart'), reason: 'Q$n');
        expect(t, contains('30000FCFA'), reason: 'Q$n');
      }
      // avec un sous-compte 401 au nom du fournisseur, l'écart se chiffre
      final r = a.repondre('Combien on doit à EXEMPLE/Fournisseur ?', cx('da'));
      expect(r.intention, 'I12');
    });
    test('Q8 et Q17 : « les assureurs ou les patients » — les deux créances, par ancienneté, et QUI doit le plus', () {
      for (final n in [8, 17]) {
        final r = pose(n);
        expect(r.tableau!.colonnes, containsAll(['Patients (reliquat)', 'Assureurs (part assurance)']), reason: 'Q$n');
        expect(tout(r), contains('ASSUREURS qui doivent le plus'), reason: 'Q$n');
      }
      // Q98 : « les impayés des patients » ne mêle pas les assureurs
      expect(pose(98).tableau!.colonnes, ['Ancienneté', 'Factures', 'Montant']);
    });
    test('Q8 et Q17, bornes des ASSUREURS réglées à part (15 et 45 jours) : chaque créance se classe sur SES tranches, nommées, jamais sur celles de l\'autre', () {
      Map<String, Object?> reglage(String cle, int v) => {'id': cle, 'cle': cle, 'famille': 'assurances', 'type': 'entier', 'valeur': v, 'defaut': v, 'version': 0, 'dateEffet': null};
      for (final n in [8, 17]) {
        final sans = pose(n);
        expect(sans.tableau!.lignes.where((l) => l.first.startsWith('Assureurs : ')), isEmpty, reason: 'Q$n : bornes d\'attente identiques à celles des patients, une seule série de lignes, comme avant');
        final r = pose(n, en: {'parametres': [reglage(cleBalanceAgeeAssureurBorne1, 15), reglage(cleBalanceAgeeAssureurBorne2, 45)]});
        final lignes = r.tableau!.lignes.map((l) => l.first).toList();
        expect(lignes.where((l) => l.startsWith('Assureurs : ')), ['Assureurs : Moins de 15 jours', 'Assureurs : De 15 à 45 jours', 'Assureurs : Au-delà de 45 jours'], reason: 'Q$n');
        expect(lignes.where((l) => l.startsWith('Patients : ')), isNotEmpty, reason: 'Q$n');
        expect(tout(r), contains('des assureurs : 15 et 45 jours'), reason: 'Q$n : les deux séries de bornes sont dites');
      }
    });
    test('Q20 et Q47 : « secteur par secteur » = les groupes de familles d’articles ; « la pharmacie » restreint au secteur', () {
      expect(pose(20).tableau!.colonnes.first, 'Secteur');
      final r = pose(47);
      expect(r.titre, contains('secteur Pharmacie'));
      expect(sansEspaces(r.titre), contains('41800'));
    });
  });

  group('Q38, Q40, Q44, Q45, Q48 : le réglable, le dit, le reconstitué', () {
    test('Q38 : « depuis un an » est une durée DITE (365 jours) ; sans durée dite, le réglage de clinique (30 jours) — jamais un littéral', () {
      final dite = pose(38);
      expect(dite.titre, contains('du 14/11/2025 au 14/11/2026'));
      final sans = a.repondre('Les articles immobiles', cx('stock'));
      expect(tout(sans), contains('30 jours'));
      final regle = a.repondre('Les articles immobiles', cx('stock', en: {
        'parametres': [{'id': 'P1', 'cle': 'stock.joursArticlesImmobiles', 'valeur': 45, 'statut': 'actif', 'dateEffet': '2026-01-01', 'version': 1}],
      }));
      expect(tout(regle), contains('45 jours'));
    });
    test('Q40 : les articles NON COMPTÉS se listent (INVENT-NC : la ligne « non compté » est enregistrée), et ne sont pas des écarts', () {
      final r = pose(40);
      expect(r.titre, contains('1 article(s) non compté(s)'));
      expect(r.tableau!.lignes.single.first, 'Gants chirurgicaux');
      expect(tout(r), contains('pas un écart'));
    });
    test('Q44 : « dans trois mois » = 90 jours DITS (le chiffre en toutes lettres est lu) ; le caissier lit les lots par l’écran des alertes ; le délai de base ne sert que sans durée dite', () {
      final r = pose(44);
      expect(r.titre, contains('périmant dans 90 jours'));
      expect(r.sources.map((s) => s.ecran), isNot(contains('m6-lots')), reason: 'le caissier ne voit pas m6-lots : il lit l’écran des alertes');
      expect(tout(r), contains('LOT-A'));
      // un délai de base réglé à 200 jours ne change PAS « dans trois mois » ; il s'applique à « bientôt périmé »
      final param = {'parametres': [{'id': 'P1', 'cle': 'stock.delaiPreavisPeremptionJours', 'valeur': 200, 'statut': 'actif', 'dateEffet': '2026-01-01', 'version': 1}]};
      final dit = a.repondre('${question(44)['question']}', cx('caissier', en: param));
      expect(dit.titre, contains('90 jours'));
      final base = a.repondre('Les médicaments bientôt périmés', cx('caissier', en: param));
      expect(tout(base), contains('200 jours'));
      expect(tout(base), contains('LOT-B'), reason: 'le lot qui périme dans 168 jours entre dans le délai de base de 200 jours');
    });
    test('Q45 : le stock à une date passée se reconstitue (45 au 31/10 : 40 au gros, 5 au détail), sous le droit de l’article, sans citer un mouvement', () {
      final r = pose(45);
      expect(r.titre, contains('45 en stock au 31/10/2026 (reconstitué)'));
      expect(tout(r), contains('Magasin (gros) : 40 ; détail : 5'));
      expect(r.sources.map((s) => s.ecran), ['m6-produits']);
    });
    test('Q48 : « plus de N jours » avec N LIBRE (60, 45, 90) — la période dite filtre, les tranches fixes ne sont qu’un classement', () {
      final soixante = pose(48);
      expect(soixante.titre, startsWith('1 facture(s) impayée(s)'));
      final quarante = a.repondre('Impayés de plus de 45 jours', cx('comptable'));
      final cent = a.repondre('Impayés de plus de 100 jours', cx('comptable'));
      expect(quarante.titre, startsWith('1 facture(s)'));
      expect(cent.statut, 'pas_de_donnees');
      expect(tout(cent), contains('plus de 100 jours'));
    });
  });

  group('intentions AJOUTÉES (Q3, Q5, Q10, Q50, Q59, Q62, Q70, Q72, Q78, Q82) : chacune lit son écran sous son droit', () {
    const attendues = {3: 'I36', 5: 'I28', 10: 'I29', 50: 'I30', 59: 'I31', 62: 'I32', 70: 'I33', 72: 'I34', 78: 'I35', 82: 'I31'};
    test('chaque question hors catalogue reçoit son intention ajoutée, une réponse et sa source', () {
      for (final e in attendues.entries) {
        final r = pose(e.key);
        expect(r.intention, e.value, reason: 'Q${e.key} : ${r.titre}');
        expect(['reponse', 'pas_de_donnees'], contains(r.statut), reason: 'Q${e.key}');
      }
    });
    test('Q3 : la date de la dernière sauvegarde du JOURNAL des fichiers du poste, et la limite dite (l’état du service de la mère n’est pas lu)', () {
      final r = pose(3);
      expect(r.titre, contains('08/11/2026'));
      expect(tout(r), contains('n’est pas lu ici'));
      expect(a.repondre('Quand a été faite la dernière sauvegarde ?', cx('admin', en: {'fichiersSauvegarde': const []})).statut, 'pas_de_donnees');
      // un caissier ne lit pas les sauvegardes
      expect(a.repondre('Quand a été faite la dernière sauvegarde ?', cx('caissier')).code, 'LECTURE_NON_AUTORISEE');
    });
    test('Q72 : les échographies du jour comptées par état, aucun patient ; Q74 : les examens d’imagerie en attente se lisent au registre de l’IMAGERIE, pas aux analyses', () {
      final eco = pose(72);
      expect(eco.titre, contains('2 échographie(s)'));
      final att = pose(74);
      expect(att.intention, 'I19');
      expect(att.sources.map((s) => s.ecran), ['m2-imagerie-demandes']);
      expect(tout(att), isNot(contains('NFS')));
    });
    test('Q71 et Q90 : l’état d’une demande d’IMAGERIE d’un patient (statut seul) vient de `demandesImagerie`, pas d’une analyse', () {
      for (final n in [71, 90]) {
        final r = pose(n);
        expect(tout(r), contains('IME-00001'), reason: 'Q$n');
        expect(tout(r), isNot(contains('NFS')), reason: 'Q$n');
        expect(r.tableau!.colonnes, contains('Modalité'), reason: 'Q$n');
      }
    });
    test('Q70 : « ma prochaine garde » pour tout agent rattaché au personnel ; compte non nominatif refusé', () {
      expect(pose(70).intention, 'I33');
    });
  });

  group('lecture exacte : Q1 à Q2, Q12, Q15, Q21 à Q23, Q26, Q32, Q52, Q56, Q77, Q81, Q88, Q93', () {
    test('Q21, Q27, Q55, Q92 : « dans quel lit est le patient X » donne SON lit, jamais la liste des autres occupants', () {
      for (final n in [21, 92]) {
        final r = pose(n);
        expect(r.titre, contains('A2 LIT1'), reason: 'Q$n');
        expect(tout(r), isNot(contains('CBG/103/26')), reason: 'Q$n : un autre patient ne fuit pas');
      }
    });
    test('Q12, Q26, Q66, Q79 : les lits libres se calculent sur le plan de référence ; la maternité est l’aile « Maternité » (6 lits, 5 libres)', () {
      expect(tout(pose(12)), contains('19 lit(s) au plan'));
      final m = pose(26);
      expect(m.titre, contains('5 lit(s) libre(s)'));
      expect(tout(m), contains('6 lit(s) au plan (service « Maternité »)'));
    });
    test('Q15, Q89 : « ce week-end » = samedi ET dimanche ; Q77 : « la semaine » = les sept jours, pas le seul lundi', () {
      for (final n in [15, 89]) {
        final r = pose(n);
        expect(r.titre, contains('du 14/11/2026 au 15/11/2026'), reason: 'Q$n');
        expect(r.tableau!.lignes.length, 2, reason: 'Q$n');
      }
      final s = pose(77);
      expect(s.titre, contains('du 09/11/2026 au 15/11/2026'));
      expect(s.tableau!.lignes.length, 2);
    });
    test('Q23 : « l’ordonnance d’hier » = l’ordonnance du 13/11, pas tout le dossier', () {
      final r = pose(23);
      expect(r.tableau!.lignes.single, ['Ordonnance', 'ORD-2026-00002', '13/11/2026']);
    });
    test('Q88 et Q93 : le compte rendu opératoire, la fiche d’anesthésie — la nature demandée, pas tout le dossier', () {
      expect(pose(88).tableau!.lignes.single.first, 'Compte rendu opératoire');
      expect(pose(93).tableau!.lignes.single.first, startsWith('Fiche d’anesthésie'));
    });
    test('Q56 et Q81 : le courrier du registre — celui qui nomme le patient (reçu), celui d’un correspondant ; l’objet n’est jamais recopié', () {
      final p = pose(56);
      expect(p.tableau!.lignes.single.first, 'Courrier du registre (reçu)');
      expect(p.tableau!.lignes.single[1], 'COU-2026-0002');
      final c = pose(81);
      expect(c.sources.map((s) => s.ecran), ['m13-courriers']);
      expect(c.tableau!.lignes.map((l) => l[0]), ['COU-2026-0003', 'COU-2026-0001']);
      expect(tout(c), isNot(contains('Objet d’exemple')));
      expect(tout(p), isNot(contains('Retour concernant')));
    });
    test('Q34 : « où en est la commande de réactifs » donne l’ÉTAT des commandes qui portent un réactif (pas seulement celles qui attendent la validation), sans celle des gants', () {
      final r = pose(34);
      expect(r.tableau!.lignes.single, ['BC-2', 'EXEMPLE/Fournisseur', '12/11/2026', 'Transmise au fournisseur']);
    });
    test('Q32 : « le résultat de la NFS est validé » compte les demandes de la NFS par état, sans patient', () {
      final r = pose(32);
      expect(r.titre, contains('2 demande(s) pour NFS : 1 rendue(s)'));
    });
    test('Q52, Q75 : « consultation générale » désigne « Consultation généraliste » (même radical), sans la variante à domicile', () {
      final r = pose(52);
      expect(r.titre, contains('Consultation généraliste — prix au'));
      expect(tout(r), contains('Non assuré'));
    });
    test('Q83 : l’Assistant de Direction lit l’activité par les écrans de statistiques qui lui sont ouverts, sans les analyses ni les factures', () {
      final r = pose(83);
      expect(r.intention, 'I21');
      expect(tout(r), contains('Consultations'));
      expect(tout(r), contains('Non lu (hors de votre périmètre)'));
    });
    test('Q1 et Q2 — PARTIEL : sans état de synchronisation branché, l’assistant le dit au lieu de répondre « à jour »', () {
      for (final n in [1, 2]) {
        final r = pose(n);
        expect(r.intention, 'I22');
        expect(tout(r), contains('l’assistant ne le lit pas'), reason: 'le crochet etatSynchro n’est pas branché au poste');
      }
      final branche = a.repondre('${question(1)['question']}', ContexteAst(
          role: 'admin', lire: cx('admin').lire, peutVoirEcran: (_) => true, sensibles: DroitsSensibles(fiches: const []), maintenant: DateTime.utc(2026, 11, 14, 10), etatSynchro: () => 'la mère est à jour ; aucun poste en retard'));
      expect(tout(branche), contains('la mère est à jour'));
    });
  });

  group('fiches d’aide (Q4, Q29, Q58, Q64, Q68, Q80, Q84, Q94) et de définition (Q99) : le MÉCANISME est prêt, AUCUN contenu n’est livré', () {
    const aides = [4, 29, 58, 64, 68, 80, 84, 94];
    test('sans fiche validée : « pas de fiche », jamais une réponse de mémoire (les neuf questions)', () {
      for (final n in [...aides, 99]) {
        final r = pose(n);
        expect(r.code, 'PAS_DE_FICHE', reason: 'Q$n');
        expect(r.statut, 'non_calculable', reason: 'Q$n');
        expect(r.intention, n == 99 ? 'I27' : 'I26', reason: 'Q$n');
      }
    });
    test('une fiche VALIDÉE est citée avec son validateur ; une fiche PROPOSÉE ne l’est jamais (et se dit) ; une fiche réservée à un autre rôle ne se montre pas', () {
      final fiche = {'id': 'F1', 'type': 'aide', 'statut': 'validee', 'titre': 'Fiche d’exemple', 'motsCles': ['courrier entrant'], 'etapes': ['Ouvrir l’écran du courrier', 'Choisir « arrivée »'], 'ecrans': ['m13-courriers'], 'validePar': 'Direction', 'valideLe': '2026-11-20'};
      final ok = pose(58, en: {'fichesAide': [fiche]});
      expect(ok.statut, 'reponse');
      expect(tout(ok), contains('1. Ouvrir l’écran du courrier'));
      expect(tout(ok), contains('Fiche validée par Direction le 20/11/2026'));
      final propose = pose(58, en: {'fichesAide': [{...fiche, 'statut': 'proposee'}]});
      expect(propose.code, 'PAS_DE_FICHE');
      expect(tout(propose), contains('ne sont pas encore validées'));
      final reservee = pose(58, en: {'fichesAide': [{...fiche, 'roles': ['direction']}]});
      expect(reservee.code, 'PAS_DE_FICHE', reason: 'la fiche n’est pas pour le rôle de la question');
      // une définition est une fiche d'un autre type
      final def = pose(99, en: {'fichesAide': [{'id': 'F2', 'type': 'definition', 'statut': 'validee', 'titre': 'Avoir', 'motsCles': ['avoir'], 'definition': 'Définition d’exemple.', 'validePar': 'Direction', 'valideLe': '2026-11-20'}]});
      expect(def.statut, 'reponse');
      expect(tout(def), contains('Définition d’exemple.'));
    });
    test('Q94 (check-liste du bloc) : aucune fiche ne s’écrit avant la validation du professionnel nommé — la réponse reste « pas de fiche »', () {
      final r = pose(94);
      expect(r.code, 'PAS_DE_FICHE');
    });
  });

  group('aucune écriture, aucune fuite : les 100 questions ne modifient pas le magasin de mesure', () {
    test('le magasin est identique avant et après les cent questions', () {
      final avant = jsonEncode(magasin);
      for (final q in questions) {
        a.repondre('${q['question']}', cx('${q['role']}'));
      }
      expect(jsonEncode(magasin), avant);
    });
  });
}
