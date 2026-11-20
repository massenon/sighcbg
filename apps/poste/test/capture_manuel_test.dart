import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show AccParametresHachage, DroitsGestes, creerFicheAide, epRoleFileul, epRoleMere;
import 'package:sigh_poste/donnees/base_portable_poste.dart';
import 'package:sigh_poste/donnees/cle_clinique_poste.dart';
import 'package:sigh_poste/donnees/maj_poste.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/mere/client_mere.dart' show Appareil, CodeReprise;
import 'package:sigh_poste/modules/mere/mrd_reprise_poste.dart' show SourceReprise, sourceRepriseInjectee;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/modules/m12/cpc_commun.dart' show amorcerExercices;
import 'package:sigh_poste/shell/coque.dart';

import 'aide_polices.dart';
import 'controle_noms_manuel_test.dart' show nomsReels, trouves;
import 'mere_sms_test.dart' show Source;
import 'package:sigh_poste/modules/mere/mrb_source.dart' show mrbSourceInjectee, mrbIntervalle;

/// CAPTURES DU MANUEL D'UTILISATION (docs/manuels/src/utilisateur) : ouvre les écrans clés du poste sur le jeu de démonstration et écrit, pour chacun,
/// un PNG et un JSON des repères (rectangles des boutons, des clés et des onglets) qui servent à placer les flèches automatiquement.
/// Sur demande seulement : `SIGH_CAPTURES=/chemin flutter test test/capture_manuel_test.dart`.
final String? _sortie = Platform.environment['SIGH_CAPTURES'];
final _donnees = DonneesNavigation.depuisDossier();
final _le = DateTime(2026, 11, 16, 10);
final _nomsReels = nomsReels();
const _taille = Size(1440, 900);

typedef Geste = Future<void> Function(WidgetTester t);

/// AUCUNE personne réelle à l'image (même remplacement que capture_admin_test.dart) : le jeu LIVRÉ porte les vrais agents de la clinique ; leurs noms et
/// prénoms sont remplacés PARTOUT (personnel, comptes, planning, présences, signatures, auteurs de pièces, journal…) par « AGENTnn Démo » avant le rendu.
/// La dénomination de la clinique, elle, reste. Le contrôle `controle_noms_manuel_test.dart` vérifie qu'aucun nom ne subsiste dans les repères ni le manuel.
Magasin anonymiser(Magasin m, List<String> collections) {
  final remplacements = <String, String>{};
  var i = 0;
  for (final p in m.collection('personnel').toutes) {
    i++;
    final nom = '${p['nom'] ?? ''}', prenom = '${p['prenom'] ?? ''}';
    final n = 'AGENT${i.toString().padLeft(2, '0')}';
    if ('${p['nomComplet'] ?? ''}'.isNotEmpty) remplacements['${p['nomComplet']}'] = '$n Démo';
    if (nom.isNotEmpty && prenom.isNotEmpty) {
      remplacements['$prenom $nom'] = 'Démo $n';
      remplacements['$nom $prenom'] = '$n Démo';
    }
    if (prenom.length >= 3) remplacements[prenom] = 'Démo';
    if (nom.length >= 3 && nom != 'BAGUIDI') remplacements[nom] = n;
  }
  final cles = remplacements.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  String neutre(String s) {
    for (final k in cles) {
      s = s.replaceAll(k, remplacements[k]!);
    }
    return s;
  }

  for (final nom in collections) {
    final c = m.collection(nom);
    if (c.toutes.isEmpty) continue;
    final avant = jsonEncode(c.toutes);
    final apres = neutre(avant);
    if (apres != avant) c.remplacerContenu([for (final f in (jsonDecode(apres) as List)) (f as Map).cast<String, Object?>()]);
  }
  return m;
}

class _Cap {
  const _Cap(this.nom, this.ecran,
      {this.role = 'admin', this.gestes = const [], this.session, this.jeuDeTest = false, this.taille = _taille, this.mode = ModePoste.fileul, this.posteNeuf = false, this.preparer});

  /// Prépare le magasin avant l'écran (données FICTIVES de démonstration : plan de travail, valeurs d'attente, vacations à valider).
  final FutureOr<void> Function(Magasin m)? preparer;

  /// Taille logique de la fenêtre (les écrans longs — configuration fiscale, planning individuel — se photographient en hauteur).
  final Size taille;
  final ModePoste mode;

  /// Un poste NEUF (aucun compte) dont l'assistant d'installation est attaché : premier lancement, première installation, rejoindre une clinique.
  final bool posteNeuf;

  /// Quelques files (dispensation, file d'attente, comptes rendus en cours) sont vides dans le jeu livré : ces captures lisent le jeu de test.
  final bool jeuDeTest;
  final String nom;
  final String? ecran;
  final String role;
  final List<Geste> gestes;
  final SessionPoste Function()? session;
}

Future<void> _pomper(WidgetTester t, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

Geste toucherCle(String cle) => (t) async {
      final f = find.byKey(Key(cle));
      if (f.evaluate().isEmpty) return;
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t);
    };

Geste toucherBouton(String libelle) => (t) async {
      final f = find.widgetWithText(BoutonSigh, libelle);
      if (f.evaluate().isEmpty) return;
      await t.ensureVisible(f.first);
      await t.pump();
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t, 6);
    };

Geste toucherTexte(String texte) => (t) async {
      final f = find.text(texte);
      if (f.evaluate().isEmpty) return;
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t, 6);
    };

Geste toucherIcone(String libelle) => (t) async {
      final f = find.byWidgetPredicate((w) => w is BoutonIcone && w.libelle == libelle);
      if (f.evaluate().isEmpty) return;
      await t.ensureVisible(f.first);
      await t.pump();
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t, 6);
    };

/// La [n]-ième icône d'action (à partir de 0) portant ce libellé : la ligne voulue d'un tableau dont la première n'est pas la bonne.
Geste toucherIconeN(String libelle, int n) => (t) async {
      final f = find.byWidgetPredicate((w) => w is BoutonIcone && w.libelle == libelle);
      if (f.evaluate().length <= n) return;
      await t.ensureVisible(f.at(n));
      await t.pump();
      await t.tap(f.at(n), warnIfMissed: false);
      await _pomper(t, 8);
    };

/// Fait défiler la page jusqu'au premier texte égal à [texte] (la carte d'un réglage loin dans la liste des paramètres).
Geste defilerVers(String texte) => (t) async {
      final f = find.text(texte);
      if (f.evaluate().isEmpty) return;
      await t.ensureVisible(f.first);
      await _pomper(t, 6);
    };

