import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import '../../impression/piece.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m4/mat_commun.dart';
import '../m4/mat_crud.dart';
import 'rha_commun.dart';
import 'rha_fiche_employe.dart';

/// `m10-personnel` — dossiers des agents (identité, fonction, catégorie, ancienneté, N° CNSS, rémunération de base). Registre `K.crud` ; la fiche du tiroir est
/// `ficheEmploye` (six onglets) ; la fiche individuelle s'imprime. Indicateurs et ancienneté : `rha_regles.dart`, rejoués sur les vecteurs de la maquette.
class EcranPersonnel extends StatelessWidget with EcranMaquette {
  const EcranPersonnel({super.key});
  @override
  String get titre => 'Personnel';
  @override
  String get description => 'Dossiers des agents : identité, fonction, catégorie, ancienneté, numéro CNSS et rémunération de base.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('personnel');
    return CrudMat(
      collection: col,
      entite: 'agent',
      entiteP: 'agents',
      prefixeId: 'PER',
      triInitial: 'matricule',
      taillePage: 15,
      largeurTiroir: 768,
      source: 'Organigramme de la ${IdentiteClinique.nomCourt}.',
      colonnes: [
        ColonneTableau(cle: 'matricule', libelle: 'Mat.', droite: true, sansCoupure: true, rendu: (_, r) => matRef('${r['matricule']}')),
        ColonneTableau(
            cle: 'nomComplet',
            libelle: 'Agent',
            rendu: (_, r) => Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: JetonsShell.slate100, shape: BoxShape.circle),
                      child: Text(rhaInitiales(r['nomComplet']), style: const TextStyle(color: JetonsShell.slate600, fontSize: 10, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Flexible(child: matCelPatient('${r['nomComplet']}', '${r['poste'] ?? ''}', mono: false)),
                ])),
        ColonneTableau(cle: 'fonction', libelle: 'Fonction', texte: (r) => rhaFonctionLabel(r['fonction']), rendu: (_, r) => BadgeSigh(rhaFonctionLabel(r['fonction']), ton: TonSigh.navy)),
        const ColonneTableau(cle: 'service', libelle: 'Service'),
        const ColonneTableau(cle: 'categorie', libelle: 'Cat./Éch.', droite: true),
        ColonneTableau(
            cle: 'anciennete',
            libelle: 'Ancienneté',
            droite: true,
            valeur: (r) => rhaJoursEntre(r['dateEmbauche'], c.aujourdhui),
            texte: (r) {
              final a = rhaAnciennete(r['dateEmbauche'], c.aujourdhui);
              return '${a.ans} ans ${a.mois} mois';
            },
            rendu: (_, r) => Text(rhaAncienneteCourte(r['dateEmbauche'], c.aujourdhui))),
        ColonneTableau(cle: 'cnss', libelle: 'N° CNSS', sansCoupure: true, rendu: (_, r) => Text('${r['cnss'] ?? ''}', style: const TextStyle(fontFamily: matPoliceMono, fontSize: 12, color: JetonsShell.slate500))),
        ColonneTableau(
            cle: 'salaireBase',
            libelle: 'Salaire de base',
            droite: true,
            texte: (r) => '${moneyOu(r['salaireBase'], 'Non renseigné', false)}${r['salaireProvisoire'] == true ? ' (provisoire)' : ''}',
            // Le marquage « provisoire » reste VISIBLE tant que la valeur n'est pas arrêtée : l'icône ET le libellé, jamais la couleur seule.
            rendu: (_, r) => Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 2, children: [
                  if (r['salaireProvisoire'] == true) const BadgeSigh('provisoire', ton: TonSigh.attention, icone: LucideIcons.hourglass),
                  Text(moneyOu(r['salaireBase'], 'Non renseigné', false), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: JetonsShell.slate800)),
                ])),
      ],
      champs: (m) => [
        const ChampDef.section('Identité'),
        const ChampDef(nom: 'matricule', libelle: 'Matricule', requis: true),
        const ChampDef(nom: 'nom', libelle: 'Nom', requis: true),
        const ChampDef(nom: 'prenom', libelle: 'Prénom(s)', requis: true),
        const ChampDef(nom: 'sexe', libelle: 'Sexe', type: TypeChamp.select, requis: true, options: [OptionChamp('M', 'Masculin'), OptionChamp('F', 'Féminin')]),
        const ChampDef(nom: 'telephone', libelle: 'Téléphone', type: TypeChamp.tel),
        ChampDef(nom: 'situation', libelle: 'Situation matrimoniale', type: TypeChamp.select, options: rhaOptions(rhaSituations)),
        const ChampDef.section('Affectation'),
        ChampDef(nom: 'fonction', libelle: 'Fonction', type: TypeChamp.select, requis: true, options: rhaOptionsFonctions()),
        const ChampDef(nom: 'poste', libelle: 'Poste occupé', col: ColChamp.plein),
        ChampDef(
            nom: 'titreOrganigramme',
            libelle: 'Titre à l’organigramme',
            indicatif: 'ex. SG',
            aide: 'Facultatif, douze caractères au plus : le titre que l’agent porte à l’organigramme quand il diffère de son poste (un infirmier surveillant général).',
            valider: (v, _) => '${v ?? ''}'.trim().length > 12 ? 'Douze caractères au plus.' : null),
        ChampDef(nom: 'service', libelle: 'Service', type: TypeChamp.select, requis: true, options: rhaOptions(rhaServices)),
        const ChampDef(nom: 'categorie', libelle: 'Catégorie / échelon', indicatif: 'ex. E3-1'),
        const ChampDef(nom: 'dateEmbauche', libelle: 'Date d’embauche', type: TypeChamp.date, requis: true),
        const ChampDef.section('Rémunération et couverture sociale'),
        const ChampDef(nom: 'salaireBase', libelle: 'Salaire de base (FCFA)', type: TypeChamp.nombre, requis: true),
        const ChampDef(nom: 'cnss', libelle: 'Numéro CNSS'),
      ],
      valeursInitiales: () => {'dateEmbauche': iso(c.aujourdhui), 'salaireBase': '60000', 'categorie': 'E1-1', 'sexe': 'F'},
      transformer: (ctx, v) => rhaAgentEnregistrable({...v, 'salaireBase': rhaNum(v['salaireBase'])}),
      // MODIFIER une valeur d'attente (salaire, date d'embauche) l'ARRÊTE : le drapeau « provisoire » tombe dans la même écriture, donc au même journal (RG-12 :
      // ancienne et nouvelle valeur, drapeau compris). Une valeur laissée telle quelle garde son marquage.
      transformerExistante: (ctx, v, existante) {
        final f = rhaAgentEnregistrable({...v, 'salaireBase': rhaNum(v['salaireBase'])});
        return {...f, ...rhaValeursArretees(existante, f, rhaAttentePersonnel)};
      },
      intro: (ctx) {
        final actifs = col.actives;
        final salaires = actifs.where((a) => a['salaireProvisoire'] == true).length;
        final dates = actifs.where((a) => a['dateEmbaucheProvisoire'] == true).length;
        if (salaires + dates == 0) return const SizedBox.shrink();
        return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: NoteSigh(
                'Valeurs d’attente : $salaires salaire(s) et $dates date(s) d’embauche sont PROVISOIRES (marqués « provisoire »). Ils le restent tant que la Direction n’a pas remis la valeur : la modifier depuis la fiche de l’agent l’arrête et retire le marquage (journalisé).',
                ton: TonSigh.attention,
                icone: LucideIcons.hourglass));
      },
      filtres: [
        FiltreTableau(nom: 'fonction', libelle: 'Fonction', options: rhaOptionsFonctions()),
        FiltreTableau(nom: 'service', libelle: 'Service', options: rhaOptions(rhaServices)),
        const FiltreTableau(nom: 'sexe', libelle: 'Sexe', options: [OptionChamp('M', 'Masculin'), OptionChamp('F', 'Féminin')]),
      ],
      kpis: (ctx, rows) => rhaKpisW(rhaKpisPersonnel(rows), const [LucideIcons.usersRound, LucideIcons.banknote, LucideIcons.calculator, LucideIcons.users]),
      detail: (ctx, f) => FicheEmploye(agent: f, c: ContexteEcran.of(ctx), ctx: ctx),
      etat: (ctx, e) => matImprimer(ctx,
          titre: 'Fiche individuelle de l’agent',
          sousTitre: '${e['nomComplet']} — matricule ${e['matricule']}',
          cartouche: [
            ('Matricule', '${e['matricule']}'),
            ('Nom et prénoms', '${e['nomComplet']}'),
            ('Fonction', rhaFonctionLabel(e['fonction'])),
            ('Service', '${e['service'] ?? ''}'),
            ('Catégorie / échelon', '${e['categorie'] ?? ''}'),
            ('Ancienneté', rhaAncienneteLongue(e['dateEmbauche'], c.aujourdhui)),
          ],
          blocs: [
            matBlocRubriques([
              ('Sexe', e['sexe'] == 'F' ? 'Féminin' : 'Masculin'),
              ('Situation matrimoniale', '${e['situation'] ?? ''}'),
              ('Téléphone', '${e['telephone'] ?? ''}'),
              ('Date d’embauche', rhaDateFR(e['dateEmbauche'])),
              ('Poste occupé', '${e['poste'] ?? ''}'),
              ('Numéro CNSS', '${e['cnss'] ?? ''}'),
              ('Salaire de base', moneyOu(e['salaireBase'])),
            ]),
          ],
          signatures: [Signature('L’Agent', nom: '${e['nomComplet']}'), rhaSignDa]),
    );
  }
}
