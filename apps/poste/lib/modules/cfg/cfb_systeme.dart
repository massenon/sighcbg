import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/persistance.dart' show CleLocale;
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/ecran_hub.dart';
import 'cfa_commun.dart';
import 'cfb_commun.dart';
import 'cfg_parametres.dart';

const _mono = 'LiberationMono';
const _idReinit = 'reinitAutorisee';
const _idBareme = 'baremeModifiable';

/// Les collections que le poste tient pour SIENNES mais que la maquette ne connaît pas : la matrice et le manifeste engendrés, et les réglages
/// d'exploitation. `validationsReferentiels` (les validations des artefacts du code) est essentielle dans la maquette (`S.COLLECTIONS_ESSENTIELLES`) ; la liste
/// `cfbEssentielles` du domaine, tenue par ses vecteurs, ne la porte pas encore : elle survit donc au vidage ici, comme les autres collections techniques. Elles survivent à tout vidage et ne figurent ni au « Contenu du jeu de données » ni à la corbeille.
const cfbCollectionsTechniques = {'rolesBase', 'modulesManifeste', 'reglages', valCollectionValidations, parCollectionParametres, parCollectionUsages};

/// Les noms des collections du poste (celles de la maquette qu'il connaît).
List<String> cfbNomsCollections() => [for (final n in Magasin.collectionsDuJeu) if (!cfbCollectionsTechniques.contains(n)) n];

/// L'état de la persistance du poste : `disponible` reste faux tant que la base locale chiffrée n'est pas branchée derrière le magasin (plan S4).
class CfbPersistance {
  const CfbPersistance._();
  static bool Function() disponible = () => false;
}

/// Où l'export JSON est écrit. Le poste n'a pas de sélecteur de fichier natif : le dossier personnel de l'agent, sinon le dossier temporaire du système.
class CfbExport {
  const CfbExport._();
  static Future<String> Function(String nom, String contenu) ecrire = (nom, contenu) async {
    final dossier = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    final base = (dossier != null && Directory(dossier).existsSync()) ? Directory(dossier) : Directory.systemTemp;
    final f = File('${base.path}${Platform.pathSeparator}$nom');
    await f.writeAsString(contenu);
    return f.path;
  };
}

/// D'où la régénération du jeu de démonstration relit ses collections : les assets du poste (injectable pour un test).
class CfbJeu {
  const CfbJeu._();
  static Future<String> Function(String nom) charger = (nom) => rootBundle.loadString('assets/donnees/jeu/$nom.json');
}

/// LE GESTE PAR DÉFAUT DE MISE EN PRODUCTION (décision D6 de la Direction, 09/11/2026) : ARCHIVER le jeu de démonstration, ne rien effacer (RG-14).
///
/// Pour chaque collection d'ACTIVITÉ (la même liste que [cfbViderActivite] : ni essentielle, ni technique), TOUTES les fiches actives passent à l'état archivé
/// avec le motif [cfbMotifArchivageJeuDemo], l'acteur de la session et la date — brouillons compris, jamais validés au passage. Les
/// files d'attente, tâches bloquées et notifications sont des collections d'activité comme les autres. Les échéances fiscales restent en service, remises à
/// « non payée » ; leur paiement de démonstration, donnée fictive et non pièce comptable, est SUPPRIMÉ et n'est rangé nulle part ([cfbRetirerPaiementDemo]).
///
/// Ce qui ne bouge PAS : les collections essentielles et techniques (personnel, tarifs, plan comptable, comptes, droits, identité, paramètres fiscaux…), les
/// salaires du personnel, les comptes de démonstration, la Corbeille, et le JOURNAL D'AUDIT — il reçoit une entrée par collection touchée (compte archivé,
/// dont brouillons) et une entrée de synthèse (RG-12). Les compteurs de numérotation ne reculent pas : les générateurs lisent les fiches archivées comprises,
/// donc un code archivé n'est jamais réattribué (RG-01). Tout se restaure depuis la Corbeille de `cfg-systeme`.
///
/// Garde-fous TENUS ICI, non seulement par le bouton : la bascule « autoriser la réinitialisation » doit être ouverte et [motifDuGeste] (celui que l'agent a
/// saisi) doit être renseigné, sinon [CfbRefusArchivage] est levée AVANT toute écriture. Le motif du geste va au journal ; celui des fiches est fixe.
CfbBilanArchivage cfbArchiverJeuDemo(Magasin m, {required String motifDuGeste}) {
  final refus = cfbRefusArchivage(autorisee: cfbReglage(m, _idReinit, false) == true, motif: motifDuGeste);
  if (refus != null) throw CfbRefusArchivage(refus);
  const motif = cfbMotifArchivageJeuDemo;
  final conservees = {...cfbEssentielles, ...cfbCollectionsTechniques};
  final par = m.utilisateur;
  final le = m.horloge();
  final marques = cfbMarquesArchivage(motif: motif, par: par, le: le);
  final archivees = <String, int>{}, brouillons = <String, int>{};
  var paiementsRetires = 0;
  final noms = [for (final n in cfbNomsCollections()) if (!conservees.contains(n)) n];
  for (final n in noms) {
    final col = m.collection(n);
    if (n == 'echeancesFiscales') {
      var retires = 0;
      final remises = [
        for (final f in col.toutes)
          () {
            final r = cfbRetirerPaiementDemo(f);
            retires += r?.retires ?? 0;
            return r?.fiche ?? f;
          }()
      ];
      paiementsRetires = retires;
      if (retires > 0) {
        col.remplacerContenu(remises);
        m.journaliser('Paiements fictifs d’échéances fiscales retirés', col.module, col.entite ?? n, n, {'paiementsFictifs': retires},
            {'paiementsRetires': retires, 'motif': motif});
      }
      continue;
    }
    final avant = col.actives.length;
    if (avant == 0) continue;
    final r = col.archiverTout(marques: marques, estBrouillon: cfbEstBrouillon);
    archivees[n] = r.archivees;
    brouillons[n] = r.brouillons;
    m.journaliser('Archivage du jeu de démonstration', col.module, col.entite ?? n, n, {'actives': avant}, cfbApresArchivageCollection(r.archivees, r.brouillons, motif));
  }
  final bilan = CfbBilanArchivage(parCollection: archivees, brouillons: brouillons, paiementsRetires: paiementsRetires, motif: motif);
  m.journaliser('Archivage du jeu de démonstration (synthèse)', 'CFG', 'Base', 'archivage', null, {
    'tables': bilan.tables,
    'fiches': bilan.total,
    'brouillons': bilan.totalBrouillons,
    'paiementsRetires': paiementsRetires,
    'motif': motif,
    'motifDuGeste': motifDuGeste.trim(),
    'parCollection': archivees,
  });
  return bilan;
}

