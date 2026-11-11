import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';
import '../import/droits_import.dart';
import '../import/execution_import.dart';
import '../import/fichier_import.dart';
import '../import/selecteurs_import.dart';
import '../shell/contexte_ecran.dart';
import 'badge.dart';
import 'bouton.dart';
import 'carte.dart';
import 'modale.dart';
import 'tableau_de_bord.dart';
import 'toast.dart';
import 'ton.dart';

/// `K.importer` : LA fabrique du bouton « Importer » et de sa fenêtre en trois étapes, partagée par TOUS les écrans qui importent un jeu de données
/// (décision de la Direction du 11/11/2026). Un écran déclare le jeu (`actionsImporter(context, 'produits')` dans ses actions d'en-tête) et n'écrit rien
/// d'autre : le modèle, la vérification, l'écriture, le journal (RG-12), l'historique des lots et les droits sont ICI, une seule fois.
///
///  1. MODÈLE : le modèle .xlsx ou .csv à télécharger (les colonnes réservées en sont absentes sans le droit) ;
///  2. VÉRIFICATION : le fichier est analysé EN ENTIER, ligne par ligne, rien n'est écrit ; les erreurs sont nommées (ligne, colonne, motif, geste) ;
///  3. IMPORT : confirmation, puis écriture du lot en un seul geste (toutes les fiches ou aucune).
///
/// La commande est ABSENTE (jamais grisée) sans le droit d'importer le jeu : ce droit est celui de l'écran du jeu dans la matrice (`DroitsImport`).
List<Widget> actionsImporter(BuildContext context, String jeuId) {
  final c = ContexteEcran.maybeOf(context);
  final jeu = jeuImportParId(jeuId);
  if (c == null || jeu == null || !DroitsImport(c).peutImporter(jeu)) return const [];
  return [BoutonImporter(jeu)];
}

/// Le bouton « Importer » d'un jeu ; rien du tout (et non un bouton grisé) quand le profil n'a pas le droit.
class BoutonImporter extends StatelessWidget {
  const BoutonImporter(this.jeu, {super.key});
  final JeuImport jeu;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.maybeOf(context);
    if (c == null || !DroitsImport(c).peutImporter(jeu)) return const SizedBox.shrink();
    return BoutonSigh(
        key: Key('importer-${jeu.id}'),
        libelle: 'Importer',
        icone: LucideIcons.fileUp,
        variante: VarianteBouton.secondaire,
        onPressed: () => ouvrirImport(context, jeu));
  }
}

/// Ouvre la fenêtre d'import d'un jeu. Refuse (sans l'ouvrir) si le profil n'a pas le droit : une adresse ou un geste programmatique ne contourne pas la matrice.
Future<void> ouvrirImport(BuildContext context, JeuImport jeu) async {
  final c = ContexteEcran.maybeOf(context);
  if (c == null || !DroitsImport(c).peutImporter(jeu)) return;
  await afficherModale<void>(context, titre: jeu.libelle, sousTitre: 'Importation de données', taille: TailleModale.lg, corps: AssistantImport(jeu));
}

/// Les trois étapes. Une étape ne s'ouvre qu'une fois la précédente franchie ; revenir en arrière ne perd pas le fichier choisi.
class AssistantImport extends StatefulWidget {
  const AssistantImport(this.jeu, {super.key});
  final JeuImport jeu;

  @override
  State<AssistantImport> createState() => _EtatAssistantImport();
}

class _EtatAssistantImport extends State<AssistantImport> {
  int _etape = 1;
  bool _ignorer = false;
  AnalyseImport? _analyse;
  Fiche? _lotRefuse;
  String? _resultat;
  bool _resultatOk = true;
  bool _occupe = false;
  bool _termine = false;

  JeuImport get _jeu => widget.jeu;

  Future<void> _enregistrer(String nom, Uint8List octets) async {
    final chemin = await SelecteursImport.enregistrer(nom, octets);
    if (!mounted) return;
    if (chemin != null) ToastsSigh.afficher(context, 'Fichier enregistré.', type: TypeToast.succes, detail: chemin);
  }

  Future<void> _modele(ContexteEcran c, {required bool csv}) async {
    final accordees = DroitsImport(c).colonnesAccordees(_jeu);
    if (csv) {
      await _enregistrer('${_jeu.fichierModele}.csv', Uint8List.fromList(utf8.encode(modeleCsvImport(_jeu, colonnesAccordees: accordees))));
    } else {
      await _enregistrer('${_jeu.fichierModele}.xlsx', classeurModele(_jeu, portImport(c), colonnesAccordees: accordees));
    }
  }

  Future<void> _choisir(ContexteEcran c) async {
    final f = await SelecteursImport.choisir();
    if (f == null || !mounted) return;
    final v = verifierFichier(c, _jeu, f, ignorerExistants: _ignorer);
    setState(() {
      _analyse = v.analyse;
      _lotRefuse = v.lotRefuse;
      _resultat = null;
    });
  }

