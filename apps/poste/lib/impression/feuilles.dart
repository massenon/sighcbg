import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../shell/logo_clinique.dart';
import 'entete_papier.dart';
import 'piece.dart';

/// 1 mm = 96/25,4 px logiques : le gabarit imprimé garde ses dimensions physiques à l'aperçu (A4 = 210 × 297 mm, rouleau = 80 mm).
const double pxParMm = 96 / 25.4;
double mm(double v) => v * pxParMm;

const _mono = 'LiberationMono';

/// Rouleau de caisse 80 mm (`P.ticket`) : largeur 80 mm, marge 4 mm, police chasse fixe, tailles 7–11 px de la maquette.
class FeuilleTicket extends StatelessWidget {
  const FeuilleTicket(
      {super.key, required this.entree, required this.reference, this.identite});
  final EntreeTicket entree;
  final String reference;

  /// L'identité en force à la date du ticket (`P.ticket({date})`).
  final IdentiteImprimee? identite;

  @override
  Widget build(BuildContext context) {
    final lignes = lignesTicket(entree, identite: identite ?? IdentiteImprimee.semence);
    return Container(
      key: const Key('impression:ticket'),
      width: mm(80),
      padding: EdgeInsets.all(mm(4)),
      color: Colors.white,
      child: DefaultTextStyle(
        style: const TextStyle(
            fontFamily: _mono,
            fontSize: 9,
            height: 1.375,
            color: JetonsShell.slate900),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final l in lignes) _ligne(l),
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Réf. $reference',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 7, color: JetonsShell.slate400))),
        ]),
      ),
    );
  }

  Widget _ligne(LigneTicket l) {
    if (l.estPaire) {
      final s =
          TextStyle(fontWeight: l.gras ? FontWeight.w700 : FontWeight.w400);
      return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: Text(l.gauche, style: s)),
            const SizedBox(width: 8),
            Text(l.droite!, textAlign: TextAlign.right, style: s),
          ]);
    }
    return switch (l.style) {
      StyleLigne.titre => Text(l.gauche,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, height: 1.25)),
      StyleLigne.centre => Text(l.gauche,
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 8)),
      StyleLigne.centreGras => Text(l.gauche,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      StyleLigne.lettres => Text(l.gauche,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600)),
      StyleLigne.separateur => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(l.gauche,
              style: const TextStyle(height: 1, color: JetonsShell.slate400))),
      _ => Text(l.gauche),
    };
  }
}

