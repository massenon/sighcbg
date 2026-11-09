import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/icones.dart' as ic;
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m1/commun_m1.dart' show imprimerM1;
import '../../impression/piece.dart' show BlocTexte, Signature;
import 'ag_commun.dart';
import 'sp_commun.dart';

/// LES QUATRE ÉCRANS GÉNÉRIQUES DES SPÉCIALITÉS (PRD P0-12) — hub, consultation, agenda et file, statistiques. Chacun reçoit le CODE d'une spécialité et
/// lit sa fiche dans la collection `specialites` : aucun n'est écrit pour une spécialité en particulier. Une quinzième fiche les fait naître, sans code.
///
/// Les commandes d'écriture sont ABSENTES (jamais grisées) sans le droit d'écrire ; les droits de chaque écran sont ceux de son écran modèle
/// (`specModelesDroits`), donc ceux que la matrice des rôles donne — et que `m14-roles` peut changer.

Widget _specialiteAbsente(String code) => NoteSigh(
    'La spécialité « $code » n’existe pas ou a été archivée : ses consultations restent lisibles au dossier des patients et au registre des consultations.',
    ton: TonSigh.attention,
    icone: LucideIcons.triangleAlert);

class _CarteLien extends StatelessWidget {
  const _CarteLien({required this.cle, required this.titre, required this.description, required this.icone, required this.surClic});
  final String cle;
  final String titre;
  final String description;
  final String? icone;
  final VoidCallback surClic;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: JetonsShell.slate200)),
        elevation: 0,
        child: InkWell(
          key: Key(cle),
          borderRadius: BorderRadius.circular(12),
          onTap: surClic,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(8)),
                child: Icon(ic.icone(icone), size: 20, color: JetonsShell.navy700),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titre, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate900)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(fontSize: 12, height: 1.625, color: JetonsShell.slate500)),
              ])),
              const SizedBox(width: 12),
              const Icon(LucideIcons.arrowRight, size: 16, color: JetonsShell.slate300),
            ]),
          ),
        ),
      );
}

Widget _grilleCartes(List<Widget> cartes) => LayoutBuilder(builder: (_, w) {
      final n = w.maxWidth >= 1280 ? 3 : (w.maxWidth >= 640 ? 2 : 1);
      final large = (w.maxWidth - 12 * (n - 1)) / n;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final k in cartes) SizedBox(width: large, child: k)]);
    });

// =============================================================================================================================================
// 1. LE HUB
// =============================================================================================================================================

/// `spec-<code>` — la page d'accueil d'une spécialité : ce qui s'y passe (comptes), où aller, ce que la fiche rattache. Sans donnée clinique : l'accueil
/// y entre pour l'agenda, il n'y lit aucun diagnostic (RG-13).
class EcranSpecialiteHub extends StatelessWidget with EcranMaquette {
  const EcranSpecialiteHub(this.code, {super.key, this.descriptionFiche});
  final String code;
  final String? descriptionFiche;

