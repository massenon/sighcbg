import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../kit/kit.dart';
import '../shell/contexte_ecran.dart';
import 'panneau_scan.dart';
import 'service_fichiers.dart';

/// « Scans numérisés » dans les paramètres système : OÙ SONT MES SCANS (le chemin sur la poste mère), ce que le dossier tient, la taille maximale réglable
/// (10 Mo proposés, « à valider »), et — sur la mère seulement — le déplacement du dossier, le contrôle des empreintes, la sauvegarde et la restauration.
/// Un fileul LIT ces informations ; il ne règle rien (les fichiers vivent chez la mère, la taille maximale est lue par la mère à chaque dépôt).
class PanneauScansPoste extends StatefulWidget {
  const PanneauScansPoste({super.key});
  @override
  State<PanneauScansPoste> createState() => _PanneauScansPosteState();
}

class _PanneauScansPosteState extends State<PanneauScansPoste> {
  Future<Map<String, Object?>?>? _info;
  bool _occupe = false;

  Future<Map<String, Object?>?> _lire(ServiceFichiers s) async {
    try {
      return await s.lireInfo?.call();
    } catch (_) {
      return null;
    }
  }

  void _rafraichir(ServiceFichiers s) {
    final f = _lire(s);
    setState(() {
      _info = f;
    });
  }

