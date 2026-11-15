import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../shell/logo_clinique.dart';
import 'piece.dart';

/// Génération PDF des mêmes pièces que l'aperçu — à partir des MÊMES lignes (`lignesTicket`, `TableauEtat.pied`) : l'écran et le papier
/// ne peuvent pas diverger. Polices Liberation (métriques d'Arial/Courier, licence SIL OFL) : le paquet `pdf` n'embarque pas les OTF d'Inter.
///
/// Montserrat Bold (dénomination) et Dancing Script (devise) sont chargées comme Liberation, depuis les OTF/TTF de l'application : même police à
/// l'écran et sur le PDF.
class PolicesPdf {
  PolicesPdf(this.sans, this.gras, this.italique, this.mono, this.monoGras, this.titre, this.devise);
  final pw.Font sans, gras, italique, mono, monoGras, titre, devise;

  static Future<PolicesPdf> charger() async {
    Future<pw.Font> f(String n) async =>
        pw.Font.ttf(await rootBundle.load('assets/polices/pdf/$n.ttf'));
    return PolicesPdf(
        await f('LiberationSans-Regular'),
        await f('LiberationSans-Bold'),
        await f('LiberationSans-Italic'),
        await f('LiberationMono-Regular'),
        await f('LiberationMono-Bold'),
        pw.Font.ttf(await rootBundle.load('assets/polices/Montserrat-Bold.ttf')),
        pw.Font.ttf(await rootBundle.load('assets/polices/DancingScript-Regular.ttf')));
  }
}

const _mm = PdfPageFormat.mm;

/// Rouleau 80 mm : largeur fixe, hauteur selon le contenu (les imprimantes thermiques coupent au bout).
Future<Uint8List> pdfTicket(EntreeTicket e, String reference, PolicesPdf p,
    {bool compresser = true, IdentiteImprimee? identite}) async {
  identite ??= IdentiteImprimee.semence;
  final doc = pw.Document(
      compress: compresser,
      title: 'Ticket $reference',
      author: identite.nom);
  final lignes = lignesTicket(e, identite: identite);
  pw.Widget ligne(LigneTicket l) {
    if (l.estPaire) {
      final s = pw.TextStyle(font: l.gras ? p.monoGras : p.mono, fontSize: 7);
      return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Flexible(child: pw.Text(l.gauche, style: s)),
            pw.SizedBox(width: 6),
            pw.Text(l.droite!, style: s),
          ]);
    }
    final gras = l.style == StyleLigne.titre ||
        l.style == StyleLigne.centreGras ||
        l.style == StyleLigne.lettres;
    final centre = l.style == StyleLigne.titre ||
        l.style == StyleLigne.centre ||
        l.style == StyleLigne.centreGras;
    return pw.Text(l.gauche,
        textAlign: centre ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
            font: gras ? p.monoGras : p.mono,
            fontSize: l.style == StyleLigne.titre
                ? 8.5
                : (l.style == StyleLigne.centre ? 6 : 7)));
  }

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat(80 * _mm, double.infinity, marginAll: 4 * _mm),
    build: (_) =>
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      for (final l in lignes) ligne(l),
      pw.SizedBox(height: 3),
      pw.Text('Réf. $reference',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: p.mono, fontSize: 5)),
    ]),
  ));
  return doc.save();
}