/// Laisse tourner les calculs asynchrones (hachage du mot de passe à la création du premier compte).
Geste attendre([int n = 8]) => (t) async {
      for (var i = 0; i < n; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await t.pump(const Duration(milliseconds: 50));
      }
      await _pomper(t, 4);
    };

/// Un bouton du kit OU une icône d'action, désigné par son libellé.
Geste toucherLibelle(String libelle) => (t) async {
      if (find.widgetWithText(BoutonSigh, libelle).evaluate().isNotEmpty) return toucherBouton(libelle)(t);
      return toucherIcone(libelle)(t);
    };

/// Remplit un champ du kit (`kit:champ:<nom>`).
Geste champ(String nom, String texte) => (t) async {
      final f = find.descendant(of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(TextField));
      if (f.evaluate().isEmpty) return;
      await t.enterText(f.first, texte);
      await _pomper(t, 2);
    };

/// Choisit une option d'une liste du kit (`kit:champ:<nom>`) : ouvre la liste puis touche le libellé.
Geste choisir(String nom, String libelle) => (t) async {
      final f = find.byKey(Key('kit:champ:$nom'));
      if (f.evaluate().isEmpty) return;
      final cible = find.descendant(of: f, matching: find.byWidgetPredicate((w) => w is DropdownButton || w is InkWell || w is GestureDetector));
      await t.tap(cible.evaluate().isEmpty ? f.first : cible.first, warnIfMissed: false);
      await _pomper(t, 6);
      final o = find.text(libelle);
      if (o.evaluate().isEmpty) return;
      await t.tap(o.last, warnIfMissed: false);
      await _pomper(t, 6);
    };

/// Ferme les modales ouvertes (touche Échap).
Geste fermerModales() => (t) async {
      for (var i = 0; i < 2; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await _pomper(t, 4);
      }
    };


/// Touche le premier widget dont la clé commence par [prefixe] (ligne d'un tableau dont l'identifiant est engendré : `aide:valider:<id>`).
Geste toucherClePrefixe(String prefixe) => (t) async {
      final f = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith(prefixe));
      if (f.evaluate().isEmpty) return;
      await t.ensureVisible(f.first);
      await t.pump();
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t, 6);
    };

/// Une source SIMULÉE pour « Reprise d'un poste » : trois fileuls de démonstration (identifiants fictifs), un code d'exemple valable 15 minutes.
class _SourceRepriseDemo implements SourceReprise {
  @override
  Future<List<Appareil>> appareils() async => [
        Appareil(uuid: '3f9c1e7a-5b2d-4c68-9a10-7d2e8b6f4a01', etiquette: 'Accueil', role: 'fileul', etat: 'actif', dernierContact: _le.subtract(const Duration(minutes: 4)), derniereSeq: 118, deriveMs: 0),
        Appareil(uuid: 'b7d20c44-91ae-4f3b-8c55-0e6a1d93f2b8', etiquette: 'Caisse', role: 'fileul', etat: 'actif', dernierContact: _le.subtract(const Duration(minutes: 11)), derniereSeq: 342, deriveMs: 0),
        Appareil(uuid: '5a1e9d03-c2f7-4b6e-a8d4-39f0b7c15e62', etiquette: 'Ancien poste du laboratoire', role: 'fileul', etat: 'revoque', dernierContact: _le.subtract(const Duration(days: 9)), derniereSeq: 3, deriveMs: 0),
      ];
  @override
  Future<CodeReprise> emettre({required String uuid, required String etiquette}) async =>
      CodeReprise(code: 'ZQ7K3M9P', expireMs: _le.add(const Duration(seconds: 900)).millisecondsSinceEpoch, validiteSecondes: 900);
}

/// Les versions de démonstration du jeu livré sont datées du 17/11/2026, APRÈS l'horloge de la capture (16/11) : on les antidate, sinon une version importée « aujourd'hui » paraîtrait antérieure.
void _liasseAntidatee(Magasin m) {
  final col = m.collection('documentsFiscaux');
  for (final f in col.toutes) {
    col.mettreAJour(f['id'], {'importeLe': '2026-11-10'}, journaliser: false);
  }
}

void _repriseDemo(Magasin _) => sourceRepriseInjectee = _SourceRepriseDemo();

/// Une fiche d'aide FICTIVE, proposée par un autre compte (la validation exige une autre personne que l'auteur). [pro] : une fiche qui engage un professionnel (la check-liste du bloc).
void _ficheAideProposee(Magasin m, {bool pro = false}) {
  final r = creerFicheAide(
      saisie: {
        'type': 'aide',
        'titre': pro ? 'Exemple : la check-liste du bloc (texte d’illustration)' : 'Exemple : une procédure (texte d’illustration)',
        'motsCles': ['exemple'],
        'etapes': ['Première étape de l’exemple.', 'Deuxième étape de l’exemple.'],
        'questionAttendue': pro ? 94 : 58,
        if (pro) 'domainePro': 'bloc',
      },
      auteurId: 'U-REDACTEUR-DEMO',
      auteurNom: 'Rédacteur Démo',
      maintenant: _le,
      rolesConnus: const []);
  m.collection('fichesAide').inserer(r.fiche!, prefixe: 'FAI');
}

/// Ouvre la modale « Régler à partir d'une date » de la carte d'un réglage, repérée par son titre (le panneau des paramètres en porte une par réglage).
Geste reglerCarte(String titre) => (t) async {
      final carte = find.ancestor(of: find.text(titre), matching: find.byType(CarteSigh));
      if (carte.evaluate().isEmpty) return;
      final bouton = find.descendant(of: carte.first, matching: find.widgetWithText(BoutonSigh, 'Régler à partir d’une date'));
      if (bouton.evaluate().isEmpty) return;
      await t.ensureVisible(bouton.first);
      await t.pump();
      await t.tap(bouton.first, warnIfMissed: false);
      await _pomper(t, 6);
    };

/// Un poste RATTACHÉ à une mère (fileul) : ses validations et ses imports sont déposés, la mère les applique.
Future<void> _rattache(Magasin m) => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'poste-fileul-demo', rejoint: true));

const _secretDemo = 'Demonstration#Parakou26';

/// La création du premier administrateur sur un poste neuf (nom fictif), jusqu'à l'affichage du code de secours.
final _premierCompte = <Geste>[
  toucherCle('ins:premiere'),
  saisir('ins:nom', 'ADMINISTRATEUR Démonstration'),
  saisir('ins:identifiant', 'admin.demo'),
  saisir('ins:motdepasse', _secretDemo),
  saisir('ins:confirmation', _secretDemo),
  toucherCle('ins:creer'),
  attendre(),
];

