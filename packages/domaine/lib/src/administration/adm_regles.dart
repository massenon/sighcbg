import '../format/format_fr.dart';
import '../format/js.dart' show arrondiJs, nombreOuZero;
import '../format/recherche.dart' show comparerNaturel, trierPar;
import 'adm_notes_donnees.dart';

export 'adm_notes_donnees.dart';

/// RÈGLES DE M13 — ADMINISTRATION & AMBULANCE : courriers, réunions, événements, plan annuel, notes de service, interventions d'ambulance,
/// répertoire des ambulances, parc technique. Portées de `prototype_html/assets/js/modules/m13-administration.js` et rejouées sur les vecteurs
/// de la maquette (`test/vecteurs/administration.json`, engendré par `prototype_html/build/vecteurs-administration.js`).
/// Symboles préfixés `adm` / `Adm`.

typedef AdmFiche = Map<String, Object?>;

/// `C.toDate` : une date sans heure est celle du jour LOCAL ; une date-heure en `Z` est ramenée à l'heure locale du poste.
DateTime? admDate(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();

String admDateFR(Object? v) {
  final d = admDate(v);
  return d == null ? '' : dateFR(d);
}

bool admVrai(Object? v) => v != null && v != false && v != 0 && v != '';

/// Un indicateur de tableau : libellé, valeur affichée, icône Lucide (par son nom), ton, indice.
class AdmKpi {
  const AdmKpi(this.libelle, this.valeur, this.icone, this.ton, [this.indice]);
  final String libelle;
  final String valeur;
  final String icone;
  final String ton;
  final String? indice;
}

/// `C.referenceSuivante` : le plus grand rang déjà écrit pour ce préfixe, plus un, lu sur les fiches EXISTANTES (archivées comprises) — jamais sur un
/// compteur de page (écart E8, E531, E534, E536).
String admReferenceSuivante(String prefixe, int largeur, Iterable<AdmFiche> fiches) {
  var max = 0;
  for (final f in fiches) {
    final r = '${f['reference'] ?? ''}';
    if (r.startsWith(prefixe)) {
      final n = int.tryParse(RegExp(r'^\s*[+-]?\d+').firstMatch(r.substring(prefixe.length))?.group(0) ?? '') ?? 0;
      if (n > max) max = n;
    }
  }
  return '$prefixe${(max + 1).toString().padLeft(largeur, '0')}';
}

/// `Array.prototype.filter(...).length` d'une liste de fiches.
int _compter(Iterable<AdmFiche> l, bool Function(AdmFiche) p) => l.where(p).length;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Courriers
// ---------------------------------------------------------------------------------------------------------------------------------------------

const List<String> admNaturesCourrier = ['Lettre', 'Courriel', 'Note', 'Facture', 'Convocation', 'Rapport'];
const List<String> admServicesCourrier = [
  'Direction Médicale',
  'Direction Administrative',
  'Comptabilité',
  'Ressources humaines',
  'Gestion des stocks',
  'Laboratoire',
  'Pharmacie'
];

/// Le filtre « Service » n'offre que les cinq premiers.
List<String> get admServicesFiltreCourrier => admServicesCourrier.sublist(0, 5);

const Map<String, (String, String)> admTraitementsCourrier = {
  'traite': ('Traité', 'success'),
  'en_cours': ('En cours', 'info'),
  'en_attente': ('En attente', 'warning'),
};

(String, String) admTraitementCourrier(Object? code) => admTraitementsCourrier['$code'] ?? ('—', 'neutral');

String admLibelleSens(Object? sens) => sens == 'arrivee' ? 'Arrivée' : 'Départ';

/// Référence d'un nouveau courrier (E538 levé) : série annuelle `ARR-AAAA-NNNN` / `DEP-AAAA-NNNN`. Le millésime est l'année de la DATE du courrier ([date], ISO), le
/// rang court par sens et par année sur les fiches EXISTANTES ([toutes], archivées comprises).
String admReferenceCourrier(Object? sens, Object? date, Iterable<AdmFiche> toutes) {
  final d = '$date';
  final an = d.length >= 4 ? d.substring(0, 4) : '';
  return admReferenceSuivante('${sens == 'arrivee' ? 'ARR-' : 'DEP-'}$an-', 4, toutes);
}

/// Les exercices que couvre un registre de courriers (années des dates, triées), à défaut l'année [parDefaut] : le sous-titre de l'état imprimé.
String admExercicesCourriers(Iterable<AdmFiche> rows, int parDefaut) {
  final an = <String>{for (final c in rows) if ('${c['date'] ?? ''}'.length >= 4) '${c['date']}'.substring(0, 4)}.toList()..sort();
  return an.isEmpty ? '$parDefaut' : an.join(', ');
}

List<AdmKpi> admKpisCourriers(List<AdmFiche> rows) => [
      AdmKpi('Courriers enregistrés', nombre(rows.length), 'mail', 'navy'),
      AdmKpi('Arrivées', nombre(_compter(rows, (c) => c['sens'] == 'arrivee')), 'mail-open', 'info'),
      AdmKpi('Départs', nombre(_compter(rows, (c) => c['sens'] == 'depart')), 'send', 'success'),
      AdmKpi('En attente de traitement', nombre(_compter(rows, (c) => c['traitement'] == 'en_attente')), 'inbox', 'warning'),
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Réunions
// ---------------------------------------------------------------------------------------------------------------------------------------------

const List<String> admTypesReunion = [
  'Réunion de direction',
  'Réunion de service',
  'Comité d’hygiène',
  'Revue mensuelle d’activité',
  'Réunion du personnel',
  'Comité de gestion des stocks'
];
const List<String> admLieuxReunion = ['Salle de réunion', 'Bureau de la Direction', 'Salle de garde'];

DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

/// « HH:MM » (le champ HTML `time` rend toujours deux chiffres) : « 9:00 » devient « 09:00 ».
String admHeure(Object? v) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch('${v ?? ''}');
  return m == null ? '${v ?? ''}'.trim() : '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
}

/// Une réunion a un DÉBUT (date + heure) : « À venir » tant qu'il n'est pas atteint (écart E540 — comparer la date à l'horloge rangeait parmi le passé
/// toute réunion du jour, même celle de 15 h).
bool admReunionAVenir(AdmFiche r, DateTime maintenant) {
  final d = admDate(r['date']);
  if (d == null) return false;
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${r['heure'] ?? '00:00'}');
  final debut = DateTime(d.year, d.month, d.day, m == null ? 0 : int.parse(m.group(1)!), m == null ? 0 : int.parse(m.group(2)!));
  return !debut.isBefore(maintenant);
}

List<AdmKpi> admKpisReunions(List<AdmFiche> rows, DateTime maintenant) => [
      AdmKpi('Réunions enregistrées', nombre(rows.length), 'users', 'navy'),
      AdmKpi('À venir', nombre(_compter(rows, (r) => admReunionAVenir(r, maintenant))), 'calendar-clock', 'info'),
      AdmKpi('Comptes rendus à rédiger',
          nombre(_compter(rows, (r) => !admVrai(r['compteRendu']) && !admReunionAVenir(r, maintenant) && admDate(r['date']) != null)), 'file-clock', 'warning'),
      AdmKpi('Participants cumulés', nombre(rows.fold<double>(0, (a, r) => a + nombreOuZero(r['participants']))), 'user-check', 'success'),
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Événements & notifications
// ---------------------------------------------------------------------------------------------------------------------------------------------

const List<String> admCategoriesEvenement = ['Santé publique', 'Formation', 'Qualité', 'Technique', 'Logistique', 'Communication', 'Sécurité', 'Réunion'];

/// Jours entre AUJOURD'HUI et la date, comptés PAR JOUR (écart E540 : à 15 h, « demain » valait 0,4 jour et se lisait « Aujourd’hui »).
int admJoursAvant(DateTime maintenant, Object? date) {
  final d = admDate(date);
  if (d == null) return 0;
  return arrondiJs(_jour(d).difference(_jour(maintenant)).inMilliseconds / 86400000).toInt();
}

/// Un événement du jour est « à venir » toute la journée (il se compare par JOUR).
bool admEvenementAVenir(AdmFiche e, DateTime maintenant) {
  final d = admDate(e['date']);
  return d != null && !_jour(d).isBefore(_jour(maintenant));
}

/// Les six prochains événements (aujourd'hui compris), du plus proche au plus lointain.
List<AdmFiche> admProchainsEvenements(List<AdmFiche> rows, DateTime maintenant) =>
    trierPar([for (final e in rows) if (admEvenementAVenir(e, maintenant)) e], (e) => e['date']).take(6).toList();

String admDelaiEvenement(int jours) => jours == 0 ? 'Aujourd’hui' : 'Dans $jours j';

/// `j <= 7` : le délai passe en rouge.
bool admDelaiUrgent(int jours) => jours <= 7;

List<String> admCanauxEvenement(Object? notifier, Object? canauxExistants) {
  if (!admVrai(notifier)) return [];
  final c = canauxExistants is List ? [for (final x in canauxExistants) '$x'] : <String>[];
  return c.isNotEmpty ? c : ['In-app'];
}

/// Création : référence `EVT-NNNN` (rang = effectif + 1) — le préfixe diffère de celui du jeu (`EV-2026-`), écart E532 porté fidèlement.
String admReferenceEvenement(int effectif) => 'EVT-${(effectif + 1).toString().padLeft(4, '0')}';

List<String> admCategoriesPresentes(List<AdmFiche> rows) {
  final s = {for (final r in rows) '${r['categorie']}'}.toList()..sort();
  return s;
}

List<AdmKpi> admKpisEvenements(List<AdmFiche> rows, DateTime maintenant) => [
      AdmKpi('Événements planifiés', nombre(rows.length), 'calendar-heart', 'navy'),
      AdmKpi('À venir', nombre(_compter(rows, (e) => admEvenementAVenir(e, maintenant))), 'calendar-clock', 'info'),
      AdmKpi('Avec notification', nombre(_compter(rows, (e) => admVrai(e['notifier']))), 'bell', 'warning'),
      AdmKpi('Catégories', nombre({for (final r in rows) '${r['categorie']}'}.length), 'layers', 'neutral'),
    ];

/// Paramétrage des notifications système (tableau statique de la maquette) : événement déclencheur, description, canaux actifs.
const List<(String, String, List<String>)> admNotificationsSysteme = [
  ('Nouvelle admission', 'Alerte à l’admission d’un patient', ['In-app']),
  ('Rupture de stock', 'Produit passant sous le seuil d’alerte', ['In-app', 'SMS']),
  ('Péremption proche', 'Lot arrivant à échéance sous 90 jours', ['In-app']),
  ('Résultat de laboratoire disponible', 'Notification au prescripteur', ['In-app', 'SMS']),
  ('Facture générée', 'Notification à la caisse et à la comptabilité', ['In-app']),
  ('Commande à valider', 'Demande de validation à la Directrice Administrative', ['In-app', 'Courriel']),
  ('Paie à valider', 'Soumission des bulletins à la Direction', ['In-app', 'Courriel']),
  ('Carte d’assurance expirée', 'Alerte à la caisse lors de la facturation', ['In-app']),
  ('Facture MECeF rejetée', 'Alerte fiscale à corriger', ['In-app', 'Courriel']),
  ('Tentative de connexion infructueuse', 'Alerte de sécurité à l’administrateur', ['In-app', 'Courriel']),
];

/// `C.seeded` : PRNG déterministe de la maquette.
double Function() admAleatoire(int graine) {
  var s = graine == 0 ? 42 : graine;
  return () {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
}

int _entre(double Function() rnd, int a, int b) => (rnd() * (b - a + 1)).floor() + a;
T _choisir<T>(double Function() rnd, List<T> l) => l[(rnd() * l.length).floor() % l.length];

DateTime _ajouterJours(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second, d.millisecond);

String _p2(int n) => n.toString().padLeft(2, '0');

/// Amorçage des événements (collection vide) : dix événements, graine 2713. `personnel` : les noms des agents actifs, dans l'ordre de la collection.
List<AdmFiche> admAmorcerEvenements(DateTime maintenant, List<String> personnel) {
  final rnd = admAleatoire(2713);
  const evts = [
    ('Journée de vaccination', 'Santé publique'),
    ('Campagne de dépistage du diabète', 'Santé publique'),
    ('Formation aux gestes d’urgence', 'Formation'),
    ('Audit qualité interne', 'Qualité'),
    ('Maintenance de l’échographe', 'Technique'),
    ('Inventaire annuel', 'Logistique'),
    ('Réception des nouveaux équipements', 'Logistique'),
    ('Journée portes ouvertes', 'Communication'),
    ('Formation au nouveau logiciel SIGH', 'Formation'),
    ('Contrôle des extincteurs', 'Sécurité'),
  ];
  final out = <AdmFiche>[];
  for (final (i, e) in evts.indexed) {
    final d = _ajouterJours(maintenant, _entre(rnd, -60, 90));
    final heure = _p2(_entre(rnd, 8, 16));
    final lieu = _choisir(rnd, const ['Clinique', 'Salle de réunion', 'Extérieur']);
    final responsable = _choisir(rnd, personnel);
    final notifier = rnd() > 0.3;
    final canaux = <String>['In-app'];
    if (rnd() > 0.5) canaux.add('SMS');
    if (rnd() > 0.6) canaux.add('Courriel');
    out.add({
      'id': 'EVT${(i + 1).toString().padLeft(3, '0')}',
      'statut': 'actif',
      'reference': 'EV-2026-${(i + 1).toString().padLeft(3, '0')}',
      'libelle': e.$1,
      'categorie': e.$2,
      'date': iso(d),
      'heure': '$heure:00',
      'lieu': lieu,
      'responsable': responsable,
      'notifier': notifier,
      'canaux': canaux,
    });
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Plan annuel de travail
// ---------------------------------------------------------------------------------------------------------------------------------------------

const List<String> admAvancementsPlan = ['Réalisée', 'En cours', 'Planifiée'];

String admTonAvancement(Object? a) => a == 'Réalisée' ? 'success' : (a == 'En cours' ? 'info' : 'warning');

/// `C.sortBy(rows, 'trimestreDebut')`.
List<AdmFiche> admTrierPlan(List<AdmFiche> rows) => trierPar(rows, (r) => r['trimestreDebut']);

/// Le diagramme : le trimestre `q` (1 à 4) est-il couvert par l'action ?
bool admTrimestreActif(AdmFiche r, int q) => q >= (r['trimestreDebut'] as num) && q <= (r['trimestreFin'] as num);

List<AdmKpi> admKpisPlan(List<AdmFiche> rows) => [
      AdmKpi('Actions programmées', nombre(rows.length), 'list-checks', 'navy'),
      AdmKpi('Réalisées', nombre(_compter(rows, (r) => r['avancement'] == 'Réalisée')), 'check-circle-2', 'success'),
      AdmKpi('En cours', nombre(_compter(rows, (r) => r['avancement'] == 'En cours')), 'loader', 'info'),
      AdmKpi('Planifiées', nombre(_compter(rows, (r) => r['avancement'] == 'Planifiée')), 'calendar-clock', 'warning'),
    ];

/// Amorçage du plan (collection vide) : douze actions de l'exercice.
List<AdmFiche> admAmorcerPlan() {
  const actions = [
    ('Déploiement du SIGH-CBG', 'Digitalisation', 1, 4, 'En cours'),
    ('Numérisation des dossiers patients actifs', 'Digitalisation', 2, 4, 'En cours'),
    ('Formation du personnel au nouveau logiciel', 'Formation', 3, 4, 'Planifiée'),
    ('Inventaire général des stocks', 'Logistique', 1, 1, 'Réalisée'),
    ('Renouvellement des conventions d’assurance', 'Partenariats', 1, 2, 'Réalisée'),
    ('Campagne de dépistage communautaire', 'Santé publique', 2, 3, 'En cours'),
    ('Acquisition d’un nouvel échographe', 'Investissement', 3, 3, 'Planifiée'),
    ('Mise à niveau du réseau informatique', 'Investissement', 1, 2, 'Réalisée'),
    ('Audit qualité et sécurité des patients', 'Qualité', 4, 4, 'Planifiée'),
    ('Révision de la grille des primes', 'Ressources humaines', 3, 3, 'Planifiée'),
    ('Clôture comptable de l’exercice', 'Finance', 4, 4, 'Planifiée'),
    ('Rapprochement bancaire mensuel', 'Finance', 1, 4, 'En cours'),
  ];
  return [
    for (final (i, a) in actions.indexed)
      {
        'id': 'PAT${(i + 1).toString().padLeft(3, '0')}',
        'statut': 'actif',
        'reference': 'PA-2026-${(i + 1).toString().padLeft(3, '0')}',
        'action': a.$1,
        'axe': a.$2,
        'trimestreDebut': a.$3,
        'trimestreFin': a.$4,
        'avancement': a.$5,
        'responsable': a.$2 == 'Finance' ? 'KASSA Augustin' : (a.$2 == 'Logistique' ? 'MAMAN Zoukanéri' : 'TAKI Alimatou'),
      }
  ];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Notes de service
// ---------------------------------------------------------------------------------------------------------------------------------------------

List<AdmKpi> admKpisNotesService(int agents) => [
      AdmKpi('Notes en vigueur', nombre(2), 'file-text', 'navy'),
      const AdmKpi('Règles métier pilotées', '2', 'settings-2', 'success', 'Évaluation et primes'),
      AdmKpi('Dernière mise à jour', admDateFR(admNs131.dateEffet), 'calendar-check', 'info'),
      AdmKpi('Agents concernés', nombre(agents), 'users-round', 'neutral'),
    ];

/// Colonne « Fonctions concernées » de la NS 132 : le premier mot du libellé de la fonction (l'identifiant si elle est inconnue).
String admLibelleCourtFonction(String id) {
  final l = admFonctions[id];
  return l == null ? id : l.split(' ').first;
}

String admModePrime(String mode) => mode == 'fixe' ? 'Forfait mensuel' : 'Par occurrence';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Interventions d'ambulance
// ---------------------------------------------------------------------------------------------------------------------------------------------

const Map<String, (String, String)> admEtatsIntervention = {
  'demandee': ('Demandée', 'warning'),
  'en_cours': ('En cours', 'info'),
  'terminee': ('Terminée', 'success'),
};

const List<String> admMotifsIntervention = [
  'Urgence médicale',
  'Transfert inter-hospitalier',
  'Évacuation sanitaire',
  'Retour à domicile',
  'Accident de la voie publique',
  'Urgence obstétricale'
];

/// `5000 + km × 500` quand aucun montant n'est saisi.
num admTarifAmbulance(Object? tarif, Object? kilometrage) =>
    admVrai(nombreOuZero(tarif)) ? nombreOuZero(tarif) : 5000 + nombreOuZero(kilometrage) * 500;

List<AdmKpi> admKpisInterventions(List<AdmFiche> rows, DateTime maintenant) {
  final mois = rows.where((a) {
    final d = admDate(a['dateHeure']);
    return d != null && d.month == maintenant.month && d.year == maintenant.year;
  });
  double somme(Iterable<AdmFiche> l, String k) => l.fold<double>(0, (a, x) => a + nombreOuZero(x[k]));
  return [
    AdmKpi('Interventions enregistrées', nombre(rows.length), 'ambulance', 'danger'),
    AdmKpi('Ce mois-ci', nombre(mois.length), 'calendar', 'navy'),
    AdmKpi('Kilométrage cumulé', '${nombre(somme(rows, 'kilometrage'))} km', 'route', 'info'),
    AdmKpi('Recettes ambulance', money(somme(rows.where((a) => admVrai(a['facture'])), 'tarif')), 'wallet', 'success'),
  ];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Répertoire des ambulances
// ---------------------------------------------------------------------------------------------------------------------------------------------

class AdmTypeAmbulance {
  const AdmTypeAmbulance(this.code, this.libelle, this.icone, this.ton);
  final String code;
  final String libelle;
  final String icone;
  final String ton;
}

class AdmDisponibilite {
  const AdmDisponibilite(this.code, this.libelle, this.ton, this.ordre);
  final String code;
  final String libelle;
  final String ton;
  final int ordre;
}

const List<AdmTypeAmbulance> admTypesAmbulance = [
  AdmTypeAmbulance('clinique', 'Ambulance de la clinique', 'ambulance', 'success'),
  AdmTypeAmbulance('partenaire', 'Structure partenaire', 'handshake', 'info'),
  AdmTypeAmbulance('publique', 'Service public', 'building-2', 'navy'),
  AdmTypeAmbulance('prive', 'Transporteur privé', 'truck', 'neutral'),
];

const List<AdmDisponibilite> admDisponibilites = [
  AdmDisponibilite('disponible', 'Disponible', 'success', 1),
  AdmDisponibilite('en_course', 'En course', 'warning', 2),
  AdmDisponibilite('indisponible', 'Indisponible', 'danger', 3),
];

/// Un type inconnu retombe sur « Transporteur privé », une disponibilité inconnue sur « Indisponible » (le plus prudent).
AdmTypeAmbulance admTypeAmbulance(Object? code) => admTypesAmbulance.firstWhere((t) => t.code == code, orElse: () => admTypesAmbulance[3]);
AdmDisponibilite admDisponibilite(Object? code) => admDisponibilites.firstWhere((d) => d.code == code, orElse: () => admDisponibilites[2]);

/// Un numéro non vérifié depuis plus de ce nombre de jours est SIGNALÉ (jamais masqué).
const int admJoursVerification = 90;

/// Jours écoulés depuis la vérification, comptés PAR JOUR (E540 : vérifié ce matin, « 1 j » dès midi) ; `null` quand la fiche n'a jamais été vérifiée.
int? admJoursDepuis(Object? iso, DateTime maintenant) {
  if (!admVrai(iso)) return null;
  final d = admDate(iso);
  if (d == null) return null;
  return arrondiJs(_jour(maintenant).difference(_jour(d)).inMilliseconds / 86400000).toInt();
}

bool admPerime(AdmFiche r, DateTime maintenant) {
  final j = admJoursDepuis(r['verifieLe'], maintenant);
  return j == null || j > admJoursVerification;
}

/// Les cartes d'appel rapide : DISPONIBLES d'abord, à égalité les moyens de la clinique avant l'extérieur, puis le libellé.
List<AdmFiche> admOrdreAppelRapide(List<AdmFiche> rows) {
  final copie = [for (final (i, l) in rows.indexed) (i, l)];
  copie.sort((a, b) {
    final da = admDisponibilite(a.$2['disponibilite']).ordre, db = admDisponibilite(b.$2['disponibilite']).ordre;
    if (da != db) return da - db;
    final ca = a.$2['type'] == 'clinique', cb = b.$2['type'] == 'clinique';
    if (ca != cb) return ca ? -1 : 1;
    final c = comparerNaturel('${a.$2['libelle']}', '${b.$2['libelle']}');
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in copie) e.$2];
}

/// Lignes du tableau : `C.sortBy(rows, 'libelle')`.
List<AdmFiche> admTrierRepertoire(List<AdmFiche> rows) => trierPar(rows, (r) => r['libelle']);

String admHrefTel(Object? telephone) => 'tel:${'$telephone'.replaceAll(RegExp(r'\s+'), '')}';

List<AdmKpi> admKpisRepertoire(List<AdmFiche> rows, DateTime maintenant) {
  final dispo = rows.where((r) => r['disponibilite'] == 'disponible' && admVrai(r['telephone'])).length;
  final aCompleter = rows.where((r) => !admVrai(r['telephone'])).length;
  final perimes = rows.where((r) => admVrai(r['telephone']) && admPerime(r, maintenant)).length;
  return [
    AdmKpi('Moyens répertoriés', nombre(rows.length), 'ambulance', 'navy'),
    AdmKpi('Disponibles maintenant', nombre(dispo), 'circle-check', dispo > 0 ? 'success' : 'danger', dispo > 0 ? null : 'aucun moyen joignable'),
    AdmKpi('Numéros à renseigner', nombre(aCompleter), 'phone-off', aCompleter > 0 ? 'warning' : 'success'),
    AdmKpi('Non vérifiés depuis $admJoursVerification j', nombre(perimes), 'clock-alert', perimes > 0 ? 'warning' : 'success'),
  ];
}

/// La note « N fiche(s) sans numéro » (texte brut) ; `null` quand toutes les fiches portent un numéro.
String? admNoteSansNumero(List<AdmFiche> rows) {
  final l = rows.where((r) => !admVrai(r['telephone'])).toList();
  if (l.isEmpty) return null;
  return '${l.length} fiche(s) sans numéro : ${l.map((r) => r['libelle']).join(' · ')}. Ces structures sont connues de la clinique mais leur numéro n’a pas été relevé. '
      'Inventer un numéro d’urgence serait la faute la plus grave de tout ce prototype — la fiche reste donc vide et le dit.';
}

const String admNoteAppelRapide =
    'Les moyens disponibles remontent en tête, ceux de la clinique avant l’extérieur. Un numéro qu’on appelle pour s’entendre dire « nous sommes en course » a coûté deux minutes qu’une urgence n’a pas.';

/// Texte de la ligne de vérification d'une carte, ou `null` (numéro vérifié depuis moins de 90 jours, ou absent).
String? admAlerteVerification(AdmFiche r, DateTime maintenant) {
  if (!admVrai(r['telephone']) || !admPerime(r, maintenant)) return null;
  final j = admJoursDepuis(r['verifieLe'], maintenant);
  return j == null ? 'Jamais vérifié' : 'Non vérifié depuis $j jours';
}

/// Fiche créée à l'accueil : la date du jour, « à compléter » si aucun numéro, l'origine — le formulaire l'emporte sur ces valeurs par défaut.
AdmFiche admFicheAmbulance(Map<String, Object?> v, DateTime maintenant) =>
    {'verifieLe': iso(maintenant), 'aCompleter': !admVrai(v['telephone']), 'source': 'Saisie à l’accueil', ...v};

/// Mention portée par chaque fiche de démonstration dont le numéro est fictif (visible sur la carte, au tableau, au tiroir).
const String admMentionNumeroFictif = 'Numéro fictif de démonstration';

/// Amorçage du répertoire (collection vide) : JEU DE DÉMONSTRATION (décision de la Direction du 08/11/2026). La règle « aucun numéro d'urgence ne
/// s'invente » est levée POUR CE JEU SEUL, à condition que chaque numéro soit visiblement FICTIF et NON COMPOSABLE : le motif `00 00 00 00 0N`
/// (N de 1 à 9) ne peut correspondre à aucun abonné. Chaque fiche numérotée porte `fictif: true` et la mention [admMentionNumeroFictif] ; une fiche
/// reste volontairement SANS numéro pour montrer « à compléter », et une autre porte une vérification périmée (> 90 j). Les numéros de l'en-tête
/// officiel de la clinique sont ceux de l'identité, pas ceux d'une ambulance : ils ne figurent plus ici. En production, ce jeu est vidé (voir
/// docs/baguidi/PRODUCTION-VIDER-LE-JEU.md) et l'accueil saisit les vrais numéros.
List<AdmFiche> admAmorcerRepertoire(DateTime maintenant, String chauffeur) {
  // libellé, type, téléphone, second numéro, contact, base, disponibilité, jours depuis la vérification (null = jamais)
  final defs = <(String, String, String?, String?, String?, String, String, int?)>[
    ('Ambulance CBG 01', 'clinique', '00 00 00 00 01', null, null, 'Parakou — clinique', 'disponible', 1),
    ('Ambulance CBG 02', 'clinique', '00 00 00 00 02', null, 'Chauffeur de garde', 'Parakou — clinique', 'en_course', 12),
    ('Hôpital de référence — ambulance', 'publique', '00 00 00 00 03', '00 00 00 00 09', 'Régulation de l’hôpital', 'Parakou', 'disponible', 20),
    ('Zone sanitaire de Parakou', 'publique', '00 00 00 00 04', null, 'Bureau de la zone', 'Parakou', 'disponible', 45),
    ('Sapeurs-pompiers', 'publique', '00 00 00 00 05', null, 'Poste de commandement', 'Parakou', 'disponible', 60),
    ('Ambulance privée — Transport sanitaire (démonstration)', 'prive', '00 00 00 00 06', null, 'Permanence', 'Parakou', 'en_course', 85),
    ('SAMU régional', 'publique', '00 00 00 00 07', null, 'Régulation médicale', 'Parakou', 'indisponible', 130),
    ('Centre de santé de renfort', 'partenaire', '00 00 00 00 08', null, 'Infirmier de garde', 'Parakou — périphérie', 'disponible', 30),
    ('Structure partenaire — évacuation sanitaire', 'partenaire', null, null, 'À identifier', 'Parakou', 'indisponible', null),
  ];
  AdmFiche une((String, String, String?, String?, String?, String, String, int?) d) {
    final tel = d.$3;
    return <String, Object?>{
      'libelle': d.$1,
      'type': d.$2,
      if (tel != null) 'telephone': tel,
      if (d.$4 != null) 'telephone2': d.$4,
      'contact': d.$5 ?? chauffeur,
      'base': d.$6,
      'disponibilite': d.$7,
      if (d.$8 != null) 'verifieLe': iso(DateTime(maintenant.year, maintenant.month, maintenant.day - d.$8!)),
      'aCompleter': tel == null,
      if (tel != null) 'fictif': true,
      'source': tel == null ? 'Structure à contacter — numéro à renseigner' : admMentionNumeroFictif,
    };
  }

  return [for (final d in defs) une(d)];
}

/// Note du jeu de démonstration (texte brut) : `null` quand aucune fiche ne porte un numéro fictif (répertoire réel).
String? admNoteDemo(List<AdmFiche> rows) {
  final n = rows.where((r) => r['fictif'] == true).length;
  if (n == 0) return null;
  return 'Jeu de démonstration : $n fiche(s) portent un $admMentionNumeroFictif (00 00 00 00 0N, non composable). '
      'Ils seront remplacés par les vrais numéros avant la mise en production.';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Parc technique & maintenance
// ---------------------------------------------------------------------------------------------------------------------------------------------

const List<(String, String, String)> admEtatsMateriel = [
  ('service', 'En service', 'success'),
  ('panne', 'En panne', 'danger'),
  ('reforme', 'Réformé', 'neutral'),
];
const List<String> admCategoriesMateriel = [
  'Automate de laboratoire',
  'Imagerie',
  'Bloc opératoire',
  'Matériel de soins',
  'Énergie & froid',
  'Bureautique & réseau',
  'Véhicule'
];
const List<String> admLocalisationsMateriel = [
  'Laboratoire',
  'Salle d’échographie',
  'Bloc opératoire',
  'Salle de soins',
  'Maternité',
  'Hospitalisation',
  'Pharmacie',
  'Administration',
  'Local technique'
];

/// Un état inconnu retombe sur « En service » (comme la maquette).
(String, String, String) admEtatMateriel(Object? code) => admEtatsMateriel.firstWhere((e) => e.$1 == code, orElse: () => admEtatsMateriel[0]);

/// Entretien échu : dernier entretien + périodicité (mois de 30,4 j) dépassés. Un équipement RÉFORMÉ n'a plus d'entretien à faire (écart E536).
bool admEntretienEchu(AdmFiche r, DateTime maintenant) {
  if (!admVrai(r['dernierEntretien']) || !admVrai(r['periodiciteMois'])) return false;
  if (r['etat'] == 'reforme') return false;
  final d = admDate(r['dernierEntretien']);
  if (d == null) return false;
  final echeance = _ajouterJours(d, arrondiJs(nombreOuZero(r['periodiciteMois']) * 30.4).toInt());
  return echeance.isBefore(maintenant);
}

/// Une fiche renseignée cesse d'être « à compléter » : le marquage disparaît par la SAISIE (marque, n° de série et mise en service).
bool admMaterielACompleter(Map<String, Object?> v) => !(admVrai(v['marque']) && admVrai(v['numeroSerie']) && admVrai(v['miseEnService']));

List<AdmKpi> admKpisMateriel(List<AdmFiche> rows, DateTime maintenant) {
  final pannes = rows.where((r) => r['etat'] == 'panne').length;
  return [
    AdmKpi('Équipements au parc', nombre(rows.length), 'wrench', 'navy'),
    AdmKpi('En panne', nombre(pannes), 'triangle-alert', pannes > 0 ? 'danger' : 'success'),
    AdmKpi('Entretien échu', nombre(rows.where((r) => admEntretienEchu(r, maintenant)).length), 'calendar-clock', 'warning'),
    AdmKpi('Fiches à compléter', nombre(rows.where((r) => admVrai(r['aCompleter'])).length), 'circle-help', 'neutral',
        'marque, n° de série et mise en service non relevés'),
  ];
}

/// Filtre « Suivi » : panne / entretien échu / fiche à compléter.
bool admSuiviMateriel(AdmFiche r, String v, DateTime maintenant) {
  if (v == 'panne') return r['etat'] == 'panne';
  if (v == 'echu') return admEntretienEchu(r, maintenant);
  return admVrai(r['aCompleter']);
}

/// Amorçage du parc (collection vide) : dix-huit équipements que les documents laissent DÉDUIRE ; marque, n° de série et mise en service NON relevés.
List<AdmFiche> admAmorcerMateriel(DateTime maintenant) {
  final rnd = admAleatoire(1348);
  const defs = [
    ('Automate d’hématologie', 'Automate de laboratoire', 'Laboratoire', 'service'),
    ('Automate de biochimie', 'Automate de laboratoire', 'Laboratoire', 'service'),
    ('Centrifugeuse', 'Automate de laboratoire', 'Laboratoire', 'service'),
    ('Microscope optique', 'Automate de laboratoire', 'Laboratoire', 'service'),
    ('Échographe', 'Imagerie', 'Salle d’échographie', 'service'),
    ('Bistouri électrique', 'Bloc opératoire', 'Bloc opératoire', 'service'),
    ('Table d’opération', 'Bloc opératoire', 'Bloc opératoire', 'service'),
    ('Aspirateur chirurgical', 'Bloc opératoire', 'Bloc opératoire', 'panne'),
    ('Autoclave de stérilisation', 'Bloc opératoire', 'Bloc opératoire', 'service'),
    ('Concentrateur d’oxygène', 'Matériel de soins', 'Hospitalisation', 'service'),
    ('Moniteur multiparamétrique', 'Matériel de soins', 'Hospitalisation', 'service'),
    ('Table d’accouchement', 'Matériel de soins', 'Maternité', 'service'),
    ('Couveuse néonatale', 'Matériel de soins', 'Maternité', 'service'),
    ('Groupe électrogène', 'Énergie & froid', 'Local technique', 'service'),
    ('Réfrigérateur à réactifs', 'Énergie & froid', 'Laboratoire', 'service'),
    ('Réfrigérateur de pharmacie', 'Énergie & froid', 'Pharmacie', 'service'),
    ('Serveur et onduleur', 'Bureautique & réseau', 'Administration', 'service'),
    ('Ambulance de la clinique', 'Véhicule', 'Local technique', 'service'),
  ];
  return [
    for (final (i, m) in defs.indexed)
      () {
        final dernier = _ajouterJours(maintenant, -_entre(rnd, 20, 260));
        return <String, Object?>{
          'id': 'MAT${(i + 1).toString().padLeft(3, '0')}',
          'statut': 'actif',
          'reference': 'EQ-${(i + 1).toString().padLeft(3, '0')}',
          'libelle': m.$1,
          'categorie': m.$2,
          'localisation': m.$3,
          'etat': m.$4,
          'periodiciteMois': (m.$2 == 'Automate de laboratoire' || m.$2 == 'Énergie & froid') ? 6 : 12,
          'dernierEntretien': iso(dernier),
          if (m.$4 == 'panne') 'observation': 'Panne signalée par le bloc — dépannage à commander.',
          'aCompleter': true,
        };
      }()
  ];
}