/// A4 : en-tête légal, titre, filtres, tableaux (total refait), signatures, pied normalisé répété sur chaque page.
Future<Uint8List> pdfA4(PieceA4 x, PolicesPdf p,
    {bool compresser = true}) async {
  final doc = pw.Document(
      compress: compresser,
      title: x.titre,
      author: x.identiteImprimee.nom,
      subject: x.reference);
  final i = x.identiteImprimee;
  pw.TextStyle s(double t, {pw.Font? f}) =>
      pw.TextStyle(font: f ?? p.sans, fontSize: t);
  final logo = pw.MemoryImage(
      (await rootBundle.load(LogoClinique.asset)).buffer.asUint8List());
  final e = EnteteTroisZones.depuis(i);
  PdfColor couleur(Color c) => PdfColor.fromInt(c.toARGB32());
  final coeur = couleur(JetonsShell.coeur500), sante = couleur(JetonsShell.sante600);

  // L'en-tête légal en trois zones : le MÊME modèle (EnteteTroisZones) que la feuille de l'écran et l'aperçu de cfg-branding.
  pw.Widget entete() => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.Expanded(
                  flex: (EnteteTroisZones.partGauche * 100).round(),
                  child: pw.Column(children: [
                    pw.Image(logo,
                        width: EnteteTroisZones.logoCm * 10 * _mm,
                        height: EnteteTroisZones.logoCm * 10 * _mm,
                        fit: pw.BoxFit.contain),
                    if (e.devise.isNotEmpty)
                      pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: pw.Text(e.devise,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: p.devise, fontSize: 9, color: coeur))),
                  ])),
              pw.Expanded(
                  flex: 100 - (EnteteTroisZones.partGauche * 100).round() - (EnteteTroisZones.partDroite * 100).round(),
                  child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                      child: pw.Column(children: [
                        // Le moteur PDF ignore l'espace insécable : la coupure est posée à la main, avant les guillemets.
                        pw.Text(e.denomination.replaceFirst(RegExp(r'\s+(?=«)'), '\n'),
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: p.titre, fontSize: 14.5, color: coeur)),
                        if (e.sousTitre.isNotEmpty)
                          pw.Padding(
                              padding: const pw.EdgeInsets.only(top: 2),
                              child: pw.Text(e.sousTitre,
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(font: p.gras, fontSize: 7.5, letterSpacing: 0.3, color: couleur(JetonsShell.anthracite900)))),
                      ]))),
              pw.Expanded(
                  flex: (EnteteTroisZones.partDroite * 100).round(),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    for (final l in e.lignesDroite)
                      pw.Text(l,
                          textAlign: pw.TextAlign.right,
                          style: s(6.8, f: l.startsWith('IFU') ? p.gras : null)),
                  ])),
            ])),
        pw.SizedBox(height: 3),
        pw.Container(height: EnteteTroisZones.filetPx, color: coeur),
        pw.SizedBox(height: EnteteTroisZones.interFiletPx),
        pw.Container(height: EnteteTroisZones.filetPx, color: sante),
      ]);

  pw.Widget pied(pw.Context c) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
            border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey500, width: 0.5))),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(e.piedLegal, style: s(6)),
                    pw.Text(
                        'Document généré par ${x.utilisateur} le ${dateHeure(x.edite)}',
                        style: s(6)),
                  ]),
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Réf. document : ${x.reference}',
                        style: s(6, f: p.mono)),
                    pw.Text(
                        'Page ${c.pageNumber} / ${c.pagesCount} — ${e.editeDepuis}',
                        style: s(6)),
                  ]),
            ]),
      );

  /// Règle unique des tableaux (identique à l'aperçu, `FeuilleA4._tableau`) : rangée de hauteur commune, texte aligné EN HAUT, bordures du tableau.
  pw.Widget tableau(TableauEtat t) {
    final pi = t.pied;
    return pw.TableHelper.fromTextArray(
      headers: [for (final c in t.colonnes) c.libelle],
      data: [...t.cellules, if (pi != null) pi],
      headerStyle: s(7.5, f: p.gras),
      cellStyle: s(7.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
      cellAlignments: {
        for (var i = 0; i < t.colonnes.length; i++)
          i: t.colonnes[i].droite
              ? pw.Alignment.topRight
              : pw.Alignment.topLeft
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    );
  }

  doc.addPage(pw.MultiPage(
    // Le moteur refuse par défaut un état de plus de 20 pages (PdfTooBigPageException) : un grand livre d'exploitation réelle les dépasse. 500 pages couvrent
    // largement l'usage ; au-delà, c'est une erreur de mise en page qui doit se voir, pas un état qu'on imprime.
    maxPages: 500,
    pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 12 * _mm,
        marginRight: 12 * _mm,
        marginTop: 12 * _mm,
        marginBottom: 12 * _mm),
    header: (c) => c.pageNumber == 1 ? entete() : pw.SizedBox(),
    footer: pied,
    build: (_) => [
      pw.SizedBox(height: 12),
      pw.Center(
          child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 3, left: 18, right: 18),
              decoration: pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(color: sante, width: 1.5))),
              child: pw.Text(x.titre.toUpperCase(), style: s(12, f: p.gras)))),
      if (x.sousTitre != null)
        pw.Center(child: pw.Text(x.sousTitre!, style: s(8))),
      pw.SizedBox(height: 10),
      if (x.filtres.isNotEmpty)
        pw.Container(
            padding: const pw.EdgeInsets.all(6),
            margin: const pw.EdgeInsets.only(bottom: 10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500, width: 0.5)),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('FILTRES APPLIQUÉS À CET ÉTAT',
                      style: s(7, f: p.gras)),
                  for (final f in x.filtres)
                    pw.Text('${f.$1} : ${f.$2}', style: s(7.5)),
                  pw.Text(
                      'L’état ne porte que les enregistrements retenus par ces filtres.',
                      style: s(7, f: p.italique)),
                ])),
      if (x.cartouche.isNotEmpty)
        pw.Container(
            padding: const pw.EdgeInsets.all(6),
            margin: const pw.EdgeInsets.only(bottom: 10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500, width: 0.5)),
            child: pw.Wrap(spacing: 16, runSpacing: 2, children: [
              for (final c in x.cartouche)
                pw.SizedBox(
                    width: 230,
                    child: pw.Text('${c.$1} : ${c.$2}', style: s(7.5))),
            ])),
      for (final b in x.blocs) ...[
        // Le tableau est posé DIRECTEMENT dans la liste de `MultiPage` (jamais dans une `Column` : un widget non « spanning » ne se coupe pas entre deux pages,
        // et un tableau plus haut qu'une page — grand livre, plan comptable, état de stock — faisait tourner la mise en page jusqu'à la limite de pages).
        ...switch (b) {
          BlocTableau() => [
              if (b.titre != null)
                pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: pw.Text(b.titre!.toUpperCase(), style: s(8, f: p.gras))),
              tableau(b.tableau),
            ],
          BlocTexte() => [
              pw.Text(b.texte, style: s(8, f: b.gras ? p.gras : (b.italique ? p.italique : null))),
            ],
        },
        pw.SizedBox(height: 10),
      ],
      if (x.lieuDate)
        pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(IdentiteClinique.faitA(dateLong(x.edite)),
                style: s(8, f: p.italique))),
      if (x.signatures.isNotEmpty)
        pw.Padding(
            padding: const pw.EdgeInsets.only(top: 28),
            child: pw.Row(children: [
              for (final g in x.signatures.take(4))
                pw.Expanded(
                    child: pw.Column(children: [
                  pw.Text(g.role, style: s(8, f: p.gras)),
                  if (g.nom != null) pw.Text(g.nom!, style: s(7)),
                  pw.SizedBox(height: 32),
                  pw.Container(
                      margin: const pw.EdgeInsets.symmetric(horizontal: 10),
                      height: 0.5,
                      color: PdfColors.grey600),
                  pw.Text(g.mention, style: s(6)),
                ])),
            ])),
    ],
  ));
  return doc.save();
}