  Future<void> _ecrire(ContexteEcran c) async {
    final a = _analyse!;
    setState(() => _occupe = true);
    final r = appliquer(_jeu, a, portImport(c));
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _termine = true;
      _resultatOk = r.ok;
      _resultat = r.ok
          ? 'Lot ${r.lot!['reference']} appliqué. ${r.ecrits} fiche(s) écrite(s)${a.ignorees.isEmpty ? '' : ', ${a.ignorees.length} ligne(s) ignorée(s)'}, journalisées (RG-12).'
          : 'Importation refusée. ${r.motif}. ${r.geste}';
    });
    if (r.ok) {
      ToastsSigh.afficher(context, 'Lot ${r.lot!['reference']} appliqué.', type: TypeToast.succes, detail: '${r.ecrits} fiche(s) écrite(s).');
    } else {
      ToastsSigh.afficher(context, 'Importation refusée.', type: TypeToast.erreur, detail: r.motif);
    }
  }

  Future<void> _rapport(ContexteEcran c) async {
    final a = _analyse!;
    final lot = _lotRefuse;
    await _enregistrer('rapport-${lot != null ? lot['reference'] : 'analyse'}.xlsx',
        classeurRapport(_jeu.libelle, a.fichier, lot != null ? '${lot['reference']}' : 'non consigné', a.nbLignes, [for (final p in a.problemes) p.versJson()]));
  }

  // --- Les trois étapes ----------------------------------------------------------------------------------------------------------

  Widget _bandeau() {
    const noms = ['Modèle', 'Vérification', 'Import'];
    return Row(children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const Expanded(child: Divider(height: 1, color: JetonsShell.slate300)),
        Container(
            key: Key('import-etape-${i + 1}'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: _etape == i + 1 ? JetonsShell.coeur500 : (_etape > i + 1 ? JetonsShell.success600 : Colors.white),
                border: Border.all(color: _etape >= i + 1 ? Colors.transparent : JetonsShell.slate300),
                borderRadius: BorderRadius.circular(16)),
            child: Text('${i + 1}. ${noms[i]}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _etape >= i + 1 ? Colors.white : JetonsShell.slate500))),
      ],
    ]);
  }

  Widget _etapeModele(ContexteEcran c) {
    final port = portImport(c);
    final ctx = _jeu.contexte(port);
    final cols = _jeu.colonnesPour(DroitsImport(c).colonnesAccordees(_jeu));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_jeu.description, style: const TextStyle(fontSize: 14, color: JetonsShell.slate600)),
      const SizedBox(height: 8),
      Text('Source : ${_jeu.source}', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
      const SizedBox(height: 12),
      const Text(
          'Téléchargez le modèle, remplissez l’onglet « Données » sans changer les en-têtes, puis passez à la vérification : rien n’est écrit tant que vous n’avez pas confirmé.',
          style: TextStyle(fontSize: 14, color: JetonsShell.slate600)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        BoutonSigh(key: const Key('import-modele-xlsx'), libelle: 'Télécharger le modèle (.xlsx)', icone: LucideIcons.fileDown, onPressed: () => _modele(c, csv: false)),
        BoutonSigh(
            key: const Key('import-modele-csv'), libelle: 'Modèle CSV', icone: LucideIcons.fileText, variante: VarianteBouton.secondaire, onPressed: () => _modele(c, csv: true)),
      ]),
      const SizedBox(height: 12),
      MiniTableauSigh(colonnes: [
        ColonneMini('Colonne', (l) => (l['c'] as ColonneImport).label),
        ColonneMini('Obligatoire', (l) => (l['c'] as ColonneImport).obligatoire ? 'oui' : 'non'),
        ColonneMini('Valeurs permises', (l) {
          final col = l['c'] as ColonneImport;
          if (col.type == 'liste') return valeursListe(col, ctx).take(6).map((x) => x.label).join(' ; ');
          return col.motifTexte ?? col.aide ?? '';
        }),
      ], lignes: [for (final col in cols) {'c': col}]),
      const SizedBox(height: 16),
      Align(
          alignment: Alignment.centerRight,
          child: BoutonSigh(key: const Key('import-vers-verification'), libelle: 'Passer à la vérification', icone: LucideIcons.arrowRight, onPressed: () => setState(() => _etape = 2))),
    ]);
  }

  Widget _etapeVerification(ContexteEcran c) {
    final a = _analyse;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh('La vérification est complète et ne modifie rien : chaque ligne est contrôlée, un refus est nommé (ligne, colonne, motif, geste de correction).',
          icone: LucideIcons.shieldCheck),
      const SizedBox(height: 12),
      if (_jeu.ignorable)
        CheckboxListTile(
            key: const Key('imp-ignorer-existants'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _ignorer,
            onChanged: _occupe ? null : (v) => setState(() {
                  _ignorer = v == true;
                  _analyse = null;
                  _lotRefuse = null;
                }),
            title: const Text('Ignorer les existants', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('Une ligne dont la fiche existe déjà est listée et ignorée, jamais modifiée. Les autres lignes s’importent.', style: TextStyle(fontSize: 12))),
      Wrap(spacing: 8, runSpacing: 8, children: [
        BoutonSigh(
            key: const Key('import-choisir-fichier'),
            libelle: a == null ? 'Choisir le fichier (.xlsx ou .csv)' : 'Choisir un autre fichier',
            icone: LucideIcons.upload,
            onPressed: () => _choisir(c)),
        BoutonSigh(libelle: 'Retour au modèle', variante: VarianteBouton.secondaire, onPressed: () => setState(() => _etape = 1)),
      ]),
      if (a != null) ...[const SizedBox(height: 16), _resultatAnalyse(c, a)],
    ]);
  }

  Widget _resultatAnalyse(ContexteEcran c, AnalyseImport a) {
    final ps = a.problemes;
    final montres = ps.take(40).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        BadgeSigh('${a.nbLignes} ligne(s) lue(s)', ton: TonSigh.navy),
        BadgeSigh('${a.compte.valides} valide(s)', ton: TonSigh.succes),
        BadgeSigh('${a.compte.avertissements} avertissement(s)', ton: TonSigh.attention),
        BadgeSigh('${a.compte.refus} refus', ton: a.compte.refus > 0 ? TonSigh.danger : TonSigh.neutre),
        if (a.ignorees.isNotEmpty) BadgeSigh('${a.ignorees.length} ignorée(s)', ton: TonSigh.info),
      ]),
      const SizedBox(height: 12),
      if (a.accepte)
        NoteSigh('Vérification conforme. ${a.nbLignes - a.ignorees.length} ligne(s) peuvent être écrites. Rien n’est encore écrit.', ton: TonSigh.succes, icone: LucideIcons.circleCheck)
      else
        NoteSigh('Fichier refusé. Rien n’a été écrit. Le fichier est consigné au lot ${_lotRefuse?['reference']} ; corrigez les points ci-dessous puis choisissez de nouveau le fichier.',
            ton: TonSigh.danger, icone: LucideIcons.octagonAlert),
      if (a.ignorees.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Lignes ignorées, la fiche existe déjà : ${a.ignorees.join(', ')}.', key: const Key('import-lignes-ignorees'), style: const TextStyle(fontSize: 13, color: JetonsShell.slate600)),
      ],
      if (montres.isNotEmpty) ...[
        const SizedBox(height: 12),
        MiniTableauSigh(colonnes: [
          ColonneMini('Ligne', (l) => l['n'] == 0 ? 'Fichier' : '${l['n']}', droite: true),
          ColonneMini('Colonne', (l) => '${l['colonne'] ?? ''}'),
          ColonneMini('Constat', (l) => '${l['motif']}. ${l['geste']}'),
        ], lignes: [for (final p in montres) p.versJson()]),
        if (ps.length > montres.length)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('… et ${ps.length - montres.length} autre(s) constat(s) : téléchargez le rapport d’erreurs.', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500))),
      ],
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (a.accepte)
          BoutonSigh(key: const Key('import-vers-import'), libelle: 'Continuer vers l’import', icone: LucideIcons.arrowRight, onPressed: () => setState(() => _etape = 3)),
        if (ps.isNotEmpty)
          BoutonSigh(libelle: 'Rapport d’erreurs (.xlsx)', icone: LucideIcons.fileDown, variante: VarianteBouton.secondaire, onPressed: () => _rapport(c)),
      ]),
    ]);
  }

  Widget _etapeImport(ContexteEcran c) {
    final a = _analyse!;
    final nb = a.nbLignes - a.ignorees.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_termine)
        NoteSigh(
            '$nb ligne(s) du fichier « ${a.fichier} » vont s’écrire en un seul geste (toutes ou aucune), au nom de ${c.agent.nom}, et journalisées (RG-12).'
            '${a.ignorees.isEmpty ? '' : ' ${a.ignorees.length} ligne(s) existante(s) seront ignorées.'} Le lot pourra être annulé par qui arbitre les lots, tant qu’aucun acte ne s’appuie dessus.',
            icone: LucideIcons.packageCheck),
      if (_resultat != null) ...[
        const SizedBox(height: 12),
        NoteSigh(_resultat!, key: const Key('import-resultat'), ton: _resultatOk ? TonSigh.succes : TonSigh.danger, icone: _resultatOk ? LucideIcons.circleCheck : LucideIcons.octagonAlert),
      ],
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (!_termine) ...[
          BoutonSigh(
              key: const Key('import-ecrire'),
              libelle: 'Importer ($nb ligne${nb > 1 ? 's' : ''})',
              icone: LucideIcons.packageCheck,
              onPressed: _occupe ? null : () => _ecrire(c)),
          BoutonSigh(libelle: 'Retour à la vérification', variante: VarianteBouton.secondaire, onPressed: () => setState(() => _etape = 2)),
        ] else
          BoutonSigh(key: const Key('import-fermer'), libelle: 'Fermer', onPressed: () => Navigator.of(context, rootNavigator: true).pop()),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _bandeau(),
      const SizedBox(height: 16),
      switch (_etape) {
        1 => _etapeModele(c),
        2 => _etapeVerification(c),
        _ => _etapeImport(c),
      },
    ]);
  }
}
