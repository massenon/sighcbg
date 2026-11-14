import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';

/// La VUE CALENDRIER de `m12-echeances` : l'exercice en douze mois, chaque échéance dans le mois de sa date (reportée au jour ouvrable le cas échéant).
/// Une vue du même suivi, jamais une seconde collection : elle lit les lignes que le tableau lit, avec leur état CALCULÉ, et chaque échéance ouvre sa fiche
/// de suivi (valider le paiement, éditer la quittance).
///
/// L'état ne se lit JAMAIS à la couleur seule : chaque échéance porte une icône ET un libellé (« En retard » avec l'alarme, « Payée » avec la coche...), et
/// le délai en jours quand il compte. Un mois sans échéance le dit.
const List<String> _mois = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
];

IconData _icone(String etat) => switch (etat) {
      'payee' => LucideIcons.circleCheck,
      'en_retard' => LucideIcons.alarmClock,
      'a_payer' => LucideIcons.coins,
      'declaration' => LucideIcons.fileSignature,
      _ => LucideIcons.calendar,
    };

TonSigh _ton(String t) => switch (t) {
      'succes' => TonSigh.succes,
      'danger' => TonSigh.danger,
      'attention' => TonSigh.attention,
      'info' => TonSigh.info,
      _ => TonSigh.neutre,
    };

/// Les échéances de [lignes] (avec leur `etat` calculé) rangées par mois de l'exercice [annee] : douze listes, triées par date.
List<List<Fiche>> echeancesParMois(List<Fiche> lignes, int annee) {
  final out = List.generate(12, (_) => <Fiche>[]);
  for (final e in lignes) {
    final d = DateTime.tryParse('${e['echeance']}');
    if (d == null || d.year != annee) continue;
    out[d.month - 1].add(e);
  }
  for (final l in out) {
    l.sort((a, b) => '${a['echeance']}'.compareTo('${b['echeance']}'));
  }
  return out;
}

Widget calendrierEcheances(BuildContext context, {required List<Fiche> lignes, required int annee, required void Function(Fiche) ouvrir}) {
  final parMois = echeancesParMois(lignes, annee);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          for (final s in cpcEtatsEcheance) BadgeSigh(s.$2, ton: _ton(s.$3), icone: _icone(s.$1)),
        ])),
    LayoutBuilder(builder: (ctx, box) {
      final colonnes = box.maxWidth >= 1100 ? 3 : (box.maxWidth >= 700 ? 2 : 1);
      const gouttiere = 12.0;
      final largeur = (box.maxWidth - gouttiere * (colonnes - 1)) / colonnes;
      return Wrap(spacing: gouttiere, runSpacing: gouttiere, children: [
        for (var i = 0; i < 12; i++) SizedBox(width: largeur, child: _mois_(context, i, parMois[i], annee, ouvrir)),
      ]);
    }),
  ]);
}

Widget _mois_(BuildContext context, int i, List<Fiche> echeances, int annee, void Function(Fiche) ouvrir) {
  final enRetard = echeances.where((e) => e['etat'] == 'en_retard').length;
  return Container(
    key: Key('cpc:cal:mois:${i + 1}'),
    decoration: BoxDecoration(
        color: Colors.white, border: Border.all(color: enRetard > 0 ? JetonsShell.danger200 : JetonsShell.slate200), borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.vertical(top: Radius.circular(9))),
        child: Row(children: [
          Expanded(
              child: Text('${_mois[i]} $annee',
                  style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
          if (enRetard > 0) BadgeSigh('$enRetard en retard', ton: TonSigh.danger, icone: LucideIcons.alarmClock),
          if (enRetard == 0 && echeances.isNotEmpty)
            Text('${echeances.length} échéance(s)', style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
        ]),
      ),
      if (echeances.isEmpty)
        const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Aucune échéance ce mois-ci.', style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12)))
      else
        for (final e in echeances) _ligne(e, ouvrir),
    ]),
  );
}

Widget _ligne(Fiche e, void Function(Fiche) ouvrir) {
  final etat = '${e['etat']}';
  final (_, libelle, ton) = cpcEtat(etat);
  final d = DateTime.tryParse('${e['echeance']}');
  final jours = e['jours'] is int ? e['jours'] as int : 0;
  final delai = e['paye'] == true ? '' : (jours < 0 ? ' · ${jours.abs()} j de retard' : ' · dans $jours j');
  return InkWell(
    key: Key('cpc:cal:${e['code']}:${e['echeance']}'),
    onTap: () => ouvrir(e),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
            width: 28,
            child: Text(d == null ? '' : '${d.day}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]))),
        const SizedBox(width: 10),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${e['code']}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w600)),
          Text('${e['libelle']}${e['reportee'] == true ? ' · reportée au jour ouvrable' : ''}$delai',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JetonsShell.slate500, fontSize: 11, height: 15 / 11)),
        ])),
        const SizedBox(width: 8),
        BadgeSigh(libelle, ton: _ton(ton), icone: _icone(etat)),
      ]),
    ),
  );
}
