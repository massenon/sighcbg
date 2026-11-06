import 'dart:io';

/// LE DOSSIER DES DONNÉES DU POSTE (PRD installateur Windows, phase A). Les données ne vivent JAMAIS dans le dossier d'installation : une mise à jour
/// remplace les fichiers du programme et n'y touche pas. Sous Windows : `%LOCALAPPDATA%\SIGHCBG\donnees` (machine locale, non itinérant). Le dossier est PROPRE à la clinique (PRD Baguidi P0-7) : SIGH-CNT
/// (`SIGHCNT`) et SIGH-CBG (`SIGHCBG`) installés sur la même machine démarrent chacun sur leurs propres données. `SIGH_DONNEES`
/// (développement, tests) l'emporte et est pris tel quel.
/// Le nom du dossier de l'application sous `%LOCALAPPDATA%` ou `~/.local/share`. FIXE : il ne suit pas le sigle modifiable de l'identité, sans quoi
/// changer le sigle déplacerait les données.
const dossierApplication = 'SIGHCBG';

class DossierDonneesInutilisable implements Exception {
  const DossierDonneesInutilisable(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

/// Le chemin, sans rien créer. [surcharge] : valeur de `SIGH_DONNEES` (vide = absente). [env] : l'environnement du processus.
String resoudreDossierDonnees({String surcharge = '', required Map<String, String> env, required bool windows}) {
  if (surcharge.trim().isNotEmpty) return surcharge.trim();
  if (windows) {
    final base = env['LOCALAPPDATA'];
    if (base == null || base.trim().isEmpty) {
      throw const DossierDonneesInutilisable(
          'Le dossier des données du poste est introuvable : la variable Windows LOCALAPPDATA n’est pas définie. Ouvrez une session Windows ordinaire, ou fixez SIGH_DONNEES.');
    }
    return '${base.trim().replaceAll(RegExp(r'[\\/]+$'), '')}\\$dossierApplication\\donnees';
  }
  final xdg = env['XDG_DATA_HOME'];
  final home = env['HOME'];
  final racine = (xdg != null && xdg.isNotEmpty) ? xdg : (home != null && home.isNotEmpty ? '$home/.local/share' : null);
  if (racine == null) {
    throw const DossierDonneesInutilisable('Le dossier des données du poste est introuvable : ni XDG_DATA_HOME ni HOME ne sont définis. Fixez SIGH_DONNEES.');
  }
  return '$racine/$dossierApplication/donnees';
}

/// Crée le dossier s'il manque, puis VÉRIFIE qu'on peut y écrire : un échec est NOMMÉ (chemin et cause), jamais une base qui ne s'ouvre pas sans un mot.
Future<String> preparerDossierDonnees(String chemin) async {
  try {
    final d = Directory(chemin);
    await d.create(recursive: true);
    final sonde = File('${d.path}${Platform.pathSeparator}.ecriture-ok');
    await sonde.writeAsString('ok', flush: true);
    await sonde.delete();
    return chemin;
  } on FileSystemException catch (e) {
    throw DossierDonneesInutilisable(
        'Le dossier des données du poste est inutilisable : $chemin (${e.osError?.message ?? e.message}). Vérifiez les droits d’écriture sur ce dossier, ou fixez SIGH_DONNEES.');
  }
}
