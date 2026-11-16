/// LA RECONNAISSANCE D'INTENTION de l'assistant, déterministe et en français (lots AST-0 et AST-1). Aucun modèle de langage, aucun réseau.
///
/// Règles : normalisation sans casse ni accents, abréviations d'agent, fautes simples tolérées par une distance d'édition BORNÉE, entités (code patient, code
/// d'analyse, numéro de facture, lit, nom, année de naissance) et période relative lue contre une date fournie (jamais l'horloge). La sortie est une INTENTION du
/// catalogue et des paramètres typés : ce module ne produit AUCUNE valeur de réponse (ni montant, ni quantité, ni nom qu'il n'ait lu dans la question).
///
/// Les refus passent AVANT toute intention : une commande d'écriture, un avis médical, un envoi hors de la clinique et une injonction de contourner les règles
/// sont refusés en les nommant — la commande n'existe pas dans l'assistant, elle n'est pas « interdite à l'exécution ».
library;

import 'ast_catalogue.dart';
import 'ast_texte.dart';

/// Un résultat de reconnaissance : une intention et des paramètres typés, jamais une valeur de réponse.
class ReconnaissanceAst {
  const ReconnaissanceAst({
    required this.statut,
    this.intention,
    this.code,
    this.parametres = const {},
    this.propositions = const [],
    this.manquants = const [],
    this.alertes = const [],
    this.ecran,
  });

  /// `comprise`, `precision_requise`, `ambigue`, `non_comprise` ou `refus`.
  final String statut;
  final String? intention;
  final String? code;
  final Map<String, Object?> parametres;
  final List<String> propositions;
  final List<String> manquants;
  final List<String> alertes;
  final String? ecran;

  Map<String, Object?> toJson() => {
        'statut': statut,
        if (intention != null) 'intention': intention,
        if (code != null) 'code': code,
        if (parametres.isNotEmpty) 'parametres': parametres,
        if (propositions.isNotEmpty) 'propositions': propositions,
        if (manquants.isNotEmpty) 'manquants': manquants,
        if (alertes.isNotEmpty) 'alertes': alertes,
        if (ecran != null) 'ecran': ecran,
      };
}

const List<String> _motsVides = [
  'le', 'la', 'les', 'l', 'un', 'une', 'des', 'du', 'de', 'd', 'en', 'et', 'ou', 'a', 'au', 'aux', 'ce', 'cet', 'cette', 'ces', 'est', 'sont', 'qui', 'que', 'quoi',
  'quel', 'quelle', 'quels', 'quelles', 'pour', 'par', 'sur', 'dans', 'avec', 'mon', 'ma', 'mes', 'il', 'elle', 'ils', 'elles', 't', 'y', 'on', 'nous', 'vous', 'je',
  'tu', 'me', 'moi', 'toi', 'se', 's', 'qu', 'c', 'n', 'ne', 'pas', 'ont', 'as', 'es', 'si', 'ok', 'merci', 'svp', 'plus', 'moins', 'tout', 'tous', 'toute', 'toutes',
  'montre', 'donne', 'voir', 'fait', 'faire', 'dis', 'dire', 'liste', 'quand', 'combien', 'soir', 'depuis', 'jusqu', 'bonjour', 'stp', 'moi', 'encore', 'deja', 'aussi',
  'boite', 'boites', 'unite', 'unites', 'son', 'sa', 'ses', 'leur', 'leurs', 'est ce',
  'veux', 'voudrais', 'puis', 'peux', 'sais', 'savoir', 'connaitre', 'quelqu', 'chez', 'cest',
];

/// Les mots génériques qui DÉSIGNENT un article sans le nommer : retirés quand ils précèdent le nom (« le stock de l'article X »), conservés derrière (« EXEMPLE/Article » est
/// un nom dont le dernier mot est « article »).
const List<String> _motsGeneriques = ['article', 'articles', 'produit', 'produits', 'medicament', 'medicaments', 'reference', 'references'];

const List<String> _motsPeriode = [
  'aujourd', 'hui', 'hier', 'demain', 'cette', 'semaine', 'mois', 'dernier', 'derniere', 'derniers', 'dernieres', 'passe', 'passee', 'annee', 'jour', 'jours',
  'prochain', 'prochains', 'prochaine', 'prochaines', 'precedent', 'janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout', 'septembre', 'octobre',
  'novembre', 'decembre', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche', 'compares', 'compare', 'comparee', 'comparees', 'comparaison', 'ci', 'matin',
  'avant', 'apres', 'fin', 'debut', 'ans', 'an',
];