/// Coche les [n] premières lignes d'un tableau du kit (case « Sélectionner la ligne »).
Geste cocherLignes(int n) => (t) async {
      final f = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Sélectionner la ligne');
      for (var i = 0; i < n && i < f.evaluate().length; i++) {
        await t.tap(f.at(i), warnIfMissed: false);
        await _pomper(t, 2);
      }
    };

Geste saisir(String cle, String texte) => (t) async {
      final f = find.byKey(Key(cle));
      if (f.evaluate().isEmpty) return;
      await t.enterText(f.first, texte);
      await _pomper(t, 2);
    };


/// Un plan de travail annuel FICTIF de l'exercice 2026, à l'état [etat] (brouillon, soumis, execution). Les actions d'abord : la garde du moteur refuse d'ajouter une action à un plan adopté.
void _semerPta(Magasin m, String etat) {
  amorcerExercices(m, _le);
  final actions = <Map<String, Object?>>[
    {'axe': 'sante_mere_enfant', 'objectif': 'Réduire les complications à l’accouchement', 'action': 'Former les sages-femmes à la partographie', 'resultatAttendu': 'Partogramme tenu à chaque accouchement',
      'indicateur': 'Sages-femmes formées', 'valeurDepart': 0, 'cibleValeur': 6, 'cibleUnite': 'agents', 'realiseValeur': 6, 'etat': 'realisee', 'calendrier': ['2026-01-01/2026-03-31'], 'responsable': 'Maternité', 'service': 'Maternité', 'budgetPrevu': 250000, 'sourceFinancement': 'fonds_propres', 'avancementMode': 'calcule'},
    {'axe': 'medicaments_consommables', 'objectif': 'Éviter les ruptures', 'action': 'Mettre en place l’inventaire trimestriel de la pharmacie', 'resultatAttendu': 'Quatre inventaires signés',
      'indicateur': 'Inventaires réalisés', 'valeurDepart': 0, 'cibleValeur': 4, 'cibleUnite': 'inventaires', 'realiseValeur': 2, 'etat': 'en_cours', 'calendrier': ['2026-01-01/2026-03-31', '2026-04-01/2026-06-30', '2026-07-01/2026-09-30', '2026-10-01/2026-12-31'], 'responsable': 'Pharmacie', 'service': 'Pharmacie', 'budgetPrevu': 120000, 'sourceFinancement': 'fonds_propres', 'avancementMode': 'calcule'},
    {'axe': 'finances_recouvrement', 'objectif': 'Réduire les créances anciennes', 'action': 'Relancer chaque mois les compagnies d’assurance', 'resultatAttendu': 'Créances de plus de 60 jours réduites de moitié',
      'indicateur': 'Taux de recouvrement', 'valeurDepart': 40, 'cibleValeur': 80, 'cibleUnite': '%', 'realiseValeur': 55, 'etat': 'en_cours', 'calendrier': ['2026-04-01/2026-06-30', '2026-07-01/2026-09-30'], 'responsable': 'Direction administrative et financière', 'service': 'Administration', 'budgetPrevu': 90000, 'sourceFinancement': 'assurances', 'avancementMode': 'calcule'},
    {'axe': 'systeme_information', 'objectif': 'Sécuriser les données', 'action': 'Former tous les agents au logiciel de gestion', 'resultatAttendu': 'Chaque agent sait ouvrir une session et saisir',
      'indicateur': 'Agents formés', 'valeurDepart': 0, 'cibleValeur': 30, 'cibleUnite': 'agents', 'realiseValeur': 0, 'etat': 'planifiee', 'calendrier': ['2026-10-01/2026-12-31'], 'responsable': 'Direction', 'service': 'Direction', 'budgetPrevu': 300000, 'sourceFinancement': 'partenaire', 'avancementMode': 'calcule'},
  ];
  for (final a in actions) {
    m.collection('planAnnuel').inserer({'statut': 'actif', 'exercice': 2026, 'planVersion': 1, ...a}, prefixe: 'PTA');
  }
  m.collection('plansTravail').inserer({
    'id': 'PTA-2026-V1',
    'statut': 'actif',
    'reference': 'PTA-2026-V1',
    'exercice': 2026,
    'version': 1,
    'etat': etat,
    if (etat == 'soumis') ...{'soumisPar': 'Démo AGENT90', 'soumisLe': '2026-11-10T09:00:00Z'},
    if (etat == 'execution') ...{'soumisPar': 'Démo AGENT90', 'soumisLe': '2026-01-05T09:00:00Z', 'adoptePar': 'Direction', 'adopteLe': '2026-01-15T09:00:00Z', 'motifAdoption': 'Comité de direction du 15 janvier'},
  });
}

/// Un agent aux valeurs d'attente (catégorie et numéro CNSS vides, salaire provisoire) : la fiche porte le bloc « Confirmer ».
void _agentAttente(Magasin m) {
  final col = m.collection('personnel');
  final p = col.toutes.first;
  col.mettreAJour(p['id'], {'salaireProvisoire': true, 'categorieProvisoire': true, 'categorie': 'E1-1', 'cnssProvisoire': true, 'cnss': ''});
}

/// Trois vacations FICTIVES de la semaine du 16/11/2026, posées depuis un poste rattaché pour le premier agent de la fiche : « à valider » tant que la mère ne les a pas appliquées.
/// La fiche s'ouvre sur le premier agent de la liste : il devient MÉDECIN (donnée de démonstration anonymisée) pour que sa catégorie ait un régime de travail à montrer.
void _medecinEnTete(Magasin m) {
  final col = m.collection('personnel');
  final p = col.toutes.first;
  col.mettreAJour(p['id'], {'fonction': 'medecin', 'poste': 'Médecin généraliste', 'service': 'Médecine générale'});
}

void _vacationsAValider(Magasin m) {
  _medecinEnTete(m);
  final p = m.collection('personnel').toutes.first;
  final col = m.collection('planning');
  for (final jour in ['2026-11-16', '2026-11-18', '2026-11-20']) {
    col.inserer({
      'statut': 'actif',
      'date': jour,
      'employeId': p['id'],
      'employe': '${p['nomComplet'] ?? '${p['nom']} ${p['prenom']}'}',
      'fonction': p['fonction'],
      'service': p['service'],
      'type': 'garde',
      'validationEtat': 'a_valider',
    }, prefixe: 'PLN');
  }
}