  @override
  String? get description => descriptionFiche;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final spec = specialiteDeCode(m, code);
    if (spec == null) return _specialiteAbsente(code);
    return ListenableBuilder(
        listenable: Listenable.merge([m.collection('consultations'), m.collection('fileAttente'), colSpecialites(m)]),
        builder: (context, _) {
          final s = specStatistiques(code,
              consultations: m.collection('consultations').actives,
              patients: const [],
              fileAttente: m.collection('fileAttente').actives,
              aujourdhui: c.aujourdhui);
          bool ouvre(String id) => c.ouvre?.call(id) ?? true;
          final vues = [
            for (final v in SpecVue.values)
              if (v != SpecVue.hub && ouvre(specIdEcran(code, v))) v
          ];
          final renvois = [
            for (final r in (spec['renvoi'] as List? ?? const []).cast<Map>())
              if (ouvre('${r['ecran']}')) r
          ];
          final actes = [
            for (final a in (spec['actes'] as List? ?? const []))
              if (m.collection('actes').actives.any((x) => x['code'] == a)) m.collection('actes').actives.firstWhere((x) => x['code'] == a)
          ];
          final praticiens = praticiensDe(m, spec);
          final rattaches = (spec['praticiens'] as List? ?? const []).isNotEmpty;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(
                  libelle: 'Consultations ce mois',
                  valeur: nombre(s.ceMois),
                  icone: LucideIcons.stethoscope,
                  ton: TonSigh.navy,
                  indice: 'Au total : ${nombre(s.consultations)}'),
              KpiSigh(libelle: 'Patients suivis', valeur: nombre(s.patients), icone: LucideIcons.users, ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Rendez-vous à venir',
                  valeur: nombre(s.rendezVousAVenir),
                  icone: LucideIcons.calendarDays,
                  ton: TonSigh.neutre),
              KpiSigh(
                  libelle: 'File d’attente',
                  valeur: nombre(s.fileEnAttente),
                  icone: LucideIcons.clock,
                  ton: s.fileEnAttente > 0 ? TonSigh.attention : TonSigh.neutre),
            ]),
            const SizedBox(height: 16),
            if (vues.isEmpty && renvois.isEmpty)
              const NoteSigh('Aucun écran de cette spécialité n’est accessible à votre profil.', ton: TonSigh.neutre, icone: LucideIcons.lock)
            else
              _grilleCartes([
                for (final v in vues)
                  _CarteLien(
                      cle: 'spec-carte:${specIdEcran(code, v)}',
                      titre: v.libelle,
                      description: switch (v) {
                        SpecVue.consultation => 'Le formulaire est engendré du modèle de la spécialité ; la consultation s’enregistre au dossier du patient.',
                        SpecVue.agenda => 'Rendez-vous et file d’attente de la spécialité.',
                        _ => 'Les chiffres sont recomptés depuis les registres, sur la période choisie.',
                      },
                      icone: ['', 'clipboard-list', 'calendar-days', 'chart-column'][v.index],
                      surClic: () => c.aller(specIdEcran(code, v))),
                for (final r in renvois)
                  _CarteLien(
                      cle: 'spec-renvoi:${r['ecran']}',
                      titre: '${r['libelle']}',
                      description: 'Écran existant de la clinique : la fiche de la spécialité y renvoie, rien n’est dupliqué.',
                      icone: c.donnees?.manifeste.ecran('${r['ecran']}')?.icone,
                      surClic: () => c.aller('${r['ecran']}')),
              ]),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (_, w) {
              final deux = w.maxWidth >= 900;
              final praticiensCarte = CarteSigh(
                  titre: 'Praticiens',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!rattaches)
                      const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('Aucun praticien n’est rattaché à cette fiche : tous les médecins de la clinique peuvent consulter.',
                              style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12))),
                    if (praticiens.isEmpty)
                      const Text('Aucun médecin au personnel.', style: TextStyle(color: JetonsShell.slate500, fontSize: 14))
                    else
                      for (final p in praticiens.take(rattaches ? 50 : 5))
                        Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('${p['nomComplet']}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14))),
                  ]));
              final actesCarte = CarteSigh(
                  titre: 'Actes du catalogue',
                  sansRemplissage: true,
                  child: MiniTableauSigh(
                      vide: 'Aucun acte du catalogue n’est rattaché à cette spécialité.',
                      colonnes: [
                        ColonneMini('Code', (a) => '${a['code']}'),
                        ColonneMini('Acte', (a) => '${a['libelle']}'),
                        ColonneMini('Tarif', (a) => a['prixNonAssure'] == null ? 'à fixer' : money(a['prixNonAssure']), droite: true),
                      ],
                      lignes: actes));
              return deux
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: praticiensCarte),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: actesCarte),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [praticiensCarte, const SizedBox(height: 16), actesCarte]);
            }),
          ]);
        });
  }
}

// =============================================================================================================================================
// 2. LA CONSULTATION SPÉCIALISÉE : le formulaire naît du modèle
// =============================================================================================================================================

/// `spec-<code>-consultation` — les consultations de la spécialité et le formulaire de la nouvelle, ENGENDRÉ du modèle de la fiche : ajouter une question
/// au modèle suffit à la faire paraître à la prochaine saisie. La consultation enregistrée apparaît au dossier du patient.
class EcranSpecialiteConsultation extends StatelessWidget with EcranMaquette {
  const EcranSpecialiteConsultation(this.code, {super.key});
  final String code;

  @override
  String? get description =>
      'Le formulaire de consultation est engendré du modèle de la spécialité ; la consultation enregistrée apparaît au dossier du patient.';

