import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../sync/config_pair.dart';
import 'base_portable_poste.dart' show refusPoste;
import 'magasin.dart';
import 'persistance.dart';

/// LA RESTAURATION DE LA CLÉ DE LA CLINIQUE SUR UN POSTE NEUF (Direction de Baguidi, 17/11/2026, décision 12). Sans la clé, les sauvegardes, les exports portables et le relais sont
/// irrécupérables ; la clé se range sous scellé hors de la mère. Les RÈGLES (formats lus, empreinte, refus) sont dans `sigh_domaine` (`cle_clinique_regles.dart`).
///
/// Deux sources, au choix de qui tient la copie : le TEXTE de la copie sous scellé (64 caractères hexadécimaux, groupés ou non, ou Base64), ou un FICHIER de sauvegarde de clé (le format
/// SGHK de « Sauvegarder la clé de chiffrement », chiffré par une phrase de passe). Dans les deux cas l'EMPREINTE notée sur le scellé est exigée AVANT acceptation : une clé qui ne la
/// reproduit pas est refusée, rien n'est écrit. La clé ne s'affiche JAMAIS et ne se journalise JAMAIS : le journal ne porte que l'empreinte courte. Elle est rangée là où le poste range déjà
/// la clé de la clinique : `pair.json`, chiffrée par la clé locale du poste.
class ServiceCleClinique {
  ServiceCleClinique({required this.magasin, required this.dossierDonnees, required this.peut, this.empreinteEnService});

  final Magasin magasin;
  final String dossierDonnees;
  final bool Function(String geste) peut;

  /// L'empreinte (complète) de la clé déjà en service sur ce poste, si elle est connue (la mère en marche donne la sienne). Par défaut : celle du `pair.json` du poste.
  final Future<String?> Function()? empreinteEnService;

  static final Expando<ServiceCleClinique> _installes = Expando<ServiceCleClinique>('ServiceCleClinique');
  static ServiceCleClinique? de(Magasin m) => _installes[m];
  void installer() => _installes[magasin] = this;

  /// L'empreinte COURTE (8 caractères) de la clé en service, pour l'écran ; `null` : aucune clé connue de ce poste.
  Future<String?> empreinteCourante() async {
    final e = await _enService();
    return e?.substring(0, 8).toUpperCase();
  }

  Future<String?> _enService() async {
    if (empreinteEnService != null) {
      final e = await empreinteEnService!();
      if (e != null && e.isNotEmpty) return e;
    }
    try {
      final hex = '${ConfigPairPoste.lireBrut(dossierDonnees)['cle'] ?? ''}';
      final b = cleLireTexte(hex);
      return b == null ? null : cleEmpreinte(b);
    } catch (_) {
      return null;
    }
  }

  /// RESTAURE la clé. [texte] (copie sous scellé) OU [fichier] et [phrase] (sauvegarde de clé) ; [empreinteAttendue] est obligatoire ; [remplacer] confirme le remplacement d'une AUTRE clé
  /// en service. Rend l'empreinte courte de la clé acceptée. Refus nommés (`ErreurExport`) : `GESTE_RESERVE`, `CLE_ILLISIBLE`, `FICHIER_CLE_INVALIDE`, `PHRASE_INCORRECTE`,
  /// `EMPREINTE_ABSENTE`, `EMPREINTE_ILLISIBLE`, `EMPREINTE_DIFFERENTE`, `CLE_EN_SERVICE_DIFFERENTE`.
  Future<String> restaurer({String? texte, String? fichier, String? phrase, required String empreinteAttendue, bool remplacer = false}) async {
    if (!peut(gesteSystemeAdministrer)) {
      throw refusPoste('GESTE_RESERVE', 'restaurer la clé de la clinique est réservé aux administrateurs du système (droit de la fiche de rôle)', 'Demander à un rôle qui détient « Administrer le système ».');
    }
    List<int>? octets;
    var source = 'texte';
    if (fichier != null && fichier.trim().isNotEmpty) {
      source = 'fichier';
      try {
        octets = await CleLocale.lireSauvegarde(fichier.trim(), phrase ?? '');
      } on FileSystemException {
        throw refusPoste('FICHIER_CLE_INVALIDE', 'le fichier de sauvegarde de clé est introuvable ou illisible', 'Choisir le fichier .cle gardé avec la copie sous scellé.');
      } on StateError catch (e) {
        final m = '$e';
        throw refusPoste(m.contains('Phrase') ? 'PHRASE_INCORRECTE' : 'FICHIER_CLE_INVALIDE', m.replaceFirst('Bad state: ', ''), 'Reprendre la copie sous scellé : fichier et phrase de passe vont ensemble. Aucune clé n’a été acceptée.');
      }
    } else {
      octets = cleLireTexte(texte ?? '');
    }
    final refus = cleControlerRestauration(octets: octets, empreinteAttendue: empreinteAttendue, empreinteEnService: await _enService(), remplacer: remplacer);
    if (refus != null) throw ErreurExport(refus);
    final cle = octets!;
    final hex = cle.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final remplacee = (await _enService()) != null;
    ConfigPairPoste.ecrire(dossierDonnees, cleHex: hex);
    final courte = cleEmpreinteAffichee(cle);
    // Le journal ne porte que l'EMPREINTE courte et la source : jamais la clé.
    magasin.journaliser('Restauration de la clé de la clinique', 'MERE', 'Clé de clinique', courte, null, {'empreinte': courte, 'source': source, 'remplacee': remplacee});
    return courte;
  }
}
