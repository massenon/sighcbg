/// L'EXPORT ET L'IMPRESSION DES LIGNES D'UN TABLEAU, côté poste (Q38 à Q42, Direction du 15/11/2026). Les règles sont au domaine (`export_tableau.dart`, `xlsx.dart`) ;
/// ce fichier les branche sur le composant commun [TableauSigh] : le droit (un geste réservé, lu à chaud), les réglages de la clinique (lus en base), les colonnes
/// et les lignes que l'écran montre (champs sensibles masqués comme à l'écran), le compteur de progression, l'écriture du fichier et le journal (RG-12).
///
/// Un export ne part JAMAIS vers un téléphone : il s'écrit dans un fichier local de ce poste, et le journal ne retient ni valeur ni texte de recherche.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../core/service_parametres.dart';
import '../impression/apercu.dart';
import '../impression/piece.dart';
import '../shell/contexte_ecran.dart';
import 'bouton.dart';
import 'carte.dart';
import 'champ_sensible.dart';
import 'modale.dart';
import 'tableau.dart';
import 'ton.dart';
import 'toast.dart';

/// Où et comment le poste écrit un fichier d'export : injectable (un test n'écrit pas sur le disque de la machine).
class ExportPoste {
  ExportPoste._();

  /// Écrit [octets] sous [nom] et rend le chemin. Par défaut : `$SIGH_EXPORTS`, sinon « Téléchargements » de l'utilisateur, sinon le dossier temporaire.
  static Future<String> Function(List<int> octets, String nom) enregistrer = (octets, nom) async {
    final dossier = dossierDesExports();
    await dossier.create(recursive: true);
    final f = File('${dossier.path}${Platform.pathSeparator}$nom');
    await f.writeAsBytes(octets);
    return f.path;
  };
}

/// Le dossier des exports : `$SIGH_EXPORTS`, sinon « Downloads » / « Téléchargements » de l'utilisateur, sinon le dossier temporaire du système.
Directory dossierDesExports() {
  final env = Platform.environment;
  final cible = env['SIGH_EXPORTS'];
  if (cible != null && cible.isNotEmpty) return Directory(cible);
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home != null) {
    for (final n in ['Downloads', 'Téléchargements']) {
      final d = Directory('$home${Platform.pathSeparator}$n');
      if (d.existsSync()) return d;
    }
  }
  return Directory.systemTemp;
}

/// Le profil de l'écran peut-il exporter ? Le geste réservé [gesteExporter], relu des fiches `rbac` à CHAQUE appel : une décision prise à l'instant vaut à
/// l'appel suivant. Sans décision, il suit la LECTURE de l'écran. Hors coque (un test de widget nu, [c] nul) : permis, rien ne dit de qui l'on parle.
bool peutExporterTableau(ContexteEcran? c) {
  if (c == null) return true;
  final mat = c.donnees?.matrice;
  final droits = DroitsGestes(fiches: c.magasin.collection('rbac').actives, estArchive: mat?.estArchive, ecranActif: mat?.ecranActif);
  return droits.peutSurEcran(c.role, gesteExporter, c.ecranId, peutVoirEcran: mat?.peutVoir);
}

/// Les réglages d'export EN VIGUEUR, lus de la base (défaut de la définition à défaut de fiche).
ReglagesExport reglagesExport(ContexteEcran? c) {
  if (c == null) return ReglagesExport.depuisParametres((_) => null);
  final s = serviceParametres(c.magasin, auteur: () => 'lecture', horloge: () => c.aujourdhui);
  final jour = parametreDateIso(c.aujourdhui);
  return ReglagesExport.depuisParametres((cle) => s.valeur(cle, jour));
}

/// Les colonnes qu'écrit le fichier : celles que l'écran montre, avec le TEXTE qu'il affiche. En plus de la colonne que l'écran a déjà masquée, un champ sensible
/// que le profil n'a pas le droit de lire est remplacé par la mention, jamais exporté en clair (champ_sensible.dart).
List<ColonneExport> colonnesExportDe(List<ColonneTableau> colonnes, ContexteEcran? c) {
  final acces = c == null ? null : AccesSensible.de(c);
  return [
    for (final col in colonnes)
      () {
        final cat = acces == null ? null : categorieDuChamp(col.cle);
        final refuse = cat != null && !acces!.peut(cat.code);
        return ColonneExport(
            libelle: col.libelle,
            texte: refuse ? (_) => acces.mention(cat.code) : col.enTexte,
            brut: refuse ? null : col.lire);
      }(),
  ];
}

