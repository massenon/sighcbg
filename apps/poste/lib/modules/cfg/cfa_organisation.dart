import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/donnees_navigation.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/fiche_organigramme.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m14/commun_m14.dart';
import 'cfa_commun.dart';

/// `cfg-organisation` — « Organisation & organigramme » : deux référentiels administrables. Les SECTEURS de la NS 145/08/DA/CBG/2026 donnent la maille
/// réelle des habilitations ; l'ORGANIGRAMME pilote la matrice RBAC (chaque poste porte un rôle). RG-14 — retirer un secteur ou un poste l'archive.
class EcranOrganisation extends StatelessWidget with EcranMaquette {
  const EcranOrganisation({super.key});
  @override
  String get titre => 'Organisation & organigramme';
  @override
  String get description => 'Secteurs de la clinique, structure hiérarchique et rôles qui en découlent.';
  @override
  String get regle =>
      'Deux référentiels administrables. Les secteurs (NS 145/08/DA/CBG/2026) donnent la maille réelle des habilitations et de l’évaluation des services. L’organigramme pilote la matrice RBAC : chaque poste porte un rôle qui détermine son périmètre d’accès. RG-14 — retirer un secteur ou un poste l’archive : rien n’est supprimé, tout se restaure.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      BoutonSigh(libelle: 'Personnel', icone: LucideIcons.users, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m10-personnel')),
      BoutonSigh(libelle: 'Rôles & permissions', icone: LucideIcons.keyRound, variante: VarianteBouton.secondaire, onPressed: () => c.aller('m14-roles')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final secteurs = c.magasin.collection('secteurs');
    final postes = c.magasin.collection('postes');
    return ListenableBuilder(
        listenable: Listenable.merge([secteurs, postes]),
        builder: (ctx, _) {
          final nbRoles = rolesDe(c.magasin).length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cfaLectureSeule(c),
            cfaKpis(cfaKpisOrganisation(
                secteurs: secteurs.actives.length, postes: postes.actives.length, effectif: cfaEffectifTotal(cfaArbre(postes.actives)), roles: nbRoles)),
            const SizedBox(height: 16),
            OngletsSigh(onglets: [
              OngletDef(id: 'secteurs', libelle: 'Secteurs (NS 145)', compte: secteurs.actives.length, construire: (_) => const _OngletSecteurs()),
              OngletDef(id: 'organigramme', libelle: 'Organigramme', compte: postes.actives.length, construire: (_) => const _OngletOrganigramme()),
              OngletDef(id: 'roles', libelle: 'Poste → rôle → accès', construire: (_) => const _OngletRoles()),
            ]),
          ]);
        });
  }
}

List<OptionChamp> _optionsRoles(Magasin m) => [for (final r in rolesDe(m)) OptionChamp(r.id, r.label)];

