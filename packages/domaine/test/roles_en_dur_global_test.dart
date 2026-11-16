// CLIQUET GLOBAL « AUCUNE LISTE DE RÔLES EN DUR » (Direction de Baguidi, compléments du 16/11/2026, section 7 : « toutes les décisions de droit passent par la matrice ou un
// geste réservé ; un cliquet global le garde »). Il REMPLACE le cliquet de la pharmacie et de la caisse (`roles_en_dur_pharmacie_caisse_test.dart`, 16/11/2026) et en étend
// le périmètre à TOUS les fichiers `lib` des quatre racines : le domaine, le poste, le mobile et le client de synchronisation.
//
// Le contrôle cherche les formes d'une DÉCISION écrite sur un identifiant de rôle (lus dans `rbac.json` : un rôle ajouté demain est cherché aussi) : comparaison
// (`== 'caissier'`), appartenance (`.contains('pharmacien')`), liste ou ensemble littéral (`['stock', 'da']`, y compris écrit sur plusieurs lignes), argument nommé
// (`role: 'caissier'`). Les accès à un champ (`p['stock']`) et les clés de table (`'poste': 'stock'`, `'stock': …`) n'en sont pas. Les lignes de commentaire sont ignorées.
//
// La table [_tolerances] est une LISTE FERMÉE des sites tolérés, fichier par fichier, avec leur MOTIF : référentiel des gestes (la seule liste d'origine), table du banc,
// axe Fonction du personnel (pas un rôle), identifiant de poste ou de profil mobile, nom de champ, chantier parallèle. Le cliquet ÉCHOUE si un site apparaît (convertir en
// droit d'écran ou en geste réservé) ET si un site disparaît sans que la liste soit abaissée (la place libérée ne doit pas servir à un autre). Un fichier absent de la table
// a ZÉRO site toléré.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Les quatre racines (chemins relatifs à `packages/domaine`).
const _racines = ['lib', '../../apps/poste/lib', '../../apps/mobile/lib', '../sync_dart/lib'];

/// Un site toléré : le nombre de littéraux du fichier, et pourquoi ils ne décident d'aucun droit.
typedef Tolerance = ({int sites, String motif});

