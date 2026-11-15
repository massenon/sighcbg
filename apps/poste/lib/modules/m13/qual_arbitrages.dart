import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/arbitrages_poste.dart';
import '../../donnees/magasin.dart';
import '../../donnees/tarifs_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../cfg/tarifs_ecran.dart';

/// LES ARBITRAGES À RENDRE du centre des validations (décisions du 16/11/2026). Deux sortes de lignes, aucune ne bloque personne :
///  * un PRIX EN DOUBLON (« Prix en doublon à arbitrer : CERT-APT ») : les deux candidats, « Garder celui-ci » archive l'autre avec motif (RG-14) — geste réservé de la matrice « décider un prix » ;
///  * un CONFLIT DE COUVERTURE (deux couvertures ouvertes pour un même patient après deux postes hors ligne) : « Clore celle-ci » avec motif — droit d'écrire « Assurés & cartes ».
/// Les commandes sont ABSENTES (jamais grisées) sans le droit : la ligne se lit, elle ne se tranche pas.
List<Widget> arbitragesARendre(BuildContext context, ContexteEcran c) {
  final m = c.magasin;
  final tarifs = tarifsDeLEcran(c, droitPrix: 'cfg-tarifs');
  final doublons = TarifsPoste.doublonsPrix(m);
  final conflits = ArbitragesPoste.conflitsCouverture(m);
  if (doublons.isEmpty && conflits.isEmpty) return const [];
  final peutPrix = tarifs.peutDecider;
  final peutCouverture = c.donnees?.matrice.peutEditer(c.role, 'm9-assures') ?? false;
  String prix(Fiche f) {
    final na = tarPrixNADe(f), pa = tarPrixADe(f);
    return '${na == null ? 'sans prix' : money(na, avecDevise: false)} non assuré${pa == null ? '' : ' · ${money(pa, avecDevise: false)} assuré'}';
  }

  Widget bloc({required Key cle, required String titre, required String detail, required List<Widget> lignes}) => Container(
      key: cle,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: JetonsShell.warning50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.warning200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
        Text(detail, style: const TextStyle(color: JetonsShell.slate600, fontSize: 12, height: 16 / 12)),
        const SizedBox(height: 8),
        ...lignes,
      ]));

  Widget candidat({required Key cle, required String texte, required String libelleBouton, required VoidCallback? action}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(texte, style: const TextStyle(color: JetonsShell.slate700, fontSize: 13, height: 18 / 13))),
        if (action != null) ...[
          const SizedBox(width: 12),
          BoutonSigh(key: cle, libelle: libelleBouton, icone: LucideIcons.check, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: action),
        ],
      ]));

  return [
    const SizedBox(height: 16),
    CarteSigh(
        titre: 'Arbitrages à rendre : choisir ce qui fait foi, sans bloquer personne',
        child: Column(children: [
          for (final (i, d) in doublons.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            bloc(
                cle: Key('arb:doublon:${d.cle}'),
                titre: 'Prix en doublon à arbitrer : ${d.code}',
                detail:
                    'Le même code porte ${d.candidats.length} lignes aux prix différents. En attendant, la caisse lit la première ligne, sans blocage. « Garder celui-ci » archive les autres (RG-14, rien n’est supprimé) avec votre motif${peutPrix ? '' : ' : le choix revient au profil qui décide les prix'}.',
                lignes: [
                  for (final f in d.candidats)
                    candidat(
                        cle: Key('arb:doublon:garder:${f['id']}'),
                        texte: '${f['libelle'] ?? d.code} (${f['id']}) : ${prix(f)}${f == d.candidats.first ? ' · lu par la caisse' : ''}',
                        libelleBouton: 'Garder celui-ci',
                        action: peutPrix ? () => _garder(context, c, tarifs, d, f) : null),
                ]),
          ],
          for (final (i, g) in conflits.indexed) ...[
            if (i > 0 || doublons.isNotEmpty) const SizedBox(height: 8),
            bloc(
                cle: Key('arb:couv:${g.first['patientId']}'),
                titre: 'Conflit de couverture à arbitrer : ${g.first['patientCode'] ?? g.first['patient'] ?? g.first['patientId']}',
                detail:
                    'Deux postes ont changé la couverture de ce patient hors ligne : plusieurs couvertures restent ouvertes. En attendant, la plus récente (début) s’applique, jamais deux à la fois. Clore l’une des deux avec un motif${peutCouverture ? '' : ' : le droit d’écrire « Assurés & cartes » est requis'}.',
                lignes: [
                  for (final f in g)
                    candidat(
                        cle: Key('arb:couv:clore:${f['id']}'),
                        texte: '${f['assureurNom'] ?? f['assureur'] ?? '?'}${f['numeroPolice'] == null ? '' : ' (police ${f['numeroPolice']})'} depuis le ${f['debut'] == null ? 'l’ouverture du dossier' : dateFR(assDate(f['debut']))}${f == g.first ? ' · appliquée en attendant' : ''}',
                        libelleBouton: 'Clore celle-ci',
                        action: peutCouverture ? () => _clore(context, c, g.first['patientId'], f) : null),
                ]),
          ],
        ])),
  ];
}

Future<void> _garder(BuildContext ctx, ContexteEcran c, TarifsPoste tarifs, TarDoublonPrix d, Fiche f) async {
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Garder ce prix pour ${d.code} ?',
      message: 'La ligne « ${f['libelle'] ?? d.code} » reste ; les autres lignes de ce code sont archivées avec votre motif (rien n’est supprimé, RG-14). Si ce prix diffère de celui que la caisse lit, il est mis en vigueur aujourd’hui.',
      libelleOk: 'Garder celui-ci');
  if (motif == null || !ctx.mounted) return;
  final r = tarifs.arbitrerDoublon(d, f['id'], motif);
  if (!r.ok) {
    ToastsSigh.afficher(ctx, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste);
    return;
  }
  ToastsSigh.afficher(ctx, 'Prix de ${d.code} arbitré.', type: TypeToast.succes, detail: 'Les autres lignes sont archivées avec votre motif.');
}

Future<void> _clore(BuildContext ctx, ContexteEcran c, Object? patientId, Fiche f) async {
  final motif = await confirmerAvecMotif(ctx,
      titre: 'Clore cette couverture ?',
      message: 'La couverture « ${f['assureurNom'] ?? f['assureur'] ?? '?'} » est close avec votre motif ; elle reste écrite (RG-14), les pièces émises sous elle la gardent. L’autre couverture reste seule en force.',
      libelleOk: 'Clore celle-ci',
      dangereux: true);
  if (motif == null || !ctx.mounted) return;
  final r = ArbitragesPoste.arbitrerCouverture(c.magasin, patientId: patientId, cloreId: f['id'], motif: motif, jour: tarIso(c.aujourdhui), auteur: c.agent.nom.isEmpty ? 'Utilisateur' : c.agent.nom);
  if (r != null) {
    ToastsSigh.afficher(ctx, r.motif, type: TypeToast.erreur, detail: r.geste);
    return;
  }
  ToastsSigh.afficher(ctx, 'Conflit de couverture arbitré.', type: TypeToast.succes, detail: 'La couverture close reste écrite ; l’alerte retombe.');
}
