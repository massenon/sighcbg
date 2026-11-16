import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/choix_exercice.dart';
import '../m9/commun.dart' show n, m, dateDe, mono;

export '../m9/commun.dart'
    show n, m, dateDe, mono, monoTexte, tiret, ecoute, actives, deuxCartes, ClassementSigh, pieceM9, signDaf, montantFort;

/// Briques communes à la comptabilité de base de M12 (tableau de bord, plan comptable, journaux, écritures, grand livre, balance, dépenses).
/// Les règles chiffrées vivent dans `packages/domaine/lib/src/comptabilite/` ; ce fichier ne porte que de la mise en page et de la lecture du magasin.

/// `exo()` : l'exercice choisi au sélecteur de la barre supérieure (en mémoire pour la session) ; à défaut, celui qui contient la date du jour (Direction du 16/11/2026, E3260).
int exerciceChoisi(ContexteEcran c) => ChoixExercice.courant(c.magasin, c.aujourdhui);

/// `ecritures()` : les écritures ACTIVES de l'exercice choisi.
List<Fiche> ecrituresExercice(ContexteEcran c) =>
    cpaEcrituresExercice(c.magasin.collection('ecritures').actives, exerciceChoisi(c));

/// `centreLabel(id)` : la collection ADMINISTRABLE fait foi (archivés compris), puis la semence ; sinon l'identifiant lui-même.
String libelleCentre(ContexteEcran c, Object? id) {
  for (final x in c.magasin.collection('centresCouts').toutes) {
    if (x['code'] == id) return '${x['libelle']}';
  }
  for (final x in cpaCentresCout) {
    if (x.$1 == id) return x.$2;
  }
  return '$id';
}

/// Les collections que lit la comptabilité : un écran se redessine quand l'une d'elles bouge.
Listenable ecouteCompta(ContexteEcran c, [List<String> en = const []]) => Listenable.merge([
      for (final k in ['ecritures', 'comptes', 'centresCouts', ...en]) c.magasin.collection(k)
    ]);

/// Signatures des états comptables (la maquette les écrit en dur).
const signComptable = Signature('Le Comptable');
const signDafCompta = Signature('La Directrice Administrative', qualite: PaiQualite.daf);

// --- Colonnes réutilisables des écritures ------------------------------------------------------------------------------------------------------------

ColonneTableau colNumeroEcriture() => ColonneTableau(
    cle: 'numero',
    libelle: 'N° pièce',
    sansCoupure: true,
    texte: (e) => '${e['numero'] ?? ''}',
    rendu: (_, e) => Text('${e['numero'] ?? ''}',
        style: mono.copyWith(color: JetonsShell.navy800, fontWeight: FontWeight.w600)));

ColonneTableau colDateEcriture() => ColonneTableau(
    cle: 'date',
    libelle: 'Date',
    sansCoupure: true,
    valeur: (e) => e['date'],
    valeurExport: (e) => valeurExportDate(e['date']),
    texte: (e) => dateDe(e['date']));

ColonneTableau colJournalEcriture() => ColonneTableau(
    cle: 'journal',
    libelle: 'Journal',
    sansCoupure: true,
    texte: (e) => '${e['journal'] ?? ''}',
    rendu: (_, e) => BadgeSigh('${e['journal'] ?? ''}', ton: TonSigh.navy));

ColonneTableau colCompteEcriture() => ColonneTableau(
    cle: 'compte',
    libelle: 'Compte',
    texte: (e) => '${e['compte']} ${e['compteLibelle'] ?? cpaCompteLibelle(e['compte'])}',
    rendu: (_, e) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${e['compte']}', style: mono.copyWith(color: JetonsShell.slate700, fontWeight: FontWeight.w600)),
          Text('${e['compteLibelle'] ?? cpaCompteLibelle(e['compte'])}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
        ]));

ColonneTableau _sens(String cle, String libelle) => ColonneTableau(
    cle: cle,
    libelle: libelle,
    droite: true,
    texte: (e) => n(e[cle]) != 0 ? m(e[cle]) : '',
    // L'export écrit le VRAI montant (décimales comprises) ; un sens vide reste une cellule vide.
    valeurExport: (e) => n(e[cle]) != 0 ? valeurExportNombre(e[cle]) : null,
    rendu: (_, e) => n(e[cle]) != 0
        ? Text(m(e[cle]),
            style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()]))
        : const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 14, height: 20 / 14)));

ColonneTableau colDebitEcriture() => _sens('debit', 'Débit');
ColonneTableau colCreditEcriture() => _sens('credit', 'Crédit');

/// Un montant FORT (14 en 600), aligné à droite par la colonne.
Widget montantGras(num v, {Color couleur = JetonsShell.slate900}) => Text(m(v),
    style: TextStyle(color: couleur, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]));

/// Le bandeau « RG-10 respectée » ou « écart » d'une saisie ou d'une consultation.
Widget noteEquilibre(num debit, num credit, {bool saisie = false}) {
  final ok = debit == credit && (!saisie || debit > 0);
  return ok
      ? NoteSigh(
          saisie
              ? 'RG-10 respectée — l’écriture est équilibrée : débit = crédit = ${money(debit)}.'
              : 'Écriture équilibrée : débit = crédit = ${money(debit)} (RG-10).',
          ton: TonSigh.succes,
          icone: LucideIcons.scale)
      : NoteSigh(
          saisie
              ? 'RG-10 — l’écriture n’est pas équilibrée : écart de ${money((debit - credit).abs())}. La validation est impossible tant que débit ≠ crédit.'
              : 'Écart de ${money((debit - credit).abs())} entre débit et crédit (RG-10).',
          ton: TonSigh.danger,
          icone: LucideIcons.scale3d);
}

