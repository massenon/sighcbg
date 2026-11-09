import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import 'referentiel_barre.dart';

/// Ce que la coque sait de la maquette : le manifeste de navigation, la matrice des droits et l'état de parité de chaque
/// écran. Tout est ENGENDRÉ (`prototype_html/build/gen-poste-assets.js`) ; rien n'est écrit à la main, sauf `modulesActifs.reference.json` : la copie
/// figée des deux fiches d'activité (MOD01, MOD02) avec lesquelles `rbac.json` a été engendré, que la maquette ne livre pas dans ce dépôt.
class DonneesNavigation {
  DonneesNavigation(
      {required this.manifeste,
      required this.matrice,
      required Map<String, Map<String, Object?>> parite,
      this.referenceRbac,
      this.referenceModules,
      this.perimetreLivre = const {},
      this.barre = const ReferentielBarre(),
      Map<String, Map<String, bool>> modulesVoir = const {},
      Map<String, ({String titre, String description})> descriptions = const {}})
      : _parite = parite,
        _modulesVoir = modulesVoir,
        _descriptions = descriptions;

  /// Droit de VOIR un module, par rôle, tel que la matrice engendrée le porte (`matriceModules` de `rbac.json`). Sert à décider si la page d'accueil d'un module
  /// (hub) est ouverte au rôle ; une décision prise à chaud sur un module n'y est pas relue (les écrans, eux, suivent la matrice à chaud).
  final Map<String, Map<String, bool>> _modulesVoir;

  /// Le module est-il ouvert au rôle ? Inconnu (matrice sans modules) : réputé ouvert, ce sont alors les écrans qui décident.
  ///
  /// Un rôle que `rbac.json` a extrait ARCHIVÉ (pharmacien, RH) n'a que des refus dans `matriceModules` ; rouvert depuis (jeu livré du 06/11/2026), il est jugé sur ce que la matrice EN FORCE lui ouvre : le module est visible dès qu'un de ses écrans l'est. Tout autre rôle suit `matriceModules`.
  bool moduleVisible(String role, String code) {
    if (_modulesVoir.isEmpty) return true;
    if (_modulesVoir[role]?[code] ?? false) return true;
    if (matrice.estArchive(role)) return false;
    // Seul un rôle extrait ARCHIVÉ (drapeau `archive` de `rbac.json`) est jugé sur ses écrans : pour les autres, le module décide (matrice engendrée).
    final extraitArchive = matrice.rolesBruts.any((r) => '${r['id']}' == role && r['archive'] == true);
    if (!extraitArchive) return false;
    return manifeste.tousLesEcrans.any((e) => !e.hub && e.module == code && matrice.peutVoir(role, e.id));
  }

  /// Rubriques de la recherche globale et actions rapides de la barre supérieure (engendrées depuis `nav.js`).
  final ReferentielBarre barre;
  final Manifeste manifeste;

  /// La matrice EN FORCE : celle de `rbac.json` (engendrée), ou la matrice superposée à chaud par [aChaud].
  final MatriceDroits matrice;
  final Map<String, Map<String, Object?>> _parite;

  /// Titre et description de chaque écran, repris de la déclaration de l'écran dans la maquette (`ecrans-descriptions.json`, engendré) : les cartes
  /// des pages d'accueil de module (hubs) les affichent.
  final Map<String, ({String titre, String description})> _descriptions;

  /// Titre de la déclaration de l'écran (vide si la maquette n'en donne pas : on retombe sur l'intitulé du manifeste).
  String? titreDeclare(String id) {
    final t = _descriptions[id]?.titre;
    return t == null || t.isEmpty ? null : t;
  }

  /// Description de la déclaration de l'écran, `null` si la maquette n'en porte aucune.
  String? descriptionDeclaree(String id) {
    final d = _descriptions[id]?.description;
    return d == null || d.isEmpty ? null : d;
  }

