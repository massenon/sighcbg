import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';
import '../kit/kit.dart';
import '../shell/contexte_ecran.dart';
import 'service_fichiers.dart';

/// Un fichier choisi par l'agent : son nom et son contenu.
class ScanChoisi {
  const ScanChoisi(this.nom, this.octets);
  final String nom;
  final Uint8List octets;
}

/// Le sélecteur de fichier du dépôt d'un scan, INJECTABLE : aucun test ne dépend d'un sélecteur natif. En exploitation il ouvre la boîte de dialogue du
/// système (`file_picker`), limitée aux PDF, JPEG et PNG (et WEBP au dossier patient).
class SelecteursScan {
  SelecteursScan._();
  static Future<ScanChoisi?> Function(String famille) choisir = choisirNatif;
  static void reinitialiser() => choisir = choisirNatif;

  static Future<ScanChoisi?> choisirNatif(String famille) async {
    final f = await FilePicker.pickFile(
        dialogTitle: 'Fichier numérisé (PDF, JPEG ou PNG)', type: FileType.custom, allowedExtensions: [for (final x in docFormats.where((x) => x.familles.contains(famille))) ...x.extensions]);
    if (f == null) return null;
    return ScanChoisi(f.name, await f.readAsBytes());
  }
}

/// Le message d'un refus nommé : le motif, puis le geste de correction.
void annoncerRefus(BuildContext ctx, Object e) {
  if (e is DocErreur) {
    ToastsSigh.afficher(ctx, e.motif, type: TypeToast.erreur, detail: 'Code ${e.code}. ${e.geste}');
  } else {
    ToastsSigh.afficher(ctx, 'Opération impossible.', type: TypeToast.erreur, detail: '$e');
  }
}

/// LA VISIONNEUSE D'IMAGE écrite pour le projet : zoom (molette, pincement, boutons), rotation par quart de tour, ajustement à la fenêtre, déplacement à la souris.
/// Aucune bibliothèque d'affichage de tiers : `InteractiveViewer` du cadriciel et un `RotatedBox`.
class VisionneuseImage extends StatefulWidget {
  const VisionneuseImage({super.key, required this.octets, this.hauteur = 380, this.libelle = 'Aperçu du scan'});
  final Uint8List octets;
  final double hauteur;
  final String libelle;
  @override
  State<VisionneuseImage> createState() => _VisionneuseImageState();
}

class _VisionneuseImageState extends State<VisionneuseImage> {
  final _ctl = TransformationController();
  int _quarts = 0;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _zoom(double f) {
    final m = _ctl.value.clone();
    final s = (m.getMaxScaleOnAxis() * f).clamp(0.2, 8.0) / m.getMaxScaleOnAxis();
    _ctl.value = m..scaleByDouble(s, s, 1, 1);
  }

  void _ajuster() {
    _ctl.value = Matrix4.identity();
    setState(() => _quarts = 0);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          BoutonIcone(icone: LucideIcons.zoomIn, libelle: 'Agrandir', onPressed: () => _zoom(1.25)),
          BoutonIcone(icone: LucideIcons.zoomOut, libelle: 'Réduire', onPressed: () => _zoom(0.8)),
          BoutonIcone(icone: LucideIcons.rotateCw, libelle: 'Pivoter à droite', onPressed: () => setState(() => _quarts = (_quarts + 1) % 4)),
          BoutonIcone(icone: LucideIcons.rotateCcw, libelle: 'Pivoter à gauche', onPressed: () => setState(() => _quarts = (_quarts + 3) % 4)),
          BoutonIcone(icone: LucideIcons.maximize, libelle: 'Ajuster à la fenêtre', onPressed: _ajuster),
          const Spacer(),
          Text('Rotation ${_quarts * 90}°', key: const Key('visionneuse:rotation'), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        Container(
            height: widget.hauteur,
            decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InteractiveViewer(
                    key: const Key('visionneuse:vue'),
                    transformationController: _ctl,
                    minScale: 0.2,
                    maxScale: 8,
                    child: Center(
                        child: RotatedBox(
                            quarterTurns: _quarts,
                            child: Image.memory(widget.octets,
                                fit: BoxFit.contain,
                                semanticLabel: widget.libelle,
                                errorBuilder: (_, __, ___) => const Text('Image illisible.', style: TextStyle(color: JetonsShell.slate500)))))))),
      ]);
}

