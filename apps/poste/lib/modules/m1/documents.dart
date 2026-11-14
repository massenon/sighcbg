import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../documents/panneau_scan.dart';
import '../../documents/service_fichiers.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'commun_m1.dart';

String _t(Object? v, [String vide = '—']) => patVrai(v) ? '$v' : vide;

/// `m1-documents` — la bibliothèque documentaire du patient. Un document se DÉPOSE (PDF, PNG ou JPEG) et reste rattaché au dossier ; le fichier est rangé
/// dans le DOSSIER DES SCANS de la poste mère, sous un nom normalisé (jamais dans le magasin, jamais sur le relais) ; la fiche garde l'empreinte SHA-256.
/// RG-14 : retirer un document l'archive, avec son motif ; remplacer un scan garde l'ancienne version.
///
/// Deux zones (RG-13) : un type de document se lit selon les CATÉGORIES SENSIBLES de la matrice (jamais un nom de rôle). Les lignes que le profil ne peut pas
/// lire sont retirées du tableau et ANNONCÉES (« N pièce(s) réservée(s) »), jamais passées sous silence.
class EcranDocuments extends StatelessWidget with EcranMaquette {
  const EcranDocuments({super.key});

  @override
  String get titre => 'Documents numérisés du patient';

  @override
  String get description =>
      'Ordonnances, résultats d’analyses, comptes rendus, consentements et imagerie rattachés au dossier patient.';