/// Une facture à une entreprise FICTIVE (société de démonstration, IFU d'exemple) déjà émise et « en attente de certification » : le jeu livré n'a aucune ligne de relevé à réclamer.
void _semerFactureEntreprise(Magasin m) {
  m.collection('facturesTiers').inserer({
    'numero': 'FT-2026-00001',
    'type': 'tiers_payeur',
    'statut': 'actif',
    'date': '2026-11-16',
    'acheteurIfu': '3201700000001',
    'acheteurNom': 'SOCIÉTÉ DÉMONSTRATION SARL',
    'aibSituation': 'ifu_actif',
    'aibTaux': 1,
    'aibMotif': 'Acheteur avec IFU actif : taux du barème arrêté en vigueur.',
    'aibMontant': 3600,
    'montantTTC': 360000,
    'montantHT': 360000,
    'tva': 0,
    'netAPayer': 363600,
    'baseMecef': 360000,
    'designation': 'Prise en charge des soins — Souscripteur démonstration (AFRICAINE DES ASSURANCES, novembre 2026)',
    'compagnieCode': 'AFR',
    'compagnie': 'AFRICAINE DES ASSURANCES',
    'souscripteur': 'Souscripteur démonstration',
    'periode': 'mois',
    'periodeLabel': 'novembre 2026',
    'debut': '2026-11-01',
    'fin': '2026-11-16',
    'montantReleve': 360000,
    'piecesFilles': ['FN-2026-00412', 'FN-2026-00418', 'FN-2026-00431'],
    'nbFilles': 3,
    'statutMecef': 'en_attente',
    'emisePar': 'Comptable',
  }, prefixe: 'FTR');
}

/// Le démarrage d'un poste (main.dart) amorce la table des exercices avant le premier affichage : la capture le reproduit.
void _exercicesAuDemarrage(Magasin m) => amorcerExercices(m, _le);

/// Les services d'export, de mise à jour et de clé que le poste branche au démarrage (la coque de capture ne les branche pas) : sur un dossier de données d'exemple.
Future<void> _servicesBase(Magasin m, {String role = epRoleFileul}) async {
  final dossier = Directory('${Directory.systemTemp.path}/SIGHCBG/donnees')..createSync(recursive: true);
  bool peut(String g) => DroitsGestes(fiches: m.collection('rbac').actives).peut('admin', g);
  final base = ServiceBasePortable(magasin: m, dossierDonnees: dossier.path, role: () => role, cleClinique: () async => List<int>.generate(32, (i) => (i * 17 + 3) % 256), peut: peut)..installer();
  ServiceMiseAJour(magasin: m, dossierDonnees: dossier.path, base: base, role: () => role, peut: peut, versionCourante: '0.1.0').installer();
  ServiceCleClinique(magasin: m, dossierDonnees: dossier.path, peut: peut).installer();
}

/// Un relais SIMULÉ pour l'écran « Passerelle SMS » : le fournisseur est lu au relais, jamais réglé depuis le poste.
void _relaisSms(String pilote, {List<String> manquants = const []}) {
  mrbIntervalle = const Duration(hours: 1);
  mrbSourceInjectee = Source(actif: true)..relais = {'plafond_jour': 100, 'envoyes_aujourdhui': 12, 'en_attente': 1, 'pilote': pilote, if (manquants.isNotEmpty) 'parametres_manquants': manquants};
}

/// Vacations FICTIVES de la semaine du 16/11/2026 pour le premier agent salarié (donnée anonymisée, devenu médecin) : une « à valider » (non payée), une « refusée » et une validée.
void _vacationsMixtes(Magasin m) {
  _medecinEnTete(m);
  final col = m.collection('personnel');
  final p = col.toutes.first;
  col.mettreAJour(p['id'], {'salaireBase': 150000});
  final plan = m.collection('planning');
  for (final (jour, etat) in [('2026-11-02', 'a_valider'), ('2026-11-04', 'refuse'), ('2026-11-06', 'validee')]) {
    plan.inserer({
      'statut': 'actif',
      'date': jour,
      'employeId': p['id'],
      'employe': '${p['nomComplet'] ?? '${p['nom']} ${p['prenom']}'}',
      'fonction': p['fonction'],
      'service': p['service'],
      'type': 'garde',
      'validationEtat': etat,
    }, prefixe: 'PLN');
  }
}

/// Un relais SIMULÉ dont la mère annonce ses envois automatiques (réglages en vigueur, dernier tour en compteurs seulement).
void _relaisSmsAutomatiques(Magasin _) {
  mrbIntervalle = const Duration(hours: 1);
  mrbSourceInjectee = Source(actif: true)
    ..relais = {'plafond_jour': 100, 'envoyes_aujourdhui': 12, 'en_attente': 1, 'pilote': 'twilio'}
    ..automatiques = {
      'reglages': {'rappel_rdv_actif': true, 'voeux_anniversaire_actif': false, 'heure': 9, 'delai_rappel_heures': 24},
      'dernier_jour': '2026-11-16',
      'dernier_bilan': {
        'jour': '2026-11-16',
        'candidats': 5,
        'deposes': {'rappel_rdv': 2, 'anniversaire': 1},
        'refus': {'SMS_CONSENTEMENT_ABSENT': 2},
        'plafondAtteint': false
      },
    };
}

/// Un journal SIMULÉ où figure un SMS « expiré avant l'envoi » (numéros masqués, aucun texte).
void _journalSmsExpire(Magasin _) {
  mrbIntervalle = const Duration(hours: 1);
  mrbSourceInjectee = Source(actif: true, journalSms: const [
    {'id': 'sms-1', 'numero_masque': '+229 •••••••• 01', 'longueur': 88, 'modele': 'Rappel de rendez-vous', 'statut': 'envoye', 'tentatives': 1, 'depose_le': 1794822000000},
    {'id': 'sms-2', 'numero_masque': '+229 •••••••• 02', 'longueur': 60, 'modele': 'Vœux d’anniversaire', 'statut': 'non_depose', 'erreur': 'plafond_atteint', 'tentatives': 0, 'depose_le': 1794822000000},
    {'id': 'sms-3', 'numero_masque': '+229 •••••••• 03', 'longueur': 60, 'modele': 'Vœux d’anniversaire', 'statut': 'expire', 'tentatives': 0, 'depose_le': 1794822000000},
  ]);
}