const List<String> _verbesEcriture = [
  'annule', 'annuler', 'supprime', 'supprimer', 'efface', 'effacer', 'modifie', 'modifier', 'change', 'changer', 'fais', 'encaisse', 'encaisser', 'enregistre', 'enregistrer', 'cree', 'creer',
  'ajoute', 'ajouter', 'emets', 'emet', 'emettre', 'signe', 'rembourse', 'rembourser', 'corrige', 'corriger', 'valide', 'valider', 'transmets', 'lance', 'declare', 'retire',
  'regle', 'regler', 'paye', 'payer', 'saisis', 'saisir', 'mets', 'met', 'archive', 'archiver', 'commande', 'commander', 'prescris', 'prescrire', 'cloture', 'cloturer', 'valide',
  'restaure', 'restaurer', 'passe', 'deplace', 'transfere', 'vire', 'renomme', 'reinitialise', 'reaffecte', 'majore', 'diminue', 'baisse', 'augmente',
];

const List<String> _preambulesPolitesse = [
  'peux tu', 'peut tu', 'peux t', 'pouvez vous', 'tu peux', 'vous pouvez', 'je veux', 'je voudrais', 'je souhaite', 'veuillez', 'merci de', 's il te plait', 's il vous plait', 'stp', 'svp',
  'il faut', 'on doit', 'faut', 'merci',
];

/// Les termes qui demandent un AVIS médical (diagnostic, traitement, dose) : refus d'emblée.
const List<String> _termesAvis = [
  'traitement*', 'dose', 'doses', 'posologie*', 'diagnostic*', 'soigne*', 'guerir', 'guerit', 'symptome*', 'prescri*', 'therapeut*', 'que faire', 'quel medicament pour',
  'conseil medical', 'avis medical', 'souffre', 'est malade', 'quelle maladie', 'quelle pathologie', 'pronostic',
];

/// Les noms de maladies : refus SAUF si la question porte, par ailleurs, sur un état de demande, un prix ou un stock (« le résultat VIH est-il rendu ? » lit un état,
/// il ne diagnostique rien).
const List<String> _termesMaladie = [
  'diabete', 'paludisme', 'palu', 'hypertension', 'vih', 'sida', 'cancer', 'typhoide', 'tuberculose', 'anemie', 'drepanocytose', 'hepatite', 'asthme', 'epilepsie', 'ulcere',
  'infection*', 'maladie*', 'covid', 'cholera', 'rougeole', 'fievre*',
];

/// Les termes de PAIE (Q16) : toute question qui en porte un est refusée en la nommant. Formes exactes ou préfixes (`*`) : « paie » ne couvre pas « paiement » (la caisse), et « cnss » ou « its »
/// restent au calendrier fiscal (échéances), qui n'est pas la paie d'un agent.
const List<String> _termesPaie = ['salaire*', 'salarial*', 'remuneration*', 'emolument*', 'cotisation*', 'masse salariale', 'conges payes', 'net a percevoir'];

/// Les termes de paie courts, comparés EXACTEMENT : la tolérance aux fautes confondrait « primes » avec « périmés » (une lettre d'écart) et « paie » avec d'autres mots courts.
const Set<String> _termesPaieExacts = {'paie', 'paies', 'prime', 'primes', 'treizieme'};

const Map<String, String> _mois = {
  'janvier': '01', 'fevrier': '02', 'mars': '03', 'avril': '04', 'mai': '05', 'juin': '06', 'juillet': '07', 'aout': '08', 'septembre': '09', 'octobre': '10',
  'novembre': '11', 'decembre': '12',
};

const List<String> _joursSemaine = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

/// Le réglage d'un passage : dans la MESURE, un volet peut être coupé pour prouver qu'il sert (mutations). Au poste, toujours [ReglageAst.complet].
class ReglageAst {
  const ReglageAst({this.accents = true, this.tolerance = true, this.refuserEcriture = true, this.refuserAvis = true, this.refuserEnvoi = true});
  static const complet = ReglageAst();
  final bool accents, tolerance, refuserEcriture, refuserAvis, refuserEnvoi;
}

class ReconnaisseurAst {
  ReconnaisseurAst(this.catalogue, {this.reglage = ReglageAst.complet});

  final CatalogueAst catalogue;
  final ReglageAst reglage;

