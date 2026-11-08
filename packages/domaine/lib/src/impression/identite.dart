import 'entete.dart';

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
    'nom': 'CLINIQUE BAGUIDI « L’AS DU CŒUR »',
    'nomCourt': 'CLINIQUE BAGUIDI',
    'activite': 'CENTRE DE MÉDECINE DU TRAVAIL, MÉDECINE GÉNÉRALE',
    'forme': '',
    'slogan': 'Votre bien-être est notre raison d’être.',
    'adresse': 'Quartier Zongo II, Parakou',
    'bp': '02 BP : 105 PARAKOU (Rép. du Bénin)',
    'telephones': ['95 74 69 56', '95 95 99 14', '97 09 34 99'],
    'email': 'cliniquebaguidi@yahoo.fr',
    'ifu': '3201001996110',
    'ifuDate': '26 novembre 2010',
    'rccm': 'RB/PKO/17 A 4240',
    'rccmDate': '19/03/2009',
    'enregistrement': '0416/ONMB/ATL/2002',
    'autorisation': '',
    'formuleArrete': 'Arrêtée la présente facture à la somme de',
    'formulePolitesse': 'Votre bien-être est notre raison d’être.',
    'pays': 'République du Bénin',
    'devise': 'FCFA',
    'codeDevise': 'XOF',
    'logo': 'assets/img/logo.jpeg',
    'regimeTva': '',
  };

  /// Les champs qu'une surcharge peut porter (les autres clés d'une fiche enregistrée, options d'impression comprises, sont ignorées ici).
  static const champs = [
    'sigle', 'nom', 'nomCourt', 'activite', 'forme', 'slogan', 'adresse', 'bp', 'telephones', 'email', 'ifu', 'ifuDate', 'rccm', 'rccmDate', 'enregistrement', 'autorisation', 'formuleArrete', 'formulePolitesse',
    'pays', 'telephoneRdv', 'devise', 'codeDevise', 'logo', 'regimeTva'
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

  /// Pays de l'adresse (en-tête de la fiche d'identité).
  static String get pays => _texte('pays');

  /// La ligne des rendez-vous citée par les messages de rappel : sauf saisie contraire, le premier téléphone de l'en-tête (vide si aucun).
  static String get telephoneRdv => _surcharge.containsKey('telephoneRdv') ? '${_surcharge['telephoneRdv']}' : (telephones.isEmpty ? '' : telephones.first);

  /// `autorisationExercice` est nulle : l'inscription à l'ordre suffit (loi 2025-1), elle n'est plus imprimée. Le motif est celui de la maquette.
  static const String? autorisationExercice = null;
  static const autorisationExerciceMotif =
      'Non applicable — l’inscription à l’ordre suffit depuis la loi 2025-1 de juin 2026. L’autorisation d’exercice n’est plus imprimée sur les états.';
  static String get devise => _texte('devise');
  static String get codeDevise => _texte('codeDevise');
  static String get logo => _texte('logo');

  /// Le régime de TVA tel que `cfg-fiscalite` l'affiche : vide tant que la Direction ne l'a pas renseigné.
  static String get regimeTva => _texte('regimeTva');

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

  /// Date de délivrance de l'IFU, telle qu'on l'écrit sur le papier (« 26 novembre 2010 ») : vide, l'en-tête n'imprime que le numéro.
  static String get ifuDate => _texte('ifuDate');
  static String get rccm => _texte('rccm');

  /// Date d'immatriculation au RCCM (19/03/2009) : conservée À PART, jamais concaténée au numéro (décision du 06/11/2026).
  static String get rccmDate => _texte('rccmDate');

  /// N° d'enregistrement / d'inscription (0416/ONMB/ATL/2002, Ordre national des médecins du Bénin, 06/11/2026) : imprimé à l'en-tête.
  static String get enregistrement => _texte('enregistrement');

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

  /// En-tête, ligne du n° d'enregistrement (ONMB). Vide si le numéro n'est pas renseigné.
  static String get ligneEnregistrement => enregistrement.isEmpty ? '' : 'N° D’ENREGISTREMENT $enregistrement';

  /// En-tête, ligne de l'autorisation d'ouverture. Vide si le numéro n'est pas renseigné (aucun libellé orphelin).
  static String get ligneAutorisation => autorisation.isEmpty ? '' : 'AUTORISATION D’OUVERTURE $autorisation';

  /// En-tête, ligne fiscale : « IFU : …   RCCM : … ». Chaque mention n'apparaît qu'avec sa valeur.
  static String get ligneFiscale => [if (ifu.isNotEmpty) 'IFU : $ifu', if (rccm.isNotEmpty) 'RCCM : $rccm'].join('   ');

  /// En-tête, ligne de l'adresse électronique. Vide si aucune adresse.
  static String get ligneEmail => email.isEmpty ? '' : 'E-mail : $email';

  /// Les lignes de l'en-tête légal sous la dénomination, dans l'ordre de la maquette, SANS les lignes vides.
  static List<String> get lignesEnTete => [ligneCoordonnees, ligneEnregistrement, ligneAutorisation, ligneFiscale, ligneEmail, slogan].where((l) => l.isNotEmpty).toList();

  /// Pied des pièces imprimées : « Dénomination — IFU — RCCM » (source unique : EnteteTroisZones.composerPied), sans mention vide.
  static String get piedLegal => EnteteTroisZones.composerPied(nom, ifu, rccm);

  /// « Fait à <ville>, le <date> » ; « Fait le <date> » si la ville n'est pas connue.
  static String faitA(String date) => ville.isEmpty ? 'Fait le $date' : 'Fait à $ville, le $date';
}

