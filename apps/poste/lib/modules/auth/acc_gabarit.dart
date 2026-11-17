import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_autonome.dart';
import '../../shell/logo_clinique.dart';

/// La présentation du logiciel sur l'écran de connexion (PRD Baguidi P1-2) : ce que la clinique gère avec lui.
const presentationLogiciel =
    'Gestion des stocks et inventaire de la pharmacie, achats et expressions de besoins, ressources humaines, paie et primes, comptabilité SYSCOHADA, pilotage et tableaux de bord.';

/// Les QUATORZE spécialités de la clinique (fiche d'identité du 06/11/2026, maquette `core.js`) : un référentiel de
/// PRÉSENTATION pour l'écran de connexion, pas le périmètre du logiciel. Aucune constante d'identité ne les portait.
const specialitesClinique = [
  'Médecine du travail',
  'Santé publique',
  'Gynécologie',
  'Chirurgie',
  'Urologie',
  'Rhumatologie',
  'Ophtalmologie',
  'Orthophonie',
  'Endocrinologie',
  'Pédiatrie',
  'Neurologie',
  'Cardiologie',
  'Kinésithérapie',
  'Imagerie (Radiologie-Échographie)',
];

/// Le gabarit commun des écrans d'accès (`shell()` de `auth.js`, charte BAGUIDI P1-2) : une carte centrée à coins arrondis
/// posée sur un fond bleu très pâle, LISERÉ SUPÉRIEUR rouge puis bleu (les deux traits du cœur du logo), panneau
/// institutionnel en dégradé bleu Santé à gauche (au-delà de 1024 px), panneau de saisie blanc à droite. Sous la largeur
/// d'une tablette, le panneau bleu passe AU-DESSUS, réduit à l'en-tête et au titre. Il sert SIX écrans (connexion, verrou,
/// mot de passe oublié, réinitialisation, double facteur) : la porte d'entrée du logiciel a un seul visage.
/// `decorSombre` (écran verrouillé) : le fond de page suit le décor anthracite de la maquette, la carte ne change pas.
class SceneAcces extends StatelessWidget {
  const SceneAcces({super.key, required this.titre, this.sousTitre, this.icone, required this.corps, this.pied, this.decorSombre = false});
  final String titre;
  final String? sousTitre;
  final IconData? icone;
  final Widget corps;
  final Widget? pied;
  final bool decorSombre;

  static const _puces = [
    (LucideIcons.shieldCheck, 'Traçabilité intégrale des actions (journal d’audit)'),
    (LucideIcons.packageSearch, 'Alertes de rupture et de péremption automatiques (FEFO)'),
    (LucideIcons.fileBadge, 'Facture normalisée conforme au dispositif MECeF'),
    (LucideIcons.bookOpenCheck, 'Comptabilité SYSCOHADA alimentée automatiquement'),
  ];