  @override
  String? get regle =>
      'Le modèle est une donnée de la fiche de la spécialité : ajouter une question suffit à la faire paraître à la prochaine saisie, les consultations déjà signées gardent leur forme. L’acte de consultation, s’il est tarifé au catalogue, passe par la caisse.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final spec = specialiteDeCode(m, code);
    if (spec == null) return _specialiteAbsente(code);
    return ListenableBuilder(
        listenable: Listenable.merge([m.collection('consultations'), colSpecialites(m)]),
        builder: (context, _) {
          final fiche = specialiteDeCode(m, code) ?? spec;
          final rows = trierPar<Fiche>([
            for (final x in m.collection('consultations').actives)
              if (specDeLaConsultation(x) == code && x['statut'] == 'terminee') x
          ], (x) => x['date'], descendant: true);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TableauSigh(
              titre: 'Consultations — ${libelleSpec(fiche)}',
              lignes: rows,
              taillePage: 10,
              nomExport: 'consultations-$code',
              libelleRecherche: 'Rechercher un patient, un diagnostic…',
              messageVide: 'Aucune consultation enregistrée dans cette spécialité.',
              indiceVide: c.droit.editer ? 'Utiliser « Nouvelle consultation » : le formulaire naît du modèle de la spécialité.' : null,
              triInitial: 'date',
              sensInitial: 'desc',
              actions: [
                if (c.droit.editer)
                  BoutonSigh(
                      libelle: 'Nouvelle consultation',
                      icone: LucideIcons.plus,
                      taille: TailleBouton.sm,
                      onPressed: () => ouvrirConsultationSpec(context, fiche)),
              ],
              alClicLigne: (r) => _detail(context, fiche, r),
              colonnes: [
                const ColonneTableau(cle: 'reference', libelle: 'Réf.'),
                ColonneTableau(cle: 'date', libelle: 'Date', valeur: (r) => '${r['date'] ?? ''}', texte: (r) => dateHeureFr(r['date'])),
                ColonneTableau(cle: 'patient', libelle: 'Patient', texte: (r) => '${r['patient']} ${r['patientCode']}'),
                const ColonneTableau(cle: 'medecin', libelle: 'Praticien'),
                const ColonneTableau(cle: 'motif', libelle: 'Motif'),
                const ColonneTableau(cle: 'diagnostic', libelle: 'Diagnostic'),
              ],
              actionsLigne: (ctx, r) => [
                BoutonIcone(icone: LucideIcons.eye, libelle: 'Voir la consultation', onPressed: () => _detail(context, fiche, r)),
              ],
            ),
          ]);
        });
  }

  void _detail(BuildContext ecran, Fiche spec, Fiche r) {
    final c = ContexteEcran.of(ecran);
    final lisibles = specReponsesLisibles(spec['modele'], (r['reponses'] as Map?)?.cast<String, Object?>() ?? const {});
    final examens = (r['examensPhysiques'] as Map?)?.cast<String, Object?>() ?? const {};
    final ants = (r['antecedentsSaisis'] as Map?)?.cast<String, Object?>() ?? const {};
    afficherTiroir<void>(ecran,
        titre: '${r['patient']}',
        sousTitre: '${r['reference'] ?? ''} — ${libelleSpec(spec)}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Patient', '${r['patient']} — ${r['patientCode']}'),
            ('Date', dateHeureFr(r['date'])),
            ('Praticien', r['medecin']),
            ('Motif', r['motif']),
            ('Diagnostic', r['diagnostic']),
            if (specVrai(r['conduite'])) ('Conduite à tenir', r['conduite']),
            if (specVrai(r['aptitude'])) ('Avis d’aptitude', r['aptitude']),
            if (specVrai(r['entreprise'])) ('Entreprise', r['entreprise']),
            if (specVrai(r['factureNumero'])) ('Pièce de caisse', r['factureNumero']),
          ]),
          if (lisibles.isNotEmpty) ...[
            const SizedBox(height: 12),
            CarteSigh(
                titre: 'Réponses du formulaire',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Question', (l) => '${l['q']}'),
                  ColonneMini('Réponse', (l) => '${l['r']}'),
                ], lignes: [
                  for (final l in lisibles) {'q': l.libelle, 'r': l.valeur}
                ])),
          ],
          if (examens.isNotEmpty) ...[
            const SizedBox(height: 12),
            CarteSigh(
                titre: 'Examen clinique',
                sansRemplissage: true,
                child: MiniTableauSigh(colonnes: [
                  ColonneMini('Appareil', (l) => '${l['a']}'),
                  ColonneMini('Temps', (l) => '${l['t']}'),
                  ColonneMini('Constat', (l) => '${l['x']}'),
                ], lignes: [
                  for (final a in examens.entries)
                    for (final t in ((a.value as Map?) ?? const {}).entries)
                      {'a': '${csAppareilExamen(a.key)['label']}', 't': '${t.key}', 'x': '${t.value}'}
                ])),
          ],
          if (ants.isNotEmpty) ...[
            const SizedBox(height: 12),
            DescListeSigh([
              for (final (nom, libelle) in specChampsAntecedents)
                if (specVrai(ants[nom])) (libelle, ants[nom]),
            ]),
          ],
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Imprimer',
                  icone: LucideIcons.printer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => imprimerM1(ecran,
                      titre: 'COMPTE RENDU DE CONSULTATION — ${libelleSpec(spec).toUpperCase()}',
                      sousTitre: 'Réf. ${r['reference'] ?? ''}',
                      cartouche: [
                        ('Patient', '${r['patient']}'),
                        ('Dossier', '${r['patientCode']}'),
                        ('Date', dateHeureFr(r['date'])),
                        ('Praticien', '${r['medecin']}'),
                      ],
                      blocs: [
                        BlocTexte('Motif : ${r['motif'] ?? ''}'),
                        for (final l in lisibles) BlocTexte('${l.libelle} : ${l.valeur}'),
                        BlocTexte('Diagnostic : ${r['diagnostic'] ?? ''}', gras: true),
                        if (specVrai(r['conduite'])) BlocTexte('Conduite à tenir : ${r['conduite']}'),
                      ],
                      signatures: [Signature('Le Praticien', nom: '${r['medecin']}', mention: 'Signature et cachet')])),
              if (c.droit.annuler)
                BoutonSigh(
                    libelle: 'Archiver',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () async {
                      fermer();
                      final motif = await confirmerAvecMotif(ecran,
                          titre: 'Archiver cette consultation ?',
                          message: 'Archivage logique (RG-14) : la consultation ne disparaît pas, elle quitte le dossier courant et l’opération est annulable.',
                          libelleOk: 'Archiver',
                          dangereux: true);
                      if (motif == null || !ecran.mounted) return;
                      final col = c.magasin.collection('consultations');
                      col.mettreAJour(r['id'], {'_motifArchivage': motif});
                      final annuler = col.archiver(r['id']);
                      ToastsSigh.afficher(ecran, 'Consultation archivée.', type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
                    }),
            ]);
  }
}

