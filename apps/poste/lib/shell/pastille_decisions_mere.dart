import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/theme.dart';
import '../donnees/magasin.dart';
import '../sync/alerte_decisions_mere.dart';

/// LA PASTILLE « N décisions en attente de la mère » (section AI, Direction du 16/11/2026) : elle compte les TROIS files — validations déposées, demandes de prix, demandes d'import —
/// et dit l'âge de la plus ancienne. Absente à zéro (un voyant qui n'a rien à dire n'apparaît pas). Au-delà du délai d'alerte de la clinique, elle passe au ton « danger ».
/// Elle se repeint à chaque dépôt ou verdict et chaque minute (l'âge avance même sans écriture). Elle ne décide de rien : l'alerte vit dans le centre de notifications.
class PastilleDecisionsMere extends StatefulWidget {
  const PastilleDecisionsMere({super.key, required this.magasin, this.horloge});
  final Magasin magasin;
  final DateTime Function()? horloge;

  @override
  State<PastilleDecisionsMere> createState() => _PastilleDecisionsMereState();
}

class _PastilleDecisionsMereState extends State<PastilleDecisionsMere> {
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge([m.collection(valCollectionDepots), m.collection(collectionDemandesPrix), m.collection(collectionDemandesImport), m.collection('parametres')]),
        builder: (context, _) {
          final s = AlerteDecisionsMere.de(m);
          if (widget.horloge != null) s.horloge = widget.horloge;
          final r = s.resume();
          if (r.total == 0) return const SizedBox.shrink();
          final retard = r.enRetard > 0;
          final texte = retard ? ThemeSigh.danger : ThemeSigh.attention;
          final fond = retard ? ThemeSigh.dangerFond : ThemeSigh.attentionFond;
          final age = r.plusAncienne == null ? '' : ' · ${libelleAgeDecision(r.plusAncienne!)}';
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: r.detail,
              child: Semantics(
                label: '${r.libelle}. ${r.detail}',
                child: Container(
                  key: const Key('barre-decisions-mere'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.hourglass_bottom, size: 12, color: texte),
                    const SizedBox(width: 6),
                    Text('${r.libelle}$age', style: TextStyle(color: texte, fontWeight: FontWeight.w600, fontSize: 12)),
                  ]),
                ),
              ),
            ),
          );
        });
  }
}