  /// Les fiches que la matrice engendrée a connues au jour de l'extraction : la collection `rbac` du jeu livré, et la configuration des activités avec
  /// laquelle `rbac.json` a été engendré (`modulesActifs.reference.json` : banque de sang et donneurs fermés, MOD01 et MOD02). Elles sont la RÉFÉRENCE de
  /// la superposition : seul ce qui a changé depuis elles remplace la matrice engendrée. `null` = inconnues, aucune superposition.
  ///
  /// La référence des activités N'EST PAS le jeu livré `jeu/modulesActifs.json` : le magasin est semé à partir de ce même fichier, si bien qu'une
  /// fermeture ajoutée au jeu (les modules hors périmètre de la Clinique Baguidi) serait aussi dans la référence, ne différerait de rien et ne fermerait
  /// rien au ruban. Comparée à la configuration de l'extraction, elle devient une différence, donc une fermeture effective.
  final List<Map<String, Object?>>? referenceRbac, referenceModules;

  /// Les identifiants des fiches d'activité que le JEU LIVRÉ ajoute à la configuration de l'extraction : le périmètre de l'établissement (Clinique
  /// Baguidi : M1 à M5, statistiques et tableaux de bord cliniques, MOD03 à MOD09). Vide depuis le 06/11/2026 (nuit) : la Direction a rouvert M1 à M10 avec
  /// tout, banque de sang et donneurs comprises ; le mécanisme demeure pour une fermeture de périmètre future. Rouvrir l'une d'elles depuis cfg-modules la rouvre comme toute autre.
  final Set<String> perimetreLivre;

  /// Le périmètre livré s'applique-t-il ? Toujours au poste. Les bancs d'essai des écrans de modules fermés (M1 à M5, écrits avant le 06/11/2026) le
  /// lèvent dans `flutter_test_config.dart` pour éprouver ces écrans comme si la clinique les rouvrait ; `fermetures_baguidi_test.dart` le rétablit
  /// et mesure le périmètre réel (même principe que `CoquePoste.panneauOuvertAuDemarrage`). Seules les fiches [perimetreLivre] sont concernées : une
  /// fermeture saisie dans cfg-modules s'applique toujours.
  static bool appliquerPerimetreLivre = true;

  /// Les mêmes données de navigation sous une autre matrice (manifeste, parité et références partagés).
  DonneesNavigation avecMatrice(MatriceDroits m) =>
      DonneesNavigation(manifeste: manifeste, matrice: m, parite: _parite, referenceRbac: referenceRbac, referenceModules: referenceModules, perimetreLivre: perimetreLivre, barre: barre, modulesVoir: _modulesVoir, descriptions: _descriptions);

  /// DROITS À CHAUD (A4) : la matrice engendrée reste la BASE ; les fiches de la collection `rbac` (surcharges par rôle, module et écran, rôles
  /// archivés ou créés) et de `modulesActifs` (activités fermées) du magasin la superposent, comme `N.can()` de la maquette, pour tout ce qui a changé
  /// depuis les fiches de l'extraction (`superposerDroits`). Fiches inchangées, matrice inchangée ; une décision saisie depuis m14-roles ou cfg-modules
  /// (ou rechargée du magasin persisté) est effective aussitôt. Références inconnues ou collections vides : la matrice engendrée reste en force.
  DonneesNavigation aChaud(Magasin m) {
    final rbac = m.collection('rbac').toutes;
    final modules = [
      for (final f in m.collection('modulesActifs').toutes)
        if (appliquerPerimetreLivre || !perimetreLivre.contains('${f['id']}')) f
    ];
    final base = ((referenceRbac == null && referenceModules == null) || (rbac.isEmpty && modules.isEmpty))
        ? this
        : avecMatrice(superposerDroits(matrice, manifeste,
            rbac: rbac, modulesActifs: modules, referenceRbac: referenceRbac ?? const [], referenceModules: referenceModules ?? const []));
    // LES SPÉCIALITÉS s'ajoutent APRÈS la superposition : leurs écrans copient les droits que la matrice EN FORCE donne à leur écran modèle, donc une
    // décision saisie dans m14-roles ou cfg-modules les suit sans qu'on les nomme.
    return base.avecSpecialites(m.collection('specialites').actives);
  }

