import 'dart:convert';
import 'dart:io';

import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';

import 'explorateur.dart';

/// Dossier lisible de chaque module (code du manifeste → nom de dossier et intitulé).
const Map<String, (String, String)> modules = {
  'M1': ('m01-patients', 'M1 — Patients & dossier médical'),
  'M2': ('m02-consultations', 'M2 — Rendez-vous, consultations, imagerie, spécialités'),
  'SPEC': ('m02-consultations', 'M2 — Rendez-vous, consultations, imagerie, spécialités'),
  'M3': ('m03-hospitalisation', 'M3 — Hospitalisation, soins & bloc'),
  'M4': ('m04-maternite', 'M4 — Maternité, naissances & décès'),
  'M5': ('m05-laboratoire', 'M5 — Laboratoire & banque de sang'),
  'M6': ('m06-pharmacie-stocks', 'M6 — Pharmacie & stocks'),
  'M7': ('m07-achats', 'M7 — Achats & fournisseurs'),
  'M8': ('m08-facturation-caisse', 'M8 — Facturation & caisse'),
  'M9': ('m09-assurances', 'M9 — Assurances & créances'),
  'M10': ('m10-ressources-humaines', 'M10 — Ressources humaines'),
  'M11': ('m11-paie', 'M11 — Paie & primes'),
  'M12': ('m12-comptabilite', 'M12 — Comptabilité & gestion'),
  'M13': ('m13-administration', 'M13 — Administration & ambulance'),
  'M14': ('m14-securite', 'M14 — Sécurité & utilisateurs'),
  'MECEF': ('mecef', 'MECeF — Facture normalisée'),
  'GED': ('ged', 'GED — Gestion documentaire'),
  'RAP': ('rap-etats', 'RAP — Rapports & états officiels'),
  'PIL': ('pil-pilotage', 'PIL — Pilotage & statistiques'),
  'DASH': ('dash-tableaux-de-bord', 'DASH — Tableaux de bord'),
  'CFG': ('cfg-configuration', 'CFG — Configuration de la clinique'),
  'IMP': ('imp-importation', 'IMP — Importation de données'),
  'MERE': ('mere-supervision', 'Poste mère — supervision'),
  'AUTH': ('auth-acces', 'Accès & sécurité'),
  'RLS': ('rls-relais', 'Relais en ligne'),
  'SUP': ('sup-aide', 'Aide & assistance'),
  'TRANSVERSE': ('transverse', 'Transverse — gabarit commun des listes filtrées'),
};

/// Rôles à essayer EN PREMIER pour chaque module : le poste qui édite réellement ces pièces.
const Map<String, List<String>> rolesParModule = {
  'M1': ['reception', 'medecin'],
  'M2': ['medecin', 'echographiste', 'reception'],
  'M3': ['infirmier', 'medecin', 'chirurgien'],
  'M4': ['infirmier', 'medecin'],
  'M5': ['laborantin', 'medecin'],
  'M6': ['stock', 'caissier'],
  'M7': ['stock', 'da'],
  'M8': ['caissier', 'da'],
  'M9': ['da', 'comptable'],
  'M10': ['da', 'direction'],
  'M11': ['da', 'comptable'],
  'M12': ['comptable', 'da'],
  'M13': ['agentadmin', 'da'],
  'M14': ['admin'],
  'MECEF': ['da', 'comptable', 'caissier'],
  'GED': ['agentadmin', 'da'],
  'RAP': ['da', 'direction'],
  'PIL': ['direction', 'da'],
  'DASH': ['direction', 'da'],
  'CFG': ['admin', 'da'],
};

/// Écrans à explorer : tous ceux du manifeste (spécialités comprises), hors pages d'accueil de module, dans l'ordre des modules.
List<String> ecransAExplorer(DonneesNavigation donnees, Magasin m) {
  final nav = donnees.aChaud(m);
  final ids = [for (final e in nav.manifeste.tousLesEcrans) if (!e.hub && !e.standalone) e.id];
  return ids;
}

/// Le rôle sous lequel on ouvre l'écran : le poste habituel du module s'il a le droit d'ÉCRIRE, sinon le premier rôle qui peut le VOIR, sinon l'administrateur.
String roleDe(DonneesNavigation nav, String id) {
  final e = nav.manifeste.ecran(id);
  final pref = rolesParModule[e?.module] ?? const <String>[];
  final tous = [for (final r in nav.matrice.rolesBruts) '${r['id']}'];
  final ordre = [...pref, ...tous.where((r) => !pref.contains(r) && r != 'admin'), 'admin'];
  for (final r in ordre) {
    if (nav.matrice.peutEditer(r, id)) return r;
  }
  for (final r in ordre) {
    if (nav.matrice.peutVoir(r, id)) return r;
  }
  return 'admin';
}

String slug(String s) {
  const de = 'àâäçéèêëîïôöùûüÿœÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸŒ’\'';
  const vers = 'aaaceeeeiioouuuyoAAACEEEEIIOOUUUYO--';
  var o = '';
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    o += i >= 0 ? vers[i] : c;
  }
  o = o.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return o.length > 72 ? o.substring(0, 72).replaceAll(RegExp(r'-+$'), '') : o;
}