/// Les champs d'identité d'une fiche de `identiteLegale` (`C.CHAMPS_IDENTITE`), dans l'ordre : ni id, ni version, ni dates.
const List<String> champsIdentiteLegale = [
  'sigle',
  'nom',
  'nomCourt',
  'activite',
  'slogan',
  'forme',
  'adresse',
  'bp',
  'pays',
  'telephones',
  'telephoneRdv',
  'email',
  'ifu',
  'ifuDate',
  'rccm',
  'rccmDate',
  'enregistrement',
  'autorisation',
  'autorisationExercice',
  'autorisationExerciceMotif',
  'devise',
  'codeDevise',
  'logo',
  'formuleArrete',
  'formulePolitesse',
  'regimeTva',
];

/// L'identité qu'une PIÈCE imprime : la version en force à sa date, ou la semence.
///
/// Configuration fiscale DATÉE (Nassiera Too, 06/11/2026) : la collection `identiteLegale` porte une fiche par version (`debut` null = depuis
/// l'ouverture, `fin` null = en force). [IdentiteClinique] reste la PORTE D'ENTRÉE des écrans et des états courants, et la SEMENCE de ces versions :
/// ses valeurs initiales sont celles de la Clinique Baguidi, surchargeables depuis `cfg-branding`. Une pièce s'imprime avec l'identité en force À
/// SA DATE (`cfbIdentiteImprimee`) : une facture d'hier garde le RCCM d'hier, même si une version prend effet demain. Chaque champ qu'une version
/// ne porte pas retombe sur [IdentiteClinique]. Les lignes composées ([lignesEnTete], [piedLegal]…) sont les MÊMES que celles de la classe
/// courante : un champ vide n'imprime ni sa ligne ni son libellé.
class IdentiteImprimee {
  const IdentiteImprimee({
    required this.sigle,
    required this.nom,
    this.nomCourtFiche = '',
    this.activite = '',
    required this.slogan,
    required this.forme,
    required this.adresse,
    required this.bp,
    required this.pays,
    required this.telephones,
    required this.telephoneRdv,
    required this.email,
    required this.ifu,
    this.ifuDate = '',
    required this.rccm,
    this.rccmDate = '',
    this.enregistrement = '',
    required this.autorisation,
    this.autorisationExercice,
    required this.autorisationExerciceMotif,
    required this.devise,
    required this.codeDevise,
    required this.logo,
    required this.formuleArrete,
    required this.formulePolitesse,
    required this.regimeTva,
    this.version,
    this.debut,
    this.fin,
  });

