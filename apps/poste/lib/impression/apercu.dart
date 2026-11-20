import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/mecef_poste.dart';
import '../kit/kit.dart';
import '../shell/contexte_ecran.dart';
import 'feuilles.dart';
import 'identite_poste.dart';
import 'pdf.dart';
import 'piece.dart';

/// Écriture du PDF : injectable (le poste y branchera l'imprimante / le dossier d'archivage ; les tests, un faux). Par défaut : le dossier
/// temporaire du système — l'impression physique n'est PAS branchée ici et l'écran le dit en annonçant le chemin.
class ImpressionPoste {
  ImpressionPoste._();
  static Future<String> Function(List<int> pdf, String nom) enregistrer =
      (pdf, nom) async {
    final f = File('${Directory.systemTemp.path}/$nom.pdf');
    await f.writeAsBytes(pdf);
    return f.path;
  };

  /// Écriture d'un fichier TEXTE (archive de clôture : CSV, états, manifeste) sous son nom : injectable. Par défaut : le dossier temporaire du système.
  static Future<String> Function(String contenu, String nom) enregistrerTexte = (contenu, nom) async {
    final f = File('${Directory.systemTemp.path}/$nom');
    await f.writeAsString(contenu);
    return f.path;
  };

  /// Exécuteur de commande (injectable : les tests n'envoient rien à une imprimante).
  static Future<ProcessResult> Function(String exe, List<String> args) lancer =
      (exe, args) => Process.run(exe, args);

  /// Système d'exploitation (injectable pour tester la commande de chaque plateforme).
  static String systeme = Platform.operatingSystem;

  /// Commande d'impression d'un PDF vers l'imprimante PAR DÉFAUT du système : `lp` (Linux, macOS, CUPS) ou le verbe « Print » du shell (Windows).
  /// Le résultat est RENDU, jamais avalé : pas d'imprimante par défaut, pas de pilote → un refus nommé que l'écran affiche.
  static (String, List<String>) commande(String chemin) => switch (systeme) {
        'windows' => (
            'powershell',
            [
              '-NoProfile',
              '-Command',
              'Start-Process -FilePath "${chemin.replaceAll('"', '')}" -Verb Print'
            ]
          ),
        _ => ('lp', [chemin]),
      };

  /// Imprime sur l'imprimante par défaut. `null` = lancée ; sinon le motif du refus. NON testé ici sur matériel réel.
  static Future<String?> imprimer(String chemin) async {
    final (exe, args) = commande(chemin);
    try {
      final r = await lancer(exe, args);
      if (r.exitCode == 0) return null;
      final detail = '${r.stderr}'.trim();
      return 'Impression refusée par le système (code ${r.exitCode})${detail.isEmpty ? '' : ' : $detail'}. Vérifier qu’une imprimante par défaut est installée.';
    } on ProcessException catch (e) {
      return 'Aucune commande d’impression disponible (${e.executable}). Enregistrer le PDF puis l’imprimer depuis un lecteur de PDF.';
    }
  }

  static int _compteur = 0;
  static int prochainNumero() => ++_compteur;
}

