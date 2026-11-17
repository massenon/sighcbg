import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import '../../sync/service_validations_deposees.dart';

/// Le sélecteur de fichier de cet écran, INJECTABLE : aucun test ne dépend d'une boîte de dialogue native.
class SelecteurLiasse {
  SelecteurLiasse._();
  static Future<String?> Function() fichier = _natif;
  static void reinitialiser() => fichier = _natif;

  static Future<String?> _natif() async {
    final f = await FilePicker.pickFile(dialogTitle: 'Liasse ou classeur à importer (JSON)', type: FileType.custom, allowedExtensions: const ['json']);
    return f?.path;
  }
}

/// `m12-liasse-import` — « Import de la liasse fiscale » : poser une VERSION DATÉE (source, date de dépôt, auteur) de la liasse déposée à la DGI ou du classeur de baseline, voir les versions
/// importées, en archiver une.
///
/// Placement : la COMPTABILITÉ (M12), pas la configuration. Les documents importés sont lus par les états financiers, le compte de résultat, le tableau des flux et la baseline de M12 ; ceux qui les
/// importent (le comptable et la DAF) ont M12 et n'ont pas forcément la configuration (réservée à l'administrateur, à la DAF et à la Direction). L'écran dit où est le document, il n'invente rien.
///
/// Le droit est un GESTE RÉSERVÉ de la fiche de rôle (`documents_fiscaux_importer` : comptable et DAF d'origine, réglable), jamais une liste de rôles ; une commande interdite est ABSENTE. La collection
/// `documentsFiscaux` est un référentiel de la MÈRE (famille R : la mère seule l'écrit, jamais vers un téléphone). IMPORTER DEPUIS UN POSTE RATTACHÉ (18/11/2026) : le fileul vérifie le document ICI avec
/// le validateur strict, puis DÉPOSE la demande d'import (circuit des validations déposées, genre `liasse_importer`) ; la mère REJOUE la validation stricte, applique sous le geste réservé du compte
/// signataire et renvoie un verdict nommé ; la version revient par la synchronisation. La taille du document est bornée par un réglage de la clinique. L'archivage d'une version reste à la mère.
class EcranLiasseImport extends StatefulWidget with EcranMaquette {
  const EcranLiasseImport({super.key});
  @override
  String get titre => 'Import de la liasse fiscale';
  @override
  String get description => 'Importer la liasse déposée et le classeur de baseline en versions datées (source, date de dépôt, auteur), voir les versions et celle qui fait foi.';
  @override
  String get regle =>
      'Rien n’est inventé ni recalculé : le document est cité tel que déposé, avec ses propres écarts. Une version nouvelle s’ajoute, la plus récente fait foi, une version se retire par archivage motivé '
      '(jamais supprimée, RG-14). Le journal d’audit garde l’identité, la source et des nombres de lignes, jamais un montant.';

  @override
  State<EcranLiasseImport> createState() => _EtatLiasseImport();
}

String _jour(Object? v) {
  final s = '${v ?? ''}';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  return m == null ? (s.isEmpty ? '—' : s) : '${m.group(3)}/${m.group(2)}/${m.group(1)}';
}

class _EtatLiasseImport extends State<EcranLiasseImport> {
  final _chemin = TextEditingController();
  final _date = TextEditingController();
  final _source = TextEditingController();
  final _motif = TextEditingController();
  DocumentFiscalLu? _lu;
  RefusImportFiscal? _refus;
  String? _confirmation;
  String? _aArchiver;

  @override
  void dispose() {
    _chemin.dispose();
    _date.dispose();
    _source.dispose();
    _motif.dispose();
    super.dispose();
  }

  Widget _champ(String libelle, TextEditingController ctl, Key cle, {String? indice}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(libelle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
        const SizedBox(height: 4),
        TextField(key: cle, controller: ctl, style: styleSaisie, decoration: decorationChamp(indicatif: indice ?? libelle)),
      ]);