  /// La semence : l'identité COURANTE ([IdentiteClinique], surcharge comprise), la version 1 « depuis l'ouverture du dossier ». Un accesseur et non une
  /// constante : la surcharge de `cfg-branding` la fait varier.
  static IdentiteImprimee get semence => IdentiteImprimee(
        sigle: IdentiteClinique.sigle,
        nom: IdentiteClinique.nom,
        nomCourtFiche: IdentiteClinique.nomCourt,
        activite: IdentiteClinique.activite,
        slogan: IdentiteClinique.slogan,
        forme: IdentiteClinique.forme,
        adresse: IdentiteClinique.adresse,
        bp: IdentiteClinique.bp,
        pays: IdentiteClinique.pays,
        telephones: IdentiteClinique.telephones,
        telephoneRdv: IdentiteClinique.telephoneRdv,
        email: IdentiteClinique.email,
        ifu: IdentiteClinique.ifu,
        ifuDate: IdentiteClinique.ifuDate,
        rccm: IdentiteClinique.rccm,
        rccmDate: IdentiteClinique.rccmDate,
        enregistrement: IdentiteClinique.enregistrement,
        autorisation: IdentiteClinique.autorisation,
        autorisationExercice: IdentiteClinique.autorisationExercice,
        autorisationExerciceMotif: IdentiteClinique.autorisationExerciceMotif,
        devise: IdentiteClinique.devise,
        codeDevise: IdentiteClinique.codeDevise,
        logo: IdentiteClinique.logo,
        formuleArrete: IdentiteClinique.formuleArrete,
        formulePolitesse: IdentiteClinique.formulePolitesse,
        regimeTva: IdentiteClinique.regimeTva,
        version: 1,
      );

  /// Une fiche du magasin (une version de `identiteLegale`) relue ; chaque champ absent retombe sur la semence. `null` : la semence.
  factory IdentiteImprimee.depuisFiche(Map<String, Object?>? f) {
    final semence = IdentiteImprimee.semence;
    if (f == null) return semence;
    String t(String k, String defaut) => f.containsKey(k) && f[k] != null ? '${f[k]}' : defaut;
    final tel = f['telephones'];
    return IdentiteImprimee(
      sigle: t('sigle', semence.sigle),
      nom: t('nom', semence.nom),
      // Une fiche qui change la dénomination sans porter de nom court le dérive de la dénomination : elle n'hérite pas du nom court d'une autre.
      nomCourtFiche: f.containsKey('nomCourt') ? t('nomCourt', '') : (f.containsKey('nom') ? '' : semence.nomCourtFiche),
      activite: t('activite', semence.activite),
      slogan: t('slogan', semence.slogan),
      forme: t('forme', semence.forme),
      adresse: t('adresse', semence.adresse),
      bp: t('bp', semence.bp),
      pays: t('pays', semence.pays),
      telephones: tel is List ? [for (final x in tel) '$x'] : (tel is String && tel.trim().isNotEmpty ? IdentiteClinique.lireTelephones(tel) : semence.telephones),
      telephoneRdv: t('telephoneRdv', semence.telephoneRdv),
      email: t('email', semence.email),
      ifu: t('ifu', semence.ifu),
      ifuDate: t('ifuDate', semence.ifuDate),
      rccm: t('rccm', semence.rccm),
      rccmDate: t('rccmDate', semence.rccmDate),
      enregistrement: t('enregistrement', semence.enregistrement),
      autorisation: t('autorisation', semence.autorisation),
      autorisationExercice: f['autorisationExercice'] == null ? null : '${f['autorisationExercice']}',
      autorisationExerciceMotif: t('autorisationExerciceMotif', semence.autorisationExerciceMotif),
      devise: t('devise', semence.devise),
      codeDevise: t('codeDevise', semence.codeDevise),
      logo: t('logo', semence.logo),
      formuleArrete: t('formuleArrete', semence.formuleArrete),
      formulePolitesse: t('formulePolitesse', semence.formulePolitesse),
      regimeTva: t('regimeTva', semence.regimeTva),
      version: f['version'] is num ? (f['version'] as num).toInt() : null,
      debut: f['debut'] == null ? null : '${f['debut']}',
      fin: f['fin'] == null ? null : '${f['fin']}',
    );
  }