/// L'aperçu d'un PDF. Le poste n'embarque AUCUN moteur de rendu de PDF (ni `pdfx` ni `pdfrx` : des bibliothèques natives, non disponibles ici) : on le DIT.
/// Ce qu'on montre : les caractéristiques, un extrait du texte quand le PDF a une couche texte, et le repli « Ouvrir avec l'application du poste ».
class ApercuPdf extends StatelessWidget {
  const ApercuPdf({super.key, required this.scan, required this.extrait, required this.onOuvrir});
  final Map<String, Object?> scan;
  final String extrait;
  final VoidCallback? onOuvrir;
  @override
  Widget build(BuildContext context) => Container(
      key: const Key('apercu:pdf'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.fileText, size: 28, color: JetonsShell.slate400),
          const SizedBox(width: 10),
          Expanded(child: Text('${scan['nom']} — PDF${scan['pages'] != null ? ', ${scan['pages']} page(s)' : ''}, ${docPoids((scan['taille'] as num).toInt())}', style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
        const SizedBox(height: 8),
        if (extrait.isNotEmpty)
          Text('Texte lu dans le PDF : $extrait…', key: const Key('apercu:extrait'), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate600, fontSize: 12))
        else
          const Text('Aucune couche texte : c’est un scan image, rien à afficher ici.', key: Key('apercu:sans-texte'), style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
        const SizedBox(height: 8),
        const NoteSigh('Ce poste n’a pas de moteur de rendu de PDF : l’aperçu page par page n’y est pas disponible. « Ouvrir avec l’application du poste » affiche le document dans le lecteur PDF du système.', icone: LucideIcons.info),
        const SizedBox(height: 10),
        if (onOuvrir != null) BoutonSigh(libelle: 'Ouvrir avec l’application du poste', icone: LucideIcons.externalLink, variante: VarianteBouton.secondaire, onPressed: onOuvrir),
      ]));
}

/// LE PANNEAU DU SCAN d'une fiche (courrier ou document du dossier patient) : l'état « Numérisé » DÉRIVÉ, le nom normalisé, l'empreinte, où est le fichier,
/// l'aperçu, et les gestes — déposer / remplacer, télécharger, retirer. Une commande interdite est ABSENTE (jamais grisée) : [peutDeposer] suit le droit
/// d'éditer de l'écran, [peutRetirer] celui d'annuler.
class PanneauScan extends StatefulWidget {
  const PanneauScan({super.key, required this.famille, required this.ficheId, required this.peutDeposer, required this.peutRetirer, this.peutCategorie, this.surChangement});
  final String famille;
  final Object? ficheId;
  final bool peutDeposer;
  final bool peutRetirer;
  final bool Function(String categorie)? peutCategorie;
  final VoidCallback? surChangement;
  @override
  State<PanneauScan> createState() => _PanneauScanState();
}

class _PanneauScanState extends State<PanneauScan> {
  Future<Uint8List?>? _octets;
  String? _sha;
  String? _erreurLecture;
  bool _occupe = false;

  ServiceFichiers _svc(BuildContext c) => ServiceFichiers.de(ContexteEcran.of(c).magasin);
  CollectionMagasin _col(BuildContext c) => ContexteEcran.of(c).magasin.collection(famillesDocuments[widget.famille]!.collection);

  Future<Uint8List?> _charger(Fiche f) async {
    try {
      _erreurLecture = null;
      return await _svc(context).lire(famille: widget.famille, fiche: f, peutCategorie: widget.peutCategorie);
    } catch (e) {
      _erreurLecture = e is DocErreur ? '${e.motif} ${e.geste}' : '$e';
      return null;
    }
  }