/// Fiche documentaire PAYSAGE (organigramme) : A4 297 × 210 mm, une page PDF par page de la fiche, MÊMES cotes que l'aperçu (`GabaritFichePaysage`), même
/// scène, mêmes lignes de légende. Le graphe est dessiné en vectoriel : traits et cases, jamais une image.
Future<Uint8List> pdfFichePaysage(FichePaysage x, PolicesPdf p, {bool compresser = true}) async {
  const g = GabaritFichePaysage();
  final doc = pw.Document(compress: compresser, title: x.titre, author: x.identite.nom, subject: x.reference);
  final logo = pw.MemoryImage((await rootBundle.load(LogoClinique.asset)).buffer.asUint8List());
  PdfColor couleur(Color c) => PdfColor.fromInt(c.toARGB32());
  final noir = couleur(JetonsShell.anthracite900),
      bleu = couleur(JetonsShell.sante600),
      bleuFonce = couleur(JetonsShell.sante800),
      bleuClair = couleur(JetonsShell.sante100),
      rouge = couleur(JetonsShell.coeur500),
      gris = couleur(JetonsShell.slate500);
  pw.TextStyle s(double t, {pw.Font? f, PdfColor? c}) => pw.TextStyle(font: f ?? p.sans, fontSize: t, color: c ?? noir);
  final trait = pw.BorderSide(color: noir, width: 0.6);

  pw.Widget cartouche(int i) {
    final droite = x.cartouche(i);
    return pw.Container(
        width: g.cartoucheLargeur * _mm,
        height: g.cartoucheHauteur * _mm,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: noir, width: 0.6)),
        child: pw.Row(children: [
          pw.Expanded(
              flex: g.colonnes[0],
              child: pw.Container(
                  decoration: pw.BoxDecoration(border: pw.Border(right: trait)),
                  padding: const pw.EdgeInsets.all(2),
                  child: pw.Center(child: pw.Image(logo, fit: pw.BoxFit.contain)))),
          pw.Expanded(
              flex: g.colonnes[1],
              child: pw.Column(children: [
                pw.Expanded(
                    flex: g.etagesTitre[0],
                    child: pw.Container(
                        decoration: pw.BoxDecoration(border: pw.Border(bottom: trait)),
                        alignment: pw.Alignment.center,
                        child: pw.Text(x.fiche.titreHaut, style: s(11)))),
                pw.Expanded(flex: g.etagesTitre[1], child: pw.Center(child: pw.Text(x.fiche.titre, style: s(11, f: p.titre, c: bleu)))),
              ])),
          pw.Expanded(
              flex: g.colonnes[2],
              child: pw.Container(
                  decoration: pw.BoxDecoration(border: pw.Border(left: trait)),
                  child: pw.Column(children: [
                    for (var k = 0; k < droite.length; k++)
                      pw.Expanded(
                          flex: g.lignesDroite[k],
                          child: pw.Container(
                              width: double.infinity,
                              decoration: pw.BoxDecoration(border: k < droite.length - 1 ? pw.Border(bottom: trait) : null),
                              padding: const pw.EdgeInsets.only(left: 4),
                              alignment: pw.Alignment.centerLeft,
                              child: pw.Text(droite[k], style: s(8.5)))),
                  ]))),
        ]));
  }

  pw.Widget graphe(SceneOrganigramme scene) {
    final w = g.zoneLargeur * _mm, h = g.zoneHauteur * _mm;
    final a = ajusterScene(scene, w, h);
    final e = a.echelle;
    return pw.SizedBox(
        width: w,
        height: h,
        child: pw.Stack(overflow: pw.Overflow.visible, children: [
          pw.Positioned(
              left: 0,
              top: 0,
              child: pw.CustomPaint(
                  size: PdfPoint(w, h),
                  painter: (canvas, size) {
                    canvas
                      ..setStrokeColor(bleu)
                      ..setLineWidth(g.traitMm * _mm);
                    for (final t in scene.traits) {
                      canvas
                        ..moveTo(a.dx + t.x1 * e, h - (a.dy + t.y1 * e))
                        ..lineTo(a.dx + t.x2 * e, h - (a.dy + t.y2 * e))
                        ..strokePath();
                    }
                  })),
          for (final n in scene.niveaux)
            pw.Positioned(
                left: a.dx + n.x * e - 20,
                top: a.dy + n.y * e - scene.police * e * 0.7,
                child: pw.SizedBox(width: 40, child: pw.Text('${n.n}', textAlign: pw.TextAlign.center, style: s(scene.police * e * 1.1)))),
          for (final k in scene.cases)
            pw.Positioned(
                left: a.dx + k.x * e,
                top: a.dy + k.y * e,
                child: pw.Container(
                    width: k.l * e,
                    height: k.h * e,
                    decoration: pw.BoxDecoration(color: bleu, border: pw.Border.all(color: bleuFonce, width: g.bordUnites * e)),
                    padding: pw.EdgeInsets.symmetric(horizontal: g.insetX * e, vertical: g.insetY * e),
                    child: pw.Container(
                        color: bleuClair,
                        alignment: pw.Alignment.center,
                        child: k.titre.isEmpty
                            ? pw.Text(k.texte, textAlign: pw.TextAlign.center, maxLines: 3, style: s(scene.police * e))
                            : pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
                                pw.Text(k.texte, textAlign: pw.TextAlign.center, maxLines: 3, style: s(scene.police * e)),
                                pw.Text(k.titre, textAlign: pw.TextAlign.center, maxLines: 1, style: s(scene.police * e * 0.8)),
                              ])))),
        ]));
  }

  pw.Widget legende(PageLegende page) => pw.Padding(
      padding: pw.EdgeInsets.only(left: (g.legendeGauche - g.margeCote) * _mm, top: g.legendeHaut * _mm),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        for (final l in page.lignes)
          pw.SizedBox(
              height: g.legendeLigne * _mm,
              child: pw.RichText(
                  text: pw.TextSpan(style: s(g.legendeCorps), children: [
                pw.TextSpan(text: l.code, style: s(g.legendeCorps, f: p.gras)),
                pw.TextSpan(text: ' : ${l.libelle}'),
              ]))),
      ]));

  pw.Widget pied() => pw.Container(
      height: g.hauteurPied * _mm,
      alignment: pw.Alignment.bottomCenter,
      child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
        for (final l in x.pied) pw.Text(l, textAlign: pw.TextAlign.center, style: s(7.5)),
        pw.Text(x.fiche.mention, textAlign: pw.TextAlign.center, style: s(9.5, c: rouge)),
        pw.Text(x.tracabilite, textAlign: pw.TextAlign.center, style: s(5.5, c: gris)),
      ]));

  for (var i = 0; i < x.pages.length; i++) {
    final page = x.pages[i];
    doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(g.largeur * _mm, g.hauteur * _mm, marginLeft: g.margeCote * _mm, marginRight: g.margeCote * _mm, marginTop: g.margeHaut * _mm, marginBottom: g.margeBas * _mm),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Center(child: cartouche(i)),
              pw.SizedBox(height: g.ecartContenu * _mm),
              pw.Expanded(
                  child: switch (page) {
                PageGraphe() => graphe(page.scene),
                PageLegende() => legende(page),
              }),
              pied(),
            ])));
  }
  return doc.save();
}