  @override
  String get regle =>
      'Un document se dépose depuis cet écran — PDF, PNG ou JPEG — et reste rattaché au dossier du patient. Le fichier est rangé chez la mère, sous un nom normalisé, avec son empreinte SHA-256 ; il ne passe jamais par le relais. RG-14 — retirer un document l’archive : il reste restaurable depuis la corbeille.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(
          libelle: 'Répertoire des patients',
          icone: LucideIcons.users,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m1-patients')),
      BoutonSigh(
          libelle: 'Plan de numérisation',
          icone: LucideIcons.scanLine,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m1-numerisation')),
    ];
  }

  static List<ChampDef> champs(ContexteEcran c, Fiche? e) => [
        ChampDef(
            nom: 'patientId',
            libelle: 'Dossier patient',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [
              for (final p in trierPar(c.magasin.collection('patients').actives, (p) => p['code']))
                OptionChamp('${p['id']}', '${p['code']} — ${p['nom']} ${p['prenom']}')
            ]),
        ChampDef(
            nom: 'type',
            libelle: 'Type de document',
            type: TypeChamp.select,
            requis: true,
            options: [for (final t in patTypesDocument) OptionChamp(t)]),
        const ChampDef(nom: 'date', libelle: 'Date du document', type: TypeChamp.date, requis: true),
        const ChampDef(
            nom: 'etat',
            libelle: 'Statut',
            type: TypeChamp.select,
            requis: true,
            options: [OptionChamp('en_attente', 'En attente de validation'), OptionChamp('valide', 'Validé')]),
        const ChampDef(nom: 'depose', libelle: 'Déposé par', requis: true),
      ];

  static void _deposer(BuildContext ctx, ContexteEcran c) {
    final acces = AccesSensible.de(c);
    // Seuls les types que ce profil peut LIRE sont proposés au dépôt : l'accueil dépose une pièce d'identité, pas un compte rendu.
    final types = [for (final t in patTypesDocument) if (docPeutLire(acces.peut, t)) t];
    if (types.isEmpty) {
      ToastsSigh.afficher(ctx, 'Ce profil ne peut déposer aucun type de document.', type: TypeToast.attention, detail: 'Les droits sur les catégories sensibles se règlent dans « Rôles & permissions ».');
      return;
    }
    final defs = [
      for (final d in champs(c, null))
        if (d.nom == 'type') ChampDef(nom: 'type', libelle: 'Type de document', type: TypeChamp.select, requis: true, options: [for (final t in types) OptionChamp(t)]) else d
    ];
    final ctl = ControleurFormulaire(defs, {'date': iso(c.aujourdhui), 'etat': 'en_attente', 'depose': acteur(c).nom});
    ScanChoisi? choix;
    String? refus;
    afficherModale<void>(ctx,
        titre: 'Ajouter un document au dossier',
        taille: TailleModale.lg,
        corps: StatefulBuilder(
            builder: (cx, maj) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FormulaireSigh(controleur: ctl),
                  const SizedBox(height: 12),
                  const LibelleChamp('Fichier numérisé * — PDF, PNG ou JPEG'),
                  Row(children: [
                    BoutonSigh(
                        libelle: choix == null ? 'Choisir le fichier' : 'Changer de fichier',
                        icone: LucideIcons.upload,
                        variante: VarianteBouton.secondaire,
                        onPressed: () async {
                          final x = await SelecteursScan.choisir(docFamillePatient);
                          if (x == null) return;
                          final r = docControlerDepot(octets: x.octets, nomOrigine: x.nom, famille: docFamillePatient, tailleMaxReglee: ServiceFichiers.de(c.magasin).tailleMax());
                          maj(() {
                            choix = r == null ? x : null;
                            refus = r == null ? null : '${r.motif} ${r.geste}';
                          });
                        }),
                    const SizedBox(width: 12),
                    if (choix != null)
                      Flexible(child: Text('${choix!.nom} — ${docPoids(choix!.octets.length)}', key: const Key('doc:fichier-choisi'), style: styleM1(t: 12, c: JetonsShell.slate600))),
                  ]),
                  if (refus != null) Padding(padding: const EdgeInsets.only(top: 8), child: NoteSigh(refus!, ton: TonSigh.danger, icone: LucideIcons.triangleAlert)),
                  if (choix != null && docFormatDesOctets(choix!.octets)?.id != 'pdf')
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 160), child: Image.memory(choix!.octets, fit: BoxFit.contain, semanticLabel: 'Aperçu du document', errorBuilder: (_, __, ___) => const SizedBox())))),
                  const SizedBox(height: 12),
                  NoteSigh('Le fichier est rangé chez la mère sous un nom normalisé, jamais dans le magasin ni sur le relais. Taille maximale : ${docPoids(ServiceFichiers.de(c.magasin).tailleMax())}.'),
                ])),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Rattacher au dossier',
                  icone: LucideIcons.upload,
                  onPressed: () async {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    if (choix == null) {
                      ToastsSigh.afficher(ctx, 'Choisir un fichier à déposer.', type: TypeToast.attention);
                      return;
                    }
                    final p = c.magasin.collection('patients').parId(v['patientId']);
                    final col = c.magasin.collection('documentsPatient');
                    // La fiche naît D'ABORD (le nom normalisé se calcule de sa référence), puis le fichier part ; un refus du dépôt DÉFAIT la fiche — rien d'écrit à moitié.
                    final r = col.inserer({
                      ...v,
                      'statut': 'actif',
                      'reference': patReferenceDocument(col.toutes.length),
                      'code': p?['code'],
                      'patient': p != null ? '${p['nom']} ${p['prenom']}' : '—',
                      'fichier': choix!.nom,
                    }, prefixe: 'DOC');
                    try {
                      final d = await ServiceFichiers.de(c.magasin).deposer(famille: docFamillePatient, ficheId: r.fiche['id'], nomOrigine: choix!.nom, octets: choix!.octets, peutCategorie: acces.peut);
                      fermer();
                      if (!ctx.mounted) return;
                      ToastsSigh.afficher(ctx, 'Document rattaché au dossier ${r.fiche['code']}.',
                          type: TypeToast.succes,
                          detail: '${v['type']} — ${d.scan['nomNormalise']}${d.avertissementIndexation != null ? ' — ${d.avertissementIndexation}' : ''}',
                          annuler: () {
                            d.annuler();
                            r.annuler();
                          },
                          messageAnnulation: 'Création annulée — la fiche est archivée, le fichier est conservé.');
                    } on DocAvertissement catch (a) {
                      r.annuler();
                      if (ctx.mounted) ToastsSigh.afficher(ctx, a.motif, type: TypeToast.attention, detail: 'Ouvrir la fiche existante, puis « Rattacher quand même » depuis son panneau de scan.');
                    } catch (e) {
                      r.annuler();
                      if (ctx.mounted) annoncerRefus(ctx, e);
                    }
                  }),
            ]);
  }

  static void _previsualiser(BuildContext ctx, ContexteEcran c, Fiche r) {
    final acces = AccesSensible.de(c);
    afficherTiroir<void>(ctx,
        titre: '${r['type']}',
        sousTitre: '${r['reference']} — ${r['patient']} (${r['code']})',
        largeurMax: 768,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Patient', '${r['patient']}'),
            ('Dossier', '${r['code']}'),
            ('Date du document', dateFrM1(r['date'])),
            ('Statut', statutsMetier['${r['etat']}']?.$1 ?? '${r['etat']}'),
            ('Déposé par', _t(r['depose'])),
          ]),
          const SizedBox(height: 16),
          PanneauScan(famille: docFamillePatient, ficheId: r['id'], peutDeposer: c.droit.editer, peutRetirer: c.droit.annuler, peutCategorie: acces.peut),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Imprimer la fiche',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => imprimerM1(ctx,
                      titre: '${r['type']}',
                      sousTitre: '${r['reference']}',
                      cartouche: [
                        ('Patient', '${r['patient']}'),
                        ('Dossier', '${r['code']}'),
                        ('Date', dateFrM1(r['date'])),
                        ('Fichier', docNumerise(r) ? '${docScan(r)!['nomNormalise']}' : 'Non déposé'),
                        ('Empreinte', docNumerise(r) ? docEmpreinteAbregee('${docScan(r)!['sha256']}') : '—'),
                        ('Taille', docNumerise(r) ? docPoids((docScan(r)!['taille'] as num).toInt()) : patPoidsDoc(r['taille'])),
                        ('Déposé par', _t(r['depose'])),
                      ],
                      blocs: const [BlocTexte('Fiche du document numérisé rattaché au dossier patient. Le fichier lui-même se télécharge depuis le panneau du scan.')])),
            ]);
  }

  @override
  Widget build(BuildContext context) => const _CorpsDocuments();
}