  /// LES SPÉCIALITÉS (PRD P0-12) : une fiche de la collection `specialites` = une entrée du ruban (« Spécialités », rangée secondaire de M2, domaine Soins)
  /// et trois écrans génériques (consultation, agenda et file, statistiques), SANS une ligne de code par spécialité. Les droits de chaque écran sont ceux de
  /// son écran modèle ([specModelesDroits]) : un rôle qui n'a pas le module n'a pas la spécialité. Aucune fiche : la navigation est rendue telle quelle.
  DonneesNavigation avecSpecialites(Iterable<Map<String, Object?>> fiches) {
    final actives = [for (final f in fiches) if (f['statut'] != 'archive' && '${f['code'] ?? ''}'.isNotEmpty) f];
    if (actives.isEmpty) return this;
    final ecrans = <EcranNav>[];
    final descriptions = {..._descriptions};
    final modeles = <String, String>{};
    for (final f in actives) {
      final code = '${f['code']}';
      final libelle = '${f['libelle'] ?? code}';
      for (final v in SpecVue.values) {
        final id = specIdEcran(code, v);
        final modele = manifeste.ecran(specModelesDroits[v]!);
        ecrans.add(EcranNav(
            id: id,
            label: v == SpecVue.hub ? libelle : '$libelle — ${v.libelle}',
            icone: v == SpecVue.hub ? '${f['icone'] ?? 'stethoscope'}' : ['clipboard-list', 'calendar-days', 'chart-column'][v.index - 1],
            module: specModule,
            moduleLabel: specRangeeLibelle,
            domaine: specDomaine,
            hub: false,
            standalone: false,
            roles: modele?.roles));
        modeles[id] = specModelesDroits[v]!;
        descriptions[id] = (
          titre: v == SpecVue.hub ? libelle : '$libelle — ${v.libelle}',
          description: v == SpecVue.hub ? '${f['description'] ?? ''}' : '${v.libelle} de la spécialité ${libelle.toLowerCase()}.'
        );
      }
    }
    return DonneesNavigation(
        manifeste: manifeste.avecEcrans(
            ecrans: ecrans,
            domaine: specDomaine,
            code: specModule,
            libelleRangee: specRangeeLibelle,
            icone: 'stethoscope',
            idsRangee: [for (final f in actives) specIdEcran('${f['code']}')]),
        matrice: matrice.avecDroitsDerives(modeles),
        parite: _parite,
        referenceRbac: referenceRbac,
        referenceModules: referenceModules,
        perimetreLivre: perimetreLivre,
        barre: barre,
        modulesVoir: _modulesVoir,
        descriptions: descriptions);
  }

  /// Tranche de portage (1 à 6) d'un écran, ou `null`.
  int? tranche(String id) => (_parite[id]?['tranche'] as num?)?.toInt();
  String statut(String id) => '${_parite[id]?['statut'] ?? 'non commencé'}';

  /// La configuration des activités avec laquelle `rbac.json` a été engendré, RÉFÉRENCE de la superposition (relative au dossier des données).
  /// Les fiches de la collection `rbac` avec lesquelles `rbac.json` a été engendré (copie figée de `jeu/rbac.json` à l'extraction : pharmacien et RH archivés).
  /// Distincte du jeu livré : réactiver un rôle dans `jeu/rbac.json` doit être une DIFFÉRENCE avec l'extraction, donc effective.
  static const fichierReferenceRbac = 'rbac.reference.json';

  static const fichierReferenceModules = 'modulesActifs.reference.json';

  /// Les fiches du jeu livré absentes de la référence de l'extraction.
  static Set<String> _perimetre(List<Map<String, Object?>>? reference, List<Map<String, Object?>>? jeu) {
    if (reference == null || jeu == null) return const {};
    final connues = {for (final f in reference) '${f['id']}'};
    return {for (final f in jeu) if (!connues.contains('${f['id']}')) '${f['id']}'};
  }

