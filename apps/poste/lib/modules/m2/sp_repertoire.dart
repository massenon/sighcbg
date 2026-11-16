import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/icones.dart' as ic;
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'sp_commun.dart';

/// Les icônes proposées à une spécialité : celles que le poste sait dessiner (les autres retomberaient sur un rond).
const _icones = [
  'stethoscope',
  'heart-pulse',
  'brain',
  'bone',
  'baby',
  'scissors',
  'droplets',
  'activity',
  'scan-line',
  'scan-search',
  'briefcase',
  'shield-check',
  'megaphone',
  'hand-heart',
  'calendar-heart',
  'syringe',
  'pill',
  'thermometer',
];

const _typesQuestion = [
  ('texte', 'Texte court'),
  ('longtexte', 'Texte long'),
  ('nombre', 'Nombre'),
  ('choix', 'Choix dans une liste'),
  ('oui_non', 'Oui / Non'),
  ('date', 'Date'),
];

/// `m2-specialites` — « Spécialités » : le répertoire ADMINISTRABLE des spécialités de la clinique. Une fiche = une spécialité : libellé, description,
/// praticiens rattachés, actes du catalogue, MODÈLE de consultation. Ajouter une quinzième fiche fait naître son ruban, son hub, son formulaire, son
/// agenda et ses statistiques, sans une ligne de code. Gynécologie, chirurgie et imagerie renvoient vers leurs écrans existants.
class EcranSpecialites extends StatelessWidget with EcranMaquette {
  const EcranSpecialites({super.key});

  @override
  String get titre => 'Spécialités';

  @override
  String get description =>
      'Les spécialités de la clinique, une fiche chacune : modèle de consultation, praticiens, actes. Une fiche de plus, c’est une spécialité de plus au ruban.';

