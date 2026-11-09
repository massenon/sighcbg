/// LES INDICATEURS AGRÉGÉS DE LA CLINIQUE, publiés par la mère au relais (décision de la Direction du 09/11/2026, ADR-0007).
///
/// Le relais reste OPAQUE pour tout dossier : il reçoit ici des NOMBRES, et seulement des nombres, plus quelques valeurs de forme imposée (un code
/// d'obligation fiscale, une date, un numéro de version, l'identifiant technique d'un appareil). Jamais un nom, un code patient, un téléphone, une adresse,
/// un motif, un diagnostic, un nom de fournisseur ou d'agent : le calculateur ne LIT même pas ces champs.
///
/// Ce fichier ne porte que des règles pures : il ne lit pas la base, ne parle pas au réseau, ne sait pas l'heure. Il reçoit les fiches par collection et
/// rend un instantané. Une mesure que les fiches reçues ne permettent pas de calculer vaut `null` (« non disponible »), jamais zéro : un zéro dirait que
/// rien ne s'est passé là où la mère n'a simplement rien reçu.
library;

/// Version du schéma de l'instantané. Le relais refuse une version qu'il ne connaît pas.
const int ikVersionSchema = 1;

/// Plafond de postes listés : un instantané reste de petite taille (le relais borne aussi le corps de la requête).
const int ikMaxAppareils = 50;

/// Réglages par défaut (graines : la valeur en vigueur vit en base, aux Paramètres du poste).
const int ikIntervalleDefautSecondes = 900;
const int ikIntervalleMinSecondes = 60;
const int ikIntervalleMaxSecondes = 86400;
const int ikJoursPeremptionDefaut = 90;

/// Un poste connu de la mère : identifiant technique et dernier contact. L'étiquette (qui peut porter un nom de personne) n'entre JAMAIS ici.
class IkAppareil {
  const IkAppareil({required this.identifiant, required this.dernierContactMs});
  final String identifiant;
  final int dernierContactMs;
}