  /// Lit et valide le fichier choisi : rien n'est écrit.
  void _verifier() {
    setState(() {
      _lu = null;
      _refus = null;
      _confirmation = null;
    });
    final chemin = _chemin.text.trim();
    if (chemin.isEmpty) {
      setState(() => _refus = const RefusImportFiscal('FICHIER_ABSENT', 'Aucun fichier choisi.', 'Choisir le document à importer.'));
      return;
    }
    String texte;
    try {
      texte = File(chemin).readAsStringSync();
    } on FileSystemException catch (e) {
      setState(() => _refus = RefusImportFiscal('FICHIER_ILLISIBLE', 'Le fichier ne peut pas être lu (${e.message}).', 'Vérifier le chemin et les droits du dossier.'));
      return;
    }
    final v = lireDocumentFiscal(texte);
    setState(() {
      _refus = v.refus;
      _lu = v.document;
      final d = v.document;
      if (d != null) {
        // Une liasse porte sa propre date de dépôt et sa source : proposées, jamais imposées (la source se corrige, la date ne peut pas contredire celle du document).
        _date.text = d.dateDepotPortee ?? '';
        _source.text = d.sourcePortee ?? '';
      }
    });
  }

  void _importer(ContexteEcran c) {
    final col = c.magasin.collection(colDocumentsFiscaux);
    if (ServiceInstallation.de(c.magasin).rattache) {
      // Un poste rattaché DÉPOSE la demande : la mère rejoue la validation stricte et écrit ; la version revient par la synchronisation.
      final d = ServiceValidationsDeposees.de(c.magasin).deposerLiasse(
          document: _lu!,
          dateDepot: _date.text.trim().isEmpty ? null : _date.text.trim(),
          source: _source.text,
          auteur: acteur(c).nom,
          role: c.role,
          gestes: droitsGestesEcran(c));
      if (!d.ok) {
        setState(() {
          _refus = RefusImportFiscal(d.refus!.code, d.refus!.motif, d.refus!.geste ?? '');
          _confirmation = null;
        });
        return;
      }
      final f = d.fiche!;
      ToastsSigh.afficher(context, d.dejaDepose ? 'Demande déjà transmise.' : 'Demande d’import transmise à la mère.', type: TypeToast.succes, detail: 'Rien n’est importé avant sa confirmation.');
      setState(() {
        _confirmation = '${f['documentGenre'] == docFiscalLiasse ? 'Liasse' : 'Classeur'} de l’exercice ${f['exercice']} (dépôt du ${_jour(f['dateDepot'])}) : demande d’import transmise à la mère, en attente. '
            'Elle rejoue la vérification stricte, applique sous votre nom si votre geste le permet, et vous répond dans le tableau ci-dessous ; la version arrive ensuite par la synchronisation.';
        _lu = null;
        _refus = null;
        _chemin.clear();
        _date.clear();
        _source.clear();
      });
      return;
    }
    final v = preparerImportFiscal(
        document: _lu!,
        dateDepot: _date.text.trim().isEmpty ? null : _date.text.trim(),
        source: _source.text,
        auteur: acteur(c).nom,
        maintenant: c.aujourdhui,
        existantes: col.toutes,
        peutImporter: gestePeutEcran(c, gesteDocumentsFiscauxImporter));
    if (!v.accepte) {
      setState(() {
        _refus = v.refus;
        _confirmation = null;
      });
      return;
    }
    final fiche = v.fiche!;
    try {
      col.inserer(fiche);
    } on EcritureRefusee catch (e) {
      setState(() => _refus = RefusImportFiscal('ECRITURE_REFUSEE', e.motif, 'Voir le journal d’audit.'));
      return;
    }
    // RG-12 : le journal dit QUI a importé QUOI (identité, source, nombres de lignes) — jamais le contenu comptable.
    c.magasin.journaliser('Import', 'M12', 'Document fiscal', '${fiche['id']}', null, docFiscalResumeJournal(fiche));
    ToastsSigh.afficher(context, 'Document fiscal importé.', type: TypeToast.succes, detail: '${fiche['genre'] == docFiscalLiasse ? 'Liasse' : 'Classeur'} ${fiche['exercice']}, déposé le ${_jour(fiche['dateEffet'])}.');
    setState(() {
      _confirmation = '${fiche['genre'] == docFiscalLiasse ? 'Liasse' : 'Classeur'} de l’exercice ${fiche['exercice']} importé (dépôt du ${_jour(fiche['dateEffet'])}, source « ${fiche['source']} »). '
          'Version « ${fiche['id']} ».';
      _lu = null;
      _refus = null;
      _chemin.clear();
      _date.clear();
      _source.clear();
    });
  }