/// Le module d'un écran pour le journal : le préfixe de son identifiant (`m6-transferts` → `M6`).
String moduleDeEcran(String ecranId) => ecranId.split('-').first.toUpperCase();

/// Inscrit un export ou une impression au journal (RG-12) : qui (le magasin porte l'agent), quel écran, combien de lignes, avec ou sans filtre. Jamais le contenu.
void journaliserSortie(ContexteEcran? c, {required String action, required String reference, required Map<String, Object?> detail, bool succes = true}) {
  if (c == null) return;
  c.magasin.journaliser(action, moduleDeEcran(c.ecranId), c.ecranId, reference, null, detail, succes: succes);
}

/// Ce qu'un tableau offre à l'export : ses compteurs par portée et la fabrique des lignes de chacune.
class SourceExport {
  const SourceExport({
    required this.nom,
    required this.titre,
    required this.colonnes,
    required this.lignes,
    required this.nbSelection,
    required this.nbFiltre,
    required this.nbTout,
    required this.filtreActif,
    this.alCsv,
  });

  /// La base du nom de fichier.
  final String nom;
  final String? titre;
  final List<ColonneTableau> Function() colonnes;
  final List<Ligne> Function(PorteeExport) lignes;
  final int nbSelection;
  final int nbFiltre;
  final int nbTout;
  final bool filtreActif;

  /// Un écran qui reçoit le CSV lui-même (écran de la poste mère) : le CSV lui est remis tel quel, le fichier est son affaire.
  final void Function(String nom, String csv)? alCsv;

  int compte(PorteeExport p) => switch (p) { PorteeExport.selection => nbSelection, PorteeExport.toutAvecFiltre => nbFiltre, PorteeExport.toutSansFiltre => nbTout };
}

const TextStyle _styleCorps = TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14);
const TextStyle _styleDiscret = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12);

/// La fenêtre « Exporter les données » : la portée (la sélection, tout avec le filtre, tout sans le filtre), puis le format. Un volume au-delà de la limite de la
/// clinique est REFUSÉ en le disant, les boutons restent éteints. [porteeInitiale] : la portée proposée (la sélection quand elle existe).
Future<void> ouvrirExport(BuildContext context, SourceExport s, {PorteeExport? porteeInitiale}) {
  final c = ContexteEcran.capturer(context);
  if (!peutExporterTableau(c)) {
    ToastsSigh.afficher(context, 'Export refusé : votre profil n’a pas le droit d’exporter ce tableau.',
        type: TypeToast.erreur, detail: 'Le droit d’exporter se règle par rôle (Rôles et permissions › Gestes réservés).');
    journaliserSortie(c, action: actionJournalExport, reference: s.nom, succes: false, detail: detailJournalExport(portee: PorteeExport.toutAvecFiltre, lignes: 0, filtreActif: false, colonnes: 0, refus: const RefusExport('EXPORT_RESERVE', 'droit retiré', '')));
    return Future.value();
  }
  final reglages = reglagesExport(c);
  var portee = porteeInitiale ?? (s.nbSelection > 0 ? PorteeExport.selection : PorteeExport.toutAvecFiltre);
  if (portee == PorteeExport.selection && s.nbSelection == 0) portee = PorteeExport.toutAvecFiltre;
  FormatExport? choisi;
  return afficherModale<void>(context,
      titre: 'Exporter les données',
      taille: TailleModale.sm,
      corps: StatefulBuilder(builder: (ctx, maj) {
        final options = [
          if (s.nbSelection > 0) PorteeExport.selection,
          PorteeExport.toutAvecFiltre,
          if (s.filtreActif) PorteeExport.toutSansFiltre,
        ];
        final n = s.compte(portee);
        final refus = reglages.verifier(n);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Que faut-il exporter ?', style: _styleCorps),
          const SizedBox(height: 8),
          for (final p in options)
            _OptionPortee(
                key: Key('export:portee:${p.code}'),
                libelle: switch (p) {
                  PorteeExport.selection => 'La sélection',
                  PorteeExport.toutAvecFiltre => s.filtreActif ? 'Tout exporter, filtre et recherche en force' : 'Tout exporter, toutes les pages',
                  PorteeExport.toutSansFiltre => 'Tout exporter, sans le filtre ni la recherche',
                },
                compte: s.compte(p),
                choisie: p == portee,
                alChoisir: () => maj(() => portee = p)),
          const SizedBox(height: 8),
          Text('Le fichier reprend les colonnes affichées du tableau (menu « Colonnes »), avec les valeurs telles que l’écran les montre.', style: _styleDiscret),
          if (refus != null) ...[
            const SizedBox(height: 8),
            NoteSigh('${refus.motif}. ${refus.geste}', key: const Key('export:refus'), ton: TonSigh.danger, icone: LucideIcons.triangleAlert),
          ],
        ]);
      }),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.fantome, onPressed: fermer),
            for (final f in FormatExport.values.reversed)
              StatefulBuilder(
                  builder: (ctx, maj) => BoutonSigh(
                      key: Key('export:format:${f.extension}'),
                      libelle: f == FormatExport.csv ? 'CSV' : f.libelle,
                      icone: f == FormatExport.csv ? LucideIcons.fileText : LucideIcons.fileSpreadsheet,
                      variante: f == FormatExport.xlsx ? VarianteBouton.primaire : VarianteBouton.secondaire,
                      onPressed: reglages.verifier(s.compte(portee)) != null
                          ? null
                          : () {
                              choisi = f;
                              fermer();
                            }))
          ]).then((_) async {
    final f = choisi;
    if (f == null || !context.mounted) return;
    await executerExport(context, s, portee, f);
  });
}