/// Tout ce que le calculateur lit. `collections` : les fiches ACTIVES (non archivées) reçues par la mère, par nom de collection ; une collection absente de
/// la table donne des mesures « non disponibles ».
class IkEntree {
  const IkEntree({
    required this.collections,
    required this.maintenant,
    this.appareils = const [],
    this.versionApplication = '0.0.0',
    this.joursPeremption = ikJoursPeremptionDefaut,
  });
  final Map<String, List<Map<String, Object?>>> collections;
  final DateTime maintenant;
  final List<IkAppareil> appareils;
  final String versionApplication;
  final int joursPeremption;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le schéma : la SEULE description de ce qui peut partir. Le relais en porte l'exacte réplique (`App\Relais\IndicateursClinique`).
// ---------------------------------------------------------------------------------------------------------------------------------------------

enum _Genre { entier, entierNullable, pourcentageNullable, instantMs, codeOuNull, dateOuNull, version, etatJeu, schema, identifiant }

class _Noeud {
  const _Noeud.feuille(this.genre)
      : enfants = null,
        liste = null;
  const _Noeud.objet(this.enfants)
      : genre = null,
        liste = null;
  const _Noeud.liste(this.liste)
      : genre = null,
        enfants = null;
  final _Genre? genre;
  final Map<String, _Noeud>? enfants;
  final _Noeud? liste;
}

const _schema = _Noeud.objet({
  'schema': _Noeud.feuille(_Genre.schema),
  'genere_le': _Noeud.feuille(_Genre.instantMs),
  'version_application': _Noeud.feuille(_Genre.version),
  'etat_jeu': _Noeud.feuille(_Genre.etatJeu),
  'patients': _Noeud.objet({
    'actifs': _Noeud.feuille(_Genre.entierNullable),
    'nouveaux_mois': _Noeud.feuille(_Genre.entierNullable),
  }),
  'activite_mois': _Noeud.objet({
    'm2_consultations': _Noeud.feuille(_Genre.entierNullable),
    'm2_visites': _Noeud.feuille(_Genre.entierNullable),
    'm2_rendezvous': _Noeud.feuille(_Genre.entierNullable),
    'm3_admissions': _Noeud.feuille(_Genre.entierNullable),
  }),
  'facturation_mois': _Noeud.objet({
    'factures_emises': _Noeud.feuille(_Genre.entierNullable),
    'montant_facture': _Noeud.feuille(_Genre.entierNullable),
    'montant_encaisse': _Noeud.feuille(_Genre.entierNullable),
    'reste_du': _Noeud.feuille(_Genre.entierNullable),
  }),
  'stock': _Noeud.objet({
    'articles_sous_seuil': _Noeud.feuille(_Genre.entierNullable),
    'lots_proches_peremption': _Noeud.feuille(_Genre.entierNullable),
    'lots_perimes': _Noeud.feuille(_Genre.entierNullable),
  }),
  'comptabilite': _Noeud.objet({
    'echeances_en_retard': _Noeud.feuille(_Genre.entierNullable),
    'brouillons_non_valides': _Noeud.feuille(_Genre.entierNullable),
    'prochaine_echeance_code': _Noeud.feuille(_Genre.codeOuNull),
    'prochaine_echeance_date': _Noeud.feuille(_Genre.dateOuNull),
  }),
  'utilisateurs_actifs': _Noeud.feuille(_Genre.entierNullable),
  'taux_occupation_lits_pct': _Noeud.feuille(_Genre.pourcentageNullable),
  'postes': _Noeud.liste(_Noeud.objet({
    'appareil': _Noeud.feuille(_Genre.identifiant),
    'derniere_synchro': _Noeud.feuille(_Genre.instantMs),
  })),
});

/// Les chemins (séparés par des points, `[]` pour les éléments d'une liste) de tous les champs permis : de quoi comparer le schéma Dart au schéma PHP.
List<String> ikChemins() {
  final sortie = <String>[];
  void marche(_Noeud n, String prefixe) {
    if (n.enfants != null) {
      for (final e in n.enfants!.entries) {
        marche(e.value, prefixe.isEmpty ? e.key : '$prefixe.${e.key}');
      }
    } else if (n.liste != null) {
      marche(n.liste!, '$prefixe[]');
    } else {
      sortie.add(prefixe);
    }
  }

  marche(_schema, '');
  return sortie;
}

final RegExp _reCode = RegExp(r'^[A-Z0-9_-]{1,24}$');
final RegExp _reDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _reVersion = RegExp(r'^\d{1,3}(\.\d{1,3}){2}(\+\d{1,6})?$');
final RegExp _reIdentifiant = RegExp(r'^[A-Za-z0-9_-]{1,40}$');
const int _plafondEntier = 10000000000000;

String? _verifierFeuille(_Genre g, Object? v) {
  bool entier(Object? x) => x is int && x >= 0 && x <= _plafondEntier;
  switch (g) {
    case _Genre.entier:
      return entier(v) ? null : 'entier positif attendu';
    case _Genre.entierNullable:
      return v == null || entier(v) ? null : 'entier positif ou nul attendu';
    case _Genre.pourcentageNullable:
      return v == null || (v is int && v >= 0 && v <= 100) ? null : 'pourcentage entier (0 à 100) ou nul attendu';
    case _Genre.instantMs:
      return entier(v) ? null : 'horodatage entier attendu';
    case _Genre.codeOuNull:
      return v == null || (v is String && _reCode.hasMatch(v)) ? null : 'code d’obligation (majuscules, chiffres, tirets) ou nul attendu';
    case _Genre.dateOuNull:
      return v == null || (v is String && _reDate.hasMatch(v)) ? null : 'date AAAA-MM-JJ ou nulle attendue';
    case _Genre.version:
      return v is String && _reVersion.hasMatch(v) ? null : 'numéro de version attendu';
    case _Genre.etatJeu:
      return v == 'demonstration' || v == 'production' ? null : 'demonstration ou production attendu';
    case _Genre.schema:
      return v == ikVersionSchema ? null : 'version de schéma inconnue';
    case _Genre.identifiant:
      return v is String && _reIdentifiant.hasMatch(v) ? null : 'identifiant technique attendu';
  }
}

/// Vérifie STRICTEMENT un instantané : tout champ absent du schéma, toute chaîne libre, tout type inattendu est un défaut. Liste vide : conforme.
List<String> ikValider(Object? instantane) {
  final defauts = <String>[];
  void marche(_Noeud n, Object? v, String chemin) {
    if (n.enfants != null) {
      if (v is! Map) {
        defauts.add('$chemin : objet attendu');
        return;
      }
      for (final k in v.keys) {
        if (!n.enfants!.containsKey(k)) defauts.add('${chemin.isEmpty ? '' : '$chemin.'}$k : champ inattendu');
      }
      for (final e in n.enfants!.entries) {
        final c = chemin.isEmpty ? e.key : '$chemin.${e.key}';
        if (!v.containsKey(e.key)) {
          defauts.add('$c : champ manquant');
        } else {
          marche(e.value, v[e.key], c);
        }
      }
    } else if (n.liste != null) {
      if (v is! List) {
        defauts.add('$chemin : liste attendue');
        return;
      }
      if (v.length > ikMaxAppareils) defauts.add('$chemin : plus de $ikMaxAppareils éléments');
      for (var i = 0; i < v.length && i < ikMaxAppareils; i++) {
        marche(n.liste!, v[i], '$chemin[$i]');
      }
    } else {
      final d = _verifierFeuille(n.genre!, v);
      if (d != null) defauts.add('$chemin : $d');
    }
  }

  marche(_schema, instantane, '');
  return defauts;
}

/// Toutes les chaînes d'un instantané, pour le contrôle de non-nominatif (un test les confronte aux noms du jeu).
List<String> ikChaines(Object? v) => [
      if (v is String) v,
      if (v is Map) ...[for (final e in v.entries) ...[e.key.toString(), ...ikChaines(e.value)]],
      if (v is List) for (final x in v) ...ikChaines(x),
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le calculateur
// ---------------------------------------------------------------------------------------------------------------------------------------------

String _deuxChiffres(int n) => n.toString().padLeft(2, '0');
String _jour(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_deuxChiffres(d.month)}-${_deuxChiffres(d.day)}';

/// Les dix premiers caractères d'une date ISO (`2026-11-09` ou `2026-11-09T10:00:00Z`), ou `null` si le champ n'en porte pas la forme.
String? _dateDe(Object? v) {
  if (v is! String || v.length < 10) return null;
  final j = v.substring(0, 10);
  return _reDate.hasMatch(j) ? j : null;
}

int _montant(Object? v) => v is num && v.isFinite ? v.round() : 0;

/// Calcule l'instantané. Les montants sont des FCFA entiers ; aucune chaîne libre n'en sort.
Map<String, Object?> ikCalculer(IkEntree e) {
  final c = e.collections;
  final auj = _jour(e.maintenant);
  final mois = auj.substring(0, 7);
  final limite = _jour(DateTime(e.maintenant.year, e.maintenant.month, e.maintenant.day + e.joursPeremption));

  List<Map<String, Object?>>? col(String n) => c[n];
  int? compter(String n, bool Function(Map<String, Object?>) q) => col(n)?.where(q).length;
  bool dansLeMois(Map<String, Object?> f, List<String> champs) => champs.any((k) => _dateDe(f[k])?.startsWith(mois) ?? false);
  bool actif(Map<String, Object?> f) => (f['statut'] ?? 'actif') == 'actif' && f['actif'] != false;

  // --- patients ---
  final patients = col('patients');
  // --- facturation du mois : les pro forma ne sont pas des factures émises ---
  final facturesMois = col('factures')?.where((f) => dansLeMois(f, ['date']) && f['proforma'] != true).toList();
  int somme(String champ) => facturesMois!.fold(0, (a, f) => a + _montant(f[champ]));
  int resteDu(Map<String, Object?> f) => f['reliquat'] is num
      ? _montant(f['reliquat'])
      : (_montant(f['montantTTC']) - _montant(f['montantPaye']) - _montant(f['partAssurance'])).clamp(0, _plafondEntier).toInt();

  // --- stock ---
  final produits = col('produits');
  int? souSeuil = produits?.where((p) {
    final seuil = p['seuilAlerte'];
    final stock = p['stock'] is num ? p['stock'] as num : (p['stockGros'] is num || p['stockDetail'] is num ? _montant(p['stockGros']) + _montant(p['stockDetail']) : null);
    return seuil is num && seuil > 0 && stock != null && stock <= seuil;
  }).length;
  final lots = col('lots')?.where((l) => _montant(l['quantiteRestante']) > 0 && _dateDe(l['datePeremption']) != null).toList();

  // --- échéances fiscales : une échéance non payée dont la date est passée est en retard ; la prochaine est la plus proche à venir ---
  final echeances = col('echeancesFiscales')?.where((x) => x['paye'] != true && _dateDe(x['echeance']) != null).toList();
  Map<String, Object?>? prochaine;
  if (echeances != null) {
    final avenir = echeances.where((x) => _dateDe(x['echeance'])!.compareTo(auj) >= 0).toList()..sort((a, b) => _dateDe(a['echeance'])!.compareTo(_dateDe(b['echeance'])!));
    prochaine = avenir.isEmpty ? null : avenir.first;
  }

  // --- écritures : une pièce = un numéro, quel que soit son nombre de lignes ---
  final brouillons = col('ecritures')?.where((x) => x['statut'] == 'brouillon').map((x) => '${x['numero'] ?? x['pieceId'] ?? x['id']}').toSet().length;

  // --- lits ---
  final lits = col('lits')?.where(actif).length;
  final occupes = compter('admissions', (a) => a['statut'] == 'en_cours');
  final taux = lits == null || lits == 0 || occupes == null ? null : ((occupes * 100) / lits).round().clamp(0, 100).toInt();

  // --- l'état du jeu se DÉDUIT des fiches : une fiche active marquée fictive fait un jeu de démonstration ---
  final demo = ['patients', 'consultations', 'factures'].any((n) => col(n)?.any((f) => f['fictif'] == true) ?? false);

  final appareils = [...e.appareils]..sort((a, b) => a.identifiant.compareTo(b.identifiant));

  return {
    'schema': ikVersionSchema,
    'genere_le': e.maintenant.millisecondsSinceEpoch,
    'version_application': _reVersion.hasMatch(e.versionApplication) ? e.versionApplication : '0.0.0',
    'etat_jeu': demo ? 'demonstration' : 'production',
    'patients': {
      'actifs': patients?.where(actif).length,
      'nouveaux_mois': patients?.where((p) => dansLeMois(p, ['dateCreation'])).length,
    },
    'activite_mois': {
      'm2_consultations': col('consultations')?.where((f) => dansLeMois(f, ['date'])).length,
      'm2_visites': col('visites')?.where((f) => dansLeMois(f, ['date', 'dateHeure'])).length,
      'm2_rendezvous': col('rendezvous')?.where((f) => dansLeMois(f, ['date', 'dateHeure'])).length,
      'm3_admissions': col('admissions')?.where((f) => dansLeMois(f, ['dateEntree'])).length,
    },
    'facturation_mois': {
      'factures_emises': facturesMois?.length,
      'montant_facture': facturesMois == null ? null : somme('montantTTC'),
      'montant_encaisse': facturesMois == null ? null : somme('montantPaye'),
      'reste_du': facturesMois == null ? null : facturesMois.fold<int>(0, (a, f) => a + resteDu(f)),
    },
    'stock': {
      'articles_sous_seuil': souSeuil,
      'lots_proches_peremption': lots?.where((l) {
        final d = _dateDe(l['datePeremption'])!;
        return d.compareTo(auj) >= 0 && d.compareTo(limite) <= 0;
      }).length,
      'lots_perimes': lots?.where((l) => _dateDe(l['datePeremption'])!.compareTo(auj) < 0).length,
    },
    'comptabilite': {
      'echeances_en_retard': echeances?.where((x) => _dateDe(x['echeance'])!.compareTo(auj) < 0).length,
      'brouillons_non_valides': brouillons,
      // Le code est assaini : une valeur qui n'aurait pas la forme d'un code d'obligation ne part pas.
      'prochaine_echeance_code': prochaine == null ? null : (_reCode.hasMatch('${prochaine['code']}') ? '${prochaine['code']}' : 'AUTRE'),
      'prochaine_echeance_date': prochaine == null ? null : _dateDe(prochaine['echeance']),
    },
    'utilisateurs_actifs': col('utilisateurs')?.where(actif).length,
    'taux_occupation_lits_pct': taux,
    'postes': [
      for (final a in appareils.take(ikMaxAppareils))
        if (_reIdentifiant.hasMatch(a.identifiant)) {'appareil': a.identifiant, 'derniere_synchro': a.dernierContactMs < 0 ? 0 : a.dernierContactMs},
    ],
  };
}