  /// La pastille blanche RONDE du logo (maquette : h-16 w-16 rounded-full bg-white shadow-raise).
  Widget _pastilleLogo(double cote, {Color? anneau}) => Container(
      width: cote,
      height: cote,
      decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: anneau == null ? null : Border.all(color: anneau, width: 2),
          boxShadow: JetonsShell.ombreRelief),
      alignment: Alignment.center,
      child: ClipOval(child: LogoClinique(largeur: cote - 10, hauteur: cote - 10)));

  /// L'en-tête de marque du panneau bleu : logo, dénomination (Montserrat gras), activité en petites capitales claires, localisation.
  Widget _marque() => Row(children: [
        _pastilleLogo(64),
        const SizedBox(width: 14),
        Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(IdentiteClinique.nom,
              key: const Key('acces:nom-clinique'),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 24 / 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: JetonsSigh.policeTitres.first,
                  fontFamilyFallback: JetonsSigh.policeTitres.skip(1).toList())),
          if (IdentiteClinique.activite.isNotEmpty)
            Text(IdentiteClinique.activite.toUpperCase(),
                style: const TextStyle(color: JetonsShell.sante200, fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
          Text(IdentiteClinique.localisation, style: const TextStyle(color: JetonsShell.sante200, fontSize: 12, height: 16 / 12)),
        ])),
      ]);

  Widget _titreSigh({double taille = 30}) => Text('Système Intégré de Gestion Hospitalière',
      style: TextStyle(
          color: Colors.white,
          fontSize: taille,
          height: 36 / 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.75,
          fontFamily: JetonsSigh.policeTitres.first,
          fontFamilyFallback: JetonsSigh.policeTitres.skip(1).toList()));

  /// Le fond du panneau institutionnel : dégradé bleu Santé, disques translucides et cœur à tracé d'électrocardiogramme en filigrane.
  Widget _fondPanneau(Widget enfant) => Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [JetonsShell.sante600, JetonsShell.sante700, JetonsShell.sante900])),
      child: Stack(children: [
        Positioned(left: -96, top: -96, child: IgnorePointer(child: _disque(320, Colors.white.withValues(alpha: 0.10)))),
        Positioned(left: -40, bottom: -112, child: IgnorePointer(child: _disque(288, JetonsShell.sante400.withValues(alpha: 0.30)))),
        Positioned(right: -64, top: 180, child: IgnorePointer(child: _disque(224, Colors.white.withValues(alpha: 0.05)))),
        Positioned(
            right: 8,
            bottom: 8,
            child: IgnorePointer(child: Icon(LucideIcons.heartPulse, size: 200, color: Colors.white.withValues(alpha: 0.10)))),
        enfant,
      ]));

  /// Une pastille de spécialité : contour blanc translucide ; la dernière, « + N spécialités », est pleine blanche.
  Widget _pastilleSpecialite(String texte, {bool pleine = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: pleine ? Colors.white : Colors.white.withValues(alpha: 0.10),
          border: pleine ? null : Border.all(color: Colors.white.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(9999)),
      child: Text(texte,
          style: TextStyle(color: pleine ? JetonsShell.sante700 : Colors.white, fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w500)));

  // Le panneau défile si la saisie est plus courte que lui : rien ne déborde, rien ne se perd.
  Widget _panneau() => _fondPanneau(SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _marque(),
        const SizedBox(height: 24),
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _titreSigh(),
              const SizedBox(height: 12),
              const Text(presentationLogiciel, style: TextStyle(color: JetonsShell.sante100, fontSize: 14, height: 22.75 / 14)),
              const SizedBox(height: 20),
              for (final p in _puces)
                Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
                          child: Icon(p.$1, size: 14, color: JetonsShell.sante100)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(p.$2, style: const TextStyle(color: JetonsShell.sante100, fontSize: 14, height: 20 / 14))),
                    ])),
              const SizedBox(height: 10),
              // Les QUATORZE spécialités de la clinique, en pastilles translucides (fiche d'identité du 06/11/2026).
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in specialitesClinique) _pastilleSpecialite(s),
              ]),
              if (IdentiteClinique.slogan.isNotEmpty) ...[
                const SizedBox(height: 20),
                // La devise, en police MANUSCRITE (font-slogan de la charte).
                Text('« ${IdentiteClinique.slogan} »',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        height: 32 / 24,
                        fontFamily: JetonsSigh.policeSlogan.first,
                        fontFamilyFallback: JetonsSigh.policeSlogan.skip(1).toList())),
              ],
            ])),
        const SizedBox(height: 24),
        Text(IdentiteClinique.mentionLegale, style: const TextStyle(color: JetonsShell.sante200, fontSize: 12, height: 16 / 12)),
      ])));

  /// Sous la largeur d'une tablette, le panneau bleu passe AU-DESSUS de la saisie, réduit à l'en-tête et au titre.
  Widget _panneauReduit() => _fondPanneau(Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _marque(),
        const SizedBox(height: 16),
        _titreSigh(taille: 22),
      ])));

  /// Le panneau de saisie, blanc (la carte elle-même est la scène ; aucun second cadre).
  Widget _carte(bool large) => Container(
      color: Colors.white,
      padding: EdgeInsets.all(large ? 40 : 24),
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                KeyedSubtree(
                    key: const Key('acces:carte'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (icone != null)
                        Container(
                            width: 48,
                            height: 48,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(color: JetonsShell.sante50, borderRadius: BorderRadius.circular(12)),
                            child: Icon(icone, size: 24, color: JetonsShell.sante700)),
                      Semantics(
                          header: true,
                          child: Text(titre,
                              style: TextStyle(
                                  color: JetonsShell.navy900,
                                  fontSize: 24,
                                  height: 32 / 24,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.6,
                                  fontFamily: JetonsSigh.policeTitres.first,
                                  fontFamilyFallback: JetonsSigh.policeTitres.skip(1).toList()))),
                      if (sousTitre != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(sousTitre!, style: const TextStyle(color: JetonsShell.slate500, fontSize: 14, height: 20 / 14))),
                      const SizedBox(height: 24),
                      corps,
                      if (pied != null) Padding(padding: const EdgeInsets.only(top: 24), child: Center(child: pied)),
                    ])),
                if (!large)
                  Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(IdentiteClinique.mentionLegale,
                          textAlign: TextAlign.center, style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
              ]))));

  Widget _disque(double d, Color c) =>
      Container(width: d, height: d, decoration: BoxDecoration(shape: BoxShape.circle, color: c));

  Widget _halo(double d, Color c) => Container(
      width: d, height: d, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)])));

  @override
  Widget build(BuildContext context) {
    // Le fond de page : bleu très pâle (connexion), ou le décor ANTHRACITE de la maquette pour l'écran verrouillé.
    final fond = decorSombre
        ? const [JetonsShell.anthracite950, JetonsShell.anthracite900, JetonsShell.sante950]
        : const [JetonsShell.slate100, JetonsShell.sante50, JetonsShell.sante100];
    return Scaffold(
        backgroundColor: JetonsShell.slate100,
        body: Container(
            decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: fond)),
            child: Stack(children: [
              // Décor : halos flous, hors flux et non cliquables.
              if (decorSombre) ...[
                Positioned(left: -96, top: -96, child: IgnorePointer(child: _halo(384, JetonsShell.sante600.withValues(alpha: 0.20)))),
                Positioned(right: -80, bottom: -112, child: IgnorePointer(child: _halo(384, JetonsShell.coeur500.withValues(alpha: 0.15)))),
              ] else ...[
                Positioned(left: -160, top: -160, child: IgnorePointer(child: _halo(544, JetonsShell.sante200.withValues(alpha: 0.70)))),
                Positioned(right: -128, bottom: -192, child: IgnorePointer(child: _halo(608, JetonsShell.sante300.withValues(alpha: 0.50)))),
                Positioned(left: 420, top: 160, child: IgnorePointer(child: _halo(288, JetonsShell.coeur100.withValues(alpha: 0.60)))),
              ],
              LayoutBuilder(builder: (context, c) {
                final large = c.maxWidth >= 1024;
                final scene = ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: JetonsShell.ombrePop),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          // Le LISERÉ SUPÉRIEUR : rouge Cœur puis bleu Santé, les deux traits du cœur du logo.
                          Container(key: const Key('acces:lisere-coeur'), height: 3, color: JetonsShell.coeur500),
                          Container(key: const Key('acces:lisere-sante'), height: 3, color: JetonsShell.sante600),
                          if (large)
                            LayoutBuilder(
                                builder: (context, k) => ConstrainedBox(
                                    constraints: const BoxConstraints(minHeight: 640),
                                    child: Stack(children: [
                                      // Le panneau (55 %) remplit la hauteur que la saisie donne à la scène.
                                      Positioned(left: 0, top: 0, bottom: 0, width: k.maxWidth * 0.55, child: _panneau()),
                                      Padding(padding: EdgeInsets.only(left: k.maxWidth * 0.55), child: _carte(true)),
                                    ])))
                          else ...[
                            _panneauReduit(),
                            _carte(false),
                          ],
                        ])));
                return SingleChildScrollView(
                    child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: c.maxHeight),
                        child: Center(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1152), child: scene)))));
              }),
            ])));
  }
}