  Future<void> _tailleMax(BuildContext ctx, ServiceFichiers s) async {
    final mo = TextEditingController(text: (s.tailleMax() / 1024 / 1024).toStringAsFixed(1).replaceAll('.0', ''));
    final motif = TextEditingController();
    final erreur = ValueNotifier<String?>(null);
    await afficherModale<void>(ctx,
        titre: 'Taille maximale d’un scan',
        taille: TailleModale.sm,
        corps: ValueListenableBuilder<String?>(
            valueListenable: erreur,
            builder: (cx, err, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const LibelleChamp('Taille maximale par fichier (Mo)'),
                  TextField(key: const Key('scans:taille'), controller: mo, style: styleSaisie, decoration: decorationChamp(indicatif: 'ex. 10')),
                  const SizedBox(height: 8),
                  const LibelleChamp('Motif du changement *'),
                  TextField(key: const Key('scans:motif'), controller: motif, style: styleSaisie, decoration: decorationChamp(indicatif: 'Pourquoi cette valeur')),
                  if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: NoteSigh(err, ton: TonSigh.danger, icone: LucideIcons.triangleAlert)),
                  const SizedBox(height: 8),
                  Text('Bornes : de ${docPoids(docTaillePlancher)} à ${docPoids(docTaillePlafond)}. Le changement vaut pour les prochains dépôts ; les fichiers déjà rangés ne bougent pas.', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                ])),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  onPressed: () {
                    final n = double.tryParse(mo.text.trim().replaceAll(',', '.'));
                    final r = n == null ? const DocErreur('TAILLE_ILLISIBLE', 'La taille maximale n’est pas un nombre.', 'Saisir un nombre de mégaoctets.') : s.reglerTailleMax((n * 1024 * 1024).round(), motif.text);
                    if (r != null) {
                      erreur.value = '${r.motif} ${r.geste}';
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Taille maximale réglée à ${docPoids(s.tailleMax())}.', type: TypeToast.succes);
                    _rafraichir(s);
                  }),
            ]);
  }

  Future<void> _dossier(BuildContext ctx, ServiceFichiers s) async {
    final chemin = TextEditingController(text: await s.cheminDesScans() ?? '');
    final motif = TextEditingController();
    if (!ctx.mounted) return;
    await afficherModale<void>(ctx,
        titre: 'Changer le dossier des scans',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const LibelleChamp('Chemin du dossier sur ce poste mère *'),
          TextField(key: const Key('scans:dossier'), controller: chemin, style: styleSaisie, decoration: decorationChamp(indicatif: r'ex. D:\Scans CBG')),
          const SizedBox(height: 8),
          const LibelleChamp('Motif du changement *'),
          TextField(key: const Key('scans:dossier-motif'), controller: motif, style: styleSaisie, decoration: decorationChamp(indicatif: 'Pourquoi ce dossier')),
          const SizedBox(height: 8),
          const NoteSigh('Tous les fichiers sont COPIÉS dans le nouveau dossier, chacun relu et comparé à son empreinte. L’ancien dossier n’est pas vidé (RG-14) : à l’administrateur de l’archiver.'),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Déplacer le dossier',
                  onPressed: () async {
                    fermer();
                    await _lancer(ctx, () async {
                      final r = await s.reglerDossier(chemin.text, motif.text);
                      if (ctx.mounted) ToastsSigh.afficher(ctx, 'Dossier des scans déplacé.', type: TypeToast.succes, detail: '${r['copies']} fichier(s) copié(s) vers ${r['nouveau']}. Ancien dossier conservé : ${r['ancien']}.');
                    }, s);
                  }),
            ]);
  }

  Future<void> _lancer(BuildContext ctx, Future<void> Function() f, ServiceFichiers s) async {
    setState(() => _occupe = true);
    try {
      await f();
    } catch (e) {
      if (ctx.mounted) annoncerRefus(ctx, e);
    } finally {
      if (mounted) {
        _occupe = false;
        _rafraichir(s);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final s = ServiceFichiers.de(c.magasin);
    _info ??= _lire(s);
    return FutureBuilder<Map<String, Object?>?>(
        future: _info,
        builder: (ctx, snap) {
          final info = snap.data;
          final chemin = info?['dossier'];
          final peutRegler = c.droit.editer && s.estMere;
          return Column(key: const Key('panneau-scans-poste'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(titre: 'Où sont mes scans ?', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(chemin is String ? chemin : (snap.connectionState != ConnectionState.done ? '…' : 'Chemin non connu : la mère ne répond pas ou ce poste n’est pas rattaché.'), key: const Key('scans:chemin-mere'), style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 14)),
              const SizedBox(height: 6),
              Text(s.estMere ? 'Ce poste est la mère : le dossier est local. Les fichiers y portent leur nom normalisé (ex. 2026-11-11_ARR_0042.pdf).' : 'Les fichiers vivent sur le poste mère, jamais sur ce poste ni sur le relais : un poste fileul les lit chez la mère, par le canal de synchronisation chiffré.', style: const TextStyle(color: JetonsShell.slate600, fontSize: 12)),
              if (info != null) ...[
                const SizedBox(height: 8),
                Text('${info['fichiers']} fichier(s), ${docPoids((info['octets'] as num?)?.toInt() ?? 0)}.', style: const TextStyle(fontSize: 12)),
              ],
            ])),
            const SizedBox(height: 12),
            CarteSigh(titre: 'Taille maximale d’un scan', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(docPoids(s.tailleMax()), key: const Key('scans:taille-max'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              Text(s.tailleMaxValidee ? 'Valeur réglée par la clinique (journalisée).' : 'Valeur proposée (10 Mo), à valider par la Direction.', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
              const SizedBox(height: 8),
              if (peutRegler) BoutonSigh(libelle: 'Régler la taille maximale', icone: LucideIcons.slidersHorizontal, variante: VarianteBouton.secondaire, onPressed: () => _tailleMax(ctx, s))
              else const Text('Se règle sur le poste mère (la mère lit ce réglage à chaque dépôt).', style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
            ])),
            const SizedBox(height: 12),
            CarteSigh(titre: 'Intégrité, sauvegarde et restauration', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Chaque fiche porte l’empreinte SHA-256 de son fichier, recalculée à chaque dépôt et à chaque lecture. Conservation illimitée : rien ne se purge, rien ne se supprime (RG-14).', style: TextStyle(fontSize: 12, color: JetonsShell.slate600)),
              const SizedBox(height: 6),
              const NoteSigh('La sauvegarde chiffrée de la base emporte une copie vérifiée du dossier des scans (sous « sauvegardes/scans » de la mère). Cette copie est en clair, comme le dossier : la ranger sur un support protégé.', ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
              const SizedBox(height: 10),
              if (peutRegler)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  BoutonSigh(libelle: 'Contrôler les fichiers', icone: LucideIcons.shieldCheck, variante: VarianteBouton.secondaire, onPressed: _occupe ? null : () => _lancer(ctx, () async {
                        final r = await s.controlerMere!();
                        if (ctx.mounted) ToastsSigh.afficher(ctx, r['complet'] == true ? 'Tous les fichiers relisent à l’identique.' : 'Des fichiers sont altérés ou manquants.', type: r['complet'] == true ? TypeToast.succes : TypeToast.erreur, detail: '${r['verifies']} vérifié(s), altérés : ${(r['alteres'] as List).join(', ')}, manquants : ${(r['manquants'] as List).join(', ')}');
                      }, s)),
                  BoutonSigh(libelle: 'Sauvegarder les scans maintenant', icone: LucideIcons.databaseBackup, variante: VarianteBouton.secondaire, onPressed: _occupe ? null : () => _lancer(ctx, () async {
                        final r = await s.sauvegarderMere!('');
                        if (ctx.mounted) ToastsSigh.afficher(ctx, 'Sauvegarde des scans faite.', type: TypeToast.succes, detail: '${r['copies']} copié(s), ${r['inchanges']} inchangé(s) vers ${r['destination']}.');
                      }, s)),
                  BoutonSigh(libelle: 'Changer le dossier', icone: LucideIcons.folderInput, variante: VarianteBouton.secondaire, onPressed: _occupe ? null : () => _dossier(ctx, s)),
                ]),
            ])),
          ]);
        });
  }
}