final _captures = <_Cap>[
  _Cap('01-connexion', 'index', session: () => SessionPoste(exigeConnexion: true, horloge: () => _le)),
  _Cap('02-verrou', 'auth-lock', session: () => SessionPoste(exigeConnexion: true, horloge: () => _le)),
  _Cap('03-accueil-tableau', 'dash-receptionniste', role: 'reception'),
  _Cap('04-ruban-accueil', 'dash-receptionniste', role: 'reception', gestes: [toucherCle('domaine-Accueil')]),
  _Cap('05-recherche', 'dash-receptionniste', role: 'reception', gestes: [toucherCle('recherche-globale'), saisir('recherche-champ', 'para')]),
  _Cap('06-notifications', 'dash-receptionniste', role: 'reception', gestes: [toucherCle('barre-cloche')]),
  _Cap('07-profil', 'dash-receptionniste', role: 'reception', gestes: [toucherCle('barre-profil')]),
  _Cap('09-assistant', 'sup-assistant', role: 'reception'),
  _Cap('10-patients', 'm1-patients', role: 'reception'),
  _Cap('17-tableau-selection', 'm6-stock-detail', gestes: [cocherLignes(3)]),
  _Cap('18-export', 'm6-stock-detail', gestes: [cocherLignes(3), toucherBouton('Exporter la sélection')]),
  _Cap('19-patient-profil', 'm1-patient-profil', role: 'medecin'),
  _Cap('12b-rdv-nouveau', 'm2-rendezvous', role: 'reception', gestes: [toucherBouton('Nouveau')]),
  _Cap('35-delivrer', 'm6-dispensation', gestes: [toucherIcone('Délivrer')], jeuDeTest: true),
  _Cap('36-inventaire-feuille', 'm6-inventaire-feuille'),
  _Cap('40b-besoin-nouveau', 'm7-besoins', gestes: [toucherBouton('Nouveau bon')]),
  _Cap('57-encaisser', 'm8-caisse', gestes: [toucherIcone('Encaisser')]),
  _Cap('85-ecriture-nouvelle', 'm12-ecritures', gestes: [toucherBouton('Nouvelle écriture')]),
  _Cap('11-patient-nouveau', 'm1-patient-nouveau', role: 'reception'),
  _Cap('13-file-attente', 'm2-file-attente', role: 'reception', jeuDeTest: true),
  _Cap('14-externe', 'm1-externe', role: 'reception'),
  _Cap('15-certificats', 'm1-pieces', role: 'reception'),
  _Cap('16-constantes', 'm1-constantes', role: 'reception'),
  _Cap('20-dossiers-consultation', 'm2-dossiers-consultation', role: 'medecin'),
  _Cap('21-fiche-consultation', 'm2-consultation-fiche', role: 'medecin'),
  _Cap('22-ordonnances', 'm2-ordonnances', role: 'medecin'),
  _Cap('23-imagerie-demandes', 'm2-imagerie-demandes', role: 'medecin', jeuDeTest: true),
  _Cap('24-admissions', 'm3-admissions', role: 'medecin'),
  _Cap('25-bloc-cro', 'm3-bloc-cro', role: 'medecin'),
  _Cap('26-dossier-obstetrical', 'm4-dossier-obstetrical'),
  _Cap('28-prelevement', 'm5-prelevement'),
  _Cap('29-resultats', 'm5-resultats'),
  _Cap('30-dispensation', 'm6-dispensation', jeuDeTest: true),
  _Cap('31-stock-detail', 'm6-stock-detail'),
  _Cap('32-lots', 'm6-lots'),
  _Cap('34-transferts', 'm6-transferts'),
  _Cap('41-commandes', 'm7-commandes'),
  _Cap('42-livraisons', 'm7-livraisons'),
  _Cap('43-factures-fournisseurs', 'm7-factures-fournisseurs'),
  _Cap('50-facturation', 'm8-facturation'),
  _Cap('52-paiements', 'm8-paiements'),
  _Cap('53-avoirs', 'm8-facture-avoir'),
  _Cap('56-mecef-config', 'mecef-config', taille: Size(1440, 2600)),
  _Cap('60-assures', 'm9-assures'),
  _Cap('62-factures-assureur', 'm9-factures-assureur'),
  _Cap('70-personnel', 'm10-personnel'),
  _Cap('72-conges', 'm10-conges'),
  _Cap('73-mon-espace', 'm10-mes'),
  _Cap('74-paie-calcul', 'm11-calcul'),
  _Cap('82-grand-livre', 'm12-grand-livre'),
  _Cap('83-cloture', 'm12-cloture'),
  _Cap('90-direction', 'dash-direction'),
  _Cap('91-dash-caissier', 'dash-caissier', role: 'caissier'),
  // ---- Assistant d'installation du poste (poste neuf, aucun compte).
  _Cap('100-ins-accueil', 'index', posteNeuf: true, session: () => SessionPoste(exigeConnexion: true, horloge: () => _le)),
  _Cap('101-ins-premiere', 'index', posteNeuf: true, session: () => SessionPoste(exigeConnexion: true, horloge: () => _le), gestes: [toucherCle('ins:premiere')]),
  _Cap('102-ins-secours', 'index', posteNeuf: true, session: () => SessionPoste(exigeConnexion: true, horloge: () => _le), gestes: _premierCompte),
  _Cap('103-ins-configurations', null,
      posteNeuf: true,
      session: () => SessionPoste(exigeConnexion: true, horloge: () => _le),
      gestes: [..._premierCompte, toucherCle('ins:range'), toucherCle('ins:suite'), attendre(4)]),
  _Cap('104-ins-rejoindre', 'index', posteNeuf: true, session: () => SessionPoste(exigeConnexion: true, horloge: () => _le), gestes: [toucherCle('ins:rejoindre')]),
  // ---- Sauvegarde.
  _Cap('110-sauvegardes', 'm14-sauvegardes', taille: Size(1440, 1700)),
  _Cap('111-hors-site', 'm14-sauvegardes', taille: Size(1440, 2800)),
  // ---- Caisse : reçu, ticket, impression de la sélection.
  _Cap('58-recu', 'm8-caisse', gestes: [toucherIcone('Réimprimer le reçu détaillé')]),
  _Cap('59-ticket', 'm8-facturation', gestes: [toucherBouton('Ticket de caisse')]),
  _Cap('19b-imprimer-selection', 'm8-paiements', gestes: [cocherLignes(2), toucherBouton('Imprimer la sélection')]),
  // ---- Satisfaction en ligne.
  _Cap('120-enquetes', 'adm-enquetes'),
  _Cap('121-enquete-partager', 'adm-enquetes', gestes: [toucherLibelle('Partager à un tiers'), choisir('usage', 'Sur Internet, par le relais — depuis chez soi (anonyme, chiffré)')]),
  _Cap('122-enquete-liens', 'adm-enquetes', gestes: [toucherTexte('Liens de partage')]),
  _Cap('123-enquete-qr', 'adm-enquetes', taille: Size(1440, 1100), gestes: [
    toucherLibelle('Partager à un tiers'),
    choisir('usage', 'Sur Internet, par le relais — depuis chez soi (anonyme, chiffré)'),
    toucherBouton('Ouvrir le lien'),
    attendre(4),
  ]),
  _Cap('123b-enquete-liens', 'adm-enquetes', gestes: [
    toucherLibelle('Partager à un tiers'),
    choisir('usage', 'Sur Internet, par le relais — depuis chez soi (anonyme, chiffré)'),
    toucherBouton('Ouvrir le lien'),
    attendre(4),
    fermerModales(),
    toucherTexte('Liens de partage (1)'),
  ]),
  _Cap('124-satisfaction', 'adm-satisfaction'),
  // ---- Planning individuel (fiche du personnel).
  // Jeu livré anonymisé (« AGENTnn Démo ») : le premier agent est mis médecin pour que son planning ait un régime à montrer.
  _Cap('130-planning-individuel', 'm10-employe-profil', preparer: _medecinEnTete, taille: Size(1440, 1500), gestes: [toucherTexte('Planning individuel')]),
  _Cap('131-planning-deroger', 'm10-employe-profil', preparer: _medecinEnTete, taille: Size(1440, 1500), gestes: [toucherTexte('Planning individuel'), toucherBouton('Déroger')]),
  // ---- Mises à jour du 17/11/2026 : PTA, agent, planning synchronisé, facture à une entreprise, taux et barèmes, numérotation.
  _Cap('150-pta-brouillon', 'm13-plan-annuel', role: 'direction', taille: Size(1440, 1500), preparer: (m) => _semerPta(m, 'brouillon')),
  _Cap('151-pta-soumis', 'm13-plan-annuel', role: 'direction', taille: Size(1440, 1000), preparer: (m) => _semerPta(m, 'soumis')),
  _Cap('152-pta-execution', 'm13-plan-annuel', role: 'direction', taille: Size(1440, 1500), preparer: (m) => _semerPta(m, 'execution')),
  _Cap('153-pta-action-nouvelle', 'm13-plan-annuel', role: 'direction', taille: Size(1440, 1700), preparer: (m) => _semerPta(m, 'brouillon'), gestes: [toucherBouton('Nouvelle action')]),
  _Cap('154-pta-reconduire', 'm13-plan-annuel', role: 'direction', taille: Size(1440, 1100), preparer: (m) => _semerPta(m, 'execution'), gestes: [toucherBouton('Reconduire les actions non réalisées vers l’exercice 2027')]),
  _Cap('155-pta-vide', 'm13-plan-annuel', role: 'direction', taille: Size(1440, 1000), preparer: (m) => amorcerExercices(m, _le)),
  _Cap('160-personnel-nouveau', 'm10-personnel', gestes: [toucherBouton('Nouveau')], taille: Size(1440, 1300)),
  _Cap('161-fiche-attente', 'm10-employe-profil', taille: Size(1440, 1300), preparer: _agentAttente),
  _Cap('162-fiche-surveillant', 'm10-employe-profil', role: 'surveillant', taille: Size(1440, 1000)),
  _Cap('170-facture-entreprise', 'm9-facture-mere', role: 'comptable', jeuDeTest: true, taille: Size(1440, 1500), gestes: [toucherTexte('Factures à une entreprise')]),
  _Cap('171-taux-comptables', 'cfg-comptabilite', role: 'da', taille: Size(1440, 4200)),
  _Cap('172-taux-cotisations', 'm11-cotisations', role: 'comptable', taille: Size(1440, 2600)),
  _Cap('173-numerotation', 'cfg-fiscalite', taille: Size(1440, 3600)),
  // ---- Mises à jour du 17/11/2026 (suite) : facture à une entreprise complète, planning individuel du Surveillant, planning entre postes, exercice au démarrage,
  // imprimante intégrée, passerelle SMS, export / import / mise à jour, restauration de la clé, Assistant.
  _Cap('174-facture-entreprise-emise', 'm9-facture-mere', role: 'comptable', taille: Size(1440, 1500), preparer: _semerFactureEntreprise, gestes: [toucherTexte('Factures à une entreprise')]),
  _Cap('175-facture-entreprise-apercu', 'm9-facture-mere', role: 'comptable', taille: Size(1440, 1900), preparer: _semerFactureEntreprise, gestes: [toucherTexte('Factures à une entreprise'), toucherIcone('Aperçu et impression')]),
  _Cap('176-facture-entreprise-avoir', 'm9-facture-mere', role: 'comptable', taille: Size(1440, 1500), preparer: _semerFactureEntreprise, gestes: [toucherTexte('Factures à une entreprise'), toucherIcone('Émettre un avoir')]),
  _Cap('132-planning-surveillant', 'm10-employe-profil', role: 'surveillant', preparer: _medecinEnTete, taille: Size(1440, 1500), gestes: [toucherTexte('Planning individuel')]),
  _Cap('133-planning-a-valider', 'm10-employe-profil', preparer: _vacationsAValider, taille: Size(1440, 1700), gestes: [toucherTexte('Planning individuel')]),
  _Cap('156-selecteur-exercice', 'm12-grand-livre', role: 'comptable', preparer: _exercicesAuDemarrage),
  _Cap('112-base-portable', 'cfg-base-portable', preparer: _servicesBase, taille: Size(1440, 2300)),
  _Cap('113-export-fait', 'cfg-base-portable', preparer: _servicesBase, taille: Size(1440, 2300), gestes: [toucherCle('base:exporter'), attendre(60)]),
  _Cap('114-cle-restauration', 'mere-cle-restauration', mode: ModePoste.mere, preparer: (m) => _servicesBase(m, role: epRoleMere), taille: Size(1440, 1100)),
  _Cap('180-assistant-sauvegarde', 'sup-assistant', gestes: [saisir('assistant:champ', 'Quand a été faite la dernière sauvegarde ?'), toucherCle('assistant:envoyer'), attendre(8)]),
  _Cap('181-assistant-avis-medical', 'sup-assistant', role: 'medecin', gestes: [saisir('assistant:champ', 'Quelle dose de paracétamol pour un enfant de 12 kg ?'), toucherCle('assistant:envoyer'), attendre(8)]),
  _Cap('182-assistant-recettes', 'sup-assistant', role: 'direction', taille: Size(1440, 1500), gestes: [saisir('assistant:champ', 'Recettes du mois dernier par secteur, comparées au mois d’avant'), toucherCle('assistant:envoyer'), attendre(8)]),
  _Cap('183-assistant-fournisseur', 'sup-assistant', role: 'da', taille: Size(1440, 1500), gestes: [saisir('assistant:champ', 'Combien on doit au fournisseur Grossiste Pharma Borgou ?'), toucherCle('assistant:envoyer'), attendre(8)]),
  _Cap('184-assistant-sans-fiche', 'sup-assistant', gestes: [saisir('assistant:champ', 'Comment je crée un nouvel utilisateur et je lui donne un rôle ?'), toucherCle('assistant:envoyer'), attendre(8)]),
  // ---- Mises à jour du 18/11/2026 (v31) : reprise d'un poste, import de la liasse, fiches d'aide, contact de l'éditeur.
  _Cap('190-reprise-liste', 'mere-reprise-poste', mode: ModePoste.mere, preparer: _repriseDemo, taille: Size(1440, 1150)),
  _Cap('191-reprise-modale', 'mere-reprise-poste', mode: ModePoste.mere, preparer: _repriseDemo, taille: Size(1440, 1150), gestes: [toucherBouton('Générer un code de reprise')]),
  _Cap('192-reprise-code', 'mere-reprise-poste', mode: ModePoste.mere, preparer: _repriseDemo, taille: Size(1440, 1150), gestes: [toucherBouton('Générer un code de reprise'), toucherCle('rep:confirmer'), attendre(4)]),
  _Cap('193-reprise-emis', 'mere-reprise-poste', mode: ModePoste.mere, preparer: _repriseDemo, taille: Size(1440, 1150), gestes: [toucherBouton('Générer un code de reprise'), toucherCle('rep:confirmer'), attendre(4), toucherCle('rep:fermer'), attendre(4)]),
  _Cap('194-liasse-import', 'm12-liasse-import', role: 'comptable', preparer: _liasseAntidatee, taille: Size(1440, 1500)),
  _Cap('195-liasse-verifiee', 'm12-liasse-import', role: 'comptable', preparer: _liasseAntidatee, taille: Size(1440, 1500), gestes: [saisir('liasse:fichier', 'tool/donnees/liasse_2025_demo.json'), toucherCle('liasse:verifier'), attendre(2)]),
  _Cap('196-liasse-importee', 'm12-liasse-import', role: 'comptable', preparer: _liasseAntidatee, taille: Size(1440, 1700), gestes: [saisir('liasse:fichier', 'tool/donnees/liasse_2025_demo.json'), toucherCle('liasse:verifier'), attendre(2), toucherCle('liasse:importer'), attendre(2)]),
  _Cap('197-liasse-refus', 'm12-liasse-import', role: 'comptable', preparer: _liasseAntidatee, taille: Size(1440, 1200), gestes: [saisir('liasse:fichier', 'tool/donnees/plan-comptable-syscohada-revise.csv'), toucherCle('liasse:verifier'), attendre(2)]),
  _Cap('198-fiches-aide', 'cfg-fiches-aide', role: 'direction', taille: Size(1440, 1500)),
  _Cap('199-fiche-redaction', 'cfg-fiches-aide', role: 'direction', taille: Size(1440, 2300), gestes: [toucherCle('aide:rediger:4')]),
  _Cap('200-fiche-validation', 'cfg-fiches-aide', role: 'direction', taille: Size(1440, 2300), preparer: _ficheAideProposee, gestes: [toucherClePrefixe('aide:valider:')]),
  _Cap('201-fiche-professionnel', 'cfg-fiches-aide', role: 'direction', taille: Size(1440, 2300), preparer: (m) => _ficheAideProposee(m, pro: true), gestes: [toucherClePrefixe('aide:valider:')]),
  _Cap('202-contact-editeur', 'contact-editeur', role: 'reception', taille: Size(1440, 1100)),
  _Cap('203-parametre-regler', 'cfg-systeme', role: 'admin', mode: ModePoste.mere, taille: Size(1440, 1100), gestes: [toucherTexte('Paramètres'), reglerCarte('Modes de paiement')]),
  _Cap('204-numerisation', 'm1-numerisation', role: 'direction', taille: Size(1440, 1500)),
  _Cap('205-fiche-aide-attente', 'cfg-fiches-aide', role: 'direction', taille: Size(1440, 2100), preparer: (m) async {
    _ficheAideProposee(m);
    await _rattache(m);
  }, gestes: [toucherClePrefixe('aide:valider:'), toucherCle('aide:valider-ok'), attendre(4)]),
  _Cap('206-liasse-fileul-attente', 'm12-liasse-import', role: 'comptable', taille: Size(1440, 1700), preparer: (m) async {
    _liasseAntidatee(m);
    await _rattache(m);
  }, gestes: [saisir('liasse:fichier', 'tool/donnees/liasse_2025_demo.json'), toucherCle('liasse:verifier'), attendre(2), toucherCle('liasse:importer'), attendre(2)]),
  // ---- SMS (poste mère).
  _Cap('140-sms-passerelle', 'mere-sms-passerelle', mode: ModePoste.mere, preparer: _relaisSmsAutomatiques, taille: Size(1440, 1750)),
  _Cap('142-sms-parametres-manquants', 'mere-sms-passerelle', mode: ModePoste.mere, preparer: (_) => _relaisSms('vonage', manquants: ['RELAIS_SMS_VONAGE_SECRET']), taille: Size(1440, 1500)),
  _Cap('141-sms-journal', 'mere-sms-journal', mode: ModePoste.mere),
  // ---- v33 (20/11/2026) : numéros MECeF de démonstration, paie et planning (vacations en attente, refusées), SMS automatiques et consentement.
  _Cap('207-mecef-demonstration', 'mecef-factures', taille: Size(1440, 1000)),
  _Cap('216-mecef-piece-demonstration', 'mecef-factures', taille: Size(1440, 1300), gestes: [toucherIconeN('Imprimer la facture normalisée', 1)]),
  _Cap('217-admission-nouvelle', 'm3-admissions', role: 'medecin', taille: Size(1440, 1100), gestes: [toucherBouton('Nouveau')]),
  _Cap('218-accouchement-nouvel', 'm4-accouchements', role: 'medecin', taille: Size(1440, 1100), gestes: [toucherBouton('Nouveau')]),
  _Cap('208-factures-demonstration', 'm8-factures', taille: Size(1440, 1000)),
  _Cap('209-paie-vacations-attente', 'm11-calcul', role: 'comptable', preparer: _vacationsMixtes, taille: Size(1440, 1500)),
  _Cap('210-planning-registre-refusee', 'm10-planning', preparer: _vacationsMixtes, taille: Size(1440, 3500)),
  _Cap('211-patient-consentement-sms', 'm1-patient-nouveau', role: 'reception', taille: Size(1440, 1500)),
  _Cap('213-sms-parametres-automatiques', 'cfg-systeme', role: 'admin', mode: ModePoste.mere, taille: Size(1440, 1500), gestes: [toucherTexte('Paramètres'), defilerVers('Rappel automatique de rendez-vous par SMS')]),
  _Cap('214-rappels-modeles-sms', 'cfg-rappels', role: 'admin', taille: Size(1440, 1500)),
  _Cap('215-sms-journal-expire', 'mere-sms-journal', mode: ModePoste.mere, preparer: _journalSmsExpire, taille: Size(1440, 1000)),
];

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height].map((v) => (v * 10).roundToDouble() / 10).toList();

