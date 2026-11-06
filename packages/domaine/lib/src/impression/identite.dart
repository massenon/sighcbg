/// Identité légale imprimée (C.BRAND de la maquette, `core.js`) : UN SEUL en-tête sur toutes les pièces.
///
/// SURCHARGEABLE (décision de la Direction du 06/11/2026, écart E841 levé) : les valeurs ci-dessous sont l'identité INITIALE de la Clinique Baguidi
/// (PRD §4). L'écran « Identité & papier à en-tête » (`cfg-branding`) enregistre ses valeurs dans le magasin ; le poste les applique ici au démarrage
/// et à chaque enregistrement ([appliquer]), si bien que TOUTES les pièces reprennent la valeur enregistrée. Les noms d'accès sont restés ceux des
/// anciennes constantes : les appelants n'ont pas changé, seuls les contextes `const` ont dû tomber.
///
/// Un champ VIDE n'imprime rien : ni valeur d'une autre clinique, ni libellé orphelin (« Autorisation : » sans numéro). Les lignes d'en-tête et de pied
/// composées ici ([ligneCoordonnees], [ligneAutorisation], [ligneFiscale], [ligneEmail], [piedLegal]) rendent une chaîne vide quand rien n'est à dire,
/// et l'appelant n'affiche pas une ligne vide.
class IdentiteClinique {
  const IdentiteClinique._();

  /// L'identité de départ (fiche d'identité fournie par la Direction de la Clinique Baguidi le 06/11/2026). Forme juridique, autorisation d'ouverture
  /// et formule de politesse ne sont pas encore connues : elles restent VIDES jusqu'à ce que la Direction les saisisse.
  static const Map<String, Object> defauts = {
    'sigle': 'CBG',
    'nom': 'CLINIQUE BAGUIDI « L’AS DE CŒUR »',
    'nomCourt': 'CLINIQUE BAGUIDI',
    'activite': 'CENTRE DE MÉDECINE DU TRAVAIL, MÉDECINE GÉNÉRALE',
    'forme': '',
    'slogan': 'Votre bien-être est notre raison d’être.',
    'adresse': 'Quartier Zongo II, Parakou',
    'bp': '02 BP : 105 PARAKOU (Rép. du Bénin)',
    'telephones': ['95 74 69 56', '95 95 99 14', '97 09 34 99'],
    'email': 'cliniquebaguidi@yahoo.fr',
    'ifu': '3201001996110',
    'rccm': 'RB/PKO/17 A 4240 du 19/03/2009',
    'autorisation': '',
    'formuleArrete': 'Arrêtée la présente facture à la somme de',
    'formulePolitesse': '',
  };

  /// Les champs qu'une surcharge peut porter (les autres clés d'une fiche enregistrée, options d'impression comprises, sont ignorées ici).
  static const champs = [
    'sigle', 'nom', 'nomCourt', 'activite', 'forme', 'slogan', 'adresse', 'bp', 'telephones', 'email', 'ifu', 'rccm', 'autorisation', 'formuleArrete', 'formulePolitesse'
  ];

  /// Le nom de la clinique que la mère exige en confirmation d'une réinitialisation de production (`_clinique` de `mere.dart`, `nomClinique` du
  /// poste). FIXE, non surchargeable : la mère et le poste peuvent tourner dans deux processus, et la phrase doit être la même des deux côtés.
  static const confirmationReinit = 'BAGUIDI';

  static Map<String, Object> _surcharge = const {};

  /// Applique l'identité ENREGISTRÉE (fiche du magasin) par-dessus les valeurs initiales. Une clé absente garde la valeur initiale ; une clé présente,
  /// même vide, l'emporte : c'est ainsi qu'un champ vidé par la Direction cesse d'être imprimé. `null` ou une fiche vide rendent l'identité initiale.
  static void appliquer(Map<String, Object?>? valeurs) {
    if (valeurs == null || valeurs.isEmpty) {
      _surcharge = const {};
      return;
    }
    final s = <String, Object>{};
    for (final k in champs) {
      if (!valeurs.containsKey(k)) continue;
      final v = valeurs[k];
      if (k == 'telephones') {
        s[k] = lireTelephones(v);
      } else {
        s[k] = v == null ? '' : '$v'.trim();
      }
    }
    _surcharge = Map.unmodifiable(s);
  }

  /// Revient à l'identité initiale (tests, réinitialisation).
  static void reinitialiser() => _surcharge = const {};

  /// La surcharge en vigueur (copie) : vide quand l'identité imprimée est l'identité initiale.
  static Map<String, Object> get surcharge => Map.of(_surcharge);

  /// Les téléphones tels qu'on les saisit (« 95 74 69 56 / 95 95 99 14 ») ou tels qu'on les stocke (liste) : une liste sans entrée vide.
  static List<String> lireTelephones(Object? v) {
    final brut = v is List ? v.map((e) => '$e') : '${v ?? ''}'.split(RegExp(r'\s*[/·;,]\s*'));
    return List.unmodifiable([for (final t in brut) if (t.trim().isNotEmpty) t.trim()]);
  }