class _OptionPortee extends StatelessWidget {
  const _OptionPortee({super.key, required this.libelle, required this.compte, required this.choisie, required this.alChoisir});
  final String libelle;
  final int compte;
  final bool choisie;
  final VoidCallback alChoisir;

  @override
  Widget build(BuildContext context) => Semantics(
        inMutuallyExclusiveGroup: true,
        checked: choisie,
        label: '$libelle, $compte ligne${compte > 1 ? 's' : ''}',
        excludeSemantics: true,
        onTap: alChoisir,
        child: InkWell(
          onTap: alChoisir,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(choisie ? LucideIcons.circleDot : LucideIcons.circle, size: 16, color: choisie ? JetonsShell.navy900 : JetonsShell.slate400),
                const SizedBox(width: 8),
                Expanded(child: Text(libelle, style: _styleCorps)),
                Text('$compte ligne${compte > 1 ? 's' : ''}', style: _styleDiscret),
              ])),
        ),
      );
}

/// Produit et écrit le fichier. Le droit est relu, la limite revérifiée (refus nommé), le compteur s'affiche au-delà du seuil réglé (avec un bouton Annuler), le
/// journal reçoit le geste ou son refus.
Future<void> executerExport(BuildContext context, SourceExport s, PorteeExport portee, FormatExport format) async {
  final c = ContexteEcran.capturer(context);
  final cols = s.colonnes();
  final detailRefus = (RefusExport r, int n) => detailJournalExport(portee: portee, lignes: n, filtreActif: portee == PorteeExport.toutAvecFiltre && s.filtreActif, colonnes: cols.length, format: format, refus: r);
  if (!peutExporterTableau(c)) {
    const r = RefusExport('EXPORT_RESERVE', 'le droit d\'exporter a été retiré à ce profil', 'Demander à l\'administrateur (Rôles et permissions › Gestes réservés).');
    ToastsSigh.afficher(context, 'Export refusé : ${r.motif}.', type: TypeToast.erreur, detail: r.geste);
    journaliserSortie(c, action: actionJournalExport, reference: s.nom, succes: false, detail: detailRefus(r, 0));
    return;
  }
  final reglages = reglagesExport(c);
  final lignes = s.lignes(portee);
  final refus = reglages.verifier(lignes.length);
  if (refus != null) {
    ToastsSigh.afficher(context, 'Export refusé : ${refus.motif}.', type: TypeToast.erreur, detail: refus.geste);
    journaliserSortie(c, action: actionJournalExport, reference: s.nom, succes: false, detail: detailRefus(refus, lignes.length));
    return;
  }
  final maintenant = c?.aujourdhui ?? DateTime.now();
  final nom = nomFichierExport(s.nom, maintenant, format, selection: portee == PorteeExport.selection);
  final parLots = lignes.length > reglages.seuilProgression;
  final avancement = ValueNotifier<int>(0);
  var annule = false;
  var fermee = false;
  if (parLots) {
    afficherModale<void>(context,
        titre: 'Export en cours',
        taille: TailleModale.sm,
        fermetureParFond: false,
        corps: ValueListenableBuilder<int>(
            valueListenable: avancement,
            builder: (_, fait, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Préparation du fichier : ${nombre(fait)} / ${nombre(lignes.length)} lignes', key: const Key('export:progression'), style: _styleCorps),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: lignes.isEmpty ? null : fait / lignes.length, color: JetonsShell.navy900, backgroundColor: JetonsShell.slate200),
                ])),
        pied: (_) => [BoutonSigh(libelle: 'Annuler l’export', variante: VarianteBouton.secondaire, onPressed: () => annule = true)]).then((_) {
      fermee = true;
      annule = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  ResultatExport r;
  try {
    r = await produireExport(
        colonnes: colonnesExportDe(cols, c),
        lignes: lignes,
        format: format,
        feuille: s.titre ?? s.nom,
        maintenant: maintenant,
        reglages: reglages,
        progression: (f, t) => avancement.value = f,
        annule: () => annule);
  } finally {
    if (parLots && !fermee && context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (!context.mounted) return;
  if (r.annule) {
    ToastsSigh.afficher(context, 'Export annulé : aucun fichier n’a été écrit.', type: TypeToast.info);
    return;
  }
  if (r.refus != null) {
    ToastsSigh.afficher(context, 'Export refusé : ${r.refus!.motif}.', type: TypeToast.erreur, detail: r.refus!.geste);
    journaliserSortie(c, action: actionJournalExport, reference: s.nom, succes: false, detail: detailRefus(r.refus!, lignes.length));
    return;
  }
  try {
    final String chemin;
    if (format == FormatExport.csv && s.alCsv != null) {
      s.alCsv!(nom, r.texte ?? '');
      chemin = nom;
    } else {
      chemin = await ExportPoste.enregistrer(r.octets!, nom);
    }
    journaliserSortie(c,
        action: actionJournalExport,
        reference: nom,
        detail: detailJournalExport(portee: portee, lignes: r.lignes, filtreActif: portee == PorteeExport.toutAvecFiltre && s.filtreActif, colonnes: cols.length, format: format));
    if (context.mounted && !(format == FormatExport.csv && s.alCsv != null)) {
      ToastsSigh.afficher(context, 'Export enregistré : ${nombre(r.lignes)} ligne${r.lignes > 1 ? 's' : ''}.', type: TypeToast.succes, detail: chemin);
    }
  } catch (e) {
    if (context.mounted) ToastsSigh.afficher(context, 'Export impossible : $e', type: TypeToast.erreur);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// L'impression des lignes cochées (Q42, (c)).
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce qu'un tableau offre à l'impression de sa sélection.
class SourceImpression {
  const SourceImpression({required this.titre, required this.colonnes, required this.lignes, required this.filtres, this.documentLigne});
  final String titre;
  final List<ColonneTableau> Function() colonnes;
  final List<Ligne> lignes;

  /// Les filtres EN FORCE, (libellé, valeur) : une impression de lignes cochées dit ce qui l'a bornée.
  final List<(String, String)> filtres;

  /// Le document unitaire de la ligne (un bon, une fiche, un reçu), là où il existe déjà : permet « un état par ligne ».
  final PieceA4 Function(BuildContext, Ligne)? documentLigne;
}

/// La pièce A4 d'un SEUL tableau des lignes cochées, au gabarit d'impression commun (en-tête légal unique, pied normalisé).
PieceA4 pieceTableauSelection(ContexteEcran? c, SourceImpression s) {
  final cols = colonnesExportDe(s.colonnes(), c);
  final maintenant = c?.aujourdhui ?? DateTime.now();
  return PieceA4(
    titre: s.titre,
    sousTitre: '${nombre(s.lignes.length)} ligne${s.lignes.length > 1 ? 's' : ''} cochée${s.lignes.length > 1 ? 's' : ''}',
    reference: PieceA4.reference_(maintenant, ImpressionPoste.prochainNumero()),
    utilisateur: c == null ? 'Utilisateur' : (c.agent.nom.isEmpty ? 'Utilisateur' : c.agent.nom),
    edite: maintenant,
    filtres: [('Lignes', 'sélection cochée'), ...s.filtres],
    blocs: [
      BlocTableau(TableauEtat(
          colonnes: [
            for (final col in cols) ColonneEtat(libelle: col.libelle, valeur: (r) => col.texte(r)),
          ],
          lignes: s.lignes)),
    ],
  );
}

/// Imprime la sélection : un seul tableau par défaut ; un état par ligne là où un document unitaire existe et que l'agent le choisit. Le droit d'exporter vaut pour
/// l'impression (même sortie des mêmes données) ; la limite des états par impression est réglée par la clinique et REFUSE en le disant.
Future<void> ouvrirImpressionSelection(BuildContext context, SourceImpression s) async {
  final c = ContexteEcran.capturer(context);
  if (!peutExporterTableau(c)) {
    ToastsSigh.afficher(context, 'Impression refusée : votre profil n’a pas le droit d’exporter ce tableau.', type: TypeToast.erreur, detail: 'Le droit se règle par rôle (Rôles et permissions › Gestes réservés).');
    journaliserSortie(c, action: actionJournalImpression, reference: s.titre, succes: false, detail: detailJournalExport(portee: PorteeExport.selection, lignes: 0, filtreActif: false, colonnes: 0, mode: 'tableau', refus: const RefusExport('EXPORT_RESERVE', 'droit retiré', '')));
    return;
  }
  var unEtatParLigne = false;
  if (s.documentLigne != null) {
    final choix = await _choisirModeImpression(context, s.lignes.length, reglagesExport(c));
    if (choix == null) return;
    unEtatParLigne = choix;
  }
  if (!context.mounted) return;
  final cols = s.colonnes();
  if (unEtatParLigne) {
    final refus = reglagesExport(c).verifierEtats(s.lignes.length);
    if (refus != null) {
      ToastsSigh.afficher(context, 'Impression refusée : ${refus.motif}.', type: TypeToast.erreur, detail: refus.geste);
      journaliserSortie(c,
          action: actionJournalImpression,
          reference: s.titre,
          succes: false,
          detail: detailJournalExport(portee: PorteeExport.selection, lignes: s.lignes.length, filtreActif: false, colonnes: cols.length, mode: 'etat_par_ligne', refus: refus));
      return;
    }
    final pieces = [for (final l in s.lignes) s.documentLigne!(context, l)];
    journaliserSortie(c,
        action: actionJournalImpression,
        reference: s.titre,
        detail: detailJournalExport(portee: PorteeExport.selection, lignes: s.lignes.length, filtreActif: false, colonnes: cols.length, mode: 'etat_par_ligne'));
    await afficherApercuLot(context, pieces);
    return;
  }
  journaliserSortie(c,
      action: actionJournalImpression,
      reference: s.titre,
      detail: detailJournalExport(portee: PorteeExport.selection, lignes: s.lignes.length, filtreActif: false, colonnes: cols.length, mode: 'tableau'));
  await afficherApercu(context, pieceTableauSelection(c, s));
}

Future<bool?> _choisirModeImpression(BuildContext context, int n, ReglagesExport reglages) {
  bool? choix;
  return afficherModale<void>(context,
      titre: 'Imprimer la sélection',
      taille: TailleModale.sm,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('$n ligne${n > 1 ? 's' : ''} cochée${n > 1 ? 's' : ''}. Un seul tableau les réunit au gabarit d’impression ; pour ce tableau, chaque ligne a aussi son document : un état par ligne.', style: _styleCorps),
        if (reglages.verifierEtats(n) != null) ...[
          const SizedBox(height: 8),
          NoteSigh('Un état par ligne est limité à ${reglages.limiteEtatsParLigne} états par impression : ici ${reglages.verifierEtats(n)!.motif}.', ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
        ],
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.fantome, onPressed: fermer),
            BoutonSigh(
                key: const Key('impression:etats'),
                libelle: 'Un état par ligne',
                icone: LucideIcons.files,
                variante: VarianteBouton.secondaire,
                onPressed: () {
                  choix = true;
                  fermer();
                }),
            BoutonSigh(
                key: const Key('impression:tableau'),
                libelle: 'Un seul tableau',
                icone: LucideIcons.table,
                onPressed: () {
                  choix = false;
                  fermer();
                }),
          ]).then((_) => choix);
}