/// Aperçu commun (`afficher()` de print.js) : la feuille dans une modale large, « Fermer » et « Imprimer / PDF ».
Future<void> afficherApercu(BuildContext context, PieceA4 piece0) {
  // « Archiver » (`afficher(…, archivable)` de print.js) : l'édition est journalisée (RG-12, module RAP) — c'est ce journal que lit l'historique des éditions.
  final magasin = ContexteEcran.maybeOf(context)?.magasin;
  // L'EN-TÊTE LÉGAL EST CELUI DE LA DATE DE LA PIÈCE (`P.etat({date})`) : une pièce qui ne fixe pas son identité (état du jour) reçoit la version en force à la
  // date d'édition, lue au magasin ; une facture, un avoir, un reçu l'ont fixée à leur date.
  final identifiee = piece0.identite != null || magasin == null ? piece0 : piece0.avecIdentite(identiteImprimeeDe(magasin, piece0.edite));
  // LES SIGNATAIRES SE LISENT AU PERSONNEL (le nom, par qualité) ET À L'ORGANIGRAMME (l'intitulé du poste), jamais dans le code : sans titulaire, la ligne de signature reste sans nom.
  final piece = magasin == null ? identifiee : identifiee.avecSignatures(magasin.collection('personnel').actives, postes: magasin.collection('postes').actives);
  return afficherModale<void>(
      context,
      titre: piece.titre,
      sousTitre: piece.reference,
      taille: TailleModale.xl,
      corps: Container(
        color: const Color(0xFFE2E8F0),
        padding: const EdgeInsets.all(16),
        // `Center` dans un défilement horizontal ne centre rien (largeur non bornée) : on impose la largeur disponible comme minimum.
        child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: c.maxWidth),
                    child: Center(child: FeuilleA4(piece: piece))))),
      ),
      pied: (fermer) => [
        BoutonSigh(
            libelle: 'Fermer',
            variante: VarianteBouton.secondaire,
            onPressed: fermer),
        BoutonSigh(
            libelle: 'Enregistrer en PDF',
            icone: LucideIcons.fileDown,
            variante: VarianteBouton.secondaire,
            onPressed: () async {
              final p = await PolicesPdf.charger();
              final octets = await pdfA4(piece, p);
              final chemin =
                  await ImpressionPoste.enregistrer(octets, piece.reference);
              if (context.mounted)
                ToastsSigh.afficher(context, 'PDF enregistré.',
                    type: TypeToast.succes, detail: chemin);
            }),
        if (magasin != null)
          BoutonSigh(
              libelle: 'Archiver',
              icone: LucideIcons.archive,
              variante: VarianteBouton.secondaire,
              onPressed: () {
                magasin.journaliser('Impression', 'RAP', 'Document', piece.reference, null, {'titre': piece.titre});
                ToastsSigh.afficher(context, 'Édition archivée au journal des éditions (RG-12).', type: TypeToast.succes, detail: 'Réf. ${piece.reference}');
              }),
      ],
    );
}

/// Aperçu du ROULEAU de caisse 80 mm (`P.ticket`) : gabarit distinct du A4, même modale, même enregistrement PDF. La largeur est celle du papier de
/// l'IMPRIMANTE DE CAISSE réglée par la clinique (Direction de Baguidi, 16/11/2026, E3762) ; l'imprimante (modèle, interface, « à renseigner » tant que la
/// clinique ne les a pas réglés) est dite sous la feuille. Aucun pilote n'est branché : l'aperçu et le PDF sont les seules sorties.
Future<void> afficherApercuTicket(
        BuildContext context, EntreeTicket entree, String reference) {
  final magasin = ContexteEcran.maybeOf(context)?.magasin;
  final identite = magasin == null ? IdentiteImprimee.semence : identiteImprimeeDe(magasin, entree.date);
  final imprimante = magasin == null ? imprimanteCaisseEnVigueur(largeur: imprimanteLargeurDefautMm) : imprimanteCaisseDuPoste(magasin, entree.date);
  return afficherModale<void>(
      context,
      titre: 'Ticket de caisse',
      sousTitre: reference,
      taille: TailleModale.sm,
      corps: Container(
        color: const Color(0xFFE2E8F0),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: c.maxWidth),
                      child: Center(
                          child: FeuilleTicket(entree: entree, reference: reference, identite: identite, largeurMm: imprimante.largeurMm))))),
          const SizedBox(height: 8),
          Text(imprimante.resume,
              key: const Key('impression:ticket-imprimante'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: JetonsShell.slate700, fontSize: 12)),
        ]),
      ),
      pied: (fermer) => [
        BoutonSigh(
            libelle: 'Fermer',
            variante: VarianteBouton.secondaire,
            onPressed: fermer),
        BoutonSigh(
            libelle: 'Enregistrer en PDF',
            icone: LucideIcons.fileDown,
            variante: VarianteBouton.secondaire,
            onPressed: () async {
              final p = await PolicesPdf.charger();
              final octets = await pdfTicket(entree, reference, p, identite: identite, largeurMm: imprimante.largeurMm);
              final chemin =
                  await ImpressionPoste.enregistrer(octets, reference);
              if (context.mounted) {
                ToastsSigh.afficher(context, 'PDF enregistré.',
                    type: TypeToast.succes, detail: chemin);
              }
            }),
      ],
    );
}