Size _tailleCourante = _taille;

bool _visible(Rect r) => r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0 && r.left < _tailleCourante.width && r.top < _tailleCourante.height;

/// Les repères de l'écran : boutons du kit (libellé), clés textuelles, infobulles, onglets.
Map<String, Object?> _reperes(WidgetTester t) {
  final boutons = <Map<String, Object?>>[];
  for (final e in find.byType(BoutonSigh).evaluate()) {
    final w = e.widget as BoutonSigh;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) boutons.add({'libelle': w.libelle, 'rect': _rect(r)});
  }
  for (final e in find.byType(BoutonIcone).evaluate()) {
    final w = e.widget as BoutonIcone;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) boutons.add({'libelle': w.libelle, 'icone': true, 'rect': _rect(r)});
  }
  for (final e in find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Sélectionner')).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) boutons.add({'libelle': (e.widget as Semantics).properties.label, 'case': true, 'rect': _rect(r)});
  }
  final cles = <String, Object?>{};
  for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String>).evaluate()) {
    final k = (e.widget.key as ValueKey<String>).value;
    if (k.startsWith('[') || cles.containsKey(k)) continue;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) cles[k] = _rect(r);
  }
  final infos = <Map<String, Object?>>[];
  for (final e in find.byType(Tooltip).evaluate()) {
    final w = e.widget as Tooltip;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached || (w.message ?? '').isEmpty) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) infos.add({'message': w.message, 'rect': _rect(r)});
  }
  final onglets = <Map<String, Object?>>[];
  for (final e in find.byType(Tab).evaluate()) {
    final w = e.widget as Tab;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) onglets.add({'libelle': w.text ?? '', 'rect': _rect(r)});
  }
  // Aucun texte de l'écran n'est écrit (noms de patients) : seuls les repères géométriques servent aux flèches.
  return {'boutons': boutons, 'cles': cles, 'infobulles': infos, 'onglets': onglets};
}