bool specVrai(Object? v) => v != null && v != '' && v != false && v != 0;

String dateHeureFr(Object? v) {
  final d = agDate(v);
  return d == null ? '' : '${dateFR(d)} ${heure(d)}';
}

/// La modale de la nouvelle consultation : le formulaire naît du modèle de la fiche. [rdv] : le rendez-vous honoré — il devient la consultation.
Future<void> ouvrirConsultationSpec(BuildContext ecran, Fiche spec, {Fiche? rdv}) {
  final c = ContexteEcran.of(ecran);
  final m = c.magasin;
  final champs = champsConsultationSpec(m, spec, rdv: rdv);
  final premierPatient = champs.firstWhere((x) => x.nom == 'patientCode');
  // Le patient se CHOISIT : la liste native présélectionnerait le premier dossier du répertoire sur un champ obligatoire.
  final liste = [
    for (final f in champs)
      if (f.nom == 'patientCode' && rdv == null)
        ChampDef(
            nom: f.nom,
            libelle: f.libelle,
            type: f.type,
            requis: true,
            col: f.col,
            recherche: true,
            options: [const OptionChamp('', '— Choisir un patient —'), ...premierPatient.options])
      else
        f
  ];
  final ctl = ControleurFormulaire(liste, {
    'date': rdv != null ? agIsoLocal(rdv['date']) : dateHeureLocale(c.aujourdhui),
    if (rdv != null) ...{'patientCode': rdv['patientCode'], 'medecin': rdv['medecin'], 'motif': rdv['motif']},
  });
  return afficherModale<void>(ecran,
      titre: 'Nouvelle consultation — ${libelleSpec(spec)}',
      sousTitre: 'Le formulaire est engendré du modèle de la spécialité.',
      taille: TailleModale.lg,
      corps: FormulaireSigh(controleur: ctl),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Enregistrer la consultation',
                icone: LucideIcons.save,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                    return;
                  }
                  try {
                    final r = enregistrerConsultationSpec(c, spec, v, existante: rdv);
                    fermer();
                    final f = r.emission?.factures.firstOrNull;
                    ToastsSigh.afficher(ecran, 'Consultation enregistrée au dossier de ${r.consultation['patient']}.',
                        type: TypeToast.succes,
                        detail: f != null
                            ? 'Pièce de caisse ${f['numero']} — ${money(f['montantTTC'])} à encaisser.'
                            : r.emission?.note,
                        messageAnnulation: 'Consultation annulée.',
                        annuler: r.annuler);
                  } on RefusSpec catch (e) {
                    ToastsSigh.afficher(ecran, e.message, type: TypeToast.erreur);
                  }
                }),
          ]);
}