  final String sigle, nom, nomCourtFiche, activite, slogan, forme, adresse, bp, pays, telephoneRdv, email, ifu, ifuDate, rccm, rccmDate, enregistrement, autorisation;
  final String autorisationExerciceMotif, devise, codeDevise, logo, formuleArrete, formulePolitesse, regimeTva;
  final String? autorisationExercice;
  final List<String> telephones;

  /// Le numéro de la version relue (1 pour la semence), et ses bornes ISO (`null` : depuis l'ouverture / en force).
  final int? version;
  final String? debut, fin;

  /// Le nom court tel que le rouleau 80 mm et l'en-tête A4 l'impriment : celui que la fiche porte, sinon le nom sans sa forme juridique.
  String get nomCourt {
    if (nomCourtFiche.trim().isNotEmpty) return nomCourtFiche.trim();
    final m = RegExp(r'^(.*?)\s+(SARL|SA|SAS|SUARL|SARLU)\.?$', caseSensitive: false).firstMatch(nom.trim());
    return m == null ? nom.trim() : m.group(1)!;
  }

  /// Le pied légal de la version (même forme que [IdentiteClinique.mentionLegale]) : un IFU ou un RCCM vide n'imprime pas son libellé.
  String get mentionLegale {
    final parts = [nom, if (ifu.isNotEmpty) 'IFU $ifu', if (rccm.isNotEmpty) 'RCCM $rccm'].where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? '' : '${parts.join(' — ')}.';
  }

  /// La ville de l'adresse géographique (dernier segment après la virgule).
  String get ville {
    final i = adresse.lastIndexOf(',');
    return (i < 0 ? adresse : adresse.substring(i + 1)).trim();
  }

  String get ligneCoordonnees => [if (bp.isNotEmpty) bp, if (telephones.isNotEmpty) 'TÉL. : ${telephones.join('  /  ')}'].join('   ');
  String get ligneEnregistrement => enregistrement.isEmpty ? '' : 'N° D’ENREGISTREMENT $enregistrement';
  String get ligneAutorisation => autorisation.isEmpty ? '' : 'AUTORISATION D’OUVERTURE $autorisation';
  String get ligneFiscale => [if (ifu.isNotEmpty) 'IFU : $ifu', if (rccm.isNotEmpty) 'RCCM : $rccm'].join('   ');
  String get ligneEmail => email.isEmpty ? '' : 'E-mail : $email';

  /// Les lignes de l'en-tête légal sous la dénomination, SANS les lignes vides.
  List<String> get lignesEnTete => [ligneCoordonnees, ligneEnregistrement, ligneAutorisation, ligneFiscale, ligneEmail, slogan].where((l) => l.isNotEmpty).toList();

  /// Pied des pièces imprimées : « Dénomination — IFU — RCCM » (source unique : EnteteTroisZones.composerPied), sans mention vide.
  String get piedLegal => EnteteTroisZones.composerPied(nom, ifu, rccm);

  String faitA(String date) => ville.isEmpty ? 'Fait le $date' : 'Fait à $ville, le $date';

  /// Les champs d'identité, sur la forme d'une fiche : ce que le semis écrit et ce qu'une version copie.
  Map<String, Object?> get fiche => {
        'sigle': sigle,
        'nom': nom,
        'nomCourt': nomCourt,
        'activite': activite,
        'slogan': slogan,
        'forme': forme,
        'adresse': adresse,
        'bp': bp,
        'pays': pays,
        'telephones': [...telephones],
        'telephoneRdv': telephoneRdv,
        'email': email,
        'ifu': ifu,
        'ifuDate': ifuDate,
        'rccm': rccm,
        'rccmDate': rccmDate,
        'enregistrement': enregistrement,
        'autorisation': autorisation,
        'autorisationExercice': autorisationExercice,
        'autorisationExerciceMotif': autorisationExerciceMotif,
        'devise': devise,
        'codeDevise': codeDevise,
        'logo': logo,
        'formuleArrete': formuleArrete,
        'formulePolitesse': formulePolitesse,
        'regimeTva': regimeTva,
      };
}