  static List<Map<String, Object?>>? _fiches(String? json) =>
      json == null ? null : [for (final f in (jsonDecode(json) as List)) (f as Map).cast<String, Object?>()];

  /// `fichesRbac` / `fichesModules` : RÉFÉRENCE de la superposition à chaud (`jeu/rbac.json`, et `modulesActifs.reference.json`, la configuration des
  /// activités de l'extraction de `rbac.json`).
  static DonneesNavigation depuisJson(
      {required String manifeste,
      required String rbac,
      required String parite,
      String? fichesRbac,
      String? fichesModules,
      String? fichesJeuModules,
      String? rubriques,
      String? descriptions}) {
    final p = <String, Map<String, Object?>>{
      for (final e in ((jsonDecode(parite) as Map)['ecrans'] as List))
        '${(e as Map)['id']}': e.cast<String, Object?>(),
    };
    return DonneesNavigation(
      manifeste: Manifeste.depuisJson(
          (jsonDecode(manifeste) as Map).cast<String, Object?>()),
      matrice: MatriceDroits.depuisJson(
          (jsonDecode(rbac) as Map).cast<String, Object?>()),
      modulesVoir: _modulesVoirDe(rbac),
      parite: p,
      referenceRbac: _fiches(fichesRbac),
      referenceModules: _fiches(fichesModules),
      perimetreLivre: _perimetre(_fiches(fichesModules), _fiches(fichesJeuModules)),
      barre: rubriques == null ? const ReferentielBarre() : ReferentielBarre.depuisJson(rubriques),
      descriptions: descriptions == null
          ? const {}
          : {
              for (final e in ((jsonDecode(descriptions) as Map)['ecrans'] as Map).entries)
                '${e.key}': (titre: '${(e.value as Map)['titre'] ?? ''}', description: '${(e.value as Map)['description'] ?? ''}')
            },
    );
  }

  static Future<DonneesNavigation> chargerAssets() async => depuisJson(
        manifeste: await rootBundle.loadString('assets/donnees/manifeste.json'),
        rbac: await rootBundle.loadString('assets/donnees/rbac.json'),
        parite: await rootBundle.loadString('assets/donnees/parite.json'),
        fichesRbac: await rootBundle.loadString('assets/donnees/$fichierReferenceRbac'),
        fichesModules: await rootBundle.loadString('assets/donnees/$fichierReferenceModules'),
        fichesJeuModules: await rootBundle.loadString('assets/donnees/jeu/modulesActifs.json'),
        rubriques: await rootBundle.loadString('assets/donnees/rubriques.json'),
        descriptions: await rootBundle.loadString('assets/donnees/ecrans-descriptions.json'),
      );

  /// Pour les tests : lit les mêmes fichiers engendrés sur le disque.
  static DonneesNavigation depuisDossier([String dossier = 'assets/donnees']) =>
      depuisJson(
        manifeste: File('$dossier/manifeste.json').readAsStringSync(),
        rbac: File('$dossier/rbac.json').readAsStringSync(),
        parite: File('$dossier/parite.json').readAsStringSync(),
        fichesRbac: _lireSiPresent('$dossier/$fichierReferenceRbac'),
        fichesModules: _lireSiPresent('$dossier/$fichierReferenceModules'),
        fichesJeuModules: _lireSiPresent('$dossier/jeu/modulesActifs.json'),
        rubriques: _lireSiPresent('$dossier/rubriques.json'),
        descriptions: _lireSiPresent('$dossier/ecrans-descriptions.json'),
      );

  static Map<String, Map<String, bool>> _modulesVoirDe(String rbac) {
    final m = (jsonDecode(rbac) as Map)['matriceModules'];
    if (m is! Map) return const {};
    return {
      for (final r in m.entries)
        '${r.key}': {
          for (final c in (r.value as Map).entries) '${c.key}': (c.value as Map)['voir'] == true || (c.value as Map)['horsMatrice'] == true
        }
    };
  }

  static String? _lireSiPresent(String chemin) => File(chemin).existsSync() ? File(chemin).readAsStringSync() : null;
}