/// `S.viderActivite(motif)` : vide les données d'ACTIVITÉ, garde l'essentiel (paramétrage, référentiels, comptes, droits, catalogues, journal), et le DIT au
/// journal — l'entrée de vidage est la première du journal conservé (RG-12). Le calendrier fiscal, dérivé d'un document, revient aussitôt SANS règlement.
CfbPlanVidage cfbViderActivite(Magasin m, String motif) {
  final conservees = {...cfbEssentielles, ...cfbCollectionsTechniques};
  final plan = cfbPlanVidage({for (final n in cfbNomsCollections()) n: m.collection(n).toutes.length}, conservees);
  for (final n in plan.collections) {
    final col = m.collection(n);
    if (n == 'echeancesFiscales') {
      col.remplacerContenu([for (final f in col.toutes) cfbRetirerPaiementDemo(f)?.fiche ?? f]);
    } else {
      col.remplacerContenu(const []);
    }
  }
  // Les référentiels CONSERVÉS perdent leurs valeurs de démonstration (`S.CHAMPS_DE_TEST_CONSERVES`) : l'effectif reste, pas la rémunération tirée pour le jeu.
  var valeursRetirees = 0;
  cfbChampsDeTestConserves.forEach((nom, champs) {
    final col = m.collection(nom);
    for (final f in col.toutes) {
      for (final ch in champs) {
        if (f[ch] != null) valeursRetirees++;
      }
    }
    col.remplacerContenu([
      for (final f in col.toutes)
        {
          ...f,
          for (final ch in champs) ch: null,
        }
    ]);
  });
  // LA CORBEILLE ET LE JOURNAL SONT VIDÉS (Direction, 02/11/2026) : un jeu de test remis à neuf ne garde ni les fiches archivées pendant les essais, ni le journal
  // d'audit des essais. Exception explicite à RG-14, limitée à cette commande : l'archivage reste la règle partout ailleurs. Les fiches archivées des
  // référentiels conservés sont retirées aussi, sans quoi la corbeille se remplirait de ce que les essais ont archivé.
  // Deux exceptions : l'archivage d'un RÔLE (`rbac`) ou d'un COMPTE (`utilisateurs`) n'est pas un déchet d'essai, il FERME un accès. Le retirer rouvrirait le rôle
  // ou le compte que la Direction a fermé (RG-14, décisions d'archivage du 28/08).
  const gardees = {'rbac', 'utilisateurs'};
  var archiveesRetirees = 0;
  for (final n in cfbNomsCollections()) {
    if (gardees.contains(n)) continue;
    final col = m.collection(n);
    final arch = col.archivees.length;
    if (arch > 0) {
      archiveesRetirees += arch;
      col.remplacerContenu(col.actives);
    }
  }
  // LES COMPTES DE DÉMONSTRATION PARTENT (Direction, 03/11/2026) : les fiches du jeu, qui n'ont ni mot de passe ni été créées par l'installation, ne servent
  // à personne. Un compte qui a un mot de passe, ou que l'assistant d'installation a créé, reste : le vidage ne doit jamais fermer la porte à celui qui l'a lancé.
  final avecMotDePasse = {for (final f in m.collection('identifiants').toutes) '${f['utilisateurId'] ?? f['id']}'};
  final comptes = m.collection('utilisateurs');
  final gardes = [for (final u in comptes.toutes) if ('${u['source']}' == 'installation' || avecMotDePasse.contains('${u['id']}')) u];
  final comptesDemoRetires = comptes.toutes.length - gardes.length;
  comptes.remplacerContenu(gardes);
  final entreesJournal = m.collection('audit').toutes.length;
  m.collection('audit').remplacerContenu(const []);
  // La première entrée du journal neuf dit ce qui vient d'être fait (RG-12) : le vidage lui-même ne s'efface pas.
  m.journaliser('Réinitialisation des jeux de test', 'CFG', 'Base', 'vidage', null, {
    'tables': plan.tables,
    'enregistrements': plan.enregistrements,
    'valeursRetirees': valeursRetirees,
    'archiveesRetirees': archiveesRetirees,
    'comptesDemoRetires': comptesDemoRetires,
    'entreesJournalRetirees': entreesJournal,
    'motif': motif
  });
  return plan;
}

/// Le geste complet, de la confirmation au toast : motif obligatoire, confirmation dangereuse qui DIT que rien n'est supprimé, puis l'archivage. Partagé par
/// l'onglet « Jeux de test » et le bouton de l'onglet « Installation » : un seul chemin, un seul bilan. Rend le bilan, ou `null` si l'agent renonce.
Future<CfbBilanArchivage?> cfbLancerArchivage(BuildContext ctx, ContexteEcran c) async {
  final m = c.magasin;
  final conservees = {...cfbEssentielles, ...cfbCollectionsTechniques};
  final nb = [for (final n in cfbNomsCollections()) if (!conservees.contains(n) && m.collection(n).actives.isNotEmpty) n].length;
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Archiver le jeu de démonstration ?',
      message:
          'Les fiches actives des $nb tables d’activité (patients, consultations, factures, écritures, brouillons compris, files d’attente, notifications…) passent à l’état archivé, avec le motif « $cfbMotifArchivageJeuDemo ». Rien n’est supprimé (RG-14) : tout se retrouve et se restaure depuis la Corbeille, à une seule exception : les paiements de démonstration des échéances fiscales, données fictives et non pièces comptables, sont SUPPRIMÉS (le journal dit combien). Le personnel, les tarifs, le plan comptable, les comptes, les droits, l’identité et le journal d’audit ne bougent pas. Générer une sauvegarde d’abord.',
      libelleOk: 'Archiver le jeu de démonstration',
      dangereux: true);
  if (motif == null || !ctx.mounted) return null;
  try {
    final bilan = cfbArchiverJeuDemo(m, motifDuGeste: motif);
    ToastsSigh.afficher(ctx, cfbToastArchivage(bilan), type: TypeToast.succes, detail: 'Journal d’audit conservé : une entrée par table et une synthèse.');
    return bilan;
  } on CfbRefusArchivage catch (e) {
    ToastsSigh.afficher(ctx, 'Archivage refusé.', type: TypeToast.erreur, detail: e.motif);
    return null;
  }
}

/// `S.reset()` : la base revient au jeu initial, paramétrage compris. L'autorisation de réinitialiser (une bascule du poste, non une donnée du jeu) survit.
Future<void> cfbRegenererJeu(Magasin m, String motif) async {
  for (final n in cfbNomsCollections()) {
    final lignes = [for (final f in (jsonDecode(await CfbJeu.charger(n)) as List)) (f as Map).cast<String, Object?>()];
    m.collection(n).remplacerContenu(lignes);
  }
  final reglages = m.collection('reglages');
  reglages.remplacerContenu([for (final f in reglages.toutes) if (f['id'] == _idReinit) f]);
  m.journaliser('Régénération du jeu de démonstration', 'CFG', 'Base', 'jeu complet', null, {'motif': motif});
}

