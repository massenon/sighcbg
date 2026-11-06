import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import '../m9/commun.dart' show ecoute;

export '../m6/points_commun.dart' show champUnique, commande;
export '../m8/commun.dart' show n, m;
export '../m9/commun.dart' show pieceM9, monoTexte, tiret, ecoute, deuxCartes, ClassementSigh;

/// Briques communes aux neuf écrans de M11 (paie & primes). Les règles chiffrées vivent dans `packages/domaine/lib/src/paie/pai_moteur.dart` ; ce
/// fichier ne porte que de la mise en page et le branchement du moteur sur le magasin.

/// L'exercice des écrans de calcul : l'exercice OUVERT de la collection `exercices` qui contient la date du poste, à défaut l'année de l'horloge. La
/// maquette écrivait « 2026 » en dur (écart E686) : un poste mis en service en 2027 aurait calculé la paie de 2026.
int paiAnnee(ContexteEcran c) => paiExercice(c.magasin.collection('exercices').actives, c.aujourdhui);

/// Les signataires des pièces de paie, LUS AU PERSONNEL (poste et fonction) : aucun nom d'agent n'est écrit dans le code. Personne ne porte la
/// qualité : la pièce imprime une ligne de signature sans nom, que l'on signe à la main.
Signature signataire(Magasin m, String role, PaiQualite q, {String mention = 'Signature'}) =>
    Signature(role, nom: paiSignataire(m.collection('personnel').actives, q), mention: mention);

Signature signComptable(Magasin m) => signataire(m, 'Le Comptable', PaiQualite.comptable);

Signature signDaf(Magasin m) => signataire(m, 'La Directrice Administrative', PaiQualite.daf);

/// La Direction signe la paie : son nom figure sur les journaux (« Validation » / « Bon à payer »).
Signature signDirection(Magasin m, String mention) => signataire(m, 'La Direction', PaiQualite.direction, mention: mention);

/// Les deux activités de Paramètres système (PRD P0-5) lues dans `modulesActifs`, et non dans un drapeau à part : fermées, le calcul n'ajoute aucune
/// prime NS 132 et ne retranche aucune sanction NS 131. Un bulletin déjà ENREGISTRÉ n'est jamais recalculé : il garde ses montants.
({bool primesNs132, bool sanctionsNs131}) activitesPaie(Magasin mag) => paiActivites(mag.collection('modulesActifs').toutes);

/// Ce que le moteur lit au magasin (la maquette interroge les collections à chaque calcul).
PaiEntrees entreesPaie(Magasin mag) {
  final a = activitesPaie(mag);
  return PaiEntrees(
    planning: mag.collection('planning').actives,
    evaluations: mag.collection('evaluations').actives,
    avances: mag.collection('avances').actives,
    participations: mag.collection('participations').actives,
    grille: mag.collection('grillePrimes').actives,
    historique: mag.collection('historiquePrimes').actives,
    heuresSup: mag.collection('heuresSup').actives,
    prets: mag.collection('pretsEtudes').actives,
    primesNs132: a.primesNs132,
    sanctionsNs131: a.sanctionsNs131,
  );
}

/// Les collections que le calcul de la paie lit : un écran se redessine quand l'une d'elles bouge.
const collectionsPaie = ['personnel', 'planning', 'evaluations', 'avances', 'participations', 'grillePrimes', 'historiquePrimes', 'heuresSup', 'pretsEtudes', 'modulesActifs', 'exercices'];

Listenable ecoutePaie(ContexteEcran c, [List<String> enPlus = const []]) => ecoute(c, [...collectionsPaie, ...enPlus]);

List<PaiCalcul> calculerTousPaie(ContexteEcran c, int mois) => paiCalculerTous(c.magasin.collection('personnel').actives, paiAnnee(c), mois, entreesPaie(c.magasin), c.aujourdhui);

/// Le bandeau qui DIT qu'une activité de la paie est fermée (Paramètres système) : un brut sans primes ou une sanction nulle doivent s'expliquer.
List<Widget> avisActivitesPaie(ContexteEcran c) {
  final a = activitesPaie(c.magasin);
  final fermees = [if (!a.primesNs132) paiBasculeNs132, if (!a.sanctionsNs131) paiBasculeNs131];
  if (fermees.isEmpty) return const [];
  return [
    NoteSigh(
        'Activité fermée dans Paramètres système : ${fermees.map((b) => '${b.libelle}. ${b.effet}').join(' ')} Les bulletins déjà enregistrés gardent leurs montants.',
        ton: TonSigh.attention,
        icone: LucideIcons.toggleLeft),
    const SizedBox(height: 16),
  ];
}