  void _archiver(ContexteEcran c) {
    final col = c.magasin.collection(colDocumentsFiscaux);
    final fiche = col.parId(_aArchiver);
    final p = preparerArchivageFiscal(
        fiche: fiche,
        motif: _motif.text,
        auteur: acteur(c).nom,
        maintenant: c.aujourdhui,
        peutImporter: gestePeutEcran(c, gesteDocumentsFiscauxImporter),
        estFileul: ServiceInstallation.de(c.magasin).rattache);
    if (p.refus != null) {
      setState(() => _refus = p.refus);
      return;
    }
    col.mettreAJour(_aArchiver, p.patch!, journaliser: false);
    c.magasin.journaliser('Archivage', 'M12', 'Document fiscal', '$_aArchiver', {'statut': fiche!['statut']}, {'statut': 'archive', 'motif': _motif.text.trim(), ...docFiscalResumeJournal(fiche)});
    ToastsSigh.afficher(context, 'Version archivée.', type: TypeToast.succes, detail: 'Elle reste lisible dans la liste ; la précédente fait foi si elle était la plus récente.');
    setState(() {
      _confirmation = 'Version « $_aArchiver » archivée (jamais supprimée).';
      _aArchiver = null;
      _refus = null;
      _motif.clear();
    });
  }