/// LES SITES TOLÉRÉS. Liste fermée : elle ne fait que DÉCROÎTRE.
const Map<String, Tolerance> _tolerances = {
  // --- Le référentiel lui-même : la SEULE liste d'origine admise.
  'lib/src/droits/gestes_reserves.dart': (sites: 160, motif: 'référentiel des gestes réservés : les rôles d’ORIGINE de chaque geste (`rolesDefaut`), que la matrice accorde ou retire — la seule liste admise'),
  // --- Chantier parallèle (caisse et tarifs, 16/11/2026) : non converti ici pour éviter les conflits, à convertir par ce chantier.
  'lib/src/consultation/cs_moteur.dart': (sites: 7, motif: 'chantier parallèle (caisse/tarifs) : `_tachesDef` (champ descriptif `role` des tâches d’aval, porté par les vecteurs, jamais lu pour décider) et `capacite == \'chirurgien\' || session.role == \'chirurgien\'` (à rapprocher du geste `rubriques_chirurgicales`)'),
  // --- Tables et données qui ne décident d'aucun droit de la session.
  'lib/src/sync/pair.dart': (sites: 80, motif: '`droitsBancPair` : la table du BANC d’essai (la production passe par `droitsDepuisMatrice` et les gestes `conflits_trancher` / `sync_valider_flux`) ; et `op.collection == \'stock\'`, un nom de collection'),
  'lib/src/achats/besoins.dart': (sites: 3, motif: 'identifiants de POSTE de notification (`\'poste\': \'comptable\' / \'stock\'`), routés au centre par les gestes `alertes_comptable` / `alertes_stock`'),
  'lib/src/rh/planning_rh.dart': (sites: 2, motif: 'identifiants d’ÉTAPE du circuit RH stockés sur les pièces (`surveillant`, `daf`) ; qui tranche chaque étape est le geste `gesteEtapeRh`'),
  'lib/src/parametres/definitions.dart': (sites: 1, motif: 'valeur de CHOIX du réglage `planning.circuitPresences` (identifiant d’étape `surveillant`)'),
  'lib/src/parametres/parametres.dart': (sites: 1, motif: 'nom de FAMILLE de paramètres (`rh`) fermée au téléphone'),
  'lib/src/rapports/rap_regles.dart': (sites: 3, motif: 'identifiants de SECTION d’un modèle de rapport (`stock`, `comptable`, `rh`)'),
  'lib/src/labo/cat_regles.dart': (sites: 1, motif: 'nom de CHAMP d’une fiche de réactif (`stock`)'),
  'lib/src/import/jeux_import.dart': (sites: 1, motif: 'nom de CHAMP des compteurs de stock (`stock`)'),
  '../../apps/poste/lib/sync/fusion_activite.dart': (sites: 1, motif: 'nom de CHAMP compteur d’un produit (`stock`)'),
  '../../apps/poste/lib/modules/m10/rhd_mes.dart': (sites: 1, motif: 'nom de CHAMP d’une colonne (`medecin` du rendez-vous)'),
  'lib/src/assistant/ast_catalogue.dart': (sites: 1, motif: 'MOTS de la question de l’agent (assistant), pas un rôle'),
  'lib/src/assistant/ast_executeurs.dart': (sites: 1, motif: 'MOTS de la question de l’agent (assistant), pas un rôle'),
  'lib/src/assistant/ast_reconnaissance.dart': (sites: 1, motif: 'MOTS de la question de l’agent (assistant), pas un rôle'),
  // --- Axe FONCTION du personnel (D.CAPACITES) : la fonction de l'agent, pas le rôle de la session.
  'lib/src/consultation/cs_referentiels.dart': (sites: 1, motif: 'axe FONCTION : `csPeutEcrireRubrique(rubrique, capacite)` lit la fonction de l’agent (chirurgien) ; le rôle passe par le geste `rubriques_chirurgicales`'),
  'lib/src/import/donnees_import.dart': (sites: 8, motif: 'référentiel des FONCTIONS du personnel importables (D.CAPACITES)'),
  'lib/src/mobile/mob_regles.dart': (sites: 6, motif: 'FONCTIONS du profil soignant du mobile et identifiant de PROFIL mobile `reception` (réception de secours)'),
  'lib/src/paie/pai_moteur.dart': (sites: 1, motif: 'axe FONCTION : le signataire « comptable » d’une pièce de paie est cherché par la fonction du personnel'),
  'lib/src/rh/rhb_regles.dart': (sites: 8, motif: 'FONCTIONS des règles de planning et colonnes de la grille des primes (NS 132)'),
  'lib/src/tableaux_de_bord/tbb_regles.dart': (sites: 3, motif: 'FONCTIONS paramédicales comptées par le tableau du surveillant'),
  '../../apps/poste/lib/modules/cfg/cfa_pieces.dart': (sites: 2, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m1/pieces.dart': (sites: 1, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m10/rhb_planning.dart': (sites: 4, motif: 'FONCTIONS dont la grille de la semaine affiche les agents'),
  '../../apps/poste/lib/modules/m2/ag_commun.dart': (sites: 1, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m2/cr_saisie.dart': (sites: 1, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m2/cs_commun.dart': (sites: 4, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m2/sp_commun.dart': (sites: 1, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m2/sp_repertoire.dart': (sites: 1, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m3/bloc_cro.dart': (sites: 1, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m3/hos_commun.dart': (sites: 4, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m3/surv_rapport.dart': (sites: 1, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m4/mat_commun.dart': (sites: 2, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m4/mat_dossier.dart': (sites: 1, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  '../../apps/poste/lib/modules/m5/dem_commun.dart': (sites: 1, motif: 'axe FONCTION du personnel (`fonction`/`qualite` de la fiche de l’agent, D.CAPACITES) : une liste d’options de praticiens, pas une décision de droit sur le RÔLE de la session'),
  // --- Profil du MOBILE (`soignant` / `reception`) : un profil d'appareil fixé par la mère, pas un rôle de session.
  '../../apps/mobile/lib/moteur/moteur_mobile.dart': (sites: 1, motif: 'identifiant de PROFIL mobile `reception` (réception de secours)'),
  '../../apps/poste/lib/modules/mere/mra_affectation.dart': (sites: 1, motif: 'identifiant de PROFIL mobile `reception` (libellé de la fonction affectée)'),
  '../../apps/poste/lib/modules/mere/mra_supervision.dart': (sites: 1, motif: 'identifiant de PROFIL mobile `reception` (libellé du code d’appairage)'),
  '../sync_dart/lib/src/mere.dart': (sites: 1, motif: 'identifiant de PROFIL mobile `reception` (affectation validée par le domaine)'),
  // --- Le COMPTE ADMINISTRATEUR d'amorçage de l'installation : une identité structurelle, pas un droit réglable.
  'lib/src/acces/acc_secours.dart': (sites: 1, motif: 'le code de secours ne rouvre QUE le compte administrateur d’amorçage (EF-INST) ; en faire un geste permettrait de l’étendre au compte d’un agent'),
  '../../apps/poste/lib/core/identifiants.dart': (sites: 1, motif: 'amorçage des identifiants du compte administrateur d’installation (premier démarrage)'),
  '../../apps/poste/lib/core/service_installation.dart': (sites: 4, motif: 'garde du DERNIER compte administrateur actif après la clôture de l’installation (il ne s’archive ni ne se dégrade)'),
  '../../apps/poste/lib/modules/mere/mrc_sources.dart': (sites: 1, motif: 'lecture d’état de la mise en service : y a-t-il un compte administrateur actif'),
  // --- À ARBITRER (écart E3584) : le défaut SEMÉ d'un réglage de clinique « liste de rôles » décidé par la Direction (Q3 du 17/11/2026).
  'lib/src/parametres/reglages_roles.dart': (sites: 2, motif: 'défaut semé du réglage `cloture.rolesInventaire` (Q3, Direction du 17/11/2026 : la liste est un PARAMÈTRE en base, versionné) — à arbitrer : le convertir en geste comme `achats_valider`'),
};

List<String> _fichiers() {
  final out = <String>[];
  for (final r in _racines) {
    final d = Directory(r);
    if (!d.existsSync()) continue;
    for (final e in d.listSync(recursive: true).whereType<File>()) {
      if (e.path.endsWith('.dart')) out.add(e.path.replaceAll('\\', '/'));
    }
  }
  return out..sort();
}

/// Les littéraux de rôle qui ont la forme d'une décision, ligne par ligne (`ligne:rôle`).
List<String> rolesEnDur(String source, List<String> roles) {
  final alt = roles.map(RegExp.escape).join('|');
  final index = RegExp(r"(?<=[\w\)\]\?!])\[\s*'[^']*'\s*\]");
  final formes = [
    RegExp("[=!]=\\s*'($alt)'"),
    RegExp("'($alt)'\\s*[=!]="),
    RegExp("\\.contains\\(\\s*'($alt)'\\s*\\)"),
    RegExp("(?<=[\\[{,])\\s*'($alt)'(?=\\s*[,\\]}])"),
    RegExp("\\brole\\w*\\s*:\\s*'($alt)'"),
    // Un élément de liste ou d'ensemble écrit SEUL sur sa ligne (littéral sur plusieurs lignes) : `  'comptable',`.
    RegExp("^\\s*'($alt)'\\s*,?\\s*[\\]}]?[,;)]*\\s*\$"),
  ];
  final out = <String>[];
  final lignes = const LineSplitter().convert(source);
  for (var i = 0; i < lignes.length; i++) {
    if (lignes[i].trimLeft().startsWith('//')) continue;
    final l = lignes[i].replaceAll(index, '');
    final vus = <int>{};
    for (final f in formes) {
      for (final m in f.allMatches(l)) {
        final debut = m.start + m.group(0)!.indexOf("'${m.group(1)}'");
        if (vus.add(debut)) out.add('${i + 1}:${m.group(1)}');
      }
    }
  }
  return out;
}

void main() {
  final rbac = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final roles = [for (final r in rbac['roles'] as List) '${(r as Map)['id']}'];

  test('le détecteur reconnaît une décision écrite sur un rôle, et pas un champ ni une clé de table', () {
    expect(rolesEnDur("if (role == 'caissier') {}", roles), ['1:caissier']);
    expect(rolesEnDur("const ['stock', 'pharmacien'].contains(r)", roles), ['1:stock', '1:pharmacien']);
    expect(rolesEnDur("x.contains('pharmacien')", roles), ['1:pharmacien']);
    expect(rolesEnDur("(role: 'caissier', module: 'M8')", roles), ['1:caissier']);
    expect(rolesEnDur("const s = {\n  'comptable',\n  'da'\n};", roles), ['2:comptable', '3:da'], reason: 'un ensemble écrit sur plusieurs lignes');
    expect(rolesEnDur("final s = p['stock'] + q['da'];", roles), isEmpty);
    expect(rolesEnDur("{'poste': 'stock', 'type': 'x'}", roles), isEmpty);
    expect(rolesEnDur("  'stock': 'Gestionnaire de stock',", roles), isEmpty, reason: 'une clé de table');
    expect(rolesEnDur("// if (role == 'caissier')", roles), isEmpty);
    expect(rolesEnDur("if (role == 'un_role_qui_n_existe_pas') {}", roles), isEmpty);
  });

  test('CLIQUET GLOBAL : aucun nouveau nom de rôle en dur dans les quatre racines ; la liste des sites tolérés ne fait que décroître', () {
    final ecarts = <String>[];
    final vus = <String>{};
    for (final f in _fichiers()) {
      vus.add(f);
      final trouves = rolesEnDur(File(f).readAsStringSync(), roles);
      final t = _tolerances[f];
      final plafond = t?.sites ?? 0;
      if (trouves.length > plafond) {
        ecarts.add('$f : ${trouves.length} littéral(aux) de rôle pour ${plafond == 0 ? 'aucun site toléré' : '$plafond toléré(s)'} (${trouves.join(', ')}). '
            'Décider sur la matrice (droit d’écran) ou sur un geste réservé (`gestesReserves`), jamais sur un nom de rôle.');
      } else if (trouves.length < plafond) {
        ecarts.add('$f : ${trouves.length} littéral(aux) pour $plafond toléré(s) : ABAISSER la tolérance (le cliquet ne remonte jamais).');
      }
    }
    for (final k in _tolerances.keys) {
      if (!vus.contains(k)) ecarts.add('$k : fichier toléré introuvable (retiré ou déplacé : retirer sa ligne).');
    }
    for (final e in _tolerances.entries) {
      if (e.value.motif.trim().isEmpty) ecarts.add('${e.key} : tolérance sans motif.');
    }
    expect(ecarts, isEmpty, reason: ecarts.join('\n'));
  });
}