// =============================================================================================================================================
// 3. L'AGENDA ET LA FILE
// =============================================================================================================================================

const _etatsRdv = {
  'planifiee': ('Planifiée', TonSigh.info),
  'en_cours': ('En cours', TonSigh.attention),
  'reporte': ('Reporté', TonSigh.attention),
  'non_honore': ('Non honoré', TonSigh.danger),
};

/// `spec-<code>-agenda` — les rendez-vous et la file d'attente de la spécialité : des VUES des registres de l'accueil (`consultations` planifiées,
/// `fileAttente`), filtrées sur la spécialité. Honorer un rendez-vous ouvre la consultation : il en devient la fiche, il n'en naît pas une seconde.
class EcranSpecialiteAgenda extends StatelessWidget with EcranMaquette {
  const EcranSpecialiteAgenda(this.code, {super.key});
  final String code;

  @override
  String? get description => 'Rendez-vous à venir et file d’attente de la spécialité.';

  @override
  String? get regle =>
      'Ce sont deux vues des registres de l’accueil, filtrées sur la spécialité : un rendez-vous honoré devient la consultation (il n’en naît pas une seconde), la file porte le poste « Consultation ».';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final spec = specialiteDeCode(m, code);
    if (spec == null) return _specialiteAbsente(code);
    return ListenableBuilder(
        listenable: Listenable.merge([m.collection('consultations'), m.collection('fileAttente'), m.collection('patients')]),
        builder: (context, _) {
          final rdvs = trierPar<Fiche>([
            for (final x in m.collection('consultations').actives)
              if (x['specialite'] == code && x['statut'] != 'terminee') x
          ], (x) => x['date']);
          final file = [
            for (final t in agFileTriee(m.collection('fileAttente').actives, 'consultation'))
              if (t['specialite'] == code) t
          ];
          final servis = [
            for (final t in m.collection('fileAttente').actives)
              if (t['specialite'] == code && t['etat'] == 'servi') t
          ];
          return OngletsSigh(onglets: [
            OngletDef(id: 'rdv', libelle: 'Rendez-vous (${rdvs.length})', construire: (_) => _tableRdv(context, c, spec, rdvs)),
            OngletDef(id: 'file', libelle: 'File d’attente (${file.length})', construire: (_) => _tableFile(context, c, spec, [...file, ...servis])),
          ]);
        });
  }

  Widget _tableRdv(BuildContext ecran, ContexteEcran c, Fiche spec, List<Fiche> rows) => TableauSigh(
        titre: 'Rendez-vous — ${libelleSpec(spec)}',
        lignes: rows,
        taillePage: 10,
        nomExport: 'rendez-vous-$code',
        messageVide: 'Aucun rendez-vous à venir dans cette spécialité.',
        triInitial: 'date',
        actions: [
          if (c.droit.editer)
            BoutonSigh(libelle: 'Nouveau rendez-vous', icone: LucideIcons.calendarPlus, taille: TailleBouton.sm, onPressed: () => _nouveauRdv(ecran, c, spec)),
        ],
        colonnes: [
          ColonneTableau(cle: 'date', libelle: 'Date et heure', valeur: (r) => '${r['date'] ?? ''}', texte: (r) => dateHeureFr(r['date'])),
          ColonneTableau(cle: 'patient', libelle: 'Patient', texte: (r) => '${r['patient']} ${r['patientCode'] ?? ''}'),
          const ColonneTableau(cle: 'medecin', libelle: 'Praticien'),
          const ColonneTableau(cle: 'motif', libelle: 'Motif'),
          ColonneTableau(
              cle: 'statut',
              libelle: 'Statut',
              texte: (r) => _etatsRdv['${r['statut']}']?.$1 ?? '${r['statut']}',
              rendu: (_, r) => BadgeSigh(_etatsRdv['${r['statut']}']?.$1 ?? '${r['statut']}', ton: _etatsRdv['${r['statut']}']?.$2 ?? TonSigh.neutre)),
        ],
        actionsLigne: (ctx, r) => [
          if (c.droit.editer && specVrai(r['patientCode']) && (c.ouvre?.call(specIdEcran(code, SpecVue.consultation)) ?? true))
            BoutonIcone(icone: LucideIcons.stethoscope, libelle: 'Consulter (honorer le rendez-vous)', onPressed: () => _consulter(ecran, spec, r)),
          if (c.droit.editer) BoutonIcone(icone: LucideIcons.calendarClock, libelle: 'Reporter', onPressed: () => reporterAg(ecran, r)),
          if (c.droit.editer && r['statut'] != 'non_honore')
            BoutonIcone(icone: LucideIcons.userX, libelle: 'Non honoré', onPressed: () => marquerNonHonoreAg(ecran, r)),
        ],
      );

  void _consulter(BuildContext ecran, Fiche spec, Fiche rdv) {
    final c = ContexteEcran.of(ecran);
    // Un patient du rendez-vous qui n'a pas de dossier au répertoire ne peut pas être consulté : on le dit, on n'ouvre pas un formulaire voué au refus.
    if (patientParCode(c.magasin, rdv['patientCode']) == null) {
      ToastsSigh.afficher(ecran, 'Ce rendez-vous n’est lié à aucun dossier du répertoire : ouvrir le dossier du patient avant de le consulter.',
          type: TypeToast.erreur);
      return;
    }
    ouvrirConsultationSpec(ecran, spec, rdv: rdv);
  }

  void _nouveauRdv(BuildContext ecran, ContexteEcran c, Fiche spec) {
    final liste = [
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient (dossier du répertoire)',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          recherche: true,
          options: [const OptionChamp('', '— Choisir un patient —'), ...optionsPatients(c.magasin)]),
      ChampDef(nom: 'medecin', libelle: 'Praticien', type: TypeChamp.select, requis: true, options: optionsPraticiens(c.magasin, spec)),
      const ChampDef(nom: 'date', libelle: 'Date et heure', type: TypeChamp.dateHeure, requis: true),
      const ChampDef(nom: 'motif', libelle: 'Motif', requis: true, col: ColChamp.plein),
    ];
    final ctl = ControleurFormulaire(liste, {'date': dateHeureLocale(c.aujourdhui)});
    afficherModale<void>(ecran,
        titre: 'Nouveau rendez-vous — ${libelleSpec(spec)}',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer le rendez-vous',
                  icone: LucideIcons.calendarCheck,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final col = c.magasin.collection('consultations');
                    final r = agNouveauRendezVous({...v, 'type': specTypeConsultation}, patients: patientsAg(c), existantes: col.toutes);
                    final ins = col.inserer({...r, 'specialite': '${spec['code']}', 'specialiteLibelle': libelleSpec(spec)}, prefixe: 'CON');
                    fermer();
                    ToastsSigh.afficher(ecran, 'Rendez-vous enregistré.',
                        type: TypeToast.succes, detail: '${r['patient']} — ${libelleSpec(spec)}', messageAnnulation: 'Rendez-vous annulé.', annuler: ins.annuler);
                  }),
            ]);
  }

  Widget _tableFile(BuildContext ecran, ContexteEcran c, Fiche spec, List<Fiche> rows) => TableauSigh(
        titre: 'File d’attente — ${libelleSpec(spec)}',
        lignes: rows,
        taillePage: 10,
        nomExport: 'file-$code',
        messageVide: 'Personne n’attend dans cette spécialité.',
        actions: [
          if (c.droit.editer)
            BoutonSigh(libelle: 'Inscrire un patient', icone: LucideIcons.userPlus, taille: TailleBouton.sm, onPressed: () => _inscrire(ecran, c, spec)),
        ],
        colonnes: [
          const ColonneTableau(cle: 'numero', libelle: 'N°'),
          ColonneTableau(cle: 'patient', libelle: 'Patient', texte: (r) => '${r['patient']} ${r['patientCode'] ?? ''}'),
          ColonneTableau(
              cle: 'priorite',
              libelle: 'Priorité',
              texte: (r) => agPriorite(r['priorite']).libelle,
              rendu: (_, r) => BadgeSigh(agPriorite(r['priorite']).libelle, ton: tonAg(agPriorite(r['priorite']).ton))),
          const ColonneTableau(cle: 'motif', libelle: 'Motif'),
          ColonneTableau(cle: 'arriveeLe', libelle: 'Arrivée', valeur: (r) => '${r['arriveeLe'] ?? ''}', texte: (r) => dateHeureFr(r['arriveeLe'])),
          ColonneTableau(
              cle: 'etat',
              libelle: 'État',
              texte: (r) => r['etat'] == 'attente' ? 'En attente' : 'Servi',
              rendu: (_, r) => r['etat'] == 'attente' ? const BadgeSigh('En attente', ton: TonSigh.attention) : const BadgeSigh('Servi', ton: TonSigh.succes)),
        ],
        actionsLigne: (ctx, r) => [
          if (c.droit.editer && r['etat'] == 'attente')
            BoutonIcone(
                icone: LucideIcons.megaphone,
                libelle: 'Appeler',
                onPressed: () {
                  final annuler = c.magasin.collection('fileAttente').mettreAJour(r['id'], agPatchAppel(acteur(c).nom, c.aujourdhui));
                  ToastsSigh.afficher(ecran, 'Patient appelé — ${r['patient']}.', type: TypeToast.succes, messageAnnulation: 'Appel annulé.', annuler: annuler);
                }),
        ],
      );

  void _inscrire(BuildContext ecran, ContexteEcran c, Fiche spec) {
    final liste = [
      ChampDef(
          nom: 'patientCode',
          libelle: 'Patient (dossier du répertoire)',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          recherche: true,
          options: [const OptionChamp('', '— Choisir un patient —'), ...optionsPatients(c.magasin)]),
      ChampDef(
          nom: 'priorite',
          libelle: 'Priorité',
          type: TypeChamp.select,
          requis: true,
          options: [for (final p in agPriorites) OptionChamp(p.code, p.libelle)]),
      ChampDef(nom: 'praticien', libelle: 'Praticien (facultatif : file commune)', type: TypeChamp.select, options: [const OptionChamp('', 'File commune'), ...optionsPraticiens(c.magasin, spec)]),
      const ChampDef(nom: 'motif', libelle: 'Motif', requis: true, col: ColChamp.plein),
    ];
    final ctl = ControleurFormulaire(liste, {'priorite': 'ordre_arrivee'});
    afficherModale<void>(ecran,
        titre: 'Inscrire un patient — ${libelleSpec(spec)}',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Inscrire',
                  icone: LucideIcons.userPlus,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final col = c.magasin.collection('fileAttente');
                    final t = agTicket(
                        poste: 'consultation',
                        patientCode: '${v['patientCode']}',
                        priorite: '${v['priorite']}',
                        motif: '${v['motif']}',
                        praticien: specVrai(v['praticien']) ? '${v['praticien']}' : null,
                        patients: patientsAg(c),
                        tous: col.toutes,
                        maintenant: c.aujourdhui);
                    final ins = col.inserer({...t, 'specialite': '${spec['code']}', 'specialiteLibelle': libelleSpec(spec)}, prefixe: 'FIL');
                    fermer();
                    ToastsSigh.afficher(ecran, 'Patient inscrit — numéro ${t['numero']}.',
                        type: TypeToast.succes, detail: '${t['patient']} — ${libelleSpec(spec)}', messageAnnulation: 'Inscription annulée.', annuler: ins.annuler);
                  }),
            ]);
  }
}