  Widget _blocRefus() {
    final r = _refus;
    if (r == null) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: NoteSigh(r.message, key: const Key('liasse:refus'), ton: TonSigh.danger, icone: LucideIcons.ban));
  }

  /// Ce qui fait foi pour un genre, ou « aucune importée » : jamais un zéro qui se lirait comme un solde.
  Widget _enForce(String genre, String quoi, List<VersionFiscale> versions) {
    final f = versions.where((v) => v.etat == versionFiscaleEnForce).firstOrNull?.fiche;
    if (f == null) {
      return NoteSigh('Aucune $quoi n’est importée : les écrans qui la lisent le disent et n’inventent aucun chiffre. Importer un document ci-dessous (geste réservé), sur le poste mère.',
          key: Key('liasse:aucune-$genre'), ton: TonSigh.attention, icone: LucideIcons.triangleAlert);
    }
    final demo = ((f['contenu'] as Map?)?['DEPOT'] as Map?)?['demonstration'];
    final estDemo = f['demonstration'] == true || ('${demo ?? ''}'.isNotEmpty);
    return NoteSigh(
        'En force : exercice ${f['exercice']}, déposée le ${_jour(f['dateEffet'])}, source « ${f['source']} », importée par ${f['importePar']} le ${_jour(f['importeLe'])}.'
        '${estDemo ? ' $cpbMentionDemonstration' : ''}',
        key: Key('liasse:en-force-$genre'),
        ton: estDemo ? TonSigh.attention : TonSigh.succes,
        icone: estDemo ? LucideIcons.triangleAlert : LucideIcons.circleCheck);
  }

  /// Les demandes d'import transmises à la mère : en attente, appliquée (avec la référence de la version écrite) ou refusée avec son motif NOMMÉ. Jamais le contenu du document.
  Widget _demandes(List<Map<String, Object?>> demandes) {
    return MiniTableauSigh(colonnes: [
      ColonneMini('Demande', (f) => '${f['libelle']}'),
      ColonneMini('Déposée par', (f) => '${f['demandePar']} · ${_jour(f['demandeLe'])}'),
      ColonneMini('État', (f) => '', rendu: (f) {
        final id = '${f['id']}';
        return switch ('${f['etat']}') {
          'appliquee' => BadgeSigh('Appliquée par la mère${f['resultatReference'] == null ? '' : ' (${f['resultatReference']})'}', key: Key('liasse:demande:$id'), ton: TonSigh.succes, icone: LucideIcons.circleCheck),
          'sans_effet' => BadgeSigh('Déjà faite', key: Key('liasse:demande:$id'), ton: TonSigh.neutre),
          'refusee' => BadgeSigh('Refusée par la mère', key: Key('liasse:demande:$id'), ton: TonSigh.danger, icone: LucideIcons.ban),
          _ => BadgeSigh('Transmise à la mère, en attente', key: Key('liasse:demande:$id'), ton: TonSigh.info, icone: LucideIcons.send),
        };
      }),
      ColonneMini('Verdict', (f) => '', rendu: (f) {
        if (f['etat'] != 'refusee' && f['etat'] != 'sans_effet') return const SizedBox.shrink();
        return Text(refusFiscalPhrase('${f['resultatCode']}', '${f['resultatMotif'] ?? ''}', '${f['resultatGeste'] ?? ''}'),
            key: Key('liasse:verdict:${f['id']}'), style: const TextStyle(fontSize: 12, color: JetonsShell.slate600));
      }),
    ], lignes: demandes);
  }

  Widget _tableau(ContexteEcran c, String genre, List<VersionFiscale> versions, bool peutArchiver) {
    return MiniTableauSigh(
        vide: genre == docFiscalLiasse ? 'Aucune version de la liasse importée.' : 'Aucune version du classeur importée.',
        colonnes: [
          ColonneMini('État', (f) => '', rendu: (f) {
            final v = versions.firstWhere((x) => x.id == '${f['id']}');
            return switch (v.etat) {
              versionFiscaleEnForce => const BadgeSigh('Fait foi', ton: TonSigh.succes, icone: LucideIcons.circleCheck),
              versionFiscaleArchivee => const BadgeSigh('Archivée', ton: TonSigh.neutre, icone: LucideIcons.archive),
              _ => const BadgeSigh('Antérieure', ton: TonSigh.info),
            };
          }),
          ColonneMini('Exercice', (f) => '${f['exercice']}'),
          ColonneMini('Dépôt', (f) => _jour(f['dateEffet'])),
          ColonneMini('Source', (f) => '${f['source']}'),
          ColonneMini('Importée par', (f) => '${f['importePar']} · ${_jour(f['importeLe'])}'),
          ColonneMini('Archivage', (f) => f['statut'] == 'archive' ? '${f['archivePar']} · ${_jour(f['archiveLe'])} · ${f['motifArchivage']}' : '', rendu: (f) {
            if (f['statut'] == 'archive') return Text('${f['archivePar']} · ${_jour(f['archiveLe'])} — ${f['motifArchivage']}', style: const TextStyle(fontSize: 12, color: JetonsShell.slate600));
            if (!peutArchiver) return const SizedBox.shrink();
            return BoutonSigh(
                key: Key('liasse:archiver:${f['id']}'),
                libelle: 'Archiver',
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                icone: LucideIcons.archive,
                onPressed: () => setState(() {
                      _aArchiver = '${f['id']}';
                      _refus = null;
                    }));
          }),
        ],
        lignes: [for (final v in versions) v.fiche]);
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection(colDocumentsFiscaux);
    final fileul = ServiceInstallation.de(c.magasin).rattache;
    final peut = gestePeutEcran(c, gesteDocumentsFiscauxImporter);
    final peutArchiver = peut && !fileul;
    final service = ServiceValidationsDeposees.de(c.magasin);
    return ListenableBuilder(
      listenable: Listenable.merge([col, c.magasin.collection(valCollectionDepots)]),
      builder: (context, _) {
        final fiches = col.toutes;
        final liasses = versionsFiscales(fiches, docFiscalLiasse);
        final classeurs = versionsFiscales(fiches, docFiscalClasseur);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (fileul && peut)
            NoteSigh(
                'Poste rattaché : vous pouvez importer. Le document est vérifié ICI (validateur strict), puis TRANSMIS à la mère, qui rejoue la vérification, applique sous votre nom si votre geste le permet et vous répond '
                'dans « Demandes d’import transmises » ; la version arrive ensuite par la synchronisation. Un document ne peut pas dépasser ${service.tailleMaxDepotFiscalKo} Ko (réglage de la clinique). L’archivage d’une version se fait sur la mère.',
                key: const Key('liasse:fileul'),
                ton: TonSigh.info,
                icone: LucideIcons.send)
          else if (!peut)
            const NoteSigh('Lecture seule : importer ou archiver une version est le geste réservé « Importer ou archiver la liasse fiscale déposée et le classeur de baseline » (comptable et DAF d’origine, réglable dans « Rôles et permissions › Gestes réservés »).',
                key: Key('liasse:lecture'), ton: TonSigh.info, icone: LucideIcons.lock),
          if ((fileul && peut) || !peut) const SizedBox(height: 12),
          CarteSigh(titre: 'Ce qui fait foi', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _enForce(docFiscalLiasse, 'liasse déposée', liasses),
            const SizedBox(height: 8),
            _enForce(docFiscalClasseur, 'classeur de baseline', classeurs),
          ])),
          if (peut) ...[
            const SizedBox(height: 16),
            CarteSigh(
              titre: 'Importer un document',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                    'Le fichier est un document JSON au schéma des documents d’import (liasse : en-tête « DEPOT », bilan, compte de résultat, flux, notes 11 et 34, écarts ; classeur : douze mois, postes de dépense, contrôle). '
                    'Il est vérifié sans rien écrire : une clé inconnue, un type faux ou un total qui ne se recoupe pas est refusé, nommément, avec l’endroit fautif.',
                    style: TextStyle(fontSize: 13, color: JetonsShell.slate600)),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: _champ('Fichier (JSON)', _chemin, const Key('liasse:fichier'))),
                  const SizedBox(width: 8),
                  BoutonSigh(
                      libelle: 'Parcourir',
                      variante: VarianteBouton.secondaire,
                      onPressed: () async {
                        final f = await SelecteurLiasse.fichier();
                        if (f != null) setState(() => _chemin.text = f);
                      }),
                ]),
                const SizedBox(height: 12),
                BoutonSigh(key: const Key('liasse:verifier'), libelle: 'Vérifier le fichier (sans rien écrire)', icone: LucideIcons.shieldCheck, variante: VarianteBouton.secondaire, onPressed: _verifier),
                if (_lu != null) ...[
                  const SizedBox(height: 12),
                  NoteSigh(
                      'Fichier accepté : ${_lu!.genre == docFiscalLiasse ? 'liasse' : 'classeur'} de l’exercice ${_lu!.exercice}. Lignes : '
                      '${docFiscalNombresDeLignes(_lu!.contenu).entries.map((e) => '${e.key} ${e.value}').join(', ')}.'
                      '${_lu!.estDemonstration ? ' $cpbMentionDemonstration' : ''}',
                      key: const Key('liasse:resume'),
                      ton: _lu!.estDemonstration ? TonSigh.attention : TonSigh.succes,
                      icone: LucideIcons.circleCheck),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _champ('Date de dépôt (AAAA-MM-JJ)', _date, const Key('liasse:date'), indice: 'AAAA-MM-JJ')),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _champ('Source (d’où vient le document)', _source, const Key('liasse:source'), indice: 'Ex. liasse remise à la DGI le …')),
                  ]),
                  const SizedBox(height: 4),
                  Text('Auteur de l’import : ${acteur(c).nom} (écrit au journal).', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
                  const SizedBox(height: 12),
                  BoutonSigh(key: const Key('liasse:importer'), libelle: 'Importer ce document', icone: LucideIcons.upload, onPressed: () => _importer(c)),
                ],
              ]),
            ),
          ],
          _blocRefus(),
          if (_confirmation != null) Padding(padding: const EdgeInsets.only(top: 12), child: NoteSigh(_confirmation!, key: const Key('liasse:ok'), ton: TonSigh.succes, icone: LucideIcons.circleCheck)),
          if (service.depotsLiasse().isNotEmpty) ...[
            const SizedBox(height: 16),
            CarteSigh(titre: 'Demandes d’import transmises', sansRemplissage: true, child: _demandes(service.depotsLiasse())),
          ],
          const SizedBox(height: 16),
          CarteSigh(titre: 'Versions de la liasse déposée', sansRemplissage: true, child: _tableau(c, docFiscalLiasse, liasses, peutArchiver)),
          const SizedBox(height: 16),
          CarteSigh(titre: 'Versions du classeur de baseline', sansRemplissage: true, child: _tableau(c, docFiscalClasseur, classeurs, peutArchiver)),
          if (_aArchiver != null && peutArchiver) ...[
            const SizedBox(height: 16),
            CarteSigh(
              titre: 'Archiver la version « $_aArchiver »',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Une version archivée ne fait plus foi mais reste lisible dans la liste : rien n’est supprimé. Si elle était la plus récente, la précédente reprend.', style: TextStyle(fontSize: 13, color: JetonsShell.slate600)),
                const SizedBox(height: 8),
                _champ('Motif de l’archivage (obligatoire)', _motif, const Key('liasse:motif')),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  BoutonSigh(key: const Key('liasse:archiver-ok'), libelle: 'Confirmer l’archivage', icone: LucideIcons.archive, variante: VarianteBouton.danger, onPressed: () => _archiver(c)),
                  BoutonSigh(libelle: 'Renoncer', variante: VarianteBouton.secondaire, onPressed: () => setState(() => _aArchiver = null)),
                ]),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}
