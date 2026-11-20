// LE ROUTAGE DES NOTIFICATIONS DE POSTE, RÉGLÉ PAR LA CLINIQUE (lot « destinataires des notifications » de l'inventaire des valeurs en dur, 17/11/2026).
//
// Une notification de poste s'adresse à un POSTE (`caisse`, `laboratoire`…), jamais à un nom de rôle : ce sont les GESTES RÉSERVÉS de la fiche de rôle (`alertes_caisse`…) qui
// disent qui reçoit, et une fiche de rôle accorde ou retire. Restait en code la table « poste → geste » (le centre de notifications la portait en constante) et, pour le besoin
// accordé, la liste des postes informés avec leur mention. Ces deux tables sont désormais deux RÉGLAGES de clinique (famille `notifications`, versionnés par date, réglés à la
// mère) : la graine ci-dessous n'est que leur valeur d'attente, reprise À L'IDENTIQUE de ce qui vivait en dur (aucun comportement ne change le jour de la conversion).
//
// Une valeur illisible ne coupe jamais une alerte : l'entrée mal formée est ignorée, un geste inconnu aussi, et la graine reste le fond de ce que la clinique n'a pas réglé.
// Fonctions PURES : le poste y branche son registre des paramètres.
library;

import '../caisse/valorisation.dart' show prefixePosteGeste;
import '../droits/gestes_reserves.dart';

/// Le réglage « poste → geste réservé » : `poste=geste;poste=geste`. Un poste absent de la table (ou tout poste écrit `geste:<id>`) se lit comme le moteur qui notifie l'a écrit.
const String cleRoutagePostes = 'notifications.routagePostes';

/// Le réglage « postes informés quand un besoin est accordé » : `poste=mention;poste=mention` (la mention complète le message de ce poste). Chaque poste doit exister dans le
/// réglage [cleRoutagePostes], sans quoi la notification est lue comme adressée à un rôle de ce nom.
const String cleDestinatairesBesoinAccorde = 'notifications.destinatairesBesoinAccorde';

/// GRAINE du routage des postes : valeur d'attente du réglage (défaut déclaré dans `definitions.dart`), reprise de la table que portait le centre de notifications.
const String routagePostesSemence = 'caisse=$gesteAlertesCaisse;stock=$gesteAlertesStock;comptable=$gesteAlertesComptable;direction=$gesteAlertesDirection;imagerie=$gesteAlertesImagerie;'
    'laboratoire=$gesteAlertesLaboratoire;prescripteur=$gesteAlertesPrescripteur;salle_soins=$gesteAlertesSalleSoins;hospitalisation=$gesteAlertesHospitalisation';

/// GRAINE des postes informés d'un besoin accordé : l'engagement budgétaire (comptabilité) et l'achat ou la distribution (stock), avec les mentions d'avant.
const String destinatairesBesoinAccordeSemence =
    'comptable=engagement budgétaire et décaissement à préparer;stock=achat à lancer ou distribution à planifier';

/// Une table `clé=valeur;clé=valeur` lue, dans l'ordre ; les entrées sans `=`, sans clé ou sans valeur (si [valeurRequise]) sont ignorées.
Map<String, String> _lireTable(Object? v, {bool valeurRequise = true}) {
  final out = <String, String>{};
  if (v == null) return out;
  for (final e in '$v'.split(';')) {
    final i = e.indexOf('=');
    if (i <= 0) continue;
    final k = e.substring(0, i).trim();
    final x = e.substring(i + 1).trim();
    if (k.isEmpty || (valeurRequise && x.isEmpty)) continue;
    out[k] = x;
  }
  return out;
}

/// Le routage EN FORCE : poste → geste réservé. La graine sert de FOND et la valeur réglée la CORRIGE entrée par entrée : un poste que la clinique n'a pas listé garde son geste
/// d'attente (une omission ne fait taire aucune alerte). Un geste qui n'existe pas au référentiel des gestes est ignoré.
Map<String, String> routagePostesDe(Object? valeur) => {
      ..._lireTable(routagePostesSemence),
      for (final e in _lireTable(valeur).entries)
        if (gesteReserve(e.value) != null) e.key: e.value,
    };

/// Le geste réservé qui tient [poste] : `geste:<id>` désigne un geste directement, sinon [routage] ; `null` quand le poste n'est tenu par aucun geste.
String? gesteDuPosteRoute(Object? poste, Map<String, String> routage) {
  final p = '${poste ?? ''}';
  if (p.startsWith(prefixePosteGeste)) return p.substring(prefixePosteGeste.length);
  return routage[p];
}

/// Un poste informé d'un événement, et la mention qui complète SON message.
typedef DestinataireNotif = ({String poste, String mention});

/// Les postes informés d'un besoin accordé, dans l'ordre du réglage ; sans entrée valable, la graine répond.
List<DestinataireNotif> destinatairesBesoinAccordeDe(Object? valeur) {
  final lu = _lireTable(valeur, valeurRequise: false);
  final t = lu.isEmpty ? _lireTable(destinatairesBesoinAccordeSemence) : lu;
  return [for (final e in t.entries) (poste: e.key, mention: e.value)];
}