// =============================================================================================================================================
// 4. LES STATISTIQUES
// =============================================================================================================================================

/// `spec-<code>-stats` — les statistiques de la spécialité, RECOMPTÉES depuis les registres (consultations, patients, file) sur la période choisie :
/// rien n'est fourni, rien n'est saisi.
class EcranSpecialiteStats extends StatefulWidget with EcranMaquette {
  const EcranSpecialiteStats(this.code, {super.key});
  final String code;

  @override
  String? get description => 'Consultations, patients, praticiens et diagnostics de la spécialité, recomptés depuis les registres.';

  @override
  String? get regle =>
      'Tout est calculé depuis les registres à l’ouverture et à chaque changement de période : consultations enregistrées (les rendez-vous planifiés et les archivées ne comptent pas), patients distincts, pièces facturées. Les recettes sont ce qui est FACTURÉ, la caisse seule dit ce qui est encaissé.';

  @override
  State<EcranSpecialiteStats> createState() => _EtatStats();
}

class _EtatStats extends State<EcranSpecialiteStats> {
  late final ControleurFormulaire _periode = ControleurFormulaire(const [
    ChampDef(nom: 'du', libelle: 'Du', type: TypeChamp.date),
    ChampDef(nom: 'au', libelle: 'Au', type: TypeChamp.date),
  ]);

