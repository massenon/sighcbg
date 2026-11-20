import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/base_portable_poste.dart';
import '../../donnees/maj_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';

/// LES DEUX SÉLECTEURS de cet écran, INJECTABLES : aucun test ne dépend d'une boîte de dialogue native.
class SelecteursBase {
  SelecteursBase._();
  static Future<String?> Function() fichier = _fichierNatif;
  static Future<String?> Function() dossier = _dossierNatif;
  static void reinitialiser() {
    fichier = _fichierNatif;
    dossier = _dossierNatif;
  }

  static Future<String?> _fichierNatif() async {
    final f = await FilePicker.pickFile(dialogTitle: 'Export de la base à importer', type: FileType.custom, allowedExtensions: const ['sghx']);
    return f?.path;
  }

  static Future<String?> _dossierNatif() => fs.getDirectoryPath(confirmButtonText: 'Choisir ce dossier');
}

String _dateHeure(DateTime d) {
  final l = d.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(l.day)}/${p(l.month)}/${l.year} ${p(l.hour)}:${p(l.minute)}';
}

Widget _champ(String libelle, TextEditingController ctl, Key cle, {bool secret = false, String? indice}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(libelle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
      const SizedBox(height: 4),
      TextField(key: cle, controller: ctl, obscureText: secret, style: styleSaisie, decoration: decorationChamp(indicatif: indice ?? libelle)),
    ]);

/// `cfg-base-portable` : l'EXPORT COMPLET de la base en UN fichier chiffré, son RÉIMPORT dans un magasin NEUF, et la PRÉPARATION d'une mise à jour. Sur la mère comme sur un fileul (décision 12 de
/// la Direction de Baguidi, 17/11/2026). Exporter et importer sont des GESTES RÉSERVÉS de la fiche de rôle ; une commande interdite est ABSENTE, jamais grisée.
class EcranBasePortable extends StatefulWidget with EcranMaquette {
  const EcranBasePortable({super.key});
  @override
  String get titre => 'Export, import et mise à jour';
  @override
  String get description => 'Exporter la base complète en un fichier chiffré, l’importer dans un magasin neuf, préparer une mise à jour avec une sauvegarde vérifiée.';
  @override
  String get regle =>
      'Le fichier d’export est chiffré par la clé de la clinique et ne contient ni cette clé ni les mots de passe. Un import n’écrit jamais sur la base en service : il écrit dans un magasin neuf, '
      'dont la mise en service est un second geste, tracé. La mère reste l’autorité : un fileul qui importe se resynchronise ensuite avec elle.';

  @override
  State<EcranBasePortable> createState() => _EtatBasePortable();
}

class _EtatBasePortable extends State<EcranBasePortable> {
  final _destination = TextEditingController();
  final _fichier = TextEditingController();
  final _motif = TextEditingController();
  bool _occupe = false;
  RapportExportPoste? _export;
  ManifesteExport? _verifie;
  RapportImportPoste? _import;
  ErreurExport? _erreur;
  String? _miseEnService;

  @override
  void dispose() {
    _destination.dispose();
    _fichier.dispose();
    _motif.dispose();
    super.dispose();
  }