/// Feuille A4 (`P.etat`) : 210 × 297 mm, marge 12 mm. En-tête légal en trois zones (`EnteteLegal`, P0-13) puis double filet rouge cœur / bleu santé.
class FeuilleA4 extends StatelessWidget {
  const FeuilleA4({super.key, required this.piece});
  final PieceA4 piece;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('impression:a4'),
        width: mm(210),
        constraints: BoxConstraints(minHeight: mm(297)),
        padding: EdgeInsets.all(mm(12)),
        color: Colors.white,
        child: DefaultTextStyle.merge(
          style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              height: 1.625,
              color: JetonsShell.slate900),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _entete(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Container(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: JetonsShell.navy900, width: 2))),
                    child: Text(piece.titre.toUpperCase(),
                        key: const Key('impression:titre'),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: JetonsShell.navy950,
                            height: 1.5))),
                if (piece.sousTitre != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(piece.sousTitre!,
                          style: const TextStyle(color: JetonsShell.slate600))),
              ]),
            ),
            if (piece.filtres.isNotEmpty) _filtres(),
            if (piece.cartouche.isNotEmpty) _cartouche(),
            for (final b in piece.blocs)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12), child: _bloc(b)),
            if (piece.lieuDate)
              Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(IdentiteClinique.faitA(dateLong(piece.edite)),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          color: JetonsShell.slate700))),
            if (piece.signatures.isNotEmpty) _signatures(),
            _pied(),
          ]),
        ),
      );

  Widget _entete() => EnteteLegal(identite: piece.identiteImprimee);

  Widget _filtres() => Container(
        key: const Key('impression:filtres'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            border: Border.all(color: JetonsShell.slate300),
            borderRadius: BorderRadius.circular(4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('FILTRES APPLIQUÉS À CET ÉTAT',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: JetonsShell.slate600)),
          Wrap(spacing: 16, runSpacing: 4, children: [
            for (final f in piece.filtres)
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${f.$1} : ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: f.$2)
              ])),
          ]),
          const Text(
              'L’état ne porte que les enregistrements retenus par ces filtres.',
              style: TextStyle(
                  fontStyle: FontStyle.italic, color: JetonsShell.slate500)),
        ]),
      );

  Widget _cartouche() => Container(
        key: const Key('impression:cartouche'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            border: Border.all(color: JetonsShell.slate300),
            borderRadius: BorderRadius.circular(4)),
        child: Wrap(spacing: 24, runSpacing: 4, children: [
          for (final p in piece.cartouche)
            SizedBox(
                width: 300,
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${p.$1} : ',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: p.$2),
                ]))),
        ]),
      );

  Widget _bloc(BlocPiece b) => switch (b) {
        BlocTableau() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (b.titre != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 4),
                    child: Text(b.titre!.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: b.alerte
                                ? JetonsShell.danger700
                                : JetonsShell.navy900))),
              _tableau(b.tableau),
            ],
          ),
        BlocTexte() => Text(b.texte,
            style: TextStyle(
                fontWeight: b.gras ? FontWeight.w600 : FontWeight.w400,
                fontStyle: b.italique ? FontStyle.italic : FontStyle.normal,
                color: JetonsShell.slate800)),
      };

  /// RÈGLE UNIQUE des tableaux imprimés (aperçu ET PDF) : toutes les cellules d'une rangée ont la hauteur de la plus haute (`intrinsicHeight`),
  /// le texte est aligné EN HAUT de sa cellule (les montants à droite), et les bordures sont tracées UNE fois par le tableau (`TableBorder.all`),
  /// jamais cellule par cellule : des conteneurs indépendants se décalaient d'une colonne à l'autre dès qu'une cellule passait sur deux lignes.
  /// Le fond de l'en-tête et de la ligne de total est porté par la RANGÉE.
  Widget _tableau(TableauEtat t) {
    final pied = t.pied;
    Widget cellule(String s, {bool droite = false, bool entete = false, bool total = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Align(
            alignment: droite ? Alignment.topRight : Alignment.topLeft,
            child: Text(s,
                textAlign: droite ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                    height: 1.3,
                    fontWeight: entete ? FontWeight.w600 : (total ? FontWeight.w700 : FontWeight.w400),
                    fontFeatures: droite ? const [FontFeature.tabularFigures()] : null))));
    return Table(
        key: const Key('impression:tableau'),
        defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
        defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
        border: TableBorder.all(color: JetonsShell.slate300, width: 0.5),
        children: [
          TableRow(decoration: const BoxDecoration(color: JetonsShell.slate100), children: [
            for (final c in t.colonnes) cellule(c.libelle, droite: c.droite, entete: true)
          ]),
          for (final r in t.cellules)
            TableRow(children: [
              for (var i = 0; i < r.length; i++) cellule(r[i], droite: t.colonnes[i].droite)
            ]),
          if (pied != null)
            TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
              for (var i = 0; i < pied.length; i++) cellule(pied[i], droite: t.colonnes[i].droite, total: true)
            ]),
        ]);
  }

  Widget _signatures() => Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Row(children: [
          for (final s in piece.signatures.take(4))
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(children: [
                  Text(s.role,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: JetonsShell.slate700)),
                  if (s.nom != null)
                    Text(s.nom!,
                        style: const TextStyle(
                            fontSize: 9, color: JetonsShell.slate500)),
                  const SizedBox(height: 40),
                  const Divider(height: 1, color: JetonsShell.slate400),
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(s.mention,
                          style: const TextStyle(
                              fontSize: 8, color: JetonsShell.slate400))),
                ]),
              ),
            ),
        ]),
      );

  Widget _pied() => Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        key: const Key('impression:pied'),
        padding: const EdgeInsets.only(top: 8),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: JetonsShell.slate300))),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
              fontSize: 8, height: 1.4, color: JetonsShell.slate500),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(EnteteTroisZones.depuis(piece.identiteImprimee).piedLegal),
                  Text(
                      'Document généré par ${piece.utilisateur} le ${dateHeure(piece.edite)}'),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Réf. document : ${piece.reference}',
                      style: const TextStyle(fontFamily: _mono)),
                  Text(EnteteTroisZones.depuis(piece.identiteImprimee).editeDepuis),
                ]),
              ]),
        ),
      ));
}