/// Aperçu d'une FICHE DOCUMENTAIRE PAYSAGE (organigramme) : les pages à 297 × 210 mm dans une modale, « Fermer » et « Enregistrer en PDF » — le PDF est le
/// rendu des MÊMES pages. L'édition est journalisée (RG-12) comme celle d'une pièce A4.
Future<void> afficherApercuFiche(BuildContext context, FichePaysage fiche) {
  final magasin = ContexteEcran.maybeOf(context)?.magasin;
  return afficherModale<void>(
    context,
    titre: fiche.titre,
    sousTitre: fiche.reference,
    taille: TailleModale.xl,
    corps: Container(
      color: const Color(0xFFE2E8F0),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: Center(child: FeuilleFichePaysage(fiche: fiche))))),
    ),
    pied: (fermer) => [
      BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer),
      BoutonSigh(
          libelle: 'Enregistrer en PDF',
          icone: LucideIcons.fileDown,
          variante: VarianteBouton.secondaire,
          onPressed: () async {
            final p = await PolicesPdf.charger();
            final octets = await pdfFichePaysage(fiche, p);
            final chemin = await ImpressionPoste.enregistrer(octets, fiche.reference);
            magasin?.journaliser('Impression', 'RAP', 'Document', fiche.reference, null, {'titre': fiche.titre, 'pages': fiche.pages.length});
            if (context.mounted) ToastsSigh.afficher(context, 'PDF enregistré.', type: TypeToast.succes, detail: chemin);
          }),
    ],
  );
}

/// Aperçu d'un LOT de pièces (« un état par ligne » d'une impression de sélection) : une feuille à la fois, « Précédent » / « Suivant », et l'enregistrement de TOUS les PDF
/// d'un geste (un fichier par état). Même résolution de l'identité légale et des signataires qu'[afficherApercu].
Future<void> afficherApercuLot(BuildContext context, List<PieceA4> pieces0) {
  final magasin = ContexteEcran.maybeOf(context)?.magasin;
  final pieces = [
    for (final p0 in pieces0)
      () {
        final identifiee = p0.identite != null || magasin == null ? p0 : p0.avecIdentite(identiteImprimeeDe(magasin, p0.edite));
        return magasin == null ? identifiee : identifiee.avecSignatures(magasin.collection('personnel').actives, postes: magasin.collection('postes').actives);
      }(),
  ];
  var i = 0;
  return afficherModale<void>(
    context,
    titre: 'Impression de la sélection',
    sousTitre: '${pieces.length} état${pieces.length > 1 ? 's' : ''}',
    taille: TailleModale.xl,
    corps: StatefulBuilder(
        builder: (ctx, maj) => Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  key: const Key('impression:lot:position'),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: JetonsShell.slate50,
                  child: Row(children: [
                    BoutonSigh(
                        key: const Key('impression:lot:precedent'),
                        libelle: 'Précédent',
                        icone: LucideIcons.chevronLeft,
                        taille: TailleBouton.sm,
                        variante: VarianteBouton.secondaire,
                        onPressed: i == 0 ? null : () => maj(() => i--)),
                    const SizedBox(width: 8),
                    BoutonSigh(
                        key: const Key('impression:lot:suivant'),
                        libelle: 'Suivant',
                        icone: LucideIcons.chevronRight,
                        taille: TailleBouton.sm,
                        variante: VarianteBouton.secondaire,
                        onPressed: i >= pieces.length - 1 ? null : () => maj(() => i++)),
                    const SizedBox(width: 12),
                    Text('État ${i + 1} sur ${pieces.length} — ${pieces[i].reference}',
                        style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12)),
                  ])),
              Container(
                color: JetonsShell.slate200,
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: Center(child: FeuilleA4(piece: pieces[i]))))),
              ),
            ])),
    pied: (fermer) => [
      BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer),
      BoutonSigh(
          key: const Key('impression:lot:pdf'),
          libelle: 'Enregistrer les ${pieces.length} PDF',
          icone: LucideIcons.fileDown,
          variante: VarianteBouton.secondaire,
          onPressed: () async {
            final p = await PolicesPdf.charger();
            var dernier = '';
            for (final piece in pieces) {
              dernier = await ImpressionPoste.enregistrer(await pdfA4(piece, p), piece.reference);
            }
            if (context.mounted) {
              ToastsSigh.afficher(context, '${pieces.length} PDF enregistrés.', type: TypeToast.succes, detail: dernier);
            }
          }),
    ],
  );
}