class _CorpsDocuments extends StatefulWidget {
  const _CorpsDocuments();
  @override
  State<_CorpsDocuments> createState() => _CorpsDocumentsState();
}

class _CorpsDocumentsState extends State<_CorpsDocuments> {
  String _du = '', _au = '';
  bool _migration = false;

  Future<void> _migrer(BuildContext ctx, ContexteEcran c) async {
    setState(() => _migration = true);
    try {
      final r = await ServiceFichiers.de(c.magasin).migrerBase64();
      if (!ctx.mounted) return;
      ToastsSigh.afficher(ctx, r.complet ? 'Documents migrés vers le dossier des scans.' : 'Migration terminée avec des refus.',
          type: r.complet ? TypeToast.succes : TypeToast.attention,
          detail: '${r.migrees.length} migré(s), ${r.refusees.length} refusé(s)${r.refusees.isEmpty ? '' : ' : ${r.refusees.map((x) => '${x.fiche} ${x.code}').join(', ')}'}. Le contenu n’est retiré du magasin qu’après relecture de l’empreinte.');
    } catch (e) {
      if (ctx.mounted) annoncerRefus(ctx, e);
    } finally {
      if (mounted) setState(() => _migration = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('documentsPatient');
    final svc = ServiceFichiers.de(c.magasin);
    return EcouteDroitsSensibles(
        builder: (context, acces) => ListenableBuilder(
            listenable: Listenable.merge([col, c.magasin.collection('fichiers')]),
            builder: (context, _) {
              final toutes = col.actives;
              // RG-13 : ce que le profil ne peut pas lire est RETIRÉ du tableau, et ANNONCÉ.
              final rows = [for (final r in toutes) if (docPeutLire(acces.peut, r['type'])) r];
              final reservees = toutes.length - rows.length;
              final k = patKpisDocuments(rows);
              final base64 = svc.enBase64();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                bandeauLectureSeule(c),
                if (reservees > 0) ...[
                  NoteSigh('$reservees pièce(s) de ce registre sont réservées à d’autres profils (droits sur les catégories sensibles : ${{for (final r in toutes) if (!docPeutLire(acces.peut, r['type'])) ...docCategoriesManquantes(acces.peut, r['type']).map((cat) => categorieSensible(cat)?.libelle ?? cat)}.join(', ')}). Elles ne sont ni listées ni cherchées pour vous.',
                      key: const Key('doc:reservees'), ton: TonSigh.attention, icone: LucideIcons.lock),
                  const SizedBox(height: 12),
                ],
                if (base64 > 0 && c.droit.editer && svc.branche) ...[
                  NoteSigh('$base64 document(s) portent encore leur fichier dans le magasin (base64). La migration les range chez la mère et ne retire le contenu qu’après avoir relu l’empreinte.', ton: TonSigh.attention, icone: LucideIcons.hardDriveUpload),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: BoutonSigh(libelle: _migration ? 'Migration…' : 'Migrer vers le dossier des scans', icone: LucideIcons.hardDriveUpload, onPressed: _migration ? null : () => _migrer(context, c))),
                  const SizedBox(height: 12),
                ],
                KpiGrilleSigh(kpis: [
                  KpiSigh(libelle: 'Documents numérisés', valeur: nombre(k.total), icone: LucideIcons.files),
                  KpiSigh(libelle: 'Validés', valeur: nombre(k.valides), icone: LucideIcons.fileCheck2, ton: TonSigh.succes),
                  KpiSigh(libelle: 'En attente de validation', valeur: nombre(k.enAttente), icone: LucideIcons.fileClock, ton: TonSigh.attention),
                  KpiSigh(libelle: 'Dossiers couverts', valeur: nombre(k.dossiers), icone: LucideIcons.folderOpen, ton: TonSigh.info),
                ]),
                const SizedBox(height: 16),
                CarteSigh(
                    titre: 'Bibliothèque documentaire du patient',
                    sansRemplissage: true,
                    child: RegistreM1(
                      collection: col,
                      entite: 'Document',
                      triInitial: 'date',
                      sensInitial: 'desc',
                      taillePage: 15,
                      messageVide: 'Aucun enregistrement.',
                      champs: EcranDocuments.champs,
                      lignes: (cc, toutes) => [
                        for (final r in toutes)
                          if (docPeutLire(acces.peut, r['type']) && docDansPlage(r['date'], du: _du, au: _au)) r
                      ],
                      rechercheExtra: (r) => svc.texteDe(r, famille: docFamillePatient, peutCategorie: acces.peut),
                      // Le dossier peut changer à l'édition : `code` et `patient` (posés à la création) suivent `patientId`, sinon les colonnes gardent l'ancien patient.
                      transformer: (cc, saisie, existante) {
                        if (existante == null) return saisie;
                        final p = cc.magasin.collection('patients').parId(saisie['patientId']);
                        return {
                          ...saisie,
                          'code': p?['code'],
                          'patient': p != null ? '${p['nom']} ${p['prenom']}' : '—',
                        };
                      },
                      libelleArchiver: 'Retirer du dossier',
                      messageArchive: 'Document retiré du dossier.',
                      titreArchivage: (f) => 'Retirer « ${f['type']} » du dossier ?',
                      actionsBarre: [
                        if (c.droit.editer)
                          BoutonSigh(libelle: 'Ajouter un document', icone: LucideIcons.upload, taille: TailleBouton.sm, onPressed: () => EcranDocuments._deposer(context, c)),
                        SizedBox(
                            width: 130,
                            child: TextField(
                                key: const Key('doc:du'),
                                style: styleSaisie,
                                decoration: decorationChamp(indicatif: 'Du (AAAA-MM-JJ)'),
                                onChanged: (v) => setState(() => _du = v.trim()))),
                        SizedBox(
                            width: 130,
                            child: TextField(
                                key: const Key('doc:au'),
                                style: styleSaisie,
                                decoration: decorationChamp(indicatif: 'Au (AAAA-MM-JJ)'),
                                onChanged: (v) => setState(() => _au = v.trim()))),
                      ],
                      actionsSup: (ctx, r) => [
                        BoutonIcone(icone: LucideIcons.eye, libelle: 'Prévisualiser', onPressed: () => EcranDocuments._previsualiser(ctx, c, r)),
                      ],
                      filtres: [
                        FiltreTableau(nom: 'type', libelle: 'Type de document', options: [for (final t in patTypesDocument) if (docPeutLire(acces.peut, t)) OptionChamp(t)]),
                        FiltreTableau(
                            nom: 'fichier',
                            libelle: 'Fichier',
                            options: const [OptionChamp('oui', 'Fichier déposé'), OptionChamp('non', 'Référencé seulement'), OptionChamp('nonindexe', 'Texte non indexé')],
                            correspond: (r, v) => switch (v) {
                                  'oui' => docNumerise(r) || patVrai(r['donnees']),
                                  'non' => !docNumerise(r) && !patVrai(r['donnees']),
                                  _ => ServiceFichiers.de(c.magasin).sansTexte(r),
                                }),
                      ],
                      colonnes: [
                        ColonneTableau(cle: 'reference', libelle: 'Référence', sansCoupure: true, rendu: (_, r) => enMono('${r['reference']}'), texte: (r) => '${r['reference']}'),
                        const ColonneTableau(cle: 'code', libelle: 'Dossier', sansCoupure: true),
                        const ColonneTableau(cle: 'patient', libelle: 'Patient'),
                        ColonneTableau(cle: 'type', libelle: 'Type', texte: (r) => '${r['type']}', rendu: (_, r) => BadgeSigh('${r['type']}', ton: TonSigh.navy)),
                        ColonneTableau(cle: 'date', libelle: 'Date', sansCoupure: true, texte: (r) => dateFrM1(r['date']), valeur: (r) => r['date']),
                        ColonneTableau(
                            cle: 'format',
                            libelle: 'Fichier',
                            sansCoupure: true,
                            texte: (r) => _texteFichier(r),
                            rendu: (_, r) {
                              final scan = docScan(r);
                              final depose = scan != null || patVrai(r['donnees']);
                              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(scan != null ? '${docFormats.firstWhere((f) => f.mime == scan['mime'], orElse: () => docFormats.first).libelle} · ${docPoids((scan['taille'] as num).toInt())}' : '${r['format'] ?? '—'} · ${patPoidsDoc(r['taille'])}',
                                    style: styleM1(t: 12, c: JetonsShell.slate600)),
                                Text(scan != null ? 'déposé · ${ServiceFichiers.de(c.magasin).libelleIndexation(r)}' : (depose ? 'déposé' : 'référencé'),
                                    style: TextStyle(color: depose ? JetonsShell.success600 : JetonsShell.slate400, fontSize: 10, height: 15 / 10)),
                              ]);
                            }),
                        const ColonneTableau(cle: 'depose', libelle: 'Déposé par'),
                        ColonneTableau(cle: 'etat', libelle: 'Statut', texte: (r) => statutsMetier['${r['etat']}']?.$1 ?? '${r['etat']}', rendu: (_, r) => statutBadge(r['etat'])),
                      ],
                    )),
              ]);
            }));
  }

  static String _texteFichier(Fiche r) {
    final scan = docScan(r);
    if (scan != null) return '${docFormats.firstWhere((f) => f.mime == scan['mime'], orElse: () => docFormats.first).libelle} · ${docPoids((scan['taille'] as num).toInt())} déposé · ${docLibelleIndexation(r)}';
    return '${r['format'] ?? '—'} · ${patPoidsDoc(r['taille'])} ${patVrai(r['donnees']) ? 'déposé' : 'référencé'}';
  }
}