  Future<void> _faire(Future<void> Function() f) async {
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    try {
      await f();
    } on ErreurExport catch (e) {
      _erreur = e;
    } on ErreurSchemaDonnees catch (e) {
      _erreur = ErreurExport(e.refus);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Widget _blocErreur() {
    final e = _erreur;
    if (e == null) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: NoteSigh('${e.refus.code} : ${e.refus.motif}. ${e.refus.geste}', key: const Key('base:erreur'), ton: TonSigh.danger, icone: LucideIcons.ban));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final svc = ServiceBasePortable.de(c.magasin);
    if (svc == null) {
      return const NoteSigh('Le service d’export et d’import n’est pas disponible sur ce poste.', ton: TonSigh.attention, icone: LucideIcons.triangleAlert);
    }
    final peutExporter = gestePeutEcran(c, gesteBaseExporter);
    final peutImporter = gestePeutEcran(c, gesteBaseImporter);
    if (_destination.text.isEmpty) _destination.text = '${svc.dossierDonnees}${Platform.pathSeparator}exports';
    final sync = svc.role() == epRoleFileul ? 'la file des saisies non encore confirmées par la mère, vos plages de numéros et l’étiquette du poste' : 'le journal de synchronisation de la clinique (opérations, fiches confirmées, appareils, plages)';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
        titre: 'Exporter la base complète',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Un fichier unique : manifeste lisible sans clé (version du logiciel et du schéma, date, clinique, compteurs par ensemble, empreinte) et contenu compressé, chiffré par la clé de la clinique. '
              'Il contient toutes les collections de ce poste (archivées comprises) et $sync.',
              style: const TextStyle(fontSize: 13, color: JetonsShell.slate600)),
          const SizedBox(height: 8),
          Text('Ne voyage jamais : la clé de la clinique ; ${epCollectionsExclues.entries.map((e) => '« ${e.key} » (${e.value})').join(' ; ')} ; les codes d’appairage non utilisés.',
              key: const Key('base:exclusions'), style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
          if (peutExporter) ...[
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _champ('Dossier de destination', _destination, const Key('base:destination'))),
              const SizedBox(width: 8),
              BoutonSigh(
                  libelle: 'Parcourir',
                  variante: VarianteBouton.secondaire,
                  onPressed: () async {
                    final d = await SelecteursBase.dossier();
                    if (d != null) setState(() => _destination.text = d);
                  }),
            ]),
            const SizedBox(height: 12),
            BoutonSigh(
                key: const Key('base:exporter'),
                libelle: 'Exporter la base complète',
                icone: LucideIcons.download,
                onPressed: _occupe ? null : () => _faire(() async => _export = await svc.exporter(dossierDestination: _destination.text.trim()))),
          ],
          if (_export != null) ...[
            const SizedBox(height: 12),
            NoteSigh(
                'Export écrit : ${_export!.chemin}. ${epResume(_export!.manifeste)}. ${_export!.verifie ? 'Relu et vérifié (déchiffrement et empreinte contrôlés).' : 'ATTENTION : le fichier n’a pas pu être relu, il n’est pas vérifié.'}',
                key: const Key('base:export-ok'),
                ton: _export!.verifie ? TonSigh.succes : TonSigh.danger,
                icone: _export!.verifie ? LucideIcons.circleCheck : LucideIcons.triangleAlert),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      if (peutImporter)
        CarteSigh(
          titre: 'Importer une base',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
                'Contrôles dans l’ordre : format, version des données, clinique, rôle de la source, puis clé, déchiffrement et empreinte. L’import écrit dans un magasin NEUF ; un fileul rattaché copie d’abord son '
                'magasin actuel et vérifie cette copie. La base en service n’est remplacée que par la mise en service, au prochain démarrage.',
                style: TextStyle(fontSize: 13, color: JetonsShell.slate600)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _champ('Fichier d’export (.sghx)', _fichier, const Key('base:fichier'))),
              const SizedBox(width: 8),
              BoutonSigh(
                  libelle: 'Parcourir',
                  variante: VarianteBouton.secondaire,
                  onPressed: () async {
                    final f = await SelecteursBase.fichier();
                    if (f != null) setState(() => _fichier.text = f);
                  }),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              BoutonSigh(
                  key: const Key('base:verifier'),
                  libelle: 'Vérifier le fichier (sans rien écrire)',
                  icone: LucideIcons.shieldCheck,
                  variante: VarianteBouton.secondaire,
                  onPressed: _occupe ? null : () => _faire(() async => _verifie = await svc.verifierFichier(_fichier.text.trim()))),
              BoutonSigh(
                  key: const Key('base:importer'),
                  libelle: 'Importer dans un magasin neuf',
                  icone: LucideIcons.upload,
                  onPressed: _occupe ? null : () => _faire(() async => _import = await svc.importer(chemin: _fichier.text.trim()))),
            ]),
            if (_verifie != null) ...[
              const SizedBox(height: 12),
              NoteSigh('Fichier vérifié : ${epResume(_verifie!)}.', key: const Key('base:verifie'), ton: TonSigh.succes, icone: LucideIcons.circleCheck),
            ],
            if (_import != null) ..._rapportImport(svc, _import!),
          ]),
        ),
      _blocErreur(),
      const SizedBox(height: 16),
      const CartePreparerMaj(),
    ]);
  }

  List<Widget> _rapportImport(ServiceBasePortable svc, RapportImportPoste r) {
    return [
      const SizedBox(height: 12),
      NoteSigh(
          'Base importée dans ${r.dossierNeuf} (${r.fiches} fiche(s), schéma ${r.manifeste.schema}, migrations jouées : ${r.migrations.isEmpty ? 'aucune' : r.migrations.join(', ')}). '
          '${r.mode == ModeImport.resynchronisation ? 'Export de la mère : point de départ de resynchronisation, la mère reste l’autorité et renverra ce qu’elle a validé. ' : ''}'
          '${r.copiePrealable != null ? 'Copie préalable vérifiée du magasin remplacé : ${r.copiePrealable}. ' : ''}'
          '${r.fileReprise > 0 ? '${r.fileReprise} saisie(s) en file reprise(s) à la mise en service. ' : ''}'
          'La base en service n’a pas été touchée.',
          key: const Key('base:import-ok'),
          ton: TonSigh.succes,
          icone: LucideIcons.circleCheck),
      if (r.avertissement != null) ...[
        const SizedBox(height: 8),
        NoteSigh(r.avertissement!.message, key: const Key('base:avertissement'), ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
        for (final s in r.avertissement!.saisies) Text('  ${s.type} ${s.collection} ${s.fiche} (${_dateHeure(s.quand)})', style: const TextStyle(fontSize: 12, color: JetonsShell.slate600)),
      ],
      if (r.fileNonReprise.isNotEmpty) ...[
        const SizedBox(height: 8),
        NoteSigh('${r.fileNonReprise.length} saisie(s) du fichier ne sont PAS reprises (ce poste n’est pas neuf : sa propre file est gardée telle quelle) ; elles restent dans le fichier d’export.',
            key: const Key('base:non-reprise'), ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
      ],
      const SizedBox(height: 12),
      _champ('Motif de la mise en service (au journal)', _motif, const Key('base:motif')),
      const SizedBox(height: 8),
      BoutonSigh(
          key: const Key('base:mise-en-service'),
          libelle: 'Programmer la mise en service',
          icone: LucideIcons.rotateCcw,
          variante: VarianteBouton.danger,
          onPressed: _occupe
              ? null
              : () => _faire(() async {
                    await svc.programmerMiseEnService(dossierNeuf: r.dossierNeuf, motif: _motif.text);
                    _miseEnService = 'Mise en service programmée : au prochain démarrage du poste, l’ancien magasin sera renommé (jamais supprimé) et la base importée prendra sa place. Redémarrez le poste.';
                  })),
      if (_miseEnService != null) ...[
        const SizedBox(height: 8),
        NoteSigh(_miseEnService!, key: const Key('base:mise-en-service-ok'), ton: TonSigh.attention, icone: LucideIcons.rotateCcw),
      ],
    ];
  }
}

/// La CARTE « Préparer la mise à jour » : posée sur `cfg-base-portable` ET sur l'écran de la mère « Mises à jour et compatibilité ». Elle montre N (réglage), l'état de la sauvegarde et de
/// l'export, le blocage nommé, et porte les deux commandes : préparer (geste `base_exporter`) et lever le blocage (geste `maj_lever_blocage`, motif obligatoire).
class CartePreparerMaj extends StatefulWidget {
  const CartePreparerMaj({super.key});
  @override
  State<CartePreparerMaj> createState() => _EtatCarteMaj();
}

class _EtatCarteMaj extends State<CartePreparerMaj> {
  final _motif = TextEditingController();
  bool _occupe = false;
  ErreurExport? _erreur;
  VerdictMaj? _dernier;
  String? _leve;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  Future<void> _faire(Future<void> Function() f) async {
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    try {
      await f();
    } on ErreurExport catch (e) {
      _erreur = e;
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Widget _ligne(String nom, PreuveMaj? p) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(p == null ? '$nom : aucune' : '$nom : ${_dateHeure(p.date)}, ${p.verifiee ? 'vérifiée' : 'NON vérifiée'}',
          style: TextStyle(fontSize: 13, color: p == null || !p.verifiee ? JetonsShell.danger500 : JetonsShell.slate700)));

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final maj = ServiceMiseAJour.de(c.magasin);
    if (maj == null) return const SizedBox.shrink();
    final v = maj.verdict();
    final aut = maj.autorisation();
    final peutPreparer = gestePeutEcran(c, gesteBaseExporter);
    final peutLever = gestePeutEcran(c, gesteMajLeverBlocage);
    return CarteSigh(
      titre: 'Préparer la mise à jour',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Une mise à jour peut changer la forme des données. Elle ne s’installe qu’avec une sauvegarde vérifiée ET un export portable vérifié de moins de ${maj.heures} heure(s) (réglage « Mise à jour du logiciel »). '
            'L’installeur Windows bloque sinon, avec un message nommé.',
            style: const TextStyle(fontSize: 13, color: JetonsShell.slate600)),
        const SizedBox(height: 8),
        _ligne(maj.role() == epRoleFileul ? 'Sauvegarde (l’export en tient lieu sur un fileul)' : 'Sauvegarde de la mère', maj.preuveSauvegarde),
        _ligne('Export portable', maj.preuveExport),
        const SizedBox(height: 4),
        if (v.autorisee && aut == null)
          const NoteSigh('Mise à jour AUTORISÉE : l’installeur peut passer (l’autorisation ne vaut que quelques heures et pour une seule mise à jour).', key: Key('maj:autorisee'), ton: TonSigh.succes, icone: LucideIcons.circleCheck)
        else if (aut == null)
          const NoteSigh('Blocage levé par un geste réservé (force majeure) : l’installeur peut passer, le motif est au journal.', key: Key('maj:levee'), ton: TonSigh.attention, icone: LucideIcons.triangleAlert)
        else
          NoteSigh(v.autorisee ? 'Préparation à faire : l’autorisation de l’installeur est ${aut.code == 'AUTORISATION_ABSENTE' ? 'absente' : 'périmée'} (${aut.code}).' : majMessageBlocage(v),
              key: const Key('maj:bloquee'), ton: TonSigh.danger, icone: LucideIcons.ban),
        if (peutPreparer) ...[
          const SizedBox(height: 12),
          BoutonSigh(
              key: const Key('maj:preparer'),
              libelle: 'Préparer la mise à jour',
              icone: LucideIcons.shieldCheck,
              onPressed: _occupe ? null : () => _faire(() async => _dernier = await maj.preparer())),
        ],
        if (peutLever) ...[
          const SizedBox(height: 12),
          _champ('Motif de la levée (force majeure, au journal)', _motif, const Key('maj:motif')),
          const SizedBox(height: 8),
          BoutonSigh(
              key: const Key('maj:lever'),
              libelle: 'Lever le blocage (force majeure)',
              icone: LucideIcons.lockOpen,
              variante: VarianteBouton.danger,
              onPressed: _occupe
                  ? null
                  : () => _faire(() async {
                        maj.lever(motif: _motif.text);
                        _leve = 'Blocage levé : motif, auteur et date au journal d’audit.';
                      })),
        ],
        if (_leve != null) Padding(padding: const EdgeInsets.only(top: 8), child: NoteSigh(_leve!, key: const Key('maj:leve-ok'), ton: TonSigh.attention, icone: LucideIcons.lockOpen)),
        if (_dernier != null && !_dernier!.autorisee)
          Padding(padding: const EdgeInsets.only(top: 8), child: NoteSigh(majMessageBlocage(_dernier!), key: const Key('maj:resultat'), ton: TonSigh.danger, icone: LucideIcons.ban)),
        if (_erreur != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: NoteSigh('${_erreur!.refus.code} : ${_erreur!.refus.motif}. ${_erreur!.refus.geste}', key: const Key('maj:erreur'), ton: TonSigh.danger, icone: LucideIcons.ban)),
      ]),
    );
  }
}
