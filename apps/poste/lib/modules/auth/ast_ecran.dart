import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_assistant.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';

/// `sup-assistant` : L'ASSISTANT (lot AST-1, décision de la Direction du 15/11/2026). Module SUP, hors ruban comme l'aide ; écran universel : tout agent authentifié l'ouvre,
/// et CHAQUE réponse est filtrée par ses droits (matrice en force, catégories sensibles, habilitations métier du résultat).
///
/// Ce que l'écran ne fait jamais : écrire (le contexte de lecture n'a aucun écrivain ; une commande d'écriture est REFUSÉE en nommant l'écran qui l'accueille), inventer
/// (toute réponse cite sa source, ou dit « non calculable », « pas de données », « vous n'avez pas le droit »), donner un avis médical, ouvrir le réseau.
class EcranAssistant extends StatefulWidget with EcranMaquette {
  const EcranAssistant({super.key, this.service});

  /// Pour les tests : un service posé de l'extérieur (mémoire, horloge fixée).
  final ServiceAssistant? service;

  @override
  String get titre => 'Assistant';
  @override
  String get description => 'Poser une question en français sur les données que votre profil peut lire : la réponse cite sa source, ne modifie rien et dit quand elle ne sait pas.';

  @override
  State<EcranAssistant> createState() => _EcranAssistantState();
}

/// Le contexte de LECTURE d'une question, construit des droits de l'écran : jamais un nom de rôle. Public pour que les tests posent la même construction.
ContexteAst contexteAssistant(ContexteEcran c) {
  final Magasin m = c.magasin;
  final matrice = c.donnees?.matrice;
  // La coque sait quels écrans sont ouverts au profil (matrice à chaud, activités fermées) ; à défaut la matrice ; à défaut rien n'est lu (jamais « tout est ouvert »).
  bool voit(String e) => c.ouvre != null ? c.ouvre!(e) : (matrice?.peutVoir(c.role, e) ?? false);
  final a = c.agent;
  return ContexteAst(
    role: c.role,
    lire: (nom) => m.collection(nom).actives,
    peutVoirEcran: voit,
    sensibles: DroitsSensibles(fiches: m.collection('rbac').actives, peutVoirEcran: (role, ecran) => role == c.role ? voit(ecran) : (matrice?.peutVoir(role, ecran) ?? false)),
    maintenant: c.aujourdhui,
    session: SessionLabo(role: c.role, fonction: a.fonction, secteur: a.secteur, id: a.utilisateurId, nom: a.nom),
    libelleEcran: (e) => c.donnees?.manifeste.ecran(e)?.label ?? e,
  );
}

class _EcranAssistantState extends State<EcranAssistant> {
  ServiceAssistant? _service;
  final _champ = TextEditingController();
  final _focus = FocusNode();
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final c = ContexteEcran.of(context);
    _service = widget.service ??
        ServiceAssistant(
          stockage: ServiceAssistant.stockageDuPoste ?? StockageMemoire(),
          agent: c.agent.utilisateurId,
          retention: () => ServiceAssistant.retentionDepuis(c.magasin, c.aujourdhui),
          maintenant: () => c.aujourdhui,
        );
    _service!.addListener(_changement);
    _service!.charger();
  }

  void _changement() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service?.removeListener(_changement);
    _champ.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Un exemple ou une proposition se POSE dans le champ, il ne part pas tout seul : les exemples portent un nom neutre (« EXEMPLE/Patient ») que l'agent remplace.
  void _remplir(String texte) {
    _champ.text = texte;
    _champ.selection = TextSelection.collapsed(offset: texte.length);
    _focus.requestFocus();
  }

  Future<void> _poser(String texte) async {
    final q = texte.trim();
    if (q.isEmpty) return;
    _champ.clear();
    await _service!.poser(q, contexteAssistant(ContexteEcran.of(context)));
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final s = _service;
    final cx = contexteAssistant(c);
    final exemples = (s?.moteur ?? AssistantAst()).exemples(cx);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(
          'Lecture seule : l’assistant ne modifie rien, ne donne aucun avis médical et n’envoie rien hors de la clinique. Chaque réponse cite sa source ; ce que votre profil ne lit pas ne vous est jamais montré.'
          '${s == null ? '' : ' Votre conversation reste sur ce poste, chiffrée, et s’efface après ${s.joursConservation} jours.'}',
          icone: LucideIcons.shieldCheck),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Votre question',
          actions: [
            if (s != null && s.tours.isNotEmpty)
              BoutonSigh(
                  key: const Key('assistant:effacer'),
                  libelle: 'Effacer la conversation',
                  icone: LucideIcons.trash2,
                  variante: VarianteBouton.fantome,
                  taille: TailleBouton.sm,
                  onPressed: () async {
                    final ok = await confirmerSigh(context,
                        titre: 'Effacer la conversation ?', message: 'Votre conversation avec l’assistant sera effacée de ce poste. Aucune donnée de la clinique n’est touchée.', libelleOk: 'Effacer', dangereux: true);
                    if (ok) await s.effacer();
                  }),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: TextField(
                      key: const Key('assistant:champ'),
                      controller: _champ,
                      focusNode: _focus,
                      maxLength: astQuestionMax,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _poser,
                      decoration: const InputDecoration(hintText: 'Ex. : Combien doit encore le patient CBG/12/26 ?', counterText: '', isDense: true, border: OutlineInputBorder()),
                      style: const TextStyle(fontSize: 14))),
              const SizedBox(width: 8),
              BoutonSigh(key: const Key('assistant:envoyer'), libelle: 'Demander', icone: LucideIcons.send, onPressed: s == null || !s.charge ? null : () => _poser(_champ.text)),
            ]),
            if (exemples.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in exemples.take(8))
                  ActionChip(
                      key: Key('assistant:exemple-${exemples.indexOf(e)}'),
                      label: Text(e, style: const TextStyle(fontSize: 12)),
                      onPressed: s == null || !s.charge ? null : () => _remplir(e)),
              ]),
            ],
          ])),
      const SizedBox(height: 16),
      if (s == null || !s.charge)
        const Padding(key: Key('assistant:chargement'), padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator()))
      else ...[
        if (s.erreur != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: NoteSigh(s.erreur!, ton: TonSigh.attention, icone: LucideIcons.triangleAlert, key: const Key('assistant:erreur'))),
        if (s.tours.isEmpty)
          const VideSigh('Aucune question pour l’instant', indice: 'Posez une question ci-dessus, ou choisissez un exemple : il ne propose que ce que votre profil peut lire.', icone: LucideIcons.sparkles, key: Key('assistant:vide'))
        else
          for (final (i, t) in s.tours.reversed.indexed) ...[
            _Tour(key: Key('assistant:tour-$i'), tour: t, contexte: c, surProposition: _remplir),
            const SizedBox(height: 16),
          ],
      ],
    ]);
  }
}