Widget _badgeRole(Magasin m, Object? role) => BadgeSigh(libelleRole(m, role), ton: TonSigh.navy);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Secteurs (NS 145) »
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletSecteurs extends StatelessWidget {
  const _OngletSecteurs();

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('secteurs');
    return ListenableBuilder(
        listenable: col,
        builder: (ctx, _) {
          final rows = trierPar(col.actives, (s) => s['ordre']);
          return cfaPile([
            NoteSigh(
                '${CfaNs145.reference} — ${CfaNs145.objet}, signée le ${dateFR(DateTime.parse(CfaNs145.dateSignature))} par ${paiSignataireLibelle(c.magasin.collection('personnel').actives, PaiQualite.daf, CfaNs145.signataire)}, avec effet au ${dateFR(DateTime.parse(CfaNs145.dateEffet))}. Une note ultérieure se saisit ici : le référentiel est versionné par sa source, pas par le code.',
                icone: LucideIcons.fileCheck2),
            CfaTableau(
              collection: 'secteurs',
              entite: 'Secteur',
              titreCreation: 'Nouveau secteur',
              prefixeId: 'SEC',
              taillePage: 20,
              triInitial: 'ordre',
              nomExport: 'secteurs',
              colonnes: [
                ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (s) => '${s['code'] ?? ''}', rendu: (_, s) => cfaCode(s['code'])),
                ColonneTableau(cle: 'libelle', libelle: 'Secteur', texte: (s) => '${s['libelle'] ?? ''}', rendu: (_, s) => cfaGras('${s['libelle'] ?? ''}')),
                ColonneTableau(
                    cle: 'responsable',
                    libelle: 'Responsable',
                    texte: (s) => '${s['responsable'] ?? ''} ${s['qualification'] ?? ''}'.trim(),
                    rendu: (_, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(cfaOuTiret(s['responsable']), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700)),
                          Text('${s['qualification'] ?? ''}', style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate400)),
                        ])),
                ColonneTableau(
                    cle: 'adjoint',
                    libelle: 'Adjoint',
                    texte: (s) => cfaVrai(s['adjoint']) ? '${s['adjoint']}' : 'non désigné',
                    rendu: (_, s) => cfaVrai(s['adjoint'])
                        ? Text('${s['adjoint']}', style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700))
                        : const Text('non désigné', style: TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate300))),
                ColonneTableau(cle: 'role', libelle: 'Rôle RBAC', texte: (s) => libelleRole(c.magasin, s['role']), rendu: (_, s) => _badgeRole(c.magasin, s['role'])),
              ],
              champs: (e) => [
                const ChampDef(nom: 'libelle', libelle: 'Secteur', requis: true, col: ColChamp.plein),
                const ChampDef(nom: 'code', libelle: 'Code', aide: 'Trois lettres, laisser vide pour une attribution automatique.'),
                ChampDef(
                    nom: 'role',
                    libelle: 'Rôle RBAC rattaché',
                    type: TypeChamp.select,
                    requis: true,
                    options: _optionsRoles(c.magasin),
                    aide: 'Détermine ce que les agents de ce secteur peuvent voir et faire.'),
                const ChampDef(nom: 'responsable', libelle: 'Responsable', col: ColChamp.plein),
                const ChampDef(nom: 'adjoint', libelle: 'Responsable adjoint', col: ColChamp.plein),
                const ChampDef(nom: 'qualification', libelle: 'Qualification'),
                const ChampDef(nom: 'source', libelle: 'Note de service d’origine', col: ColChamp.plein),
              ],
              valeursInitiales: () => {'role': 'agentadmin', 'source': 'Décision de la Direction'},
              fiche: (s, e) => e == null ? cfaFicheSecteur(s, col.toutes.length) : {...s},
              actions: [
                BoutonSigh(
                    libelle: 'Imprimer la répartition',
                    icone: LucideIcons.printer,
                    variante: VarianteBouton.secondaire,
                    taille: TailleBouton.sm,
                    onPressed: () => cfaImprimer(context,
                        titre: 'Répartition des secteurs de la clinique',
                        sousTitre: CfaNs145.reference,
                        cartouche: [
                          ('Objet', CfaNs145.objet),
                          ('Secteurs', nombre(rows.length)),
                          ('Date d’effet', dateFR(DateTime.parse(CfaNs145.dateEffet))),
                          ('Date d’édition', dateFR(c.aujourdhui)),
                        ],
                        blocs: [
                          BlocTableau(TableauEtat(colonnes: [
                            ColonneEtat(libelle: 'N°', droite: true, valeur: (l) => l['ordre']),
                            ColonneEtat(libelle: 'Secteur', valeur: (l) => l['libelle']),
                            ColonneEtat(libelle: 'Responsable', valeur: (l) => cfaOuTiret(l['responsable'])),
                            ColonneEtat(libelle: 'Responsable adjoint', valeur: (l) => cfaOuTiret(l['adjoint'])),
                            ColonneEtat(libelle: 'Qualification', valeur: (l) => cfaOuTiret(l['qualification'])),
                          ], lignes: rows)),
                        ],
                        signatures: const [Signature('La Directrice Administrative', qualite: PaiQualite.daf)])),
              ],
            ),
            cfaSource(CfaNs145.source),
          ], espace: 12);
        });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Organigramme »
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le choix « garder le titulaire actuel » d'un poste dont le nom écrit ne correspond à aucun agent du personnel (nom saisi avant le lien au dossier RH) : il évite
/// qu'une retouche sans rapport (renommer le poste) efface ce nom.
const String _titulaireActuel = '__actuel';

