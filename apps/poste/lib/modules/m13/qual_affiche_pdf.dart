import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../impression/pdf.dart' show PolicesPdf;

/// L'AFFICHE D'UN LIEN DE SATISFACTION EN LIGNE (décision du 16/11/2026) : une feuille A4 à poser en salle d'attente ou à remettre à la sortie, avec le
/// code QR de l'adresse publiée sur le relais. Le QR ne porte QUE l'adresse (le jeton), jamais un nom ni un numéro de dossier ; il naît de l'encodeur
/// local (aucune requête réseau), en vectoriel. Pied normalisé : référence, utilisateur, date d'édition.
const double _mm = PdfPageFormat.mm;

pw.Widget _qr(String charge, double cote) {
  final image = QrImage(QrCode.fromData(data: charge, errorCorrectLevel: QrErrorCorrectLevel.M));
  const marge = 3;
  return pw.SizedBox(
      width: cote,
      height: cote,
      child: pw.CustomPaint(painter: (canvas, taille) {
        final total = image.moduleCount + 2 * marge;
        final u = taille.x / total;
        canvas
          ..setFillColor(PdfColors.white)
          ..drawRect(0, 0, taille.x, taille.y)
          ..fillPath()
          ..setFillColor(PdfColors.black);
        for (var r = 0; r < image.moduleCount; r++) {
          for (var c = 0; c < image.moduleCount; c++) {
            if (image.isDark(r, c)) canvas.drawRect((c + marge) * u, taille.y - (r + marge + 1) * u, u + 0.1, u + 0.1);
          }
        }
        canvas.fillPath();
      }));
}

Future<pw.MemoryImage?> _logo() async {
  try {
    return pw.MemoryImage((await rootBundle.load('assets/img/logo.jpeg')).buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// Le PDF de l'affiche. [lien] : l'adresse publiée par la mère (`lienPublic` de la fiche du lien).
Future<Uint8List> pdfAfficheSatisfaction(
    {required String titre,
    required String lien,
    required String expireLe,
    required String reference,
    required String utilisateur,
    required DateTime edite,
    required PolicesPdf polices,
    bool compresser = true}) async {
  final doc = pw.Document(compress: compresser, title: 'Questionnaire de satisfaction', author: IdentiteClinique.nom, subject: reference);
  final logo = await _logo();
  final navy = PdfColor.fromInt(0xFF12315E);
  final doux = PdfColor.fromInt(0xFF475569);
  pw.TextStyle s(double t, {pw.Font? f, PdfColor? c}) => pw.TextStyle(font: f ?? polices.sans, fontSize: t, color: c ?? PdfColors.black);
  final fin = DateTime.tryParse(expireLe);
  doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18 * _mm),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            if (logo != null) pw.Image(logo, width: 22 * _mm, height: 22 * _mm),
            pw.SizedBox(height: 4 * _mm),
            pw.Text(IdentiteClinique.nomCourt, style: s(16, f: polices.gras, c: navy)),
            pw.Text(IdentiteClinique.slogan, style: s(10, f: polices.italique, c: doux)),
            pw.SizedBox(height: 12 * _mm),
            pw.Text('Votre avis nous aide à mieux vous accueillir', style: s(20, f: polices.gras, c: navy), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 3 * _mm),
            pw.Text(titre, style: s(13, c: doux), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 10 * _mm),
            _qr(lien, 90 * _mm),
            pw.SizedBox(height: 6 * _mm),
            pw.Text('Scannez ce code avec votre téléphone, ou saisissez l’adresse :', style: s(11, c: doux)),
            pw.SizedBox(height: 2 * _mm),
            pw.Text(lien, style: s(10, f: polices.mono)),
            pw.SizedBox(height: 10 * _mm),
            pw.Container(
                padding: const pw.EdgeInsets.all(4 * _mm),
                decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5FB), borderRadius: pw.BorderRadius.circular(3 * _mm)),
                child: pw.Text(
                    'Questionnaire ANONYME : on ne vous demande ni votre nom, ni votre numéro de dossier, et aucune question ne porte sur votre santé. '
                    'Votre réponse est chiffrée sur votre téléphone avant de partir : seule la clinique peut la lire.',
                    style: s(10, c: navy),
                    textAlign: pw.TextAlign.center)),
            if (fin != null) ...[
              pw.SizedBox(height: 4 * _mm),
              pw.Text('Questionnaire ouvert jusqu’au ${dateFR(fin)}.', style: s(10, c: doux)),
            ],
            pw.Spacer(),
            pw.Divider(color: PdfColor.fromInt(0xFFE2E8F0)),
            pw.Text('Réf. $reference · édité par $utilisateur le ${dateFR(edite)}', style: s(7, c: doux)),
          ])));
  return doc.save();
}