  static String _texte(String k) => '${_surcharge[k] ?? defauts[k] ?? ''}';

  static String get sigle => _texte('sigle');
  static String get nom => _texte('nom');
  static String get nomCourt => _texte('nomCourt');

  /// L'activité de l'établissement, sous la dénomination (écran de connexion) : « CENTRE DE MÉDECINE DU TRAVAIL, MÉDECINE GÉNÉRALE ».
  static String get activite => _texte('activite');

  /// « Parakou, République du Bénin » : la ville de l'adresse géographique, puis le pays.
  static String get localisation => ville.isEmpty ? 'République du Bénin' : '$ville, République du Bénin';

  /// Forme juridique (SARL, SA…) : vide tant que la Direction ne l'a pas renseignée.
  static String get forme => _texte('forme');
  static String get slogan => _texte('slogan');

  /// Adresse géographique (« Quartier Zongo II, Parakou »).
  static String get adresse => _texte('adresse');

  /// La ville de la clinique, lue sur l'adresse géographique (dernier segment après la virgule) : c'est elle que porte « Fait à …, le … ».
  static String get ville {
    final a = adresse;
    final i = a.lastIndexOf(',');
    return (i < 0 ? a : a.substring(i + 1)).trim();
  }

  static String get bp => _texte('bp');
  static List<String> get telephones {
    final t = _surcharge['telephones'] ?? defauts['telephones'];
    return t is List<String> ? t : lireTelephones(t);
  }

  static String get email => _texte('email');
  static String get ifu => _texte('ifu');
  static String get rccm => _texte('rccm');

  /// N° d'autorisation d'ouverture : vide tant que la Direction ne l'a pas renseigné.
  static String get autorisation => _texte('autorisation');
  static String get formuleArrete => _texte('formuleArrete');

  /// Formule de politesse du bas des factures : vide tant que la Direction ne l'a pas choisie.
  static String get formulePolitesse => _texte('formulePolitesse');

  /// Le nom du logiciel tel qu'il s'affiche (titre de fenêtre, pied des pièces) : « SIGH- » suivi du sigle de la clinique.
  static String get logiciel => sigle.isEmpty ? 'SIGH' : 'SIGH-$sigle';

  /// Le préfixe des fichiers produits par le logiciel (sauvegardes, exports) : « sigh-cbg ». Deux installations de cliniques différentes ne
  /// confondent pas leurs fichiers.
  static String get prefixeFichier => sigle.isEmpty ? 'sigh' : 'sigh-${sigle.toLowerCase()}';

  /// La mention « Édité depuis le SIGH-… » du pied des pièces imprimées.
  static String get editeDepuis => 'Édité depuis le $logiciel';

  /// Le pied de page légal de tous les écrans : lu de l'identité unique, jamais réécrit ailleurs. Les séparateurs sont une identité légale imprimée,
  /// pas de la ponctuation rédigée. Un IFU ou un RCCM vide n'imprime pas son libellé.
  static String get mentionLegale {
    final parts = [nom, if (ifu.isNotEmpty) 'IFU $ifu', if (rccm.isNotEmpty) 'RCCM $rccm'].where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? '' : '${parts.join(' — ')}.';
  }

  /// En-tête, ligne des coordonnées : « BP   TÉL. : a  /  b ». Vide si ni BP ni téléphone.
  static String get ligneCoordonnees {
    final t = telephones;
    return [if (bp.isNotEmpty) bp, if (t.isNotEmpty) 'TÉL. : ${t.join('  /  ')}'].join('   ');
  }

  /// En-tête, ligne de l'autorisation d'ouverture. Vide si le numéro n'est pas renseigné (aucun libellé orphelin).
  static String get ligneAutorisation => autorisation.isEmpty ? '' : 'AUTORISATION D’OUVERTURE $autorisation';

  /// En-tête, ligne fiscale : « IFU : …   RCCM : … ». Chaque mention n'apparaît qu'avec sa valeur.
  static String get ligneFiscale => [if (ifu.isNotEmpty) 'IFU : $ifu', if (rccm.isNotEmpty) 'RCCM : $rccm'].join('   ');

  /// En-tête, ligne de l'adresse électronique. Vide si aucune adresse.
  static String get ligneEmail => email.isEmpty ? '' : 'E-mail : $email';

  /// Les lignes de l'en-tête légal sous la dénomination, dans l'ordre de la maquette, SANS les lignes vides.
  static List<String> get lignesEnTete => [ligneCoordonnees, ligneAutorisation, ligneFiscale, ligneEmail, slogan].where((l) => l.isNotEmpty).toList();

  /// Pied des pièces imprimées : « Dénomination — RCCM — IFU … », sans mention vide.
  static String get piedLegal => [nom, rccm, if (ifu.isNotEmpty) 'IFU $ifu'].where((p) => p.isNotEmpty).join(' — ');

  /// « Fait à <ville>, le <date> » ; « Fait le <date> » si la ville n'est pas connue.
  static String faitA(String date) => ville.isEmpty ? 'Fait le $date' : 'Fait à $ville, le $date';
}