  Future<void> _deposer(Fiche f, {bool confirmer = false, ScanChoisi? choix}) async {
    final ctx = context;
    final svc = _svc(ctx);
    final ch = choix ?? await SelecteursScan.choisir(widget.famille);
    if (ch == null || !ctx.mounted) return;
    setState(() => _occupe = true);
    try {
      final r = await svc.deposer(famille: widget.famille, ficheId: widget.ficheId, nomOrigine: ch.nom, octets: ch.octets, peutCategorie: widget.peutCategorie, confirmerAilleurs: confirmer);
      if (!ctx.mounted) return;
      ToastsSigh.afficher(ctx, r.remplacement ? 'Scan remplacé : l’ancienne version est conservée.' : 'Scan déposé.',
          type: TypeToast.succes,
          detail: '${r.scan['nomNormalise']} — ${docPoids((r.scan['taille'] as num).toInt())}${r.avertissementIndexation != null ? ' — ${r.avertissementIndexation}' : ''}',
          annuler: r.annuler,
          messageAnnulation: 'Dépôt annulé — la pièce est rangée aux versions antérieures, le fichier est conservé.');
      widget.surChangement?.call();
    } on DocAvertissement catch (a) {
      if (!ctx.mounted) return;
      final ok = await confirmerSigh(ctx, titre: 'Fichier déjà rattaché ailleurs', message: '${a.motif}\nLe rattacher aussi à cette fiche ?', libelleOk: 'Rattacher quand même');
      if (ok && ctx.mounted) await _deposer(f, confirmer: true, choix: ch);
    } catch (e) {
      if (ctx.mounted) annoncerRefus(ctx, e);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _retirer(Fiche f) async {
    final ctx = context;
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Retirer ce scan de la fiche ?', message: 'La pièce quitte la fiche et passe aux versions antérieures ; le fichier reste conservé chez la mère (RG-14). L’opération est annulable.', libelleOk: 'Retirer le scan', dangereux: true);
    if (motif == null || !ctx.mounted) return;
    try {
      final annuler = _svc(ctx).retirer(famille: widget.famille, ficheId: widget.ficheId, motif: motif);
      ToastsSigh.afficher(ctx, 'Scan retiré de la fiche.', type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Retrait annulé — le scan est de nouveau sur la fiche.');
      widget.surChangement?.call();
    } catch (e) {
      annoncerRefus(ctx, e);
    }
  }

  Future<void> _telecharger(Fiche f, {Map<String, Object?>? version}) async {
    final ctx = context;
    try {
      final chemin = await _svc(ctx).telecharger(famille: widget.famille, fiche: f, version: version, peutCategorie: widget.peutCategorie);
      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Fichier enregistré sous son nom normalisé.', type: TypeToast.succes, detail: chemin);
    } catch (e) {
      if (ctx.mounted) annoncerRefus(ctx, e);
    }
  }

  Future<void> _ouvrir(Fiche f) async {
    final ctx = context;
    try {
      final ok = await _svc(ctx).ouvrir(famille: widget.famille, fiche: f, peutCategorie: widget.peutCategorie);
      if (!ok && ctx.mounted) ToastsSigh.afficher(ctx, 'Aucune application du poste n’a ouvert le fichier.', type: TypeToast.attention, detail: 'Télécharger le fichier, puis l’ouvrir depuis son dossier.');
    } catch (e) {
      if (ctx.mounted) annoncerRefus(ctx, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = _col(context);
    final svc = _svc(context);
    return ListenableBuilder(
        listenable: col,
        builder: (context, _) {
          final f = col.parId(widget.ficheId);
          if (f == null) return const SizedBox();
          final scan = docScan(f);
          if ('${scan?['sha256']}' != _sha) {
            _sha = scan == null ? null : '${scan['sha256']}';
            _octets = scan == null ? null : _charger(f);
          }
          final anterieurs = docScansAnterieurs(f);
          return Column(key: const Key('panneau-scan'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Text('Numérisé', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              scan != null ? const BadgeSigh('Oui', ton: TonSigh.succes) : const BadgeSigh('À scanner', ton: TonSigh.attention),
              if (scan != null) ...[const SizedBox(width: 8), BadgeSigh(docLibelleIndexation(f), ton: docEtatIndexation(f) == 'indexe' ? TonSigh.info : TonSigh.neutre)],
              if (scan != null) ...[const SizedBox(width: 8), BadgeSigh('Version ${scan['version']}', ton: TonSigh.navy)],
            ]),
            const SizedBox(height: 10),
            if (scan != null) ...[
              DescListeSigh([
                ('Nom normalisé', '${scan['nomNormalise']}'),
                ('Nom d’origine', '${scan['nom']}'),
                ('Poids', docPoids((scan['taille'] as num).toInt())),
                ('Empreinte SHA-256', docEmpreinteAbregee('${scan['sha256']}')),
                ('Déposé par', '${scan['deposePar'] ?? '—'}'),
                ('Déposé le', '${scan['deposeLe'] ?? '—'}'.split('T').first),
              ]),
              const SizedBox(height: 10),
              FutureBuilder<String?>(
                  future: svc.cheminDesScans(),
                  builder: (_, s) => Text(
                      s.data == null
                          ? 'Les scans sont rangés sur le poste mère (chemin non encore connu de ce poste).'
                          : 'Fichier chez la mère : ${s.data}${s.data!.contains('\\') ? '\\' : '/'}${scan['nomNormalise']}',
                      key: const Key('scan:chemin'),
                      style: const TextStyle(color: JetonsShell.slate600, fontSize: 12))),
              const SizedBox(height: 10),
              FutureBuilder<Uint8List?>(
                  future: _octets,
                  builder: (_, s) {
                    if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                    if (s.data == null) {
                      return NoteSigh(_erreurLecture ?? 'Fichier non lu.', ton: TonSigh.danger, icone: LucideIcons.triangleAlert);
                    }
                    return scan['mime'] == 'application/pdf'
                        ? ApercuPdf(scan: scan, extrait: svc.texteDe(f).split(' ').take(40).join(' '), onOuvrir: () => _ouvrir(f))
                        : VisionneuseImage(octets: s.data!);
                  }),
              const SizedBox(height: 10),
            ] else
              const NoteSigh('Aucun fichier n’est rattaché à cette fiche. « Numérisé » se coche seul dès qu’un scan est déposé.', icone: LucideIcons.scanLine),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (widget.peutDeposer)
                BoutonSigh(
                    libelle: scan == null ? 'Déposer un scan' : 'Remplacer le scan',
                    icone: LucideIcons.upload,
                    variante: scan == null ? VarianteBouton.primaire : VarianteBouton.secondaire,
                    onPressed: _occupe ? null : () => _deposer(f)),
              if (scan != null) BoutonSigh(libelle: 'Télécharger', icone: LucideIcons.download, variante: VarianteBouton.secondaire, onPressed: () => _telecharger(f)),
              if (scan != null && widget.peutRetirer) BoutonSigh(libelle: 'Retirer le scan', icone: LucideIcons.trash2, variante: VarianteBouton.secondaire, onPressed: () => _retirer(f)),
            ]),
            if (widget.peutDeposer) ...[
              const SizedBox(height: 6),
              Text('PDF, JPEG ou PNG, jusqu’à ${docPoids(svc.tailleMax())}${svc.tailleMaxValidee ? '' : ' (valeur proposée, à valider)'}. Le glisser-déposer depuis l’explorateur n’est pas disponible dans ce poste : le bouton ouvre la boîte de sélection du système.',
                  style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
            ],
            if (anterieurs.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Versions antérieures (conservées)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final v in anterieurs.reversed)
                Row(key: Key('version:${v['sha256']}'), children: [
                  Expanded(child: Text('v${v['version']} — ${v['nomNormalise']} — ${'${v['retireLe'] ?? ''}'.split('T').first} — ${v['motifRetrait'] ?? ''}', style: const TextStyle(fontSize: 12, color: JetonsShell.slate600))),
                  BoutonIcone(icone: LucideIcons.download, libelle: 'Télécharger cette version', onPressed: () => _telecharger(f, version: v)),
                ]),
            ],
          ]);
        });
  }
}