// ---------------------------------------------------------------------------------------------------------------------------------------------
// Fiche documentaire PAYSAGE (organigramme) : toutes les cotes viennent de `GabaritFichePaysage`, la scène du domaine, la fiche de la base.
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les pages d'une fiche paysage, l'une sous l'autre, chacune à 297 × 210 mm : l'aperçu montre ce que le PDF imprime.
class FeuilleFichePaysage extends StatelessWidget {
  const FeuilleFichePaysage({super.key, required this.fiche});
  final FichePaysage fiche;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < fiche.pages.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _page(i),
        ]
      ]);

  Widget _page(int i) {
    const g = GabaritFichePaysage();
    final page = fiche.pages[i];
    return Container(
      key: Key('impression:fiche:$i'),
      width: mm(g.largeur),
      height: mm(g.hauteur),
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(mm(g.margeCote), mm(g.margeHaut), mm(g.margeCote), mm(g.margeBas)),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Inter', fontSize: 10, height: 1.2, color: JetonsShell.anthracite900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: _cartouche(i)),
          SizedBox(height: mm(g.ecartContenu)),
          Expanded(
              child: switch (page) {
            PageGraphe() => _Graphe(scene: page.scene),
            PageLegende() => _legende(page),
          }),
          _pied(),
        ]),
      ),
    );
  }

  Widget _cartouche(int i) {
    const g = GabaritFichePaysage();
    final bord = Border.all(color: JetonsShell.anthracite900, width: 0.8);
    const trait = BorderSide(color: JetonsShell.anthracite900, width: 0.8);
    final droite = fiche.cartouche(i);
    return Container(
      key: Key('impression:fiche:cartouche:$i'),
      width: mm(g.cartoucheLargeur),
      height: mm(g.cartoucheHauteur),
      decoration: BoxDecoration(border: bord),
      child: Row(children: [
        Expanded(
            flex: g.colonnes[0],
            child: Container(
                decoration: const BoxDecoration(border: Border(right: trait)),
                padding: const EdgeInsets.all(2),
                child: const Center(child: LogoClinique(largeur: 70, hauteur: 70)))),
        Expanded(
            flex: g.colonnes[1],
            child: Column(children: [
              Expanded(
                  flex: g.etagesTitre[0],
                  child: Container(
                      decoration: const BoxDecoration(border: Border(bottom: trait)),
                      alignment: Alignment.center,
                      child: Text(fiche.fiche.titreHaut, style: const TextStyle(fontSize: 11)))),
              Expanded(
                  flex: g.etagesTitre[1],
                  child: Container(
                      alignment: Alignment.center,
                      child: Text(fiche.fiche.titre,
                          style: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w700, fontSize: 11, color: JetonsShell.sante600)))),
            ])),
        Expanded(
            flex: g.colonnes[2],
            child: Container(
                decoration: const BoxDecoration(border: Border(left: trait)),
                child: Column(children: [
                  for (var k = 0; k < droite.length; k++)
                    Expanded(
                        flex: g.lignesDroite[k],
                        child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(border: k < droite.length - 1 ? const Border(bottom: trait) : null),
                            padding: const EdgeInsets.only(left: 4),
                            alignment: Alignment.centerLeft,
                            child: Text(droite[k], style: const TextStyle(fontSize: 9)))),
                ]))),
      ]),
    );
  }

  Widget _legende(PageLegende page) {
    const g = GabaritFichePaysage();
    return Padding(
        key: const Key('impression:fiche:legende'),
        padding: EdgeInsets.only(left: mm(g.legendeGauche - g.margeCote), top: mm(g.legendeHaut)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in page.lignes)
            SizedBox(
                height: mm(g.legendeLigne),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: l.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' : ${l.libelle}'),
                ]), style: TextStyle(fontSize: g.legendeCorps * 96 / 72))),
        ]));
  }

  Widget _pied() => Container(
        key: const Key('impression:fiche:pied'),
        height: mm(const GabaritFichePaysage().hauteurPied),
        alignment: Alignment.bottomCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final l in fiche.pied) Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8.5, height: 1.25)),
          Text(fiche.fiche.mention, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, height: 1.3, color: JetonsShell.coeur500)),
          Text(fiche.tracabilite, textAlign: TextAlign.center, style: const TextStyle(fontSize: 6.5, height: 1.4, color: JetonsShell.slate500)),
        ]),
      );
}