  @override
  void initState() {
    super.initState();
    _periode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _periode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final spec = specialiteDeCode(m, widget.code);
    if (spec == null) return _specialiteAbsente(widget.code);
    return ListenableBuilder(
        listenable: Listenable.merge([m.collection('consultations'), m.collection('fileAttente'), m.collection('patients')]),
        builder: (context, _) {
          final s = specStatistiques(widget.code,
              consultations: m.collection('consultations').actives,
              patients: m.collection('patients').actives,
              fileAttente: m.collection('fileAttente').actives,
              du: '${_periode['du'] ?? ''}',
              au: '${_periode['au'] ?? ''}',
              aujourdhui: c.aujourdhui);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CarteSigh(titre: 'Période', child: FormulaireSigh(controleur: _periode)),
            const SizedBox(height: 16),
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Consultations', valeur: nombre(s.consultations), icone: LucideIcons.stethoscope, ton: TonSigh.navy, indice: 'Sur la période'),
              KpiSigh(libelle: 'Patients distincts', valeur: nombre(s.patients), icone: LucideIcons.users, ton: TonSigh.info),
              KpiSigh(libelle: 'Facturé', valeur: money(s.recettes), icone: LucideIcons.receipt, ton: TonSigh.succes, indice: 'Pièces émises, non encaissé'),
              KpiSigh(
                  libelle: 'Rendez-vous à venir',
                  valeur: nombre(s.rendezVousAVenir),
                  icone: LucideIcons.calendarDays,
                  ton: TonSigh.neutre,
                  indice: 'File : ${nombre(s.fileEnAttente)}'),
            ]),
            const SizedBox(height: 16),
            if (s.consultations == 0)
              const VideSigh('Aucune consultation enregistrée sur cette période.', icone: LucideIcons.chartColumn)
            else
              LayoutBuilder(builder: (_, w) {
                final deux = w.maxWidth >= 900;
                final evolution = CarteSigh(
                    titre: 'Consultations par mois',
                    child: GraphiqueBarres(
                        etiquettes: [for (final e in s.parMois) e.libelle],
                        series: [SerieGraphique('Consultations', [for (final e in s.parMois) e.valeur])],
                        hauteur: 220));
                final sexe = CarteSigh(
                    titre: 'Répartition par sexe',
                    child: s.parSexe.isEmpty
                        ? const Text('Le sexe n’est renseigné sur aucun dossier de la période.', style: TextStyle(color: JetonsShell.slate500, fontSize: 14))
                        : GraphiqueAnneau(etiquettes: [for (final e in s.parSexe) e.libelle], valeurs: [for (final e in s.parSexe) e.valeur], hauteur: 200));
                return deux
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 2, child: evolution), const SizedBox(width: 16), Expanded(child: sexe)])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [evolution, const SizedBox(height: 16), sexe]);
              }),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (_, w) {
              final deux = w.maxWidth >= 900;
              final prat = CarteSigh(
                  titre: 'Par praticien',
                  sansRemplissage: true,
                  child: MiniTableauSigh(
                      vide: 'Aucune consultation.',
                      colonnes: [ColonneMini('Praticien', (l) => '${l['x']}'), ColonneMini('Consultations', (l) => '${l['n']}', droite: true)],
                      lignes: [for (final e in s.parPraticien) {'x': e.libelle, 'n': e.valeur}]));
              final diag = CarteSigh(
                  titre: 'Diagnostics les plus fréquents',
                  sansRemplissage: true,
                  child: MiniTableauSigh(
                      vide: 'Aucune consultation.',
                      colonnes: [ColonneMini('Diagnostic', (l) => '${l['x']}'), ColonneMini('Cas', (l) => '${l['n']}', droite: true)],
                      lignes: [for (final e in s.diagnostics) {'x': e.libelle, 'n': e.valeur}]));
              return deux
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: prat), const SizedBox(width: 16), Expanded(child: diag)])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [prat, const SizedBox(height: 16), diag]);
            }),
            if (s.aptitudes.isNotEmpty) ...[
              const SizedBox(height: 16),
              CarteSigh(
                  titre: 'Avis d’aptitude',
                  sansRemplissage: true,
                  child: MiniTableauSigh(
                      colonnes: [ColonneMini('Avis', (l) => '${l['x']}'), ColonneMini('Visites', (l) => '${l['n']}', droite: true)],
                      lignes: [for (final e in s.aptitudes) {'x': e.libelle, 'n': e.valeur}])),
            ],
          ]);
        });
  }
}