/// Quand et par qui une fiche a été archivée : ses marques `_archiveLe` / `_archivePar` / `_motifArchivage` (jeu de la maquette) ou, à défaut, la dernière
/// entrée « Archivage » du journal qui la nomme (le magasin du poste n'écrit pas ces marques sur la fiche, il les journalise).
({String? le, String par, String? motif}) cfbInfosArchivage(Magasin m, CollectionMagasin col, Fiche f) {
  if (f['_archiveLe'] != null || f['_archivePar'] != null || f['_motifArchivage'] != null) {
    return (le: f['_archiveLe'] == null ? null : '${f['_archiveLe']}', par: '${f['_archivePar'] ?? '—'}', motif: f['_motifArchivage'] == null ? null : '${f['_motifArchivage']}');
  }
  final ref = '${f['numero'] ?? f['reference'] ?? f['code'] ?? f['id']}';
  final entite = col.entite ?? col.nom;
  final a = m.collection('audit').toutes.where((x) => x['action'] == 'Archivage' && x['entite'] == entite && x['reference'] == ref).firstOrNull;
  return a == null ? (le: null, par: '—', motif: null) : (le: '${a['dateHeure']}', par: '${a['utilisateur'] ?? '—'}', motif: null);
}

/// `S.corbeille()` : toutes les fiches archivées, tous modules confondus, la plus récente d'abord.
List<CfbLigneCorbeille> cfbCorbeille(Magasin m) {
  final out = <CfbLigneCorbeille>[];
  for (final n in cfbNomsCollections()) {
    final col = m.collection(n);
    final (mod, ent) = cfbLibelleCollection(n);
    for (final f in col.archivees) {
      final i = cfbInfosArchivage(m, col, f);
      out.add(CfbLigneCorbeille(collection: n, module: mod, entite: ent, libelle: cfbLibelleElement(f), refId: '${f['id']}', archiveLe: i.le, archivePar: i.par, motif: i.motif));
    }
  }
  return cfbTrierCorbeille(out);
}

/// `cfg-systeme` — « Paramètres système » : l'installation et le contenu des données, la CORBEILLE (RG-14 : rien n'est jamais supprimé, tout ce qui a été
/// archivé dans n'importe quel module se retrouve et se restaure ici), les deux ACTIVITÉS DE LA PAIE (primes NS 132, évaluations et sanctions NS 131 :
/// PRD P0-5), la porte du barème NS 131 et les jeux de test.
class EcranSysteme extends StatefulWidget with EcranMaquette {
  const EcranSysteme({super.key, this.estMere = false});
  final bool estMere;
  @override
  String get titre => 'Paramètres système';
  @override
  String get description => 'Configuration technique, environnement d’exécution et outils de maintenance du prototype.';
  @override
  String get regle =>
      'Les paramètres décrivent l’installation technique et ne se saisissent pas ici. L’onglet Corbeille, lui, agit : RG-14 — rien n’est jamais supprimé, tout ce qui a été archivé dans n’importe quel module s’y retrouve et s’y restaure.';

  @override
  State<EcranSysteme> createState() => _EtatSysteme();
}

/// L'onglet « Relais en ligne » : les écrans du relais en cartes de hub (ils ont quitté le ruban, arbitrage du 05/11/2026). Absent d'un poste fileul : le
/// relais s'administre depuis la mère.
class _Relais extends StatelessWidget {
  const _Relais({required this.c, required this.estMere});
  final ContexteEcran c;
  final bool estMere;
  @override
  Widget build(BuildContext context) {
    final nav = c.donnees;
    if (nav == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Le relais en ligne (apps/web) est opaque : il transporte les opérations chiffrées entre la mère, les fileuls et les mobiles, sans jamais les lire. Ses écrans ne sont plus au ruban : ils sont ici.',
          ton: TonSigh.info,
          icone: LucideIcons.cloud),
      const SizedBox(height: 12),
      GroupesCartes(domaines: nav.manifeste.cartesParametres(nav.matrice, c.role, estMere: estMere, domaines: const {'Relais en ligne'}), nav: nav, aller: c.aller),
    ]);
  }
}