/// Un champ de saisie de la maquette (`.label` + `.input`) : libellé 12/16 en 500, saisie 14/20, bordure arrondie.
class ChampAcces extends StatelessWidget {
  const ChampAcces({
    super.key,
    required this.libelle,
    required this.controleur,
    this.indicatif,
    this.masque = false,
    this.suffixe,
    this.entete,
    this.surValidation,
    this.cle,
    this.autofocus = false,
  });
  final String libelle;
  final TextEditingController controleur;
  final String? indicatif;
  final bool masque;
  final Widget? suffixe;

  /// Un élément à droite du libellé (« Mot de passe oublié ? »).
  final Widget? entete;
  final VoidCallback? surValidation;
  final Key? cle;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        entete == null
            ? LibelleChamp(libelle)
            : Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(libelle,
                      style: const TextStyle(
                          color: JetonsShell.slate600, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500)),
                  entete!,
                ])),
        Semantics(
            textField: true,
            label: libelle,
            child: TextField(
                key: cle,
                controller: controleur,
                obscureText: masque,
                autofocus: autofocus,
                enableSuggestions: !masque,
                autocorrect: !masque,
                style: styleSaisie,
                decoration: decorationChamp(indicatif: indicatif, suffixe: suffixe),
                onSubmitted: surValidation == null ? null : (_) => surValidation!())),
      ]);
}