// --- Bandeau de l'exercice (lot CLO, décision du 16/11/2026, § 6, point e) -------------------------------------------------------------------------

/// LE BANDEAU DE L'EXERCICE sur les écrans M12 à année : l'ÉTAT de l'exercice affiché (ouvert · en clôture · clos · non amorcé), ce que cet état veut dire pour les
/// chiffres de l'écran, et les boutons « Exercice N-1 » / « Exercice N+1 » — ABSENTS aux bornes (pas d'exercice voisin), jamais grisés, comme les flèches de la barre
/// supérieure. Il ne change PAS la règle du défaut : l'exercice affiché reste celui du choix de session, à défaut celui qui contient la date du jour (v21, E3260).
/// [voisins] : les années voisines imposées par l'écran (un écran qui n'offre qu'une partie des exercices) ; absent, les exercices de la collection font foi.
/// [surChoix] : ce que fait un bouton ; absent, il pose le choix d'exercice de la session (la coque repeint l'écran).
class BandeauExercice extends StatelessWidget {
  const BandeauExercice({super.key, required this.annee, this.voisins, this.surChoix, this.precision});
  final int annee;
  final (int?, int?)? voisins;
  final void Function(int annee)? surChoix;

  /// Une phrase propre à l'écran, ajoutée à l'explication de l'état (par exemple : « les colonnes N-1 sont calculées au même filtre »).
  final String? precision;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final exos = c.magasin.collection('exercices');
    final fiche = cpcExercice(exos.toutes, annee);
    final amorce = fiche != null;
    final etat = cpcEtatExercice(exos.toutes, annee);
    final prec = voisins != null ? voisins!.$1 : cpcExerciceVoisin(exos.actives, annee, -1);
    final suiv = voisins != null ? voisins!.$2 : cpcExerciceVoisin(exos.actives, annee, 1);
    final valideLe = DateTime.tryParse('${fiche?['valideLe'] ?? ''}')?.toLocal();
    final (String libelle, String texte, TonSigh ton, Color fond, Color bord) = !amorce
        ? (
            'non amorcé',
            'Exercice $annee non amorcé : aucune fiche d’exercice pour cette année. Les chiffres affichés sont ceux du journal, sans état d’exercice.',
            TonSigh.neutre,
            JetonsShell.slate50,
            JetonsShell.slate200
          )
        : switch (etat) {
            'clos' => (
                'clos',
                fiche['source'] == 'liasse'
                    ? 'Exercice $annee clos d’office : il est fait par la liasse déposée. Lecture seule.'
                    : 'Exercice $annee clôturé${valideLe != null ? ' le ${dateFR(valideLe)}' : ''} : lecture seule, les états sont définitifs. Une correction passe par la réouverture (circuit de clôture, motif obligatoire) ou par une écriture de l’exercice ouvert.',
                TonSigh.navy,
                JetonsShell.navy50,
                JetonsShell.navy200
              ),
            'en_cloture' => (
                'en clôture',
                'Exercice $annee en clôture : les modules n’y écrivent plus ; seules les écritures d’inventaire des rôles réglés y passent. Les états sont en cours d’arrêt.',
                TonSigh.attention,
                JetonsShell.warning50,
                JetonsShell.warning200
              ),
            _ => (
                'ouvert',
                'Exercice $annee ouvert : les écritures y entrent encore ; les états sont provisoires tant qu’il n’est pas clôturé.',
                TonSigh.succes,
                JetonsShell.success50,
                JetonsShell.success200
              ),
          };
    void choisir(int a) => surChoix != null ? surChoix!(a) : ChoixExercice.valeur.value = a;
    return Semantics(
      label: 'Exercice $annee, $libelle',
      container: true,
      child: Container(
        key: const Key('bandeau-exercice'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: fond, border: Border.all(color: bord), borderRadius: BorderRadius.circular(8)),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (prec != null)
            BoutonSigh(
                key: const Key('bandeau-exercice-precedent'),
                libelle: 'Exercice $prec',
                icone: LucideIcons.chevronLeft,
                variante: VarianteBouton.secondaire,
                taille: TailleBouton.sm,
                onPressed: () => choisir(prec)),
          // Le badge porte l'ÉTAT seul : « Exercice N · état » est le libellé du sélecteur de la barre supérieure, le répéter ferait deux fois la même ligne.
          BadgeSigh('${libelle[0].toUpperCase()}${libelle.substring(1)}', key: const Key('bandeau-exercice-etat'), ton: ton, icone: LucideIcons.calendarRange),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Text('$texte${precision == null ? '' : ' $precision'}',
                  key: const Key('bandeau-exercice-texte'), style: const TextStyle(color: JetonsShell.slate700, fontSize: 13, height: 18 / 13))),
          if (suiv != null)
            BoutonSigh(
                key: const Key('bandeau-exercice-suivant'),
                libelle: 'Exercice $suiv',
                icone: LucideIcons.chevronRight,
                variante: VarianteBouton.secondaire,
                taille: TailleBouton.sm,
                onPressed: () => choisir(suiv)),
        ]),
      ),
    );
  }
}