  @override
  String get regle =>
      'Une spécialité est une DONNÉE, pas un module : sa fiche engendre son entrée du ruban, son hub, le formulaire de consultation (du modèle), l’agenda et la file, et les statistiques. Gynécologie, chirurgie et imagerie ont déjà leurs écrans : leur fiche y renvoie, rien n’est dupliqué. Une fiche s’archive, elle ne se supprime pas (RG-14) : ses consultations restent lisibles.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    final col = colSpecialites(m);
    return ListenableBuilder(
        listenable: Listenable.merge([col, m.collection('consultations')]),
        builder: (context, _) {
          final rows = specialitesActives(m);
          final consultations = m.collection('consultations').actives;
          int n(Fiche f) => consultations.where((x) => specDeLaConsultation(x) == '${f['code']}' && x['statut'] == 'terminee').length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiGrilleSigh(kpis: [
              KpiSigh(libelle: 'Spécialités', valeur: nombre(rows.length), icone: LucideIcons.stethoscope, ton: TonSigh.navy),
              KpiSigh(
                  libelle: 'Avec leurs propres écrans',
                  valeur: nombre(rows.where((f) => (f['renvoi'] as List? ?? const []).isNotEmpty).length),
                  icone: LucideIcons.link,
                  ton: TonSigh.info,
                  indice: 'La fiche y renvoie'),
              KpiSigh(
                  libelle: 'Consultations enregistrées',
                  valeur: nombre(consultations.where((x) => specDeLaConsultation(x) != null && x['statut'] == 'terminee').length),
                  icone: LucideIcons.clipboardList,
                  ton: TonSigh.neutre),
              KpiSigh(
                  libelle: 'Sans praticien rattaché',
                  valeur: nombre(rows.where((f) => (f['praticiens'] as List? ?? const []).isEmpty).length),
                  icone: LucideIcons.users,
                  ton: TonSigh.neutre,
                  indice: 'Tous les médecins peuvent consulter'),
            ]),
            const SizedBox(height: 16),
            TableauSigh(
              titre: 'Spécialités de la clinique',
              lignes: rows,
              taillePage: 14,
              nomExport: 'specialites',
              messageVide: 'Aucune spécialité.',
              triInitial: 'ordre',
              actions: [
                if (c.droit.editer)
                  BoutonSigh(libelle: 'Nouvelle spécialité', icone: LucideIcons.plus, taille: TailleBouton.sm, onPressed: () => _editer(context, null)),
              ],
              alClicLigne: (r) => _fiche(context, r),
              colonnes: [
                ColonneTableau(cle: 'ordre', libelle: '№', valeur: (r) => r['ordre'] ?? 9999),
                ColonneTableau(
                    cle: 'libelle',
                    libelle: 'Spécialité',
                    texte: (r) => '${r['libelle']} ${r['description'] ?? ''}',
                    rendu: (_, r) => Row(children: [
                          Icon(ic.icone('${r['icone']}'), size: 16, color: JetonsShell.navy700),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r['libelle']}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
                            Text('${r['description'] ?? ''}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
                          ])),
                        ])),
                const ColonneTableau(cle: 'code', libelle: 'Code'),
                ColonneTableau(
                    cle: 'praticiens',
                    libelle: 'Praticiens',
                    droite: true,
                    valeur: (r) => (r['praticiens'] as List? ?? const []).length,
                    texte: (r) => '${(r['praticiens'] as List? ?? const []).length}'),
                ColonneTableau(
                    cle: 'actes',
                    libelle: 'Actes',
                    droite: true,
                    valeur: (r) => (r['actes'] as List? ?? const []).length,
                    texte: (r) => '${(r['actes'] as List? ?? const []).length}'),
                ColonneTableau(cle: 'consultations', libelle: 'Consultations', droite: true, valeur: n, texte: (r) => '${n(r)}'),
                ColonneTableau(
                    cle: 'renvoi',
                    libelle: 'Écrans',
                    texte: (r) => (r['renvoi'] as List? ?? const []).isEmpty ? 'Génériques' : 'Renvoie vers des écrans existants',
                    rendu: (_, r) => (r['renvoi'] as List? ?? const []).isEmpty
                        ? const BadgeSigh('Génériques', ton: TonSigh.neutre)
                        : const BadgeSigh('Renvoie vers des écrans existants', ton: TonSigh.info)),
              ],
              actionsLigne: (ctx, r) => [
                BoutonIcone(icone: LucideIcons.arrowRight, libelle: 'Ouvrir la spécialité', onPressed: () => _ouvrir(context, r)),
                if (c.droit.editer) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier la fiche', onPressed: () => _editer(context, r)),
              ],
            ),
          ]);
        });
  }

  void _ouvrir(BuildContext ecran, Fiche r) {
    final c = ContexteEcran.of(ecran);
    final id = specIdEcran('${r['code']}');
    if (c.ouvre?.call(id) ?? true) {
      c.aller(id);
    } else {
      ToastsSigh.afficher(ecran, 'Cette spécialité n’est pas ouverte à votre profil.', type: TypeToast.attention);
    }
  }

  void _fiche(BuildContext ecran, Fiche r) {
    final c = ContexteEcran.of(ecran);
    final m = c.magasin;
    final questions = specQuestionsPlates(r['modele']);
    final modele = (r['modele'] as Map?)?.cast<String, Object?>() ?? const {};
    final noms = {
      for (final p in m.collection('personnel').actives) '${p['id']}': '${p['nomComplet']}',
    };
    afficherTiroir<void>(ecran,
        titre: '${r['libelle']}',
        sousTitre: '${r['code']}',
        largeurMax: 672,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Description', r['description']),
            ('Praticiens rattachés', (r['praticiens'] as List? ?? const []).isEmpty ? 'Aucun : tous les médecins' : [for (final p in r['praticiens'] as List) noms['$p'] ?? '$p'].join(', ')),
            ('Actes du catalogue', (r['actes'] as List? ?? const []).isEmpty ? '—' : (r['actes'] as List).join(', ')),
            ('Acte de consultation', r['acteConsultation'] ?? 'Aucun'),
            ('Source', r['source']),
          ]),
          const SizedBox(height: 12),
          CarteSigh(
              titre: 'Modèle de consultation',
              sansRemplissage: true,
              child: MiniTableauSigh(
                  vide: 'Aucune question.',
                  colonnes: [
                    ColonneMini('Section', (l) => '${l['s']}'),
                    ColonneMini('Question', (l) => '${l['q']}'),
                    ColonneMini('Type', (l) => '${l['t']}'),
                  ],
                  lignes: [
                    for (final q in questions)
                      {'s': q['section'], 'q': q['libelle'], 't': _typesQuestion.where((x) => x.$1 == q['type']).map((x) => x.$2).firstOrNull ?? q['type']}
                  ])),
          const SizedBox(height: 8),
          Text(
              'Examen clinique : ${(modele['appareils'] as List? ?? const []).isEmpty ? 'aucun appareil' : (modele['appareils'] as List).map((a) => csAppareilExamen('$a')['label']).join(', ')} · Antécédents : ${modele['antecedents'] == true ? 'oui' : 'non'}',
              style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
          if ((r['renvoi'] as List? ?? const []).isNotEmpty) ...[
            const SizedBox(height: 12),
            NoteSigh('Cette spécialité renvoie vers : ${[for (final x in (r['renvoi'] as List).cast<Map>()) x['libelle']].join(', ')}.'),
          ],
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Ouvrir',
                  icone: LucideIcons.arrowRight,
                  variante: VarianteBouton.secondaire,
                  onPressed: () {
                    fermer();
                    _ouvrir(ecran, r);
                  }),
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Modifier',
                    icone: LucideIcons.pencil,
                    onPressed: () {
                      fermer();
                      _editer(ecran, r);
                    }),
              if (c.droit.annuler)
                BoutonSigh(
                    libelle: 'Archiver',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () {
                      fermer();
                      _archiver(ecran, r);
                    }),
            ]);
  }

  Future<void> _archiver(BuildContext ecran, Fiche r) async {
    final c = ContexteEcran.of(ecran);
    final motif = await confirmerAvecMotif(ecran,
        titre: 'Archiver la spécialité « ${r['libelle']} » ?',
        message:
            'Archivage logique (RG-14) : la spécialité quitte le ruban, ses consultations restent lisibles au dossier des patients. L’opération est annulable.',
        libelleOk: 'Archiver',
        dangereux: true);
    if (motif == null || !ecran.mounted) return;
    final col = colSpecialites(c.magasin);
    col.mettreAJour(r['id'], {'_motifArchivage': motif});
    final annuler = col.archiver(r['id']);
    ToastsSigh.afficher(ecran, 'Spécialité archivée.', type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
  }

  void _editer(BuildContext ecran, Fiche? r) {
    final c = ContexteEcran.of(ecran);
    final m = c.magasin;
    final creation = r == null;
    final existants = [for (final f in colSpecialites(m).toutes) '${f['code']}'];
    final modele = (r?['modele'] as Map?)?.cast<String, Object?>() ?? const {};
    final questions = <Fiche>[for (final q in specQuestionsPlates(r?['modele'])) {...q}];
    final actes = [for (final a in m.collection('actes').actives) OptionChamp('${a['code']}', '${a['code']} — ${a['libelle']}')];
    final champs = [
      const ChampDef.section('Identité de la spécialité'),
      const ChampDef(nom: 'libelle', libelle: 'Libellé', requis: true),
      ChampDef(
          nom: 'code',
          libelle: 'Code (adresse des écrans)',
          requis: true,
          aide: creation ? 'Minuscules, chiffres et tirets : ne se change plus ensuite (exemple : dermatologie).' : 'Le code ne se change pas : il est dans l’adresse des écrans.',
          valider: (v, _) => creation ? specRefusCode('$v', existants) : null),
      const ChampDef(nom: 'description', libelle: 'Description', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ChampDef(nom: 'icone', libelle: 'Icône du ruban', type: TypeChamp.select, options: [for (final i in _icones) OptionChamp(i)]),
      const ChampDef(nom: 'ordre', libelle: 'Place au ruban', type: TypeChamp.nombre),
      const ChampDef.section('Rattachements'),
      ChampDef(
          nom: 'praticiens',
          libelle: 'Praticiens rattachés',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          aide: 'Laisser vide : tous les médecins de la clinique peuvent consulter.',
          options: [
            for (final p in m.collection('personnel').actives)
              if (p['fonction'] == 'medecin') OptionChamp('${p['id']}', '${p['nomComplet']}')
          ]),
      ChampDef(nom: 'actes', libelle: 'Actes du catalogue', type: TypeChamp.multiselect, col: ColChamp.plein, options: actes),
      ChampDef(
          nom: 'acteConsultation',
          libelle: 'Acte facturé à la consultation',
          type: TypeChamp.select,
          col: ColChamp.plein,
          aide: 'Passe par la caisse à chaque consultation. Vide : consultation non facturée.',
          options: [const OptionChamp('', '— Aucun —'), ...actes]),
      const ChampDef.section('Examen clinique et antécédents'),
      ChampDef(
          nom: 'appareils',
          libelle: 'Appareils examinés (examen par appareil du dossier de consultation)',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final a in csAppareils) OptionChamp('${a['code']}', '${a['label']}')]),
      const ChampDef(nom: 'antecedents', libelle: 'Recueillir les antécédents', type: TypeChamp.case_),
    ];
    final ctl = ControleurFormulaire(champs, {
      'libelle': r?['libelle'],
      'code': r?['code'],
      'description': r?['description'],
      'icone': r?['icone'] ?? 'stethoscope',
      'ordre': r?['ordre'] ?? (rowsMax(m) + 1),
      'praticiens': [for (final p in (r?['praticiens'] as List? ?? const [])) '$p'],
      'actes': [for (final a in (r?['actes'] as List? ?? const [])) '$a'],
      'acteConsultation': r?['acteConsultation'] ?? '',
      'appareils': [for (final a in (modele['appareils'] as List? ?? const [])) '$a'],
      'antecedents': modele['antecedents'] == true,
    });
    afficherModale<void>(ecran,
        titre: creation ? 'Nouvelle spécialité' : 'Modifier — ${r['libelle']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormulaireSigh(controleur: ctl),
          const SizedBox(height: 12),
          CarteSigh(titre: 'Modèle de consultation — les questions', child: _EditeurQuestions(ecran, questions)),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: creation ? 'Créer la spécialité' : 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ecran, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final nouveau = specModeleDepuisQuestions(questions,
                        appareils: [for (final a in (v['appareils'] as List? ?? const [])) '$a'], antecedents: v['antecedents'] == true);
                    final refus = specRefusModele(nouveau);
                    if (refus != null) {
                      ToastsSigh.afficher(ecran, refus, type: TypeToast.erreur);
                      return;
                    }
                    final col = colSpecialites(m);
                    final donnees = <String, Object?>{
                      'libelle': '${v['libelle']}'.trim(),
                      'description': '${v['description'] ?? ''}'.trim(),
                      'icone': '${v['icone']}',
                      'ordre': nombreOuZero(v['ordre']).toInt(),
                      'praticiens': [for (final p in (v['praticiens'] as List? ?? const [])) '$p'],
                      'actes': [for (final a in (v['actes'] as List? ?? const [])) '$a'],
                      'acteConsultation': '${v['acteConsultation'] ?? ''}',
                      'modele': nouveau,
                    };
                    if (creation) {
                      final ins = col.inserer({
                        ...donnees,
                        'code': '${v['code']}'.trim(),
                        'statut': 'actif',
                        'source': 'Créée dans l’application par ${acteur(c).nom}',
                      }, prefixe: 'SPE');
                      fermer();
                      ToastsSigh.afficher(ecran, 'Spécialité créée — elle paraît au ruban.',
                          type: TypeToast.succes, detail: '${donnees['libelle']}', messageAnnulation: 'Création annulée.', annuler: ins.annuler);
                    } else {
                      final annuler = col.mettreAJour(r['id'], donnees);
                      fermer();
                      ToastsSigh.afficher(ecran, 'Fiche enregistrée.', type: TypeToast.succes, annuler: annuler);
                    }
                  }),
            ]);
  }

  /// La plus grande place au ruban déjà prise : la nouvelle fiche passe en dernier.
  static int rowsMax(Magasin m) =>
      specialitesActives(m).fold<int>(0, (a, f) => ((f['ordre'] as num?)?.toInt() ?? 0) > a ? (f['ordre'] as num).toInt() : a);
}

