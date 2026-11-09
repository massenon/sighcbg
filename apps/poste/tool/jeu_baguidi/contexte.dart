// LE CONTEXTE DU GÉNÉRATEUR DU JEU DE DÉMONSTRATION BAGUIDI (J12, Direction, 08/11/2026).
//
// Un Contexte porte tout ce dont une étape de génération a besoin et rien d'autre : le MAGASIN en mémoire (celui du poste, donc ses règles : archivage
// logique RG-14, journal RG-12, gardes d'exercice), un TIRAGE seedé, une HORLOGE fixe et les écritures de collection. Une étape (socle, personnes, puis un
// `module_*.dart` par sous-lot) reçoit le contexte, lit ce que les étapes précédentes ont écrit et écrit les siennes ; elle n'ouvre jamais un fichier.
//
// Trois garanties, que `test/generer_jeu_baguidi_test.dart` éprouve :
//  - DÉTERMINISME : mêmes entrées, mêmes octets. La graine est fixe (20261108), l'horloge est fixe (07/11/2026 12:00), le tirage est un générateur écrit ici
//    (Mulberry32) et non `dart:math`, dont la suite de valeurs n'est pas garantie d'une version du SDK à l'autre. Chaque étape reçoit son PROPRE flux
//    (`tirageDe('nom')`) : ajouter un tirage dans une étape ne décale jamais les données d'une autre.
//  - AUCUN CHAMP NUL ÉCRIT : un null se relit `undefined` côté poste (aucun enregistrement n'est comparé à `null`) ; l'écrire ne ferait que gonfler le jeu.
//    Les chaînes vides, `false` et `0` sont écrits. Un null DANS une liste est gardé.
//  - LES 154 NOMS DE FICHIER sont conservés (une collection vide s'écrit `[]` : le chargeur plante sinon). Écrire une collection inconnue est refusé.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_poste/donnees/magasin.dart';

/// Le générateur pseudo-aléatoire du jeu : Mulberry32, entièrement en entiers 32 bits, donc identique sur toutes les plateformes et toutes les versions du SDK.
class Tirage {
  Tirage(int graine) : _etat = graine & 0xFFFFFFFF;
  int _etat;