  String _norm(String t) => reglage.accents ? astNormaliser(t) : t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9àâäáãåéèêëîïíìôöòóõùûüúçñÿœæ]+'), ' ').trim();

  bool _egal(String mot, String cible) {
    if (mot == cible) return true;
    if (!reglage.tolerance) return false;
    final t = astTolerance(cible.length);
    if (t == 0 || mot.length < 4) return false;
    return astDistance(mot, cible, t) <= t;
  }

  bool _prefixe(String mot, String prefixe) {
    if (mot.startsWith(prefixe)) return true;
    if (!reglage.tolerance) return false;
    final t = astTolerance(prefixe.length);
    if (t == 0 || mot.length < 4) return false;
    final debut = mot.length >= prefixe.length ? mot.substring(0, prefixe.length) : mot;
    return astDistance(debut, prefixe, t) <= t;
  }

  /// Un indice (formes consécutives, `*` = préfixe) trouvé dans les mots : l'indice du premier mot couvert, ou -1.
  int _trouve(List<String> mots, String indice) {
    final formes = indice.split(' ');
    for (var i = 0; i + formes.length <= mots.length; i++) {
      var ok = true;
      for (var k = 0; k < formes.length && ok; k++) {
        final f = formes[k];
        ok = f.endsWith('*') ? _prefixe(mots[i + k], f.substring(0, f.length - 1)) : _egal(mots[i + k], f);
      }
      if (ok) return i;
    }
    return -1;
  }

  bool _a(List<String> mots, String indice) => _trouve(mots, indice) >= 0;

  /// La reconnaissance d'une question. [aujourdhui] : `AAAA-MM-JJ` (le module ne lit jamais l'horloge).
  ReconnaissanceAst reconnaitre(String question, {required String aujourdhui}) {
    final jour = _jour(aujourdhui);
    final brut = question.trim();
    final mots = [for (final m in _norm(brut).split(' ')) if (m.isNotEmpty) astAbreviations[m] ?? m];
    final texte = ' ${mots.join(' ')} ';
    if (mots.isEmpty) return const ReconnaissanceAst(statut: 'non_comprise', code: 'INTENTION_INCONNUE');

    final params = <String, Object?>{};
    _entites(brut, mots, params);
    final nomSeul = params.remove('_nomSeul') == true;

    // 1. Les refus, avant toute intention.
    final refus = _refus(mots, params);
    if (refus != null) return refus;

    // 2. La période.
    final periode = _periode(texte, jour, params);

    // 3. Les scores par intention. Les indices d'une intention ne se cumulent pas sur les MÊMES mots.
    final scores = <String, int>{};
    final couverts = <String, Set<int>>{};
    var motsScore = mots;
    final iNA = _trouve(mots, 'non assure');
    if (iNA >= 0) motsScore = [...mots]..replaceRange(iNA, iNA + 2, ['', '']);
    for (final i in catalogue.actives) {
      var s = 0;
      final ordonnes = [...i.indices]..sort((x, y) => y.$2 != x.$2 ? y.$2.compareTo(x.$2) : y.$1.length.compareTo(x.$1.length));
      final pris = <int>{};
      for (final (indice, poids) in ordonnes) {
        final p = _trouve(motsScore, indice);
        if (p < 0 || poids <= 0) continue;
        final n = indice.split(' ').length;
        final positions = [for (var k = 0; k < n; k++) p + k];
        if (positions.any(pris.contains)) continue;
        s += poids;
        pris.addAll(positions);
        (couverts[i.id] ??= {}).addAll(positions);
      }
      if (s > 0) scores[i.id] = s;
    }
    void plus(String id, int n) {
      if (catalogue.actif(id)) scores[id] = (scores[id] ?? 0) + n;
    }

    if (iNA >= 0) plus('I05', 3);
    if (params.containsKey('codePatient') || params.containsKey('nomPatient')) plus('I01', 1);
    if (nomSeul) plus('I01', 3);
    if (params.containsKey('anneeNaissance')) plus('I01', 1);
    if (params.containsKey('codeAnalyse')) plus('I19', 3);
    if (params.containsKey('numeroFacture')) plus('I03', 2);
    final certif = _a(mots, 'certificat*') || _a(mots, 'attestation*');
    final prix = _a(mots, 'prix') || _a(mots, 'tarif') || _a(mots, 'coute') || _a(mots, 'combien');
    if (certif && prix) plus('I18', 8);
    final stats = _a(mots, 'consultation*') || _a(mots, 'admission*') || _a(mots, 'analyse*') || _a(mots, 'examen*');
    if ((_a(mots, 'combien de') || _a(mots, 'nombre de') || _a(mots, 'nombre d')) && stats) plus('I21', 5);

    // 4. Les noms de maladie : refus, sauf si la question lit un état, un prix ou un stock.
    if (reglage.refuserAvis && _termesMaladie.any((t) => _a(mots, t))) {
      final fort = ['I19', 'I05', 'I07', 'I08', 'I17'].any((id) => (scores[id] ?? 0) >= 4);
      if (!fort) return const ReconnaissanceAst(statut: 'refus', code: 'AVIS_MEDICAL_REFUSE');
    }

    // 5. Un énoncé réduit à un mot de domaine est AMBIGU : trois intentions proches.
    final informatifs = [for (final m in mots) if (m.isNotEmpty && !_motsVides.contains(m)) m];
    final meilleur = scores.values.isEmpty ? 0 : scores.values.reduce((a, b) => a > b ? a : b);
    if (informatifs.isNotEmpty && informatifs.length <= 2 && meilleur <= 4) {
      for (final d in domainesAst.entries) {
        if (informatifs.every((m) => m == d.key || _egal(m, d.key))) {
          return ReconnaissanceAst(statut: 'ambigue', code: 'QUESTION_AMBIGUE', propositions: [for (final x in d.value.take(3)) x], parametres: {'secteur': d.key});
        }
      }
    }

    if (scores.isEmpty) return const ReconnaissanceAst(statut: 'non_comprise', code: 'INTENTION_INCONNUE');
    final tries = scores.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    final premier = tries.first;
    final second = tries.length > 1 ? tries[1] : null;
    if (premier.value < 2) {
      return ReconnaissanceAst(statut: 'non_comprise', code: 'INTENTION_INCONNUE', propositions: [for (final t in tries.take(3)) t.key]);
    }
    if (second != null && second.value == premier.value) {
      return ReconnaissanceAst(
          statut: 'ambigue', code: 'QUESTION_AMBIGUE', propositions: [for (final t in tries.where((t) => t.value >= premier.value - 1).take(3)) t.key]);
    }
    var id = premier.key;
    if (certif && prix) id = 'I18';
    final intention = catalogue[id];
    if (intention == null || !intention.actif) return const ReconnaissanceAst(statut: 'non_comprise', code: 'INTENTION_INCONNUE');

    // 6. Les paramètres propres à l'intention, puis les alertes de période.
    _parametresPropres(id, mots, couverts[id] ?? const {}, params);
    final alertes = <String>[];
    final iso = astIso(jour);
    if (periode != null) {
      final debut = periode['debut'] as String?;
      final fin = periode['fin'] as String?;
      if (debut != null && debut.compareTo(iso) > 0 && !intention.futurOk) alertes.add('PERIODE_FUTURE');
      if (fin != null && fin.compareTo(iso) < 0 && !intention.historique) alertes.add('NON_CALCULABLE_HISTORIQUE');
    }
    final manquants = [for (final r in intention.requis) if (!_possede(r, params)) r];
    if (manquants.isNotEmpty) {
      return ReconnaissanceAst(statut: 'precision_requise', intention: id, code: 'PRECISION_REQUISE', manquants: manquants, parametres: params, alertes: alertes);
    }
    return ReconnaissanceAst(statut: 'comprise', intention: id, parametres: params, alertes: alertes);
  }

  bool _possede(String requis, Map<String, Object?> p) => switch (requis) {
        'patient' => p.containsKey('codePatient') || p.containsKey('nomPatient') || p.containsKey('patient'),
        'patient_ou_analyse' => p.containsKey('codePatient') || p.containsKey('nomPatient') || p.containsKey('patient') || p.containsKey('codeAnalyse'),
        'acte' => '${p['acte'] ?? ''}'.isNotEmpty,
        'article' => '${p['article'] ?? ''}'.isNotEmpty,
        'fournisseur' => '${p['fournisseur'] ?? ''}'.isNotEmpty,
        _ => p.containsKey(requis),
      };

  // --- refus -----------------------------------------------------------------------------------------------------------------------------------

  ReconnaissanceAst? _refus(List<String> mots, Map<String, Object?> entites) {
    final texte = mots.join(' ');
    // Injonction : contourner les règles, ou extraire tout le répertoire.
    if (((_a(mots, 'ignore') || _a(mots, 'oublie') || _a(mots, 'desactive') || _a(mots, 'contourne') || _a(mots, 'outrepasse')) &&
            (_a(mots, 'regles') || _a(mots, 'consignes') || _a(mots, 'instructions') || _a(mots, 'droits') || _a(mots, 'restrictions'))) ||
        texte.contains('tous les patients') ||
        texte.contains('toute la base') ||
        texte.contains('mode administrateur') ||
        texte.contains('fais comme si')) {
      return const ReconnaissanceAst(statut: 'refus', code: 'INJONCTION_REFUSEE');
    }
    // Paie (Q16) : aucune intention de paie, sans exception — refusée avant tout le reste, écriture et envoi compris.
    if (mots.any(_termesPaieExacts.contains) || _termesPaie.any((t) => _a(mots, t))) return const ReconnaissanceAst(statut: 'refus', code: 'PAIE_HORS_ASSISTANT');
    // Envoi hors de la clinique.
    if (reglage.refuserEnvoi &&
        (_a(mots, 'envoie') || _a(mots, 'envoyer') || _a(mots, 'transmets') || _a(mots, 'partage') || _a(mots, 'transfere') || _a(mots, 'exporte')) &&
        (_a(mots, 'mail') || _a(mots, 'email') || _a(mots, 'courriel') || _a(mots, 'adresse') || _a(mots, 'whatsapp') || _a(mots, 'sms') || _a(mots, 'cloud') || _a(mots, 'drive') ||
            _a(mots, 'dehors') || _a(mots, 'usb') || _a(mots, 'telegram') || _a(mots, 'dropbox') || _a(mots, 'facebook') || _a(mots, 'disque externe'))) {
      return const ReconnaissanceAst(statut: 'refus', code: 'ENVOI_EXTERNE_REFUSE');
    }
    // Avis médical.
    if (reglage.refuserAvis && _termesAvis.any((t) => _a(mots, t))) {
      return const ReconnaissanceAst(statut: 'refus', code: 'AVIS_MEDICAL_REFUSE');
    }
    // Écriture : une commande à l'impératif en tête d'énoncé (après une formule de politesse éventuelle).
    if (reglage.refuserEcriture) {
      var debut = mots;
      var coupe = true;
      while (coupe) {
        coupe = false;
        for (final p in _preambulesPolitesse) {
          final pm = p.split(' ');
          if (debut.length > pm.length && [for (var i = 0; i < pm.length; i++) debut[i]].join(' ') == p) {
            debut = debut.sublist(pm.length);
            coupe = true;
            break;
          }
        }
      }
      if (debut.isNotEmpty && _verbesEcriture.any((v) => debut.first == v || (v.length >= 6 && !_connu(debut.first) && _egal(debut.first, v)))) {
        String? ecran;
        for (final e in ecransEcritureAst) {
          if (e.mots.any(mots.contains)) {
            ecran = e.ecran;
            break;
          }
        }
        return ReconnaissanceAst(statut: 'refus', code: 'ECRITURE_ABSENTE', ecran: ecran, parametres: {...entites});
      }
    }
    return null;
  }

  // --- entités ---------------------------------------------------------------------------------------------------------------------------------

  static final RegExp _codePatient = RegExp(r'\b([A-Za-z]{2,6})\s*/?\s*(\d{1,6})\s*/\s*(\d{2})\b');
  static final RegExp _codeAnalyse = RegExp(r'\b(\d{5})-(\d{4})\b');
  static final RegExp _numeroFacture = RegExp(r'\b([A-Z]{1,3}-\d{4}-\d{3,6})\b');
  static final RegExp _factureN = RegExp(r'\bfacture\s+n?°?\s*(\d{3,})\b', caseSensitive: false);
  static final RegExp _lit = RegExp(r'\blit\s+n?°?\s*([A-Za-z]?\d{1,3}[A-Za-z]?)\b', caseSensitive: false);
  static final RegExp _naissance = RegExp(r'\bn[ée]e?\s+en\s+(\d{4})\b', caseSensitive: false, unicode: true);
  static final RegExp _civilite = RegExp(r"\b(?:Mme|Mlle|Mr|Madame|Monsieur|Mademoiselle|M\.)\s+([A-ZÀ-Ý][A-Za-zÀ-ÿ'’/-]+(?:\s+[A-ZÀ-Ý][a-zà-ÿ]+)?)", unicode: true);

  void _entites(String brut, List<String> mots, Map<String, Object?> p) {
    final c = _codePatient.firstMatch(brut);
    if (c != null) p['codePatient'] = '${c.group(1)!.toUpperCase()}/${int.parse(c.group(2)!)}/${c.group(3)}';
    final a = _codeAnalyse.firstMatch(brut);
    if (a != null) p['codeAnalyse'] = '${a.group(1)}-${a.group(2)}';
    final f = _numeroFacture.firstMatch(brut) ?? _factureN.firstMatch(brut);
    if (f != null) p['numeroFacture'] = f.group(1);
    final l = _lit.firstMatch(brut);
    if (l != null) p['lit'] = l.group(1)!.toUpperCase();
    final n = _naissance.firstMatch(brut);
    if (n != null) p['anneeNaissance'] = int.parse(n.group(1)!);
    final cv = _civilite.firstMatch(brut);
    final lettres = brut.replaceAll(RegExp(r'[^\p{L}\p{N}\s/]', unicode: true), ' ').trim().split(RegExp(r'\s+'));
    if (cv != null) {
      p['nomPatient'] = cv.group(1);
      if (lettres.length <= 2) p['_nomSeul'] = true;
    } else if (c == null) {
      // Un nom : un mot en majuscule initiale qui n'est ni du vocabulaire connu ni un mot vide, derrière « patient », « dossier de », « pour », « chez »… ou seul.
      final k = _nomApresDeclencheur(lettres);
      if (k != null) {
        p['nomPatient'] = k;
      } else if (lettres.length == 1 && RegExp(r'^[A-ZÀ-Ý][A-Za-zà-ÿ/-]+$', unicode: true).hasMatch(lettres.first) && !_connu(lettres.first)) {
        p['nomPatient'] = lettres.first;
        p['_nomSeul'] = true;
      }
    }
    if (_a(mots, 'ce patient') || _a(mots, 'le patient') || _a(mots, 'cette patiente') || _a(mots, 'ce dossier') || _a(mots, 'meme patient')) {
      if (!p.containsKey('codePatient') && !p.containsKey('nomPatient')) p['patient'] = 'contexte';
    }
  }

  /// Le nom de famille posé après un mot qui annonce un patient. Majuscule initiale exigée : un mot ordinaire en minuscules n'est jamais un nom.
  String? _nomApresDeclencheur(List<String> lettres) {
    for (var i = 0; i < lettres.length - 1; i++) {
      final d = _norm(lettres[i]);
      if (!const ['patient', 'patiente', 'dossier', 'de', 'du', 'pour', 'chez', 'pr', 'a'].contains(d)) continue;
      final cand = <String>[];
      for (var j = i + 1; j < lettres.length && cand.length < 2; j++) {
        final t = lettres[j];
        if (!RegExp(r'^[A-ZÀ-Ý]', unicode: true).hasMatch(t) || _connu(t)) break;
        cand.add(t);
      }
      if (cand.isNotEmpty) return cand.join(' ');
    }
    return null;
  }

  bool _connu(String mot) {
    final m = _norm(mot);
    if (m.isEmpty || _motsVides.contains(m) || _motsPeriode.contains(m) || astAbreviations.containsKey(m)) return true;
    if (domainesAst.keys.any((d) => _egal(m, d))) return true;
    for (final i in catalogue.intentions.values) {
      for (final (indice, _) in i.indices) {
        if (indice.split(' ').any((f) => f.endsWith('*') ? m.startsWith(f.substring(0, f.length - 1)) : f == m)) return true;
      }
    }
    return false;
  }

  void _parametresPropres(String id, List<String> mots, Set<int> couverts, Map<String, Object?> p) {
    final texte = mots.join(' ');
    // Un nom en majuscule initiale n'est un PATIENT que pour une question qui en cherche un : ailleurs (un article, un acte, un fournisseur) il fait partie du libellé.
    final cherchePatient = id == 'I01' || (catalogue[id]?.requis.any((r) => r.startsWith('patient')) ?? false);
    if (!cherchePatient) p.remove('nomPatient');
    for (final d in domainesAst.keys) {
      if (d != 'patient' && d != 'fournisseur' && mots.any((m) => m == d || _egal(m, d))) {
        p['secteur'] = d;
        break;
      }
    }
    final top = RegExp(r'\b(\d{1,3}) (?:articles|produits|medicaments|references)\b').firstMatch(texte);
    if (id == 'I09' && top != null) p['topN'] = int.parse(top.group(1)!);
    if (id == 'I23') {
      if (texte.contains('rouleau') || texte.contains('80 mm')) p['gabarit'] = 'rouleau80';
      if (texte.contains(' a4') || texte.endsWith(' a4')) p['gabarit'] = 'a4';
    }
    final iF = mots.indexWhere((m) => m.startsWith('fournisseur'));
    if (iF >= 0 && iF + 1 < mots.length) {
      final reste = [
        for (var k = iF + 1; k < mots.length; k++)
          if (!_motsVides.contains(mots[k]) && !_motsPeriode.contains(mots[k]) && !RegExp(r'^\d+$').hasMatch(mots[k])) mots[k]
      ];
      if (reste.isNotEmpty) p['fournisseur'] = reste.join(' ');
    }
    if (id == 'I12' && !p.containsKey('fournisseur')) {
      // « Que devons-nous à EXEMPLE/Fournisseur ? » : le nom suit le verbe, sans le mot « fournisseur ».
      final reste = _restes(id, mots, couverts, p);
      if (reste.isNotEmpty) p['fournisseur'] = reste;
    }
    if (const ['I05', 'I06', 'I07', 'I18'].contains(id)) {
      final reste = _restes(id, mots, couverts, p);
      if (reste.isNotEmpty) p[id == 'I07' ? 'article' : 'acte'] = reste;
    }
  }

  /// Les mots qui restent une fois retirés mots vides, indices de l'intention, entités et période : le nom d'un article, d'un acte ou d'un fournisseur.
  String _restes(String id, List<String> mots, Set<int> couverts, Map<String, Object?> p) {
    final indicesIntention = {for (final (i, _) in (catalogue[id]?.indices ?? const <IndiceAst>[])) ...i.split(' ').map((x) => x.replaceAll('*', ''))};
    final entitesTexte = {
      for (final v in [p['codePatient'], p['nomPatient'], p['codeAnalyse']])
        if (v != null) ..._norm('$v').split(' '),
    };
    final per = p['periode'] as Map<String, Object?>?;
    final chiffresPeriode = per == null ? const <String>{} : {if (per['n'] != null) '${per['n']}', ...mots.where((m) => RegExp(r'^\d{1,2}$').hasMatch(m) && per['type'] == 'date')};
    final reste = <String>[];
    for (var k = 0; k < mots.length; k++) {
      final m = mots[k];
      if (m.isEmpty || _motsVides.contains(m) || _motsPeriode.contains(m) || entitesTexte.contains(m) || couverts.contains(k) || chiffresPeriode.contains(m)) continue;
      if (indicesIntention.any((x) => x == m || (x.length >= 5 && _egal(m, x)))) continue;
      if (const ['assure', 'non', 'avant', 'quelle', 'valeur', 'montant', 'reste', 'devons', 'doit'].contains(m)) continue;
      if (reste.isEmpty && _motsGeneriques.contains(m)) continue;
      reste.add(m);
    }
    return reste.join(' ').trim();
  }

  // --- période ---------------------------------------------------------------------------------------------------------------------------------

  Map<String, Object?>? _periode(String texte, DateTime jour, Map<String, Object?> p) {
    Map<String, Object?> j(String type, DateTime d, DateTime f, {int? n}) => {'type': type, 'debut': astIso(d), 'fin': astIso(f), if (n != null) 'n': n};
    Map<String, Object?>? principale;
    Map<String, Object?>? comparee;
    final lundi = jour.subtract(Duration(days: jour.weekday - 1));
    final mois0 = DateTime.utc(jour.year, jour.month, 1);
    final moisFin = DateTime.utc(jour.year, jour.month + 1, 0);
    final moisPrec0 = DateTime.utc(jour.year, jour.month - 1, 1);
    final moisPrecFin = DateTime.utc(jour.year, jour.month, 0);
    bool a(String s) => texte.contains(' $s ');

    final plusDe = RegExp(r' plus de (\d{1,4}) jours? ').firstMatch(texte);
    final njours = RegExp(r' (\d{1,4}) (?:derniers )?jours? ').firstMatch(texte);
    final nmois = RegExp(r' (\d{1,3}) mois ').firstMatch(texte);
    final dateExplicite = RegExp(r' (\d{1,2}) (janvier|fevrier|mars|avril|mai|juin|juillet|aout|septembre|octobre|novembre|decembre)( dernier)? ').firstMatch(texte);
    final moisNomme = RegExp(r' (janvier|fevrier|mars|avril|mai|juin|juillet|aout|septembre|octobre|novembre|decembre) ').firstMatch(texte);

    if (plusDe != null) {
      principale = {'type': 'anciennete_jours', 'n': int.parse(plusDe.group(1)!)};
    } else if (dateExplicite != null) {
      final jj = int.parse(dateExplicite.group(1)!);
      final mm = int.parse(_mois[dateExplicite.group(2)]!);
      var d = DateTime.utc(jour.year, mm, jj);
      if (dateExplicite.group(3) != null && !d.isBefore(jour)) d = DateTime.utc(jour.year - 1, mm, jj);
      principale = j('date', d, d);
    } else if (a('aujourd hui') || a('ce soir') || a('ce matin') || a('du jour') || a('ce jour')) {
      principale = j('aujourdhui', jour, jour);
    } else if (a('hier')) {
      final d = jour.subtract(const Duration(days: 1));
      principale = j('hier', d, d);
    } else if (a('demain')) {
      final d = jour.add(const Duration(days: 1));
      principale = j('demain', d, d);
    } else if (a('semaine derniere') || a('semaine passee')) {
      final d = lundi.subtract(const Duration(days: 7));
      principale = j('semaine_derniere', d, d.add(const Duration(days: 6)));
    } else if (a('semaine prochaine')) {
      final d = lundi.add(const Duration(days: 7));
      principale = j('semaine_prochaine', d, d.add(const Duration(days: 6)));
    } else if (a('semaine') && (a('cette') || a('de la') || a('la'))) {
      principale = j('semaine', lundi, lundi.add(const Duration(days: 6)));
    } else if (nmois != null && (a('dans les ${nmois.group(1)} mois') || a('dans ${nmois.group(1)} mois') || a('prochains ${nmois.group(1)} mois'))) {
      final n = int.parse(nmois.group(1)!);
      principale = j('horizon_mois', jour, _plusMois(jour, n), n: n);
    } else if (nmois != null) {
      final n = int.parse(nmois.group(1)!);
      principale = j('n_mois', _plusMois(jour, -n), jour, n: n);
    } else if (njours != null) {
      final n = int.parse(njours.group(1)!);
      principale = j('n_jours', jour.subtract(Duration(days: n)), jour, n: n);
    } else if (a('annee derniere') || a('annee passee')) {
      principale = j('annee_derniere', DateTime.utc(jour.year - 1, 1, 1), DateTime.utc(jour.year - 1, 12, 31));
    } else if (a('mois dernier') || a('mois passe') || a('mois precedent')) {
      principale = j('mois_dernier', moisPrec0, moisPrecFin);
    } else if (a('mois prochain')) {
      principale = j('mois_prochain', DateTime.utc(jour.year, jour.month + 1, 1), DateTime.utc(jour.year, jour.month + 2, 0));
    } else if (moisNomme != null && (a('mois d ${moisNomme.group(1)}') || !a('mois'))) {
      final mm = int.parse(_mois[moisNomme.group(1)]!);
      final an = mm <= jour.month ? jour.year : jour.year - 1;
      principale = j('mois_nomme', DateTime.utc(an, mm, 1), DateTime.utc(an, mm + 1, 0));
    } else if (a('ce mois') || a('du mois') || a('de ce mois') || a('mois') || a('ce mois ci')) {
      principale = j('mois', mois0, moisFin);
    } else if (a('cette annee') || a('de l annee') || a('annee en cours')) {
      principale = j('annee', DateTime.utc(jour.year, 1, 1), DateTime.utc(jour.year, 12, 31));
    } else {
      for (final js in _joursSemaine) {
        if (a(js)) {
          final cible = _joursSemaine.indexOf(js) + 1;
          var d = jour;
          while (d.weekday != cible) {
            d = d.add(const Duration(days: 1));
          }
          principale = j('jour_semaine', d, d);
          break;
        }
      }
    }
    if (principale != null && principale['type'] == 'mois' && (a('mois dernier') || a('mois passe')) && texte.contains('compar')) {
      comparee = j('mois_dernier', moisPrec0, moisPrecFin);
    }
    if (principale != null) p['periode'] = principale;
    if (comparee != null) p['periodeComparee'] = comparee;
    return principale;
  }

  DateTime _plusMois(DateTime d, int n) {
    final m0 = d.month - 1 + n;
    final an = d.year + (m0 / 12).floor();
    final mm = (m0 % 12) + 1;
    final dernierJour = DateTime.utc(an, mm + 1, 0).day;
    return DateTime.utc(an, mm, d.day > dernierJour ? dernierJour : d.day);
  }

  DateTime _jour(String s) => DateTime.utc(int.parse(s.substring(0, 4)), int.parse(s.substring(5, 7)), int.parse(s.substring(8, 10)));
}
