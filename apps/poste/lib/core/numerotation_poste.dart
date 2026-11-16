import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';

/// LE RÉFÉRENTIEL DE NUMÉROTATION BRANCHÉ SUR LE MAGASIN (lot 2, 16/11/2026).
///
/// La fabrique du domaine (`numeroSuivant`, `numeroFormate`, `racineNumero`…) lit un registre de processus ; ce fichier l'alimente avec les versions
/// ACTIVES de la collection `seriesNumerotation` : au démarrage du poste, puis à chaque écriture de la collection — une version écrite à la mère, ou reçue
/// par la synchronisation chez un fileul (famille R), s'applique aux pièces suivantes sans redémarrage. Même mécanisme que l'identité de la clinique.
/// Une collection vide laisse les SEMENCES faire foi (formats du code au 16/11/2026, « à valider »).

/// Change à chaque application : l'écran d'administration des séries se reconstruit.
final ValueNotifier<int> versionNumerotation = ValueNotifier<int>(0);

/// Applique les versions du magasin au registre de numérotation.
void appliquerNumerotation(Magasin m) {
  Numerotation.appliquer(m.collection(colSeriesNumerotation).toutes);
  // Appliquée pendant une construction (ouverture de la coque), l'annonce attend la fin de l'image : notifier en pleine construction est refusé par le cadre.
  final liant = SchedulerBinding.instance;
  if (liant.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    liant.addPostFrameCallback((_) => versionNumerotation.value++);
  } else {
    versionNumerotation.value++;
  }
}

final Expando<VoidCallback> _branches = Expando<VoidCallback>('numerotation');

/// Branche le registre sur le magasin : application immédiate, puis à chaque changement de la collection. Idempotent.
void brancherNumerotation(Magasin m) {
  appliquerNumerotation(m);
  if (_branches[m] != null) return;
  void ecoute() => appliquerNumerotation(m);
  m.collection(colSeriesNumerotation).addListener(ecoute);
  _branches[m] = ecoute;
}
