import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';

import '../donnees/magasin.dart';
import '../mere/client_mere.dart';
import 'service_fichiers.dart';

/// Branche le service des scans du poste sur le bon dossier :
///  * poste MÈRE : le service de la mère (même processus) par sa boucle locale et le secret d'administration — le dossier est LOCAL, le chemin se règle ici ;
///  * poste FILEUL : le client des fichiers du moteur de synchronisation, scellé par la clé de clinique (jamais le relais).
/// Le mode se relit à chaque appel (`estMere`) : un poste qui devient mère en cours de session change de branche sans redémarrer.
void brancherFichiers({
  required Magasin magasin,
  required bool Function() estMere,
  required ClientMere clientMere,
  required ClientFichiers Function(String famille) clientFileul,
}) {
  final svc = ServiceFichiers.de(magasin);
  Future<(int, Map<String, Object?>)> admin(String methode, String chemin, Object? corps) async {
    try {
      return (200, await clientMere.brut(methode, chemin, corps is Map<String, Object?> ? corps : null));
    } on ErreurMere catch (e) {
      return (e.statut, {'code': e.code, 'motif': e.motif});
    } catch (e) {
      return (503, {'code': 'mere_injoignable', 'motif': 'Le service de la mère ne répond pas : $e.', 'geste': 'Vérifier que le mode mère est actif sur ce poste.'});
    }
  }

  svc.stockagePour = (famille) => estMere()
      ? ClientFichiers(appeler: admin, prefixe: '/admin/fichiers', famille: famille)
      : clientFileul(famille);
  svc.lireInfo = () async {
    if (estMere()) {
      final (st, j) = await admin('GET', '/admin/fichiers/info', null);
      if (st != 200) throw DocErreur('${j['code']}', '${j['motif']}', '${j['geste'] ?? ''}');
      return j;
    }
    return clientFileul(docFamillePatient).info();
  };
  Future<Map<String, Object?>> mere(String methode, String chemin, Object? corps) async {
    if (!estMere()) {
      throw const DocErreur('REGLAGE_RESERVE_A_LA_MERE', 'Cette opération se fait sur le poste mère : les fichiers y vivent.', 'La faire depuis le poste mère.');
    }
    final (st, j) = await admin(methode, chemin, corps);
    if (st != 200) throw DocErreur('${j['code']}', '${j['motif']}', '${j['geste'] ?? ''}');
    return j;
  }

  svc.controlerMere = () => mere('GET', '/admin/fichiers/controle', null);
  svc.sauvegarderMere = (dest) => mere('POST', '/admin/fichiers/sauvegarder', {'destination': dest});
  svc.restaurerMere = (src) => mere('POST', '/admin/fichiers/restaurer', {'source': src});
  svc.changerDossierMere = (dossier) async {
    if (!estMere()) {
      throw const DocErreur('REGLAGE_RESERVE_A_LA_MERE', 'Le dossier des scans se règle sur le poste mère.', 'Faire le réglage depuis le poste mère.');
    }
    final (st, j) = await admin('POST', '/admin/fichiers/dossier', {'dossier': dossier});
    if (st != 200) throw DocErreur('${j['code']}', '${j['motif']}', '${j['geste'] ?? ''}');
    return j;
  };
}

/// MÈRE, au démarrage : si la clinique a réglé un dossier des scans AUTRE que celui par défaut, le service de la mère y est ramené (copie vérifiée, ancien
/// dossier conservé). Sans réglage, rien ne change. Échec silencieux interdit : le motif est rendu à l'appelant.
Future<String?> appliquerDossierRegle(Magasin magasin, ClientMere clientMere) async {
  final voulu = magasin.collection('reglages').parId('dossierScans')?['chemin'];
  if (voulu is! String || voulu.isEmpty) return null;
  try {
    final info = await clientMere.brut('GET', '/admin/fichiers/info');
    if (info['dossier'] == voulu) return null;
    await clientMere.brut('POST', '/admin/fichiers/dossier', {'dossier': voulu});
    return null;
  } catch (e) {
    return 'Dossier des scans « $voulu » non appliqué : $e';
  }
}