/// L'éditeur des questions du modèle : la liste ordonnée, une question = section, libellé, type, choix, unité, bornes. Ajouter, modifier, retirer.
class _EditeurQuestions extends StatefulWidget {
  const _EditeurQuestions(this.ecran, this.questions);
  final BuildContext ecran;
  final List<Fiche> questions;

  @override
  State<_EditeurQuestions> createState() => _EtatEditeur();
}

class _EtatEditeur extends State<_EditeurQuestions> {
  String _type(Object? t) => _typesQuestion.where((x) => x.$1 == t).map((x) => x.$2).firstOrNull ?? '$t';

  @override
  Widget build(BuildContext context) {
    final qs = widget.questions;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (qs.isEmpty)
        const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Aucune question — en ajouter, ou cocher au moins un appareil d’examen clinique.',
                style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))),
      for (final (i, q) in qs.indexed)
        Container(
            key: Key('spec-question:$i'),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
            child: Row(children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. ${q['libelle']}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14)),
                Text(
                    '${q['section'] ?? ''} · ${_type(q['type'])}${q['unite'] != null ? ' (${q['unite']})' : ''}${(q['options'] as List? ?? const []).isNotEmpty ? ' — ${(q['options'] as List).join(' · ')}' : ''}',
                    style: const TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)),
              ])),
              BoutonIcone(icone: LucideIcons.arrowUp, libelle: 'Monter la question', onPressed: i == 0 ? null : () => setState(() => qs.insert(i - 1, qs.removeAt(i)))),
              BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier la question', onPressed: () => _editer(q, i)),
              const SizedBox(width: 4),
              BoutonIcone(icone: LucideIcons.trash2, libelle: 'Retirer la question', onPressed: () => setState(() => qs.removeAt(i))),
            ])),
      Align(
          alignment: Alignment.centerLeft,
          child: BoutonSigh(
              libelle: 'Ajouter une question',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed: () => _editer(null, -1))),
    ]);
  }

  void _editer(Fiche? q, int idx) {
    final qs = widget.questions;
    final champs = [
      const ChampDef(nom: 'libelle', libelle: 'Question', requis: true, col: ColChamp.plein),
      ChampDef(nom: 'section', libelle: 'Section du formulaire', col: ColChamp.plein, aide: 'Les questions qui se suivent sous le même titre forment une carte.'),
      ChampDef(nom: 'type', libelle: 'Type de réponse', type: TypeChamp.select, requis: true, options: [for (final x in _typesQuestion) OptionChamp(x.$1, x.$2)]),
      const ChampDef(nom: 'requis', libelle: 'Réponse obligatoire', type: TypeChamp.case_),
      const ChampDef(nom: 'optionsTexte', libelle: 'Choix proposés (séparés par |)', col: ColChamp.plein, aide: 'Pour une question à choix.'),
      const ChampDef(nom: 'unite', libelle: 'Unité (nombre)', condition: (controle: 'type', quand: ['nombre'])),
      const ChampDef(nom: 'min', libelle: 'Minimum', type: TypeChamp.nombre, condition: (controle: 'type', quand: ['nombre'])),
      const ChampDef(nom: 'max', libelle: 'Maximum', type: TypeChamp.nombre, condition: (controle: 'type', quand: ['nombre'])),
    ];
    final ctl = ControleurFormulaire(champs, {
      'libelle': q?['libelle'],
      'section': q?['section'] ?? (qs.isEmpty ? 'Questions' : qs.last['section']),
      'type': q?['type'] ?? 'texte',
      'requis': q?['requis'] == true,
      'optionsTexte': (q?['options'] as List? ?? const []).join('|'),
      'unite': q?['unite'],
      'min': q?['min'] == null ? '' : '${q!['min']}',
      'max': q?['max'] == null ? '' : '${q!['max']}',
    });
    afficherModale<void>(widget.ecran,
        titre: q != null ? 'Modifier la question' : 'Nouvelle question',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: q != null ? 'Enregistrer' : 'Ajouter',
                  icone: q != null ? LucideIcons.save : LucideIcons.plus,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final optionsTexte = '${v['optionsTexte'] ?? ''}';
                    if (v['type'] == 'choix' && optionsTexte.trim().isEmpty) {
                      ToastsSigh.afficher(widget.ecran, 'Une question à choix a besoin de ses choix.', type: TypeToast.erreur);
                      return;
                    }
                    final neuf = <String, Object?>{
                      'code': q != null ? q['code'] : _codeNeuf(qs),
                      'libelle': '${v['libelle']}'.trim(),
                      'section': '${v['section'] ?? ''}'.trim(),
                      'type': v['type'],
                      if (v['requis'] == true) 'requis': true,
                      if (v['type'] == 'choix') 'options': [for (final x in optionsTexte.split('|')) if (x.trim().isNotEmpty) x.trim()],
                      if (v['type'] == 'nombre' && '${v['unite'] ?? ''}'.trim().isNotEmpty) 'unite': '${v['unite']}'.trim(),
                      if (v['type'] == 'nombre' && '${v['min'] ?? ''}'.trim().isNotEmpty) 'min': nombreOuZero(v['min']),
                      if (v['type'] == 'nombre' && '${v['max'] ?? ''}'.trim().isNotEmpty) 'max': nombreOuZero(v['max']),
                    };
                    fermer();
                    setState(() {
                      if (q != null) {
                        qs[idx] = neuf;
                      } else {
                        qs.add(neuf);
                      }
                    });
                  }),
            ]);
  }

  /// Un code unique dans le modèle, lisible : `qN`.
  String _codeNeuf(List<Fiche> qs) {
    var n = qs.length + 1;
    while (qs.any((q) => q['code'] == 'q$n')) {
      n++;
    }
    return 'q$n';
  }
}