void main() {
  setUpAll(() async {
    await chargerPolices();
    // La famille « monospace » (identifiants d'appairage, empreintes, chemins) n'existe pas dans le banc d'essai : sans police, elle se dessine en carrés pleins. On lui donne Liberation Mono.
    final monospace = FontLoader('monospace');
    for (final f in ['Regular', 'Bold']) {
      monospace.addFont(Future.value(ByteData.view(File('assets/polices/pdf/LiberationMono-$f.ttf').readAsBytesSync().buffer)));
    }
    await monospace.load();
    // Le hachage d'essai (rapide) : la création du premier compte de l'assistant d'installation ne prend pas de longues secondes.
    ServiceIdentifiants.parametres = AccParametresHachage.tests;
  });
  setUp(() => CoquePoste.panneauOuvertAuDemarrage = false);
  tearDown(() {
    ToastsSigh.viderPourTests();
    mrbSourceInjectee = null;
    sourceRepriseInjectee = null;
  });

  for (final c in _captures) {
    testWidgets('capture manuel : ${c.nom}', skip: _sortie == null, (t) async {
      _tailleCourante = c.taille;
      t.view.physicalSize = c.taille;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      Magasin? neuf;
      if (c.posteNeuf) {
        const noms = ['audit', 'utilisateurs', 'rbac', 'tentativesConnexion', 'personnel', 'soignants', 'rolesBase', 'support'];
        neuf = anonymiser(Magasin.depuisDossier(noms, 'assets/donnees/jeu'), noms);
        await t.runAsync(() => ServiceInstallation.de(neuf!).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'poste-demo')));
      }
      Magasin? prepare;
      if (neuf == null) {
        prepare = c.jeuDeTest
            ? Magasin.depuisDossier(Magasin.collectionsDuJeu)
            : anonymiser(Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu'), Magasin.collectionsDuJeu);
        await t.runAsync(() async => c.preparer?.call(prepare!));
      }
      await t.pumpWidget(RepaintBoundary(
          key: const Key('cap-manuel'),
          child: SighPoste(
              key: UniqueKey(),
              donnees: _donnees,
              config: ConfigPoste(mode: c.mode, role: c.role),
              ecranInitial: c.ecran,
              // Le jeu de démonstration LIVRÉ avec le poste (assets/donnees/jeu) : noms fictifs de Baguidi, jamais le jeu de test.
              magasin: neuf ?? prepare,
              session: c.session?.call(),
              horloge: () => _le)));
      await _pomper(t, 6);
      for (final g in c.gestes) {
        await g(t);
      }
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await _pomper(t, 2);
      // GARDE : aucun texte de l'écran ne porte le nom d'un agent réel (le jeu livré est anonymisé ; un oubli ferait échouer la capture, sans image).
      final textes = [
        for (final e in find.byWidgetPredicate((w) => w is RichText).evaluate()) (e.widget as RichText).text.toPlainText(),
        for (final e in find.byType(EditableText).evaluate()) (e.widget as EditableText).controller.text,
      ].join('\n');
      final reels = trouves(textes, _nomsReels);
      expect(reels, isEmpty, reason: '${c.nom} : nom(s) d’agent réel à l’écran : ${reels.join(', ')}');
      final reperes = _reperes(t);
      await t.runAsync(() async {
        final RenderRepaintBoundary b = t.renderObject(find.byKey(const Key('cap-manuel')));
        final ui.Image img = await b.toImage(pixelRatio: 1.25);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory(_sortie!).createSync(recursive: true);
        File('$_sortie/${c.nom}.png').writeAsBytesSync(d!.buffer.asUint8List());
        File('$_sortie/${c.nom}.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
          'nom': c.nom,
          'ecran': c.ecran,
          'role': c.role,
          'taille': [c.taille.width, c.taille.height],
          'echelle': 1.25,
          ...reperes,
        }));
      });
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });
  }
}