/// `avisSansSalaire()` : le bandeau (suivi d'un espace) qui nomme les agents exclus du calcul faute de salaire de base ; vide s'ils sont tous calculables.
List<Widget> avisPaie(ContexteEcran c) {
  final avis = paiAvisSansSalaire(c.magasin.collection('personnel').actives);
  return avis == null ? const [] : [NoteSigh(avis, ton: TonSigh.attention, icone: LucideIcons.wallet), const SizedBox(height: 16)];
}

/// `String(nombre)` de JavaScript : 10 → « 10 », 3.6 → « 3.6 » (jamais « 10.0 »).
String paiNum(num v) => v == v.truncate() ? '${v.truncate()}' : '$v';

/// « octobre 2026 » : les cartouches de période de la maquette n'ont PAS de majuscule (`C.MOIS[m]` brut).
String periodeBrute(ContexteEcran c, int mois) => '${paiMois[mois]} ${paiAnnee(c)}';

/// « Octobre 2026 » : les options des sélecteurs de période (`C.MOIS` capitalisé + année).
List<OptionChamp> optionsMoisCap(int annee) => [
      for (var i = 0; i < 12; i++) OptionChamp('$i', paiPeriodeLibelle(annee, i))
    ];

/// Les options de l'écran ORTB : `C.MOIS[m] + ' ' + annee` — SANS majuscule (comme la maquette).
List<OptionChamp> optionsMoisBrut(int annee) => [
      for (var i = 0; i < 12; i++) OptionChamp('$i', '${paiMois[i]} $annee')
    ];

/// Un sélecteur de mois à UN champ (la barre de l'écran), initialisé au mois de l'horloge du poste.
ControleurFormulaire selecteurMois(ContexteEcran c, String libelle, List<OptionChamp> options) => champUnique(
    ChampDef(nom: 'mois', libelle: libelle, type: TypeChamp.select, col: ColChamp.plein, options: options), '${c.aujourdhui.month - 1}');

int moisChoisi(ControleurFormulaire ctl) => int.tryParse('${ctl['mois']}') ?? 0;

/// La barre de commandes d'un écran de période : `.card > .card-body.flex.flex-wrap.items-end.gap-3` (le sélecteur, puis les boutons).
Widget barrePeriode(ControleurFormulaire selecteur, List<Widget> boutons) => CarteSigh(
    child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
      commande(selecteur, largeur: 224),
      ...boutons,
    ]));

/// Une cellule de montant (`C.money(v, false)`).
Widget cellMontant(num v, {bool fort = false, Color? couleur}) => Text(money(v, avecDevise: false),
    style: TextStyle(
        color: couleur ?? (fort ? JetonsShell.slate800 : JetonsShell.slate700),
        fontSize: 14,
        height: 20 / 14,
        fontWeight: fort ? FontWeight.w600 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()]));

Widget cellTexte(String t, {Color couleur = JetonsShell.slate700, FontWeight? poids, double taille = 14}) =>
    Text(t, style: TextStyle(color: couleur, fontSize: taille, height: taille == 14 ? 20 / 14 : 16 / 12, fontWeight: poids));

Widget cellSecondaire(String t) => Text(t, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12));

/// Deux lignes (nom, puis détail) : la cellule « Agent » des écrans de paie.
Widget cellAgent(String nom, String detail) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(nom, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
      Text(detail, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
    ]);

/// La ligne de tableau d'un calcul : les clés des colonnes, et le calcul lui-même sous `_c`.
Map<String, Object?> ligneCalcul(PaiCalcul c) => {
      'id': c.employe['id'],
      'matricule': c.matricule,
      'agent': c.nomComplet,
      'salaireBase': c.salaireBase,
      'gardes': c.gardes,
      'permanences': c.permanences,
      'totalPrimes': c.totalPrimes,
      'brut': c.brut,
      'sanction': c.sanction,
      'cnssOuvriere': c.cnssOuvriere,
      'cnssPatronale': c.cnssPatronale,
      'vps': c.vps,
      'its': c.its,
      'ortbRadio': c.ortbRadio,
      'ortbTele': c.ortbTele,
      'ortb': c.ortb,
      'avances': c.avances,
      'participations': c.participations,
      'net': c.net,
      '_c': c,
    };

PaiCalcul calculDe(Map<String, Object?> ligne) => ligne['_c'] as PaiCalcul;

const iconePaie = LucideIcons.calculator;