class _Tour extends StatelessWidget {
  const _Tour({super.key, required this.tour, required this.contexte, required this.surProposition});
  final TourAst tour;
  final ContexteEcran contexte;
  final void Function(String) surProposition;

  @override
  Widget build(BuildContext context) {
    final r = tour.reponse;
    final ton = switch (r.statut) {
      'reponse' => TonSigh.succes,
      'refus' => TonSigh.danger,
      'non_calculable' || 'pas_de_donnees' || 'precision' || 'ambigue' => TonSigh.attention,
      _ => TonSigh.neutre,
    };
    final cat = CatalogueAst();
    final ouvre = contexteAssistant(contexte).peutVoirEcran;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
          alignment: Alignment.centerRight,
          child: Container(
              key: const Key('assistant:question'),
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: JetonsShell.navy50, borderRadius: BorderRadius.circular(12), border: Border.all(color: JetonsShell.navy200)),
              child: Text(tour.question, style: const TextStyle(color: JetonsShell.navy900, fontSize: 14, height: 20 / 14)))),
      const SizedBox(height: 8),
      Align(
          alignment: Alignment.centerLeft,
          child: Container(
              constraints: const BoxConstraints(maxWidth: 820),
              padding: const EdgeInsets.all(16),
              decoration: decorationCarte(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(r.titre, key: const Key('assistant:titre'), style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
                  if (r.code != null) BadgeSigh(r.code!, ton: ton),
                ]),
                for (final l in r.lignes) ...[
                  const SizedBox(height: 6),
                  Text(l, style: const TextStyle(color: JetonsShell.slate600, fontSize: 13, height: 19 / 13)),
                ],
                if (r.tableau != null) ...[const SizedBox(height: 12), _Tableau(r.tableau!)],
                if (r.propositions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final p in r.propositions)
                      ActionChip(
                          key: Key('assistant:proposition-$p'),
                          label: Text(cat[p]?.exemple.isNotEmpty == true ? cat[p]!.exemple : (cat[p]?.libelle ?? p), style: const TextStyle(fontSize: 12)),
                          onPressed: () => surProposition(cat[p]?.exemple.isNotEmpty == true ? cat[p]!.exemple : p)),
                  ]),
                ],
                if (r.ecranRenvoi != null && ouvre(r.ecranRenvoi!)) ...[
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: BoutonSigh(
                          key: Key('assistant:ouvrir-${r.ecranRenvoi}'),
                          libelle: 'Ouvrir « ${contexte.donnees?.manifeste.ecran(r.ecranRenvoi!)?.label ?? r.ecranRenvoi} »',
                          icone: LucideIcons.externalLink,
                          variante: VarianteBouton.secondaire,
                          taille: TailleBouton.sm,
                          onPressed: () => contexte.aller(r.ecranRenvoi!))),
                ],
                if (r.sources.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('Source :', style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                    for (final s in r.sources)
                      // Un lien n'existe que vers un écran que l'agent voit AUJOURD'HUI (la réponse a pu être donnée sous d'autres droits).
                      if (ouvre(s.ecran))
                        InkWell(
                            key: Key('assistant:source-${s.ecran}'),
                            onTap: () => contexte.aller(s.ecran),
                            child: Text('${contexte.donnees?.manifeste.ecran(s.ecran)?.label ?? s.ecran} (${s.collection})',
                                style: const TextStyle(color: JetonsShell.navy700, fontSize: 12, decoration: TextDecoration.underline)))
                      else
                        Text('${contexte.donnees?.manifeste.ecran(s.ecran)?.label ?? s.ecran} (${s.collection})', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12)),
                  ]),
                ],
              ]))),
    ]);
  }
}

class _Tableau extends StatelessWidget {
  const _Tableau(this.t);
  final TableauAst t;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: const TableBorder(horizontalInside: BorderSide(color: JetonsShell.slate100), bottom: BorderSide(color: JetonsShell.slate200)),
          children: [
            TableRow(children: [for (final c in t.colonnes) _cellule(c, entete: true)]),
            for (final l in t.lignes) TableRow(children: [for (final c in l) _cellule(c)]),
          ]));

  Widget _cellule(String texte, {bool entete = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(texte, style: TextStyle(color: entete ? JetonsShell.slate500 : JetonsShell.slate800, fontSize: 12, fontWeight: entete ? FontWeight.w600 : FontWeight.w400)));
}