  /// Le prochain entier non signé sur 32 bits.
  int suivant32() {
    _etat = (_etat + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _etat;
    t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF;
    t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  /// Un réel dans [0, 1).
  double reel() => suivant32() / 4294967296;

  /// Un entier dans [0, n[.
  int entier(int n) {
    if (n <= 0) throw ArgumentError('entier(n) exige n > 0');
    return (reel() * n).floor();
  }

  /// Un entier dans [a, b] (bornes comprises).
  int entre(int a, int b) => a + entier(b - a + 1);

  /// Vrai avec la probabilité [p].
  bool chance(double p) => reel() < p;

  T choisir<T>(List<T> l) => l[entier(l.length)];

  /// Un choix pondéré : les poids sont des entiers positifs.
  T pondere<T>(Map<T, int> poids) {
    final total = poids.values.fold<int>(0, (a, b) => a + b);
    var r = entier(total);
    for (final e in poids.entries) {
      if (r < e.value) return e.key;
      r -= e.value;
    }
    return poids.keys.last;
  }

  /// Une copie mélangée (Fisher-Yates) ; la liste d'origine n'est pas modifiée.
  List<T> melanger<T>(Iterable<T> source) {
    final l = [...source];
    for (var i = l.length - 1; i > 0; i--) {
      final j = entier(i + 1);
      final x = l[i];
      l[i] = l[j];
      l[j] = x;
    }
    return l;
  }
}

/// Le contexte partagé par toutes les étapes de génération.
class Contexte {
  Contexte._(this.magasin, this._reference, this.referentiels, this.nomsCollections, this.dossierReference);

  /// La graine fixe du jeu : la date de la décision (08/11/2026).
  static const int graine = 20261108;

  /// L'horloge fixe : le jeu est « arrêté » au 07/11/2026 à midi. Aucune étape ne lit `DateTime.now()`.
  static final DateTime maintenant = DateTime(2026, 11, 7, 12);

  /// La fenêtre d'activité du jeu (J2) : du 01/08/2026 au 07/11/2026.
  static final DateTime debutFenetre = DateTime(2026, 8, 1);
  static final DateTime finFenetre = DateTime(2026, 11, 7);

  /// L'identité qui signe les écritures du générateur au journal (RG-12 : aucune action anonyme). Le journal n'est pas livré : le poste démarre sur un
  /// journal neuf, ces gestes sont la fabrication du jeu et non des gestes d'agent.
  static const String acteur = 'Générateur du jeu de démonstration';

  /// Le magasin en mémoire : les moteurs de `packages/domaine` (facture, encaissement, avoir, écriture) travaillent dessus par les mêmes collections que
  /// le poste, donc les invariants (RG-03, RG-10) tiennent PAR CONSTRUCTION et non par un contrôle après coup.
  final Magasin magasin;

  /// Les référentiels statiques du jeu (`referentiels.json`, objet et non collection).
  final Map<String, Object?> referentiels;

  /// Les collections du jeu, dans l'ordre alphabétique : ce sont aussi les noms des fichiers écrits.
  final List<String> nomsCollections;

  /// Le dossier du jeu de référence (copie pseudonymisée du jeu d'origine).
  final String dossierReference;

  final Map<String, List<Fiche>> _reference;

  /// Les lignes du rapport de génération (une par fait notable) : le point d'entrée les affiche.
  final List<String> notes = [];

  final Map<String, Tirage> _tirages = {};

  /// Construit le contexte. Toutes les collections démarrent VIDES : une étape y écrit ce qui est à Baguidi et recopie, par [reference], ce qui est
  /// générique. Le jeu d'origine n'est jamais livré tel quel.
  static Contexte demarrer({String dossierReference = Magasin.dossierJeuDeTest}) {
    final dir = Directory(dossierReference);
    if (!dir.existsSync()) throw StateError('Le jeu de référence est absent : $dossierReference (voir tool/README.md).');
    final noms = [
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.json') && !f.path.endsWith('referentiels.json')) f.uri.pathSegments.last.replaceAll('.json', '')
    ]..sort();
    final ref = {
      for (final n in noms)
        n: [
          for (final f in jsonDecode(File('$dossierReference/$n.json').readAsStringSync()) as List) (f as Map).cast<String, Object?>()
        ]
    };
    final referentiels = (jsonDecode(File('$dossierReference/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>();
    final m = Magasin({for (final n in noms) n: const <Fiche>[]}, 'GENERATEUR', const {});
    m.horloge = () => maintenant;
    m.utilisateur = acteur;
    return Contexte._(m, ref, {...referentiels}, noms, dossierReference);
  }

  /// Le flux pseudo-aléatoire PROPRE à une étape : sa graine dérive de la graine du jeu et du nom de l'étape (FNV-1a).
  Tirage tirageDe(String etape) => _tirages.putIfAbsent(etape, () {
        var h = 0x811C9DC5;
        for (final c in etape.codeUnits) {
          h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
        }
        return Tirage(graine ^ h);
      });

  /// Le flux du socle (référentiels), pour les étapes qui n'ont pas besoin du leur.
  Tirage get tirage => tirageDe('socle');

  void _exiger(String nom) {
    if (!nomsCollections.contains(nom)) {
      throw ArgumentError('Collection inconnue « $nom » : le jeu garde ses ${nomsCollections.length} fichiers, une collection nouvelle se déclare d\'abord au poste.');
    }
  }

  /// La collection du magasin (lecture, et écriture par les moteurs).
  CollectionMagasin collection(String nom) {
    _exiger(nom);
    return magasin.collection(nom);
  }

  /// Les fiches ACTIVES d'une collection, telles que les étapes précédentes les ont écrites.
  List<Fiche> fiches(String nom) => collection(nom).actives;

  /// REMPLACE le contenu d'une collection (sans journal : c'est la fabrication du jeu).
  void remplacer(String nom, Iterable<Fiche> fiches) {
    _exiger(nom);
    magasin.collection(nom).remplacerContenu(fiches);
  }

  /// Ajoute une fiche À LA FIN, sans journal : l'ordre d'écriture est l'ordre du fichier, donc déterministe.
  void ajouter(String nom, Fiche fiche) {
    _exiger(nom);
    magasin.collection(nom).ajouterSansJournal(fiche, notifier: false);
  }

  /// La collection du jeu DE RÉFÉRENCE, en copie profonde (la référence n'est jamais modifiée). À manier avec précaution : elle porte des PSEUDONYMES
  /// d'agents et de patients (voir `tools/baguidi/pseudonymiser.mjs`), qui ne doivent pas entrer dans le jeu livré. Les champs `_cree*` / `_modifie*`
  /// (qui a saisi la fiche dans la clinique d'origine) en sont retirés.
  List<Fiche> reference(String nom) {
    _exiger(nom);
    return [for (final f in _reference[nom]!) _nettoyer(_copie(f))];
  }

  static Fiche _nettoyer(Fiche f) => {
        for (final e in f.entries)
          if (!e.key.startsWith('_cree') && !e.key.startsWith('_modifie')) e.key: e.value
      };

  static Fiche _copie(Fiche f) => (jsonDecode(jsonEncode(f)) as Map).cast<String, Object?>();

  /// `aaaa-mm-jj`.
  static String date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Les jours ouvrés (lundi à samedi : la clinique ouvre six jours sur sept) de la fenêtre, du plus ancien au plus récent.
  List<DateTime> joursOuvres({DateTime? du, DateTime? au}) {
    final a = du ?? debutFenetre;
    final b = au ?? finFenetre;
    return [
      for (var d = DateTime(a.year, a.month, a.day); !d.isAfter(b); d = DateTime(d.year, d.month, d.day + 1))
        if (d.weekday != DateTime.sunday) d
    ];
  }

  void note(String ligne) => notes.add(ligne);

  // --- Sortie ---------------------------------------------------------------------------------------------------------------------------------

  /// Retire récursivement les champs nuls (jamais les `false`, `0` ni les chaînes vides).
  static Object? sansNuls(Object? v) {
    if (v is Map) {
      return {
        for (final e in v.entries)
          if (e.value != null) '${e.key}': sansNuls(e.value)
      };
    }
    if (v is List) return [for (final x in v) sansNuls(x)];
    return v;
  }

  /// Le contenu de chaque fichier du jeu : nom de fichier (sans dossier) → texte. Une fiche par ligne (diff lisible, taille maîtrisée).
  /// Le journal d'audit est LIVRÉ VIDE : le poste démarre sur un journal neuf (RG-12 vaut pour les gestes des agents, pas pour la fabrication du jeu).
  Map<String, String> sortie() {
    final fichiers = <String, String>{};
    for (final n in nomsCollections) {
      final fiches = n == 'audit' ? const <Fiche>[] : magasin.collection(n).toutes;
      fichiers['$n.json'] = fiches.isEmpty
          ? '[]\n'
          : '[\n${[for (final f in fiches) jsonEncode(sansNuls(f))].join(',\n')}\n]\n';
    }
    final r = sansNuls(referentiels) as Map;
    fichiers['referentiels.json'] = '{\n${[for (final e in r.entries) '${jsonEncode(e.key)}: ${jsonEncode(e.value)}'].join(',\n')}\n}\n';
    return fichiers;
  }
}