/// Les titulaires possibles : le PERSONNEL actif (jamais une seconde liste de noms), plus « Poste vacant ».
List<OptionChamp> _optionsTitulaires(Magasin m, Fiche? e) {
  final agents = trierPar([...m.collection('personnel').actives], (a) => a['nomComplet']);
  return [
    const OptionChamp('', '— Poste vacant —'),
    if (e != null && cfaVrai(e['titulaire']) && agentDuPoste(m, e) == null) OptionChamp(_titulaireActuel, '${e['titulaire']} (nom conservé, hors personnel)'),
    for (final a in agents) OptionChamp('${a['id']}', '${a['nomComplet']}${cfaVrai(a['poste']) ? ' — ${a['poste']}' : ''}'),
  ];
}

/// La fiche d'un poste telle qu'elle s'écrit : le titulaire choisi au personnel est recopié par son NOM (les lecteurs historiques du champ continuent de
/// fonctionner) avec le lien `personnelId` ; « poste vacant » efface les deux.
Fiche _fichePoste(Magasin m, Map<String, Object?> saisie, Fiche? existante) {
  final v = cfaFichePoste(saisie);
  final choix = '${v['personnelId'] ?? ''}';
  if (choix == _titulaireActuel && existante != null) {
    v['titulaire'] = existante['titulaire'];
    v['personnelId'] = '';
    return v;
  }
  final agent = m.collection('personnel').actives.where((a) => '${a['id']}' == choix).firstOrNull;
  v['titulaire'] = agent == null ? '' : '${agent['nomComplet']}';
  v['personnelId'] = agent == null ? '' : choix;
  return v;
}

class _OngletOrganigramme extends StatelessWidget {
  const _OngletOrganigramme();

