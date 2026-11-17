import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../donnees/magasin.dart';

/// LE CHOIX D'EXERCICE DE LA SESSION (arbitrage du 05/11/2026), miroir de `sigh-cbg:exercice` de la maquette : tenu EN MÉMOIRE pour la session du poste, jamais
/// écrit dans le magasin. Absent, l'exercice affiché est celui qui CONTIENT LA DATE DU JOUR ([cpcExerciceParDefaut], Direction de Baguidi du 16/11/2026, qui remplace « le plus récent
/// encore ouvert » de la maquette, E3260) : l'exercice suivant ouvert d'avance en décembre reste choisissable. Une nouvelle session repart du défaut.
class ChoixExercice {
  ChoixExercice._();
  static final ValueNotifier<int?> valeur = ValueNotifier<int?>(null);

  static void reinitialiser() => valeur.value = null;

  /// L'exercice effectivement affiché, d'après la liste des exercices du magasin (vide : l'année de l'horloge). Jamais un autre exercice en silence : l'exercice du jour NON AMORCÉ
  /// reste affiché et le sélecteur le dit (« non amorcé »).
  static int courant(Magasin m, DateTime aujourdhui) {
    final exos = m.collection('exercices').actives;
    if (exos.isEmpty) return aujourdhui.year;
    return cpcExerciceChoisi(exos, valeur.value, aujourdhui);
  }
}

/// Le sélecteur de la barre supérieure : ‹ Exercice N · état ›. Les flèches sont ABSENTES aux bornes (pas d'exercice voisin), jamais grisées.
class SelecteurExercice extends StatefulWidget {
  const SelecteurExercice({super.key, required this.magasin, required this.aujourdhui});
  final Magasin magasin;
  final DateTime aujourdhui;

  @override
  State<SelecteurExercice> createState() => _EtatSelecteurExercice();
}

class _EtatSelecteurExercice extends State<SelecteurExercice> {
  Magasin get magasin => widget.magasin;
  DateTime get aujourdhui => widget.aujourdhui;
  late Listenable _ecoute;

  // Le sélecteur écoute le CHOIX et la COLLECTION des exercices : amorcée après le premier dessin (un écran qui l'amorce, une réception du pont), la table vide ne le laisse plus absent (défaut PTA
  // du 17/11/2026 : « le widget n'écoutait pas la collection »). Un écran qui amorce pendant SA construction notifie en pleine phase de construction : le repeint est alors reporté à la fin de l'image
  // (setState en construction est une erreur du cadriciel).
  void _surChangement() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _brancher() {
    _ecoute = Listenable.merge([ChoixExercice.valeur, magasin.collection('exercices')])..addListener(_surChangement);
  }

  @override
  void initState() {
    super.initState();
    _brancher();
  }

  @override
  void didUpdateWidget(SelecteurExercice ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.magasin != widget.magasin) {
      _ecoute.removeListener(_surChangement);
      _brancher();
    }
  }

  @override
  void dispose() {
    _ecoute.removeListener(_surChangement);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (_) {
        final exos = magasin.collection('exercices').actives;
        if (exos.isEmpty) return const SizedBox.shrink();
        final annee = ChoixExercice.courant(magasin, aujourdhui);
        final etat = cpcEtatExercice(magasin.collection('exercices').toutes, annee);
        final prec = cpcExerciceVoisin(exos, annee, -1);
        final suiv = cpcExerciceVoisin(exos, annee, 1);
        // L'exercice du jour sans fiche : le dire plutôt que montrer un autre exercice à sa place (E3261).
        final amorce = cpcExerciceAmorce(exos, annee);
        final libelleEtat = !amorce ? 'non amorcé' : switch (etat) { 'clos' => 'clos', 'en_cloture' => 'en clôture', _ => 'ouvert' };
        Widget fleche(String cle, IconData i, int? vers) => vers == null
            ? const SizedBox(width: 4)
            : Tooltip(
                message: 'Exercice $vers',
                child: InkWell(
                    key: Key(cle),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => ChoixExercice.valeur.value = vers,
                    child: Padding(padding: const EdgeInsets.all(4), child: Icon(i, size: 16, color: JetonsShell.navy200))));
        final libelle = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Exercice $annee · $libelleEtat',
                key: const Key('exercice-affiche'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)));
        return Semantics(
          label: 'Exercice comptable $annee, $libelleEtat',
          child: Container(
            key: const Key('selecteur-exercice'),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF), border: Border.all(color: const Color(0x26FFFFFF)), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              fleche('exercice-precedent', LucideIcons.chevronLeft, prec),
              if (amorce) libelle else Tooltip(message: 'L’exercice $annee (celui de la date du jour) n’est pas encore amorcé : aucun autre exercice n’est affiché à sa place. Choisir un exercice existant avec les flèches.', child: libelle),
              fleche('exercice-suivant', LucideIcons.chevronRight, suiv),
            ]),
          ),
        );
      },
    );
  }
}