/// `m1-numerisation` — le plan de reprise des dossiers papier (CDCT §24). Les chiffres sont ceux du rapport de cadrage (environ 18 000 dossiers
/// recensés) : des valeurs de la maquette, non des mesures du magasin.
class EcranNumerisation extends StatelessWidget with EcranMaquette {
  const EcranNumerisation({super.key});

  @override
  String get titre => 'Plan de numérisation des dossiers';

  @override
  String get description => 'Suivi de la reprise progressive et priorisée des dossiers patients papier (CDCT §24).';

  @override
  String get regle =>
      'Le périmètre exclut la migration rétroactive intégrale : seuls les dossiers actifs sont numérisés en priorité, les dossiers inactifs restant numérisables à la demande.';

  static const _total = 18000;
  static const _traites = 4230;
  static const _lots = <(String, int, int)>[
    ('Lot 1 — Hospitalisations en cours', 320, 320),
    ('Lot 2 — Patients suivis (chroniques)', 1450, 1450),
    ('Lot 3 — Maternité et suivis prénataux', 980, 860),
    ('Lot 4 — Patients assurés', 2300, 1600),
    ('Lot 5 — Consultations 2025-2026', 1150, 0),
    ('Lot 6 — Fonds inactif (à la demande)', 11800, 0),
  ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final mois = parMois(const [], 'x', ref: c.aujourdhui);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'Dossiers papier recensés', valeur: nombre(_total), icone: LucideIcons.archive, ton: TonSigh.neutre),
        KpiSigh(
            libelle: 'Dossiers numérisés',
            valeur: nombre(_traites),
            icone: LucideIcons.scanLine,
            ton: TonSigh.succes,
            indice: '${pourcent(_traites / _total * 100)} du fonds'),
        KpiSigh(libelle: 'Dossiers actifs prioritaires', valeur: nombre(6200), icone: LucideIcons.star, indice: 'Vus au cours des 24 derniers mois'),
        KpiSigh(libelle: 'Reste à traiter (prioritaires)', valeur: nombre(6200 - _traites), icone: LucideIcons.clock, ton: TonSigh.attention),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Avancement par lot de reprise',
          actions: [
            BoutonSigh(
                libelle: 'Éditer l’état d’avancement',
                icone: LucideIcons.printer,
                taille: TailleBouton.sm,
                onPressed: () => imprimerM1(context,
                    titre: 'État d’avancement de la numérisation',
                    sousTitre: 'Reprise des dossiers patients — CDCT §24',
                    cartouche: [
                      ('Fonds total', '${nombre(_total)} dossiers'),
                      ('Numérisés', nombre(_traites)),
                      ('Avancement', pourcent(_traites / _total * 100)),
                      ('Date d’édition', dateFR(c.aujourdhui)),
                    ],
                    blocs: [
                      BlocTableau(TableauEtat(colonnes: [
                        ColonneEtat(libelle: 'Lot de reprise', valeur: (l) => l['lot']),
                        ColonneEtat(libelle: 'Total', valeur: (l) => l['total'], droite: true, somme: (l) => l['total'] as num),
                        ColonneEtat(libelle: 'Numérisés', valeur: (l) => l['fait'], droite: true, somme: (l) => l['fait'] as num),
                        ColonneEtat(libelle: 'Avancement', valeur: (l) => '${((l['fait'] as int) / (l['total'] as int) * 100).round()} %', droite: true),
                      ], lignes: [
                        for (final l in _lots) {'lot': l.$1, 'total': l.$2, 'fait': l.$3}
                      ])),
                    ],
                    signatures: const [Signature('Le Secrétaire Médical'), Signature('La Directrice Administrative', qualite: PaiQualite.daf)]))
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final l in _lots)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(l.$1, style: styleM1(p: FontWeight.w500))),
                      Text('${nombre(l.$3)} / ${nombre(l.$2)} (${(l.$3 / l.$2 * 100).round()} %)', style: styleM1(t: 12, c: JetonsShell.slate500)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                            value: (l.$3 / l.$2).clamp(0.01, 1.0).toDouble(),
                            minHeight: 8,
                            backgroundColor: JetonsShell.slate100,
                            valueColor: AlwaysStoppedAnimation(l.$3 == l.$2
                                ? JetonsShell.success500
                                : (l.$3 > 0 ? JetonsShell.navy500 : JetonsShell.slate300)))),
                  ])),
          ])),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (_, w) {
        final barres = CarteSigh(
            titre: 'Cadence de numérisation (12 derniers mois)',
            child: GraphiqueBarres(etiquettes: mois.etiquettes, series: const [
              SerieGraphique('Dossiers numérisés', [0, 0, 120, 310, 480, 520, 610, 430, 380, 520, 460, 400])
            ]));
        final anneau = CarteSigh(
            titre: 'Répartition du fonds',
            child: GraphiqueAnneau(
                etiquettes: const ['Numérisés', 'Prioritaires restants', 'Fonds inactif'],
                valeurs: [_traites, 6200 - _traites, _total - 6200]));
        return w.maxWidth >= 1024
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: barres), const SizedBox(width: 16), Expanded(child: anneau)])
            : Column(children: [barres, const SizedBox(height: 16), anneau]);
      }),
      const SizedBox(height: 12),
      const Text('Source : Rapport de cadrage — environ 18 000 dossiers patients recensés.',
          style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
    ]);
  }
}