class _EtatSysteme extends State<EcranSysteme> {
  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final noms = cfbNomsCollections();
    // Toute écriture d'une collection (archivage, restauration, vidage) recompose l'écran : le compteur de la corbeille doit suivre.
    return ListenableBuilder(
        listenable: Listenable.merge([for (final n in noms) c.magasin.collection(n), c.magasin.collection('reglages'), c.magasin.collection('modulesActifs')]),
        builder: (ctx, _) => OngletsSigh(onglets: [
              OngletDef(id: 'installation', libelle: 'Installation et données', construire: (_) => _Installation(c: c, rafraichir: () => setState(() {}))),
              OngletDef(id: 'corbeille', libelle: 'Corbeille', compte: cfbCorbeille(c.magasin).length, construire: (_) => _Corbeille(c: c)),
              OngletDef(id: 'activites', libelle: 'Primes et évaluations', construire: (_) => _ActivitesPaie(c: c)),
              OngletDef(id: 'bareme', libelle: 'Barème NS 131', construire: (_) => _Bareme(c: c)),
              OngletDef(id: 'reinitialisation', libelle: 'Jeux de test', construire: (_) => _JeuxDeTest(c: c, rafraichir: () => setState(() {}))),
              OngletDef(id: 'relais', libelle: 'Relais en ligne', construire: (_) => _Relais(c: c, estMere: widget.estMere)),
              OngletDef(id: 'parametres', libelle: 'Paramètres', construire: (_) => PanneauParametres(c: c, estMere: widget.estMere)),
            ]));
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Installation et données »
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _Installation extends StatelessWidget {
  const _Installation({required this.c, required this.rafraichir});
  final ContexteEcran c;
  final VoidCallback rafraichir;

  Future<void> _reinitialiser(BuildContext ctx) async {
    // La maquette laisse ce bouton à tout profil et le fait passer outre la bascule des jeux de test. Le poste tient la doctrine : fermée, l'effacement est
    // REFUSÉ en le disant (E889) — le bouton reste visible pour que le refus ait un endroit où se dire.
    if (cfbReglage(c.magasin, _idReinit, false) != true) {
      ToastsSigh.afficher(ctx, 'Réinitialisation verrouillée.', type: TypeToast.erreur, detail: 'Autoriser d’abord l’effacement des jeux de test, à l’onglet « Jeux de test ».');
      return;
    }
    // Le geste par défaut de mise en production ARCHIVE (D6, RG-14) : la suppression physique a sa propre porte, à l'onglet « Jeux de test ».
    await cfbLancerArchivage(ctx, c);
    rafraichir();
  }

  /// La clé qui chiffre les données du poste, exportée sous une phrase de passe. Sans elle, une session Windows réinstallée ou un poste remplacé rend les
  /// données illisibles : le fichier se range au coffre, avec les sauvegardes.
  void _sauvegarderCle(BuildContext ctx) {
    final f = ControleurFormulaire(const [
      ChampDef(nom: 'phrase', libelle: 'Phrase de passe (12 caractères au moins)', type: TypeChamp.motDePasse, requis: true, col: ColChamp.plein),
      ChampDef(nom: 'confirmation', libelle: 'Confirmer la phrase de passe', type: TypeChamp.motDePasse, requis: true, col: ColChamp.plein),
    ], const {});
    afficherModale<void>(ctx,
        titre: 'Sauvegarder la clé de chiffrement',
        taille: TailleModale.md,
        corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh('Les données de ce poste sont chiffrées. La clé qui les ouvre est protégée par votre session Windows : si elle est perdue, les données sont illisibles. Le fichier exporté ne contient la clé que CHIFFRÉE par votre phrase de passe ; conservez les deux séparément, au coffre.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: f),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('cfg:cle-exporter'),
                  libelle: 'Exporter la clé',
                  icone: LucideIcons.download,
                  onPressed: () async {
                    final v = f.valider();
                    if (v == null) return;
                    if (v['phrase'] != v['confirmation']) {
                      ToastsSigh.afficher(ctx, 'Les deux phrases de passe ne correspondent pas.', type: TypeToast.erreur);
                      return;
                    }
                    try {
                      final dossier = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
                      final chemin = await CleLocale.courante!.exporter('$dossier${Platform.pathSeparator}sigh-cle-${cfbIso(c.aujourdhui)}.cle', '${v['phrase']}');
                      c.magasin.journaliser('Sauvegarde de la clé de chiffrement', 'CFG', 'Systeme', 'cle-poste', null, {'fichier': chemin});
                      fermer();
                      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Clé sauvegardée.', type: TypeToast.succes, detail: chemin);
                    } catch (e) {
                      if (ctx.mounted) ToastsSigh.afficher(ctx, '$e', type: TypeToast.erreur);
                    }
                  }),
            ]);
  }

  void _basculerPlanDuSite(BuildContext ctx, bool voulue) {
    cfbPoserReglage(c.magasin, cfbIdPlanDuSite, voulue);
    c.magasin.journaliser(voulue ? 'Activation' : 'Désactivation', 'CFG', 'Plan du site', 'affichage', {'actif': !voulue}, {'actif': voulue});
    rafraichir();
  }