/// Le graphe : traits fins, cases foncées à étiquette claire, numéros de niveau en marge. Les positions sont celles de la scène, mises à l'échelle de la zone.
class _Graphe extends StatelessWidget {
  const _Graphe({required this.scene});
  final SceneOrganigramme scene;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const g = GabaritFichePaysage();
        final a = ajusterScene(scene, c.maxWidth, c.maxHeight);
        final e = a.echelle;
        return SizedBox(
            key: const Key('impression:fiche:graphe'),
            width: c.maxWidth,
            height: c.maxHeight,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: CustomPaint(painter: _PeintreTraits(scene, a))),
              for (final n in scene.niveaux)
                Positioned(
                    left: a.dx + n.x * e - 20,
                    top: a.dy + n.y * e - scene.police * e * 0.7,
                    width: 40,
                    child: Text('${n.n}', textAlign: TextAlign.center, style: TextStyle(fontSize: scene.police * e * 1.1, height: 1.2))),
              for (final k in scene.cases)
                Positioned(
                    key: Key('case:${k.id}'),
                    left: a.dx + k.x * e,
                    top: a.dy + k.y * e,
                    width: k.l * e,
                    height: k.h * e,
                    child: Container(
                        decoration: BoxDecoration(color: JetonsShell.sante600, border: Border.all(color: JetonsShell.sante800, width: g.bordUnites * e)),
                        padding: EdgeInsets.symmetric(horizontal: g.insetX * e, vertical: g.insetY * e),
                        child: Container(
                            color: JetonsShell.sante100,
                            alignment: Alignment.center,
                            child: k.titre.isEmpty
                                ? Text(k.texte,
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(fontSize: scene.police * e, height: 1.1, color: JetonsShell.anthracite900))
                                // Le titre porté par le titulaire, sous le code : « (SG) ». La boîte a grandi pour deux lignes (voir la scène).
                                : Column(mainAxisSize: MainAxisSize.min, children: [
                                    Text(k.texte,
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.clip,
                                        style: TextStyle(fontSize: scene.police * e, height: 1.1, color: JetonsShell.anthracite900)),
                                    Text(k.titre,
                                        key: Key('titre:${k.id}'),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        style: TextStyle(fontSize: scene.police * e * 0.8, height: 1.1, color: JetonsShell.anthracite900)),
                                  ])))),
            ]));
      });
}

class _PeintreTraits extends CustomPainter {
  _PeintreTraits(this.scene, this.a);
  final SceneOrganigramme scene;
  final AjustementScene a;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = JetonsShell.sante600
      ..strokeWidth = mm(const GabaritFichePaysage().traitMm)
      ..style = PaintingStyle.stroke;
    for (final t in scene.traits) {
      canvas.drawLine(Offset(a.dx + t.x1 * a.echelle, a.dy + t.y1 * a.echelle), Offset(a.dx + t.x2 * a.echelle, a.dy + t.y2 * a.echelle), p);
    }
  }

  @override
  bool shouldRepaint(_PeintreTraits o) => o.scene != scene || o.a.echelle != a.echelle;
}