/// Le lien de pied de carte (`font-medium text-navy-700 hover:underline`).
class LienAcces extends StatelessWidget {
  const LienAcces(this.texte, {super.key, required this.onTap, this.petit = false});
  final String texte;
  final VoidCallback onTap;
  final bool petit;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Text(texte,
          style: TextStyle(
              color: JetonsShell.navy700, fontSize: petit ? 12 : 14, height: petit ? 16 / 12 : 20 / 14, fontWeight: FontWeight.w500)));
}

/// Le message rouge de la connexion (`border-danger-200 bg-danger-50`, icône `alert-circle`).
class MessageErreurAcces extends StatelessWidget {
  const MessageErreurAcces(this.texte, {super.key});
  final String texte;
  @override
  Widget build(BuildContext context) => Container(
      key: const Key('acces:erreur'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: JetonsShell.danger50, border: Border.all(color: JetonsShell.danger200), borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(LucideIcons.circleAlert, size: 16, color: JetonsShell.danger600),
        const SizedBox(width: 8),
        Expanded(child: Text(texte, style: const TextStyle(color: JetonsShell.danger900, fontSize: 12, height: 16 / 12))),
      ]));
}

/// Ce que le poste ne fait pas — dit à l'écran, comme la maquette dit ce qu'elle fait. Posé sous les écrans qui simulent.
class NoteSimulation extends StatelessWidget {
  const NoteSimulation(this.texte, {super.key});
  final String texte;
  @override
  Widget build(BuildContext context) => KeyedSubtree(key: const Key('acces:simulation'), child: NoteSigh(texte, ton: TonSigh.attention, icone: LucideIcons.triangleAlert));
}

/// Une police fixe (`font-mono text-xs`).
Widget mono(String texte) =>
    Text(texte, style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate700));

/// La date ISO d'une fiche en `jj/mm/aaaa`.
String dateIsoFr(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// Aller à l'accueil du profil, ou à la connexion quand personne n'est connecté (`url(N.ROLES[role].home)` / `url('index')`).
void allerAccueil(BuildContext c) {
  final x = ContexteAutonome.of(c);
  x.aller(x.accueil());
}