  Future<void> _exporter(BuildContext ctx) async {
    try {
      final contenu = const JsonEncoder.withIndent('  ').convert({for (final n in cfbNomsCollections()) n: c.magasin.collection(n).toutes});
      final chemin = await CfbExport.ecrire('sigh-cbg-donnees-${cfbIso(c.aujourdhui)}.json', contenu);
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Export JSON généré.', type: TypeToast.succes, detail: chemin);
    } catch (e) {
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Export impossible : $e', type: TypeToast.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = c.magasin;
    final noms = cfbNomsCollections();
    final stats = [for (final n in noms) cfbStatCollection(n, m.collection(n).toutes)];
    final total = stats.fold<int>(0, (a, s) => a + s.total);
    final persistant = CfbPersistance.disponible();
    return cfaPile([
      cfaKpis([
        CfaKpi('Collections de données', nombre(noms.length), 'database', 'navy'),
        CfaKpi('Enregistrements', nombre(total), 'layers', 'info'),
        CfaKpi('Persistance', persistant ? 'Base locale' : 'Mémoire', 'hard-drive', persistant ? 'success' : 'warning', persistant ? 'Stockage local actif' : 'Stockage local indisponible'),
        const CfaKpi('Version du prototype', 'v1.0', 'tag', 'neutral'),
      ]),
      CarteSigh(
          titre: 'Contenu du jeu de données',
          sansRemplissage: true,
          child: TableauSigh(
            lignes: [
              for (final s in stats) {'id': s.nom, 'collection': s.nom, 'nb': s.total, 'actifs': s.actifs, 'archives': s.archives}
            ],
            taillePage: 30,
            triInitial: 'nb',
            sensInitial: 'desc',
            nomExport: 'collections',
            colonnes: [
              ColonneTableau(
                  cle: 'collection',
                  libelle: 'Collection',
                  rendu: (_, r) => Text('${r['collection']}', style: const TextStyle(fontFamily: _mono, fontSize: 12, height: 16 / 12, color: JetonsShell.slate900))),
              const ColonneTableau(cle: 'nb', libelle: 'Enregistrements', droite: true),
              const ColonneTableau(cle: 'actifs', libelle: 'Actifs', droite: true),
              ColonneTableau(
                  cle: 'archives',
                  libelle: 'Archivés',
                  droite: true,
                  texte: (r) => (r['archives'] as int) > 0 ? '${r['archives']}' : '—',
                  rendu: (_, r) => (r['archives'] as int) > 0 ? Text('${r['archives']}', style: const TextStyle(fontSize: 14, color: JetonsShell.warning600)) : const Text('—')),
            ],
          )),
      CarteSigh(
          titre: 'Affichage',
          child: InkWell(
              key: const Key('cfg:plan-du-site:bascule'),
              onTap: c.droit.editer ? () => _basculerPlanDuSite(context, !cfbPlanDuSiteActif(c.magasin)) : null,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                        value: cfbPlanDuSiteActif(c.magasin),
                        onChanged: c.droit.editer ? (v) => _basculerPlanDuSite(context, v == true) : null,
                        activeColor: JetonsShell.navy900,
                        visualDensity: VisualDensity.compact)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Afficher le plan du site', style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
                  Text('Désactivé par défaut : fermé, l’écran et les boutons qui y mènent n’apparaissent pas. Le changement est journalisé.',
                      style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
                ])),
              ]))),
      CarteSigh(
          titre: 'Maintenance du prototype',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (c.droit.editer) BoutonSigh(libelle: 'Réinitialiser le jeu de données', icone: LucideIcons.rotateCcw, variante: VarianteBouton.danger, onPressed: () => _reinitialiser(context)),
            BoutonSigh(libelle: 'Exporter les données', icone: LucideIcons.download, variante: VarianteBouton.secondaire, onPressed: () => _exporter(context)),
            if (CleLocale.courante != null)
              BoutonSigh(
                  key: const Key('cfg:sauvegarder-cle'),
                  libelle: 'Sauvegarder la clé de chiffrement',
                  icone: LucideIcons.keyRound,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => _sauvegarderCle(context)),
            if (cfbPlanDuSiteActif(c.magasin)) BoutonSigh(libelle: 'Plan du site', icone: LucideIcons.map, variante: VarianteBouton.secondaire, onPressed: () => c.aller('plan-du-site')),
            BoutonSigh(libelle: 'Sauvegardes', icone: LucideIcons.databaseBackup, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m14-sauvegardes')),
          ])),
      cfbNote(
          'Ce prototype fonctionne intégralement hors ligne : la feuille de style, les polices, la bibliothèque de graphiques et les icônes sont hébergées dans le dossier du projet. Aucune requête réseau n’est émise.',
          ton: 'success',
          icone: LucideIcons.wifiOff),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Corbeille » (RG-14)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _Corbeille extends StatelessWidget {
  const _Corbeille({required this.c});
  final ContexteEcran c;

  Future<void> _restaurer(BuildContext ctx, CfbLigneCorbeille r) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Restaurer « ${r.libelle} » ?',
        message: 'La fiche réapparaîtra dans ${r.entite} (${r.module}) et redeviendra modifiable. La restauration est journalisée (RG-12).',
        libelleOk: 'Restaurer');
    if (!ok || !ctx.mounted) return;
    c.magasin.collection(r.collection).restaurer(r.refId);
    ToastsSigh.afficher(ctx, 'Fiche restaurée dans ${r.entite}.', type: TypeToast.succes);
  }

  @override
  Widget build(BuildContext context) {
    final rows = cfbCorbeille(c.magasin);
    final modules = {for (final r in rows) r.module};
    return cfaPile([
      cfaKpis([
        CfaKpi('Fiches archivées', nombre(rows.length), 'trash-2', rows.isNotEmpty ? 'warning' : 'success'),
        CfaKpi('Modules concernés', nombre(modules.length), 'layers', 'info'),
        const CfaKpi('Suppression définitive', 'Impossible', 'shield-check', 'success', 'RG-14 — archivage logique'),
      ]),
      cfbNote(
          'RG-14 — aucune donnée n’est jamais supprimée physiquement. Archiver retire la fiche des listes de travail ; la restaurer la remet exactement où elle était, et l’opération est journalisée dans les deux sens.'),
      if (rows.isEmpty)
        const CarteSigh(titre: 'Corbeille', child: VideSigh('La corbeille est vide — aucune fiche archivée.', icone: LucideIcons.trash2))
      else
        CarteSigh(
            titre: 'Fiches archivées',
            sansRemplissage: true,
            child: TableauSigh(
              lignes: [
                for (final r in rows)
                  {'id': r.id, 'collection': r.collection, 'module': r.module, 'entite': r.entite, 'libelle': r.libelle, 'refId': r.refId, 'archiveLe': r.archiveLe, 'archivePar': r.archivePar, 'motif': r.motif}
              ],
              taillePage: 15,
              triInitial: 'archiveLe',
              sensInitial: 'desc',
              nomExport: 'corbeille',
              filtres: [FiltreTableau(nom: 'module', libelle: 'Module', options: [for (final mo in (modules.toList()..sort())) OptionChamp(mo)])],
              colonnes: [
                ColonneTableau(cle: 'module', libelle: 'Module', sansCoupure: true, rendu: (_, r) => BadgeSigh('${r['module']}')),
                const ColonneTableau(cle: 'entite', libelle: 'Type de fiche'),
                ColonneTableau(
                    cle: 'libelle',
                    libelle: 'Élément',
                    texte: (r) => '${r['libelle']} ${r['refId']}',
                    rendu: (_, r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('${r['libelle']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
                          Text('${r['refId']}', style: const TextStyle(fontFamily: _mono, fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
                        ])),
                ColonneTableau(
                    cle: 'archiveLe',
                    libelle: 'Archivée le',
                    sansCoupure: true,
                    valeur: (r) => '${r['archiveLe'] ?? ''}',
                    texte: (r) => r['archiveLe'] != null ? dateFR(DateTime.parse('${r['archiveLe']}').toLocal()) : '—'),
                const ColonneTableau(cle: 'archivePar', libelle: 'Par', sansCoupure: true),
                ColonneTableau(
                    cle: 'motif',
                    libelle: 'Motif',
                    texte: (r) => cfaOuTiret(r['motif']),
                    rendu: (_, r) => cfaVrai(r['motif']) ? Text('${r['motif']}') : const Text('—', style: TextStyle(color: JetonsShell.slate300))),
              ],
              actionsLigne: (ctx, r) => [
                if (c.droit.annuler)
                  BoutonIcone(
                      icone: LucideIcons.undo2,
                      libelle: 'Restaurer',
                      onPressed: () => _restaurer(
                          ctx,
                          rows.firstWhere((x) => x.id == r['id']))),
              ],
            )),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Barème NS 131 » — LA PORTE du barème
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _Bareme extends StatelessWidget {
  const _Bareme({required this.c});
  final ContexteEcran c;

  Future<void> _basculer(BuildContext ctx, bool ouverte) async {
    if (ouverte) {
      cfbPoserReglage(c.magasin, _idBareme, false);
      c.magasin.journaliser('Fermeture de la modification du barème', 'M10', 'Barème', cfbNs131.reference, null, const {});
      ToastsSigh.afficher(ctx, 'Modification du barème refermée.', type: TypeToast.succes, detail: 'Le barème redevient consultable seulement.');
      return;
    }
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Autoriser la modification du barème NS 131 ?',
        message:
            'Le barème fixe les retenues sur salaire. L’ouvrir rend ses critères et ses taux modifiables depuis l’écran « Évaluations ».\n\nChaque modification demandera sa portée — évaluations à venir seulement, ou évaluations déjà prononcées comprises. Refermer la porte après usage évite qu’elle reste ouverte des mois durant.',
        libelleOk: 'Autoriser la modification',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    cfbPoserReglage(c.magasin, _idBareme, true);
    c.magasin.journaliser('Ouverture de la modification du barème', 'M10', 'Barème', cfbNs131.reference, null, {'motif': motif});
    ToastsSigh.afficher(ctx, 'Modification du barème autorisée.',
        type: TypeToast.attention, detail: 'Le CRUD est ouvert à l’écran « Évaluations ». Penser à refermer après usage.', duree: const Duration(seconds: 8));
  }

  @override
  Widget build(BuildContext context) {
    final ouverte = cfbReglage(c.magasin, _idBareme, false) == true;
    final ns131Ouvert = paiActivites(c.magasin.collection('modulesActifs').toutes).sanctionsNs131;
    return cfaPile([
      if (!ns131Ouvert)
        cfbNote('L’activité « ${paiBasculeNs131.libelle} » est fermée (onglet « Primes et évaluations ») : le barème reste consultable ici, mais aucune retenue ne remonte à la paie et l’écran des évaluations est retiré du menu.',
            ton: 'warning', icone: LucideIcons.toggleLeft),
      cfbNote(
          'Le barème d’évaluation ${cfbNs131.reference} fixe les retenues appliquées au salaire brut. Sa modification est fermée par défaut. L’ouvrir ici rend le barème modifiable à l’écran « Évaluations » — et l’ouverture est journalisée. Chaque modification demandera ensuite sa portée : évaluations à venir seulement, ou évaluations déjà prononcées comprises.',
          ton: ouverte ? 'warning' : 'info',
          icone: ouverte ? LucideIcons.lockOpen : LucideIcons.lock),
      CarteSigh(
          titre: 'Modification du barème',
          child: cfaPile([
            DescListeSigh([
              ('État', ouverte ? const BadgeSigh('Ouverte', ton: TonSigh.attention) : const BadgeSigh('Fermée', ton: TonSigh.succes)),
              ('Référence', cfbNs131.reference),
              ('En vigueur depuis', dateFR(DateTime.parse(cfbNs131.dateEffet))),
              ('Critères au barème', nombre(c.magasin.collection('baremeNS131').actives.length)),
              ('Versions antérieures', nombre(c.magasin.collection('historiqueBareme').actives.length)),
            ]),
            // La porte est une décision de l'institution : sans le droit d'écrire, la commande est ABSENTE.
            if (c.droit.editer)
              Align(
                  alignment: Alignment.centerLeft,
                  child: BoutonSigh(
                      libelle: ouverte ? 'Refermer la modification' : 'Autoriser la modification',
                      icone: ouverte ? LucideIcons.lock : LucideIcons.lockOpen,
                      variante: ouverte ? VarianteBouton.secondaire : VarianteBouton.danger,
                      onPressed: () => _basculer(context, ouverte))),
          ], espace: 12)),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Primes et évaluations » : les deux activités de la paie (PRD P0-5), OUVERTES par défaut (décision de la Direction du 06/11/2026)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Chaque bascule écrit UNE fiche de la collection `modulesActifs` (la même que « Activité des modules » lit et pilote) : fermer retire ses écrans du
/// menu et de leurs adresses, et le calcul de la paie lit son état dans ces mêmes fermetures. Aucun second drapeau n'est stocké. La fiche n'est jamais
/// supprimée : rouvrir la passe à `actif: true`, datée et signée, et chaque geste est journalisé (RG-12, RG-14).
class _ActivitesPaie extends StatelessWidget {
  const _ActivitesPaie({required this.c});
  final ContexteEcran c;

  CollectionMagasin get _col => c.magasin.collection('modulesActifs');

  Future<void> _fermer(BuildContext ctx, PaiBascule b) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Fermer l’activité « ${b.libelle} » ?',
        message:
            '${b.effet}\n\nLes écrans concernés quittent le menu pour tous les rôles ; leurs données restent intactes et la réouverture les rend en l’état. Les bulletins déjà enregistrés gardent leurs montants.',
        libelleOk: 'Fermer l’activité',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final jour = cfbIso(c.aujourdhui);
    final nom = acteur(c).nom;
    final existante = paiFicheBascule(_col.toutes, b);
    final champs = {'actif': false, 'motif': motif, 'fermeLe': jour, 'fermePar': nom, 'rouvertLe': null, 'rouvertPar': null};
    if (existante == null) {
      _col.inserer({'statut': 'actif', 'code': b.code, 'libelle': b.libelle, 'module': b.module, 'ecrans': b.ecrans, 'source': b.source, ...champs}, prefixe: 'MOD');
    } else {
      _col.mettreAJour(existante['id'], champs);
    }
    c.magasin.journaliser('Fermeture d’une activité de la paie', 'CFG', 'Activité', b.code, {'actif': true}, {'actif': false, 'motif': motif});
    ToastsSigh.afficher(ctx, 'Activité « ${b.libelle} » fermée.', type: TypeToast.succes, detail: b.effet);
  }

  Future<void> _rouvrir(BuildContext ctx, PaiBascule b, CfbFermetures fermetures) async {
    final fiche = fermetures.fermeturePour(b.ecranPilote, b.module);
    if (fiche == null) return;
    // Une fermeture posée AILLEURS (une activité déclarée sur le même écran, ou le module entier) se rouvre là où elle a été posée : la rouvrir d'ici
    // rouvrirait peut-être tout le module, sans que celui qui l'a fermé le sache.
    if (fiche['code'] != b.code) {
      ToastsSigh.afficher(ctx, 'Réouverture impossible ici.',
          type: TypeToast.erreur,
          detail: 'L’activité est fermée par « ${fiche['libelle'] ?? fiche['code']} » : la rouvrir depuis Activité des modules.');
      return;
    }
    final ok = await confirmerSigh(ctx,
        titre: 'Rouvrir l’activité « ${b.libelle} » ?',
        message: 'Les écrans concernés reviennent au menu avec leurs données, et le calcul de la paie reprend la note ${b.source}.',
        libelleOk: 'Rouvrir l’activité');
    if (!ok || !ctx.mounted) return;
    _col.mettreAJour(fiche['id'], {'actif': true, 'rouvertLe': cfbIso(c.aujourdhui), 'rouvertPar': acteur(c).nom});
    c.magasin.journaliser('Réouverture d’une activité de la paie', 'CFG', 'Activité', b.code, {'actif': false}, {'actif': true});
    ToastsSigh.afficher(ctx, 'Activité « ${b.libelle} » rouverte.', type: TypeToast.succes, detail: 'Les écrans réapparaissent au menu avec leurs données.');
  }

  String _date(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '—' : dateFR(d);
  }

  Widget _carte(BuildContext ctx, PaiBascule b, CfbFermetures fermetures) {
    final ouverte = paiBasculeOuverte(fermetures, b);
    final fermante = fermetures.fermeturePour(b.ecranPilote, b.module);
    final propre = paiFicheBascule(_col.toutes, b);
    final lignes = <(String, Object)>[
      ('État', ouverte ? const BadgeSigh('Ouverte', ton: TonSigh.succes) : const BadgeSigh('Fermée', ton: TonSigh.attention)),
      ('Écrans concernés', b.ecrans.join(', ')),
      ('Barème', 'Note de service ${b.source}, reprise du logiciel d’origine et non encore remplacée par une note de la clinique.'),
      if (!ouverte && fermante != null) ...[
        ('Fermée le', _date(fermante['fermeLe'])),
        ('Par', '${fermante['fermePar'] ?? '—'}'),
        ('Motif', '${fermante['motif'] ?? '—'}'),
        if (fermante['code'] != b.code) ('Fermée par', '${fermante['libelle'] ?? fermante['code']} (Activité des modules)'),
      ],
      if (ouverte && propre != null && propre['rouvertLe'] != null) ...[
        ('Rouverte le', _date(propre['rouvertLe'])),
        ('Par', '${propre['rouvertPar'] ?? '—'}'),
      ],
    ];
    return CarteSigh(
        titre: b.libelle,
        child: cfaPile([
          cfbNote(ouverte ? 'Ouverte : ${b.libelle} entre au calcul de la paie. Fermée : ${b.effet}' : b.effet,
              ton: ouverte ? 'info' : 'warning', icone: ouverte ? LucideIcons.toggleRight : LucideIcons.toggleLeft),
          DescListeSigh(lignes),
          // Une décision de l'institution : sans le droit d'écrire sur Paramètres système, la commande est ABSENTE.
          if (c.droit.editer)
            Align(
                alignment: Alignment.centerLeft,
                child: BoutonSigh(
                    key: Key('cfg:bascule:${b.code}'),
                    libelle: ouverte ? 'Fermer l’activité' : 'Rouvrir l’activité',
                    icone: ouverte ? LucideIcons.toggleLeft : LucideIcons.toggleRight,
                    variante: ouverte ? VarianteBouton.danger : VarianteBouton.secondaire,
                    onPressed: () => ouverte ? _fermer(ctx, b) : _rouvrir(ctx, b, fermetures))),
        ], espace: 12));
  }

  @override
  Widget build(BuildContext context) {
    final fermetures = CfbFermetures.depuis(_col.toutes);
    return cfaPile([
      cfbNote(
          'Deux activités de la paie s’ouvrent et se ferment ici. Elles arrivent OUVERTES à l’installation. Fermer l’une retire ses écrans du menu pour tous les rôles, et le calcul de la paie cesse de l’appliquer : plus aucune prime de la note NS 132, ou plus aucune retenue d’évaluation NS 131. Les bulletins déjà enregistrés ne sont jamais recalculés. Chaque geste est daté, signé et journalisé.',
          icone: LucideIcons.slidersHorizontal),
      for (final b in paiBascules) _carte(context, b, fermetures),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Jeux de test » — la bascule fermée par défaut : fermée, le bouton est ABSENT et non grisé
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _JeuxDeTest extends StatefulWidget {
  const _JeuxDeTest({required this.c, required this.rafraichir});
  final ContexteEcran c;
  final VoidCallback rafraichir;
  @override
  State<_JeuxDeTest> createState() => _EtatJeuxDeTest();
}

class _EtatJeuxDeTest extends State<_JeuxDeTest> {
  ContexteEcran get c => widget.c;
  VoidCallback get rafraichir => widget.rafraichir;

  /// Le bilan du dernier archivage de cette ouverture de l'écran : dit combien de fiches par table, et combien de brouillons.
  CfbBilanArchivage? _bilan;

  bool get _autorisee => cfbReglage(c.magasin, _idReinit, false) == true;

  Future<void> _basculerAutorisation(BuildContext ctx, bool voulue) async {
    if (voulue) {
      final ok = await confirmerSigh(ctx,
          titre: 'Autoriser la réinitialisation des jeux de test ?',
          message:
              'Une fois autorisée, la réinitialisation devient possible depuis ce poste. Sur un poste en production, la laisser fermée est la seule position raisonnable : elle protège les données réelles de l’établissement.',
          libelleOk: 'Autoriser',
          dangereux: true);
      if (!ok || !ctx.mounted) return;
      cfbPoserReglage(c.magasin, _idReinit, true);
      c.magasin.journaliser('Déverrouillage', 'CFG', 'Réinitialisation', 'jeux de test', {'etat': 'verrouillée'}, {'etat': 'autorisée'});
    } else {
      cfbPoserReglage(c.magasin, _idReinit, false);
      c.magasin.journaliser('Verrouillage', 'CFG', 'Réinitialisation', 'jeux de test', {'etat': 'autorisée'}, {'etat': 'verrouillée'});
    }
    rafraichir();
  }

  Future<void> _archiver(BuildContext ctx) async {
    final b = await cfbLancerArchivage(ctx, c);
    if (b != null) setState(() => _bilan = b);
    rafraichir();
  }

  /// LA SUPPRESSION PHYSIQUE : seconde porte, nommée, qui CONTREDIT RG-14 et le dit. Gardée pour un poste d'essai qu'on remet à neuf (jamais pour la mise en
  /// production, qui archive) : le motif d'abord, puis une confirmation à part dont le titre et le bouton disent « suppression physique ».
  Future<void> _viderPhysiquement(BuildContext ctx, CfbPlanVidage plan) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Suppression physique des jeux de test ?',
        message:
            'Les ${plan.tables} tables d’activité seront VIDÉES, la Corbeille et le journal d’audit aussi. Ce n’est pas l’archivage : c’est une suppression physique, qui contredit RG-14 et ne se défait pas. Pour mettre le poste en production, utiliser « Archiver le jeu de démonstration ».',
        libelleOk: 'Continuer',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    final sure = await confirmerSigh(ctx,
        titre: 'Suppression physique : dernière confirmation',
        message:
            'Vous allez SUPPRIMER PHYSIQUEMENT ${nombre(plan.enregistrements)} enregistrements, sans archivage ni retour possible depuis la Corbeille. Les numéros de dossier et de pièce repartiront du début. Une sauvegarde préalable est indispensable.',
        libelleOk: 'Supprimer physiquement',
        libelleAnnuler: 'Renoncer',
        dangereux: true);
    if (!sure || !ctx.mounted) return;
    final bilan = cfbViderActivite(c.magasin, motif);
    setState(() => _bilan = null);
    ToastsSigh.afficher(ctx, cfbToastVidage(bilan), type: TypeToast.succes, detail: 'Suppression physique faite. Paramétrage, référentiels, comptes et droits conservés.');
    rafraichir();
  }

  Future<void> _regenerer(BuildContext ctx) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Régénérer entièrement le jeu de démonstration ?',
        message: 'Toute la base est remplacée par le jeu initial, paramétrage compris. À n’utiliser que sur un poste de démonstration.',
        libelleOk: 'Régénérer',
        dangereux: true);
    if (motif == null || !ctx.mounted) return;
    try {
      await cfbRegenererJeu(c.magasin, motif);
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Jeu de démonstration régénéré.', type: TypeToast.succes);
    } catch (e) {
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Régénération impossible : $e', type: TypeToast.erreur);
    }
    rafraichir();
  }

  Widget _puces(String titre, List<String> puces, {required bool danger}) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: danger ? JetonsShell.danger50 : JetonsShell.success50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: danger ? JetonsShell.danger200 : JetonsShell.success200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre.toUpperCase(), style: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: danger ? JetonsShell.danger700 : JetonsShell.success700)),
        const SizedBox(height: 8),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final p in puces)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                child: Text(p, style: TextStyle(fontSize: 10, height: 14 / 10, color: danger ? JetonsShell.danger700 : JetonsShell.success700))),
        ]),
      ]));

  @override
  Widget build(BuildContext context) {
    final m = c.magasin;
    final noms = cfbNomsCollections();
    final tailles = {for (final n in noms) n: m.collection(n).toutes.length};
    final plan = cfbPlanVidage(tailles, {...cfbEssentielles, ...cfbCollectionsTechniques});
    final conservees = [for (final n in cfbEssentielles) if (tailles.containsKey(n)) n];
    final actives = {for (final n in plan.collections) n: m.collection(n).actives.length};
    // `echeancesFiscales` reste en service (ses paiements fictifs sont retirés, la fiche n'est pas archivée) : elle ne figure pas parmi les collections archivées.
    final aArchiver = [for (final e in actives.entries) if (e.value > 0 && e.key != 'echeancesFiscales') e.key];
    final fichesActives = actives.values.fold<int>(0, (a, b) => a + b);
    final autorisee = _autorisee;
    return cfaPile([
      cfaKpis([
        CfaKpi('Réinitialisation', autorisee ? 'Autorisée' : 'Verrouillée', autorisee ? 'unlock' : 'lock', autorisee ? 'danger' : 'success',
            autorisee ? 'Le poste accepte l’archivage du jeu de démonstration' : 'Aucun effacement possible'),
        CfaKpi('Tables d’activité', nombre(plan.tables), 'database', 'info', '${nombre(fichesActives)} fiches actives, ${nombre(plan.enregistrements)} au total'),
        CfaKpi('Tables de paramétrage préservées', nombre(noms.length - plan.tables), 'shield-check', 'success', 'Tarifs, secteurs, conventions, comptes'),
      ]),
      CarteSigh(
          titre: 'Autorisation',
          child: Tooltip(
              message: 'Autoriser la réinitialisation des jeux de test sur ce poste',
              child: InkWell(
                  key: const Key('cfb:reinit:bascule'),
                  onTap: c.droit.editer ? () => _basculerAutorisation(context, !autorisee) : null,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(value: autorisee, onChanged: c.droit.editer ? (v) => _basculerAutorisation(context, v == true) : null, activeColor: JetonsShell.navy900, visualDensity: VisualDensity.compact)),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Autoriser la réinitialisation des jeux de test sur ce poste', style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: JetonsShell.slate800)),
                      Text('À laisser fermé sur un poste en service. Le déverrouillage et le verrouillage sont journalisés.', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
                    ])),
                  ])))),
      CarteSigh(
          titre: 'Ce qui serait archivé, ce qui serait conservé',
          child: LayoutBuilder(builder: (_, k) {
            final a = _puces('Archivé — données d’activité (fiches actives)', [for (final n in aArchiver.take(24)) '${cfbLibelleCollection(n).$2} (${actives[n]})'], danger: true);
            final b = _puces('Conservé — paramétrage et référentiels', [for (final n in conservees) '${cfbLibelleCollection(n).$2} (${tailles[n]})'], danger: false);
            return k.maxWidth >= 640
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
                : cfaPile([a, b], espace: 12);
          })),
      cfbNote(
          'Mettre le poste en production, c’est ARCHIVER le jeu de démonstration (RG-14 : rien n’est supprimé). Chaque fiche active garde son contenu, passe à l’état archivé avec le motif « $cfbMotifArchivageJeuDemo », l’auteur et la date, et se restaure depuis la Corbeille. Seule exception : le paiement de démonstration d’une échéance fiscale est une donnée fictive, il est SUPPRIMÉ (échéance remise à non payée, une ligne du journal dit combien) et n’est rangé nulle part. Les brouillons sont archivés comme les autres, jamais validés. L’administrateur, les réglages, les référentiels, le journal d’audit et les compteurs de numérotation ne sont pas touchés : un code archivé n’est jamais réattribué (RG-01).'),
      if (_bilan != null) _carteBilan(_bilan!),
      if (autorisee)
        CarteSigh(
            titre: 'Mise en production',
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (c.droit.editer) ...[
                BoutonSigh(
                    key: const Key('cfb:reinit:archiver'),
                    libelle: 'Archiver le jeu de démonstration',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () => _archiver(context)),
                BoutonSigh(libelle: 'Régénérer le jeu de démonstration complet', icone: LucideIcons.rotateCcw, variante: VarianteBouton.secondaire, onPressed: () => _regenerer(context)),
              ]
            ]))
      else
        const CarteSigh(titre: 'Mise en production', child: VideSigh('Réinitialisation verrouillée — activer l’autorisation ci-dessus pour la rendre possible.', icone: LucideIcons.lock)),
      if (autorisee && c.droit.editer)
        CarteSigh(
            titre: 'Suppression physique (hors RG-14)',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const NoteSigh(
                  'La suppression physique CONTREDIT RG-14 : les fiches d’activité, la Corbeille et le journal d’audit sont vidés, sans retour possible, et les numéros de dossier et de pièce repartent du début. Elle ne sert qu’à remettre à neuf un poste d’essai. Pour la mise en production, archiver.',
                  ton: TonSigh.attention,
                  icone: LucideIcons.triangleAlert),
              const SizedBox(height: 12),
              BoutonSigh(
                  key: const Key('cfb:reinit:supprimer'),
                  libelle: 'Suppression physique des jeux de test',
                  icone: LucideIcons.trash2,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => _viderPhysiquement(context, plan)),
            ])),
    ]);
  }

  Widget _carteBilan(CfbBilanArchivage b) => CarteSigh(
      titre: 'Bilan de l’archivage',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(cfbToastArchivage(b), key: const Key('cfb:reinit:bilan'), style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800)),
        const SizedBox(height: 4),
        Text('${nombre(b.paiementsRetires)} paiement(s) fictif(s) d’échéances fiscales retiré(s) : donnée de démonstration supprimée, non rangée, échéances remises à non payées.',
            style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
        const SizedBox(height: 8),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final l in cfbLignesBilanArchivage(b))
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: JetonsShell.success50, borderRadius: BorderRadius.circular(4)),
                child: Text(l, style: const TextStyle(fontSize: 10, height: 14 / 10, color: JetonsShell.success700))),
        ]),
      ]));
}