  Widget _noeud(Magasin m, CfaNoeud n, int niveau) {
    final carte = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: niveau == 0 ? JetonsShell.navy50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: niveau == 0 ? JetonsShell.navy300 : JetonsShell.slate200)),
      child: Row(children: [
        Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: niveau == 0 ? JetonsShell.navy900 : JetonsShell.slate100, borderRadius: BorderRadius.circular(8)),
            child: Icon(niveau == 0 ? LucideIcons.crown : LucideIcons.user, size: 14, color: niveau == 0 ? Colors.white : JetonsShell.slate500)),
        const SizedBox(width: 8),
        Flexible(child: Text(n.poste, style: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800))),
        const SizedBox(width: 8),
        BadgeSigh('(${n.effectif.toString().padLeft(2, '0')})'),
        const SizedBox(width: 8),
        Flexible(
            child: cfaVrai(n.fiche['titulaire'])
                ? Text('${cfaTitulaireDuPoste(m, n.fiche)}${cfaVrai(n.fiche['chef']) ? ' — chef de service' : ''}',
                    key: Key('organigramme:titulaire:${n.fiche['id']}'), style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500))
                : Text('Poste vacant',
                    key: Key('organigramme:vacant:${n.fiche['id']}'),
                    style: const TextStyle(fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic, color: JetonsShell.slate400))),
        if (cfaVrai(n.fiche['role'])) ...[const Spacer(), _badgeRole(m, n.fiche['role'])],
      ]),
    );
    return Container(
        padding: niveau > 0 ? const EdgeInsets.only(left: 16) : EdgeInsets.zero,
        margin: niveau > 0 ? const EdgeInsets.only(left: 24) : EdgeInsets.zero,
        decoration: niveau > 0 ? const BoxDecoration(border: Border(left: BorderSide(color: JetonsShell.slate200))) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [carte, for (final e in n.enfants) _noeud(m, e, niveau + 1)]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('postes');
    return ListenableBuilder(
        listenable: Listenable.merge([col, c.magasin.collection(ficheDocCollection), c.magasin.collection('personnel')]),
        builder: (ctx, _) {
          final plats = col.actives;
          final racines = cfaArbre(plats);
          String nomDe(Object? id) => plats.where((p) => p['id'] == id).map((p) => '${p['poste']}').firstOrNull ?? '—';
          // L'ORGANIGRAMME IMPRIMÉ : la fiche documentaire paysage (cartouche, graphe, légende) bâtie sur les postes actifs et les paramètres de la fiche.
          void imprimerOrganigramme() => afficherApercuFiche(
              context,
              fichePaysageOrganigramme(c.magasin,
                  utilisateur: acteur(c).nom, edite: c.aujourdhui, reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero())));
          void imprimer() => cfaImprimer(context,
              titre: 'Organigramme de la ${IdentiteClinique.nomCourt}',
              sousTitre: 'Structure organisationnelle et correspondance des rôles',
              cartouche: [
                ('Effectif total', '${nombre(cfaEffectifTotal(racines))} agents'),
                ('Postes distincts', nombre(plats.length)),
                ('Rôles définis', nombre(rolesDe(c.magasin).length)),
                ('Date d’édition', dateFR(c.aujourdhui)),
              ],
              blocs: [
                BlocTableau(TableauEtat(colonnes: [
                  ColonneEtat(libelle: 'Poste', valeur: (l) => l['poste']),
                  ColonneEtat(libelle: 'Rattaché à', valeur: (l) => nomDe(l['parentId'])),
                  ColonneEtat(libelle: 'Effectif', droite: true, valeur: (l) => l['effectif']),
                  ColonneEtat(libelle: 'Titulaire / chef de service', valeur: (l) => cfaVrai(l['titulaire']) ? cfaTitulaireDuPoste(c.magasin, l) : 'Poste vacant'),
                  ColonneEtat(libelle: 'Rôle dans le système', valeur: (l) => libelleRole(c.magasin, l['role'])),
                ], lignes: plats)),
              ],
              signatures: const [Signature('La Directrice Administrative', qualite: PaiQualite.daf), cfaSignDm]);
          return cfaPile([
            CarteSigh(
                titre: 'Organigramme de la ${IdentiteClinique.nomCourt}',
                actions: [
                  BoutonSigh(
                      libelle: 'Imprimer l’organigramme', icone: LucideIcons.printer, variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: imprimerOrganigramme),
                  BoutonSigh(
                      libelle: 'Imprimer la liste des postes', icone: LucideIcons.listOrdered, variante: VarianteBouton.secondaire, taille: TailleBouton.sm, onPressed: imprimer),
                ],
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final r in racines) _noeud(c.magasin, r, 0)])),
            CfaTableau(
              collection: ficheDocCollection,
              titre: 'Fiche imprimée de l’organigramme — cartouche et mention de propriété',
              entite: 'Fiche',
              prefixeId: 'FDO',
              nomExport: 'fiches-documentaires',
              archivable: false,
              creer: false,
              colonnes: [
                const ColonneTableau(cle: 'reference', libelle: 'Référence'),
                ColonneTableau(cle: 'date', libelle: 'Date', texte: (f) => ParametresFiche.depuisFiche(f).dateImprimee),
                const ColonneTableau(cle: 'version', libelle: 'Version'),
                ColonneTableau(cle: 'titre', libelle: 'Titre', texte: (f) => '${f['titreHaut'] ?? ''} / ${f['titre'] ?? ''}'),
                const ColonneTableau(cle: 'mention', libelle: 'Mention de propriété'),
              ],
              champs: (e) => const [
                ChampDef(nom: 'reference', libelle: 'Référence documentaire', requis: true, aide: 'Imprimée dans le cartouche (ex. FCH_GRH_006).'),
                ChampDef(nom: 'date', libelle: 'Date de la fiche', type: TypeChamp.date, requis: true),
                ChampDef(nom: 'version', libelle: 'Version', requis: true),
                ChampDef(nom: 'titreHaut', libelle: 'Titre (haut du cartouche)', requis: true),
                ChampDef(nom: 'titre', libelle: 'Titre (bas du cartouche)', requis: true),
                ChampDef(nom: 'mention', libelle: 'Mention de propriété (pied de page)', requis: true, col: ColChamp.plein),
              ],
            ),
            CfaTableau(
              collection: 'postes',
              titre: 'Postes — création, réaffectation et archivage',
              entite: 'Poste',
              titreCreation: 'Nouveau poste ou département',
              prefixeId: 'PST',
              archivage: (ctx2, col, f) => _archiverPoste(ctx2, col, f),
              taillePage: 20,
              nomExport: 'postes',
              colonnes: [
                ColonneTableau(cle: 'poste', libelle: 'Poste', texte: (p) => '${p['poste'] ?? ''}', rendu: (_, p) => cfaGras('${p['poste'] ?? ''}')),
                ColonneTableau(
                    cle: 'parentId',
                    libelle: 'Rattaché à',
                    texte: (p) => nomDe(p['parentId']),
                    rendu: (_, p) => cfaVrai(p['parentId'])
                        ? Text(nomDe(p['parentId']), style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate600))
                        : const BadgeSigh('Sommet', ton: TonSigh.navy)),
                const ColonneTableau(cle: 'effectif', libelle: 'Effectif', droite: true),
                ColonneTableau(
                    cle: 'titulaire',
                    libelle: 'Titulaire',
                    texte: (p) => cfaVrai(p['titulaire']) ? '${cfaTitulaireDuPoste(c.magasin, p)}${cfaVrai(p['chef']) ? ' — chef de service' : ''}' : 'Poste vacant',
                    rendu: (_, p) => cfaVrai(p['titulaire'])
                        ? Text('${cfaTitulaireDuPoste(c.magasin, p)}${cfaVrai(p['chef']) ? ' — chef de service' : ''}', style: const TextStyle(fontSize: 14, height: 20 / 14, color: JetonsShell.slate700))
                        : const Text('Poste vacant', style: TextStyle(fontSize: 12, height: 16 / 12, fontStyle: FontStyle.italic, color: JetonsShell.slate400))),
                ColonneTableau(cle: 'role', libelle: 'Rôle RBAC', texte: (p) => libelleRole(c.magasin, p['role']), rendu: (_, p) => _badgeRole(c.magasin, p['role'])),
              ],
              champs: (e) {
                final autres = trierPar([for (final p in plats) if (e == null || p['id'] != e['id']) p], (p) => p['poste']);
                return [
                  const ChampDef(nom: 'poste', libelle: 'Intitulé du poste', requis: true, col: ColChamp.plein),
                  ChampDef(
                      nom: 'parentId',
                      libelle: 'Rattaché à',
                      type: TypeChamp.select,
                      options: [const OptionChamp('', '— Sommet de l’organigramme —'), for (final p in autres) OptionChamp('${p['id']}', '${p['poste']}')],
                      aide: 'Déplacer un poste ici le réaffecte, lui et les postes qu’il porte.',
                      valider: (v, _) => e != null && '$v'.isNotEmpty && cfaDescendantsDe(plats, '${e['id']}').contains('$v')
                          ? 'Un poste ne peut pas être rattaché à l’un des postes qu’il porte.'
                          : null),
                  const ChampDef(nom: 'effectif', libelle: 'Effectif', type: TypeChamp.nombre, requis: true),
                  ChampDef(
                      nom: 'personnelId',
                      libelle: 'Titulaire',
                      type: TypeChamp.select,
                      col: ColChamp.plein,
                      options: _optionsTitulaires(c.magasin, e),
                      aide: 'Choisi parmi le personnel : le nom suit son dossier. Aucun titulaire : le poste s’affiche « Poste vacant ». Le titre porté à l’organigramme se règle au dossier de l’agent.'),
                  ChampDef(nom: 'role', libelle: 'Rôle RBAC', type: TypeChamp.select, requis: true, options: _optionsRoles(c.magasin)),
                  const ChampDef(nom: 'chef', libelle: 'Chef de service', type: TypeChamp.case_),
                  const ChampDef.section('Place dans l’organigramme imprimé'),
                  const ChampDef(
                      nom: 'code',
                      libelle: 'Code abrégé',
                      col: ColChamp.tiers,
                      aide: 'Écrit dans la case du graphe et expliqué en légende. Vide : l’intitulé complet s’écrit dans la case, sans légende.'),
                  const ChampDef(nom: 'codeLegende', libelle: 'Code en légende', col: ColChamp.tiers, aide: 'Seulement si la légende l’écrit autrement que la case.'),
                  const ChampDef(nom: 'ordreLegende', libelle: 'Rang en légende', type: TypeChamp.nombre, col: ColChamp.tiers),
                  const ChampDef(nom: 'niveau', libelle: 'Niveau (1 à 6)', type: TypeChamp.nombre, col: ColChamp.tiers, aide: 'Vide : niveau du rattachement + 1.'),
                  const ChampDef(nom: 'x', libelle: 'Position horizontale (centre)', type: TypeChamp.nombre, col: ColChamp.tiers, aide: 'Unités de grille ; x et y vides : le poste est placé automatiquement.'),
                  const ChampDef(nom: 'y', libelle: 'Position verticale (centre)', type: TypeChamp.nombre, col: ColChamp.tiers),
                  const ChampDef(nom: 'largeur', libelle: 'Largeur de la case', type: TypeChamp.nombre, col: ColChamp.tiers),
                  const ChampDef(nom: 'hauteur', libelle: 'Hauteur de la case', type: TypeChamp.nombre, col: ColChamp.tiers),
                  ChampDef(
                      nom: 'lien',
                      libelle: 'Lien au rattachement',
                      type: TypeChamp.select,
                      col: ColChamp.tiers,
                      options: [
                        const OptionChamp('', 'Hiérarchique (par une barre)'),
                        for (final l in organigrammeLiens.skip(1)) OptionChamp(l, l == 'accole' ? 'Accolé (trait horizontal)' : 'Direct (descente droite)'),
                      ]),
                  const ChampDef(nom: 'barre', libelle: 'Hauteur de la barre', type: TypeChamp.nombre, col: ColChamp.tiers, aide: 'Vide : à mi-chemin du rattachement.'),
                  const ChampDef(nom: 'coudeX', libelle: 'Coude du tronc : horizontale', type: TypeChamp.nombre, col: ColChamp.tiers),
                  const ChampDef(nom: 'coudeY', libelle: 'Coude du tronc : verticale', type: TypeChamp.nombre, col: ColChamp.tiers),
                ];
              },
              valeursInitiales: () => {'effectif': '1', 'role': 'agentadmin'},
              fiche: (s, e) => _fichePoste(c.magasin, s, e),
              preparer: (f) => {...f, 'personnelId': '${agentDuPoste(c.magasin, f)?['id'] ?? (cfaVrai(f['titulaire']) ? _titulaireActuel : '')}'},
            ),
            cfaSource('Organigramme de la ${IdentiteClinique.nomCourt} : document de cadrage, désormais administrable.'),
          ], espace: 12);
        });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Onglet « Poste → rôle → accès » (calculé : lecture seule)
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletRoles extends StatelessWidget {
  const _OngletRoles();

  @override
  Widget build(BuildContext context) {
    final nav = cfaNavigationChargee;
    if (nav != null) return _corps(context, nav);
    return FutureBuilder<DonneesNavigation>(
        future: cfaNavigation(),
        builder: (ctx, snap) => snap.hasData ? _corps(ctx, snap.data!) : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
  }

  Widget _corps(BuildContext context, DonneesNavigation nav) {
    final c = ContexteEcran.of(context);
    final plats = c.magasin.collection('postes').actives;
    final memo = <String, List<String>>{};
    // DROITS À CHAUD (A4) : la matrice en force est l'engendrée superposée aux fiches `rbac` et `modulesActifs`, calculée UNE fois pour les 16 postes.
    final vive = nav.aChaud(c.magasin);
    List<String> modules(Object? role) => memo.putIfAbsent('$role', () => cfaModulesDuRole(c.magasin, vive, '$role'));
    final lignes = [
      for (final p in plats) {'poste': p['poste'], 'effectif': p['effectif'], 'titulaire': cfaOuTiret(p['titulaire']), 'role': p['role']}
    ];
    return cfaPile([
      const NoteSigh(
          'État calculé — lecture seule. Cette correspondance est calculée depuis l’organigramme et la matrice RBAC. Pour la modifier, changer le rôle du poste dans l’onglet Organigramme, ou la matrice dans Rôles & permissions.',
          ton: TonSigh.neutre,
          icone: LucideIcons.lock),
      TableauSigh(
        lignes: lignes,
        taillePage: 20,
        nomExport: 'organigramme-rbac',
        colonnes: [
          const ColonneTableau(cle: 'poste', libelle: 'Poste'),
          const ColonneTableau(cle: 'effectif', libelle: 'Effectif', droite: true),
          const ColonneTableau(cle: 'titulaire', libelle: 'Titulaire / chef de service'),
          ColonneTableau(cle: 'role', libelle: 'Rôle RBAC', texte: (l) => libelleRole(c.magasin, l['role']), rendu: (_, l) => _badgeRole(c.magasin, l['role'])),
          ColonneTableau(
              cle: 'modules',
              libelle: 'Modules accessibles',
              texte: (l) => modules(l['role']).join(', '),
              rendu: (_, l) => Wrap(spacing: 4, runSpacing: 4, children: [for (final m in modules(l['role'])) BadgeSigh(m)])),
        ],
      ),
    ], espace: 12);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Archivage d'un poste : ses sous-postes actifs sont réaffectés à son rattachement (décision de la Direction)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// UN geste : la confirmation nomme les sous-postes réaffectés et leur nouveau rattachement ; chaque sous-poste est mis à jour par le magasin (une ligne
/// de journal par sous-poste, ancien et nouveau `parentId` — RG-12) ; le poste porte la liste de ce qui a été réaffecté (la Corbeille la relit) ; rien n'est
/// supprimé (RG-14). L'annulation restitue les rattachements d'origine — sauf ceux qu'on a modifiés entre-temps, qu'elle nomme sans les écraser.
Future<void> _archiverPoste(BuildContext ctx, CollectionMagasin col, Fiche f) async {
  final plan = cfaPlanArchivagePoste(col.actives, '${f['id']}');
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Archiver le poste « ${plan.poste} » ?',
      message: 'Archivage logique (RG-14) : le poste reste consultable et l’opération est annulable. ${plan.phrase}',
      libelleOk: 'Archiver',
      dangereux: true);
  if (motif == null || !ctx.mounted) return;
  for (final r in plan.reaffectations) {
    col.mettreAJour(r.id, {'parentId': r.nouveauParentId});
  }
  if (plan.reaffectations.isNotEmpty) {
    col.mettreAJour(plan.posteId, {'sousPostesReaffectes': [for (final r in plan.reaffectations) r.toJson()]});
  }
  final restaurer = col.archiver(plan.posteId);
  void annuler() {
    restaurer();
    final p = cfaPlanAnnulationArchivage(col.actives, plan.reaffectations);
    for (final r in p.restituables) {
      col.mettreAJour(r.id, {'parentId': r.ancienParentId});
    }
    if (plan.reaffectations.isNotEmpty) col.mettreAJour(plan.posteId, {'sousPostesReaffectes': <Object?>[]});
    if (p.modifies.isNotEmpty) {
      ToastsSigh.afficher(ctx, 'Archivage annulé ; ${p.modifies.length > 1 ? 'des sous-postes ont été modifiés' : 'un sous-poste a été modifié'} entre-temps et n’${p.modifies.length > 1 ? 'ont' : 'a'} pas été remis sous ce poste.',
          type: TypeToast.attention, detail: p.modifies.map((r) => '« ${r.poste} »').join(', '));
    }
  }

  ToastsSigh.afficher(ctx, 'Poste archivé.',
      type: TypeToast.succes,
      detail: plan.reaffectations.isEmpty ? null : plan.phrase,
      annuler: annuler,
      messageAnnulation: 'Archivage annulé — les sous-postes retrouvent leur rattachement.');
}