/// Titre de repli quand la fenêtre d'aperçu n'en donne pas (badge : modale propre au module M10).
const Map<String, String> titresParDefaut = {
  'm10-badges': 'Badge du personnel — carte CR80',
  'm10-badges-impression': 'Planche de badges (A4)',
};

/// Écrit `presentation/<module>/<document>.pdf`, `INDEX.md` (tableau de couverture produit par l'outil) et `couverture.json`. FUSIONNE avec ce qui existe : un
/// rejeu partiel (`SIGH_SPECIMENS_ECRANS`) ne retire rien du dossier.
Future<void> ecrireDossier(String dossier, DonneesNavigation donnees, List<Capture> captures, List<String> notes, Map<String, String> ecrans) async {
  final racine = Directory(dossier)..createSync(recursive: true);
  final nav = donnees;
  final jsonExistant = File('${racine.path}/couverture.json');
  final ancien = jsonExistant.existsSync() ? (jsonDecode(jsonExistant.readAsStringSync()) as Map).cast<String, Object?>() : <String, Object?>{};
  final lignes = <String, Map<String, Object?>>{
    for (final l in (ancien['specimens'] as List? ?? const [])) '${(l as Map)['fichier']}': l.cast<String, Object?>(),
  };
  final doublons = <String>{...((ancien['memeGabarit'] as List? ?? const []).cast<String>())};
  // UN SPÉCIMEN PAR DOCUMENT : une même pièce se retrouve depuis le tableau de bord, le pilotage et son écran propre (« Reçu de paiement », « Fiche patient »…). On garde
  // celle de l'écran du module, et l'on ramène les titres qui portent une donnée (période, journal) à leur titre de gabarit.
  String canon(String t) => t
      .replaceFirst(RegExp(r'^Journal comptable — .*'), 'Journal comptable')
      .replaceFirst(RegExp(r'^Fiche d’évaluation du mois de .*'), 'Fiche d’évaluation du mois');
  int rang(Capture c) {
    final code = nav.manifeste.ecran(c.ecran)?.module ?? '';
    final secondaire = const {'DASH', 'PIL', 'CFG', 'IMP', 'RAP'}.contains(code);
    return (secondaire ? 10 : 0) + (c.geste.startsWith('fabrique') ? 1 : 0);
  }

  final choisies = <String, Capture>{};
  for (final c in captures) {
    var titre = c.titre.isEmpty ? (titresParDefaut[c.ecran] ?? c.reference) : c.titre;
    if (titre.startsWith('Sélection — ')) {
      doublons.add('$titre (${c.ecran})');
      titre = 'Sélection — liste filtrée d’un registre';
    }
    final cle = slug(canon(titre));
    final actuelle = choisies[cle];
    if (actuelle == null || rang(c) < rang(actuelle)) choisies[cle] = c;
  }
  for (final c in choisies.values) {
    final e = nav.manifeste.ecran(c.ecran);
    final code = c.module ?? e?.module ?? c.ecran.split('-').first.toUpperCase();
    var titre = canon(c.titre.isEmpty ? (titresParDefaut[c.ecran] ?? c.reference) : c.titre);
    var rep = (modules[code] ?? ('autres', code)).$1;
    if (titre.startsWith('Sélection — ')) {
      rep = 'transverse';
      titre = 'Sélection — liste filtrée d’un registre';
    }
    final fichier = '$rep/${slug(titre)}.pdf';
    Directory('${racine.path}/$rep').createSync(recursive: true);
    File('${racine.path}/$fichier').writeAsBytesSync(c.octets);
    lignes[fichier] = {
      'module': rep == 'transverse' ? 'TRANSVERSE' : code,
      'dossier': rep,
      'fichier': fichier,
      'document': titre,
      'ecran': c.ecran,
      'role': c.role,
      'geste': c.geste,
      'octets': c.octets.length,
    };
  }
  final liste = lignes.values.toList()..sort((a, b) => '${a['fichier']}'.compareTo('${b['fichier']}'));
  final toutesNotes = <String>{...((ancien['notes'] as List? ?? const []).cast<String>()), ...notes}.toList();
  File(jsonExistant.path).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'specimens': liste,
    'notes': toutesNotes,
    'memeGabarit': doublons.toList()..sort(),
    'ecransParcourus': {...((ancien['ecransParcourus'] as Map? ?? const {}).cast<String, Object?>()), ...ecrans},
  }));
  final sb = StringBuffer('# Index des spécimens (engendré par l’outil — ne pas éditer à la main)\n\n');
  sb.writeln('Dossier engendré par `apps/poste/tool/specimens/generer_specimens_test.dart` : ${liste.length} spécimens.\n');
  String? courant;
  for (final l in liste) {
    if (courant != l['module']) {
      courant = '${l['module']}';
      sb.writeln('\n## ${modules[courant]?.$2 ?? courant}\n');
      sb.writeln('| Document | Fichier | Écran source | Rôle | Geste |');
      sb.writeln('|---|---|---|---|---|');
    }
    sb.writeln('| ${l['document']} | `${l['fichier']}` | `${l['ecran']}` | ${l['role']} | ${l['geste']} |');
  }
  File('${racine.path}/INDEX.md').writeAsStringSync(sb.toString());
}