/// Les pages-renvoi hors ruban (`m1-dossier-medical`, `m1-dossier-etendu`, `m1-certificats-externes`) : elles se portent comme la maquette — elles
/// RENVOIENT. Retirer l'entrée du manifeste n'est jamais la bonne façon de fermer un écran : elle casserait tout lien qui la vise.
class EcranRenvoiM1 extends StatelessWidget with EcranMaquette {
  const EcranRenvoiM1._(this.titre, this.description, this._note, this._boutons, {this.regleTexte});

  const EcranRenvoiM1.dossierMedical({Key? key})
      : this._('Dossier médical informatisé',
            'Fusionné dans le répertoire des patients — un seul point d’entrée du dossier (Bug 1).',
            'Le dossier médical informatisé est fusionné dans le répertoire des patients : la fiche de chaque patient y agrège consultations, hospitalisations, analyses, ordonnances et documents — et les épisodes de soins se tiennent dans Consultations (M2), leur écran d’origine.',
            const [
              ('Ouvrir le répertoire des patients', 'm1-patients', LucideIcons.users, true),
              ('Consultations', 'm2-consultations', LucideIcons.stethoscope, false)
            ]);

  const EcranRenvoiM1.dossierEtendu({Key? key})
      : this._('Dossier de consultation étendu',
            'Page de renvoi : le dossier de consultation vit désormais dans son propre écran.',
            'Le dossier de consultation a déménagé dans son propre écran — « Soins › Consultations & prescriptions › Dossiers de consultation » (14/09/2026). Le dossier s’y enregistre d’abord (anamnèse, antécédents, examen clinique IPPOA) ; la fiche de consultation en fait ensuite le récapitulatif et porte seule la prescription.',
            const [('Ouvrir les dossiers de consultation', 'm2-dossiers-consultation', LucideIcons.folderHeart, true)]);

  const EcranRenvoiM1.certificatsExternes({Key? key})
      : this._('Certificats — patients externes',
            'Page de renvoi : les pièces des patients externes figurent au registre unique.',
            'Les certificats des patients adressés de l’extérieur ont rejoint le registre unique — « Certificats & attestations », onglet Patients externes (22/09/2026). La délivrance y ouvre au besoin le dossier du patient, et la pièce passe par la caisse comme celle d’un patient de la clinique.',
            const [('Ouvrir le registre des certificats', 'm1-pieces', LucideIcons.stamp, true)]);

  @override
  final String titre;
  @override
  final String description;
  final String _note;
  final List<(String, String, IconData, bool)> _boutons;
  final String? regleTexte;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 576),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  NoteSigh(_note, icone: LucideIcons.merge),
                  const SizedBox(height: 16),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                    for (final b in _boutons)
                      BoutonSigh(
                          libelle: b.$1,
                          icone: b.$3,
                          variante: b.$4 ? VarianteBouton.primaire : VarianteBouton.secondaire,
                          onPressed: () => c.aller(b.$2)),
                  ]),
                ]))));
  }
}
