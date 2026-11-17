/// LES SMS PAR LE RELAIS (ADR-0009, décision de la Direction de Baguidi du 16/11/2026, `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` § 8).
///
/// La mère COMPOSE le SMS à partir d'un modèle de message ; le relais ne reçoit qu'un numéro au format international et un texte déjà composé, qu'il efface
/// après l'envoi. Ce fichier porte les règles PURES de la composition, appliquées au poste (avant de déposer) ET au service de la mère (avant d'envoyer au
/// relais) — une règle, deux contrôles, jamais deux exemplaires :
///
///  * AUCUN CONTENU MÉDICAL : un rappel dit le jour, l'heure et la clinique. Un texte qui contient un mot de [smsMotsInterdits] est REFUSÉ
///    (`SMS_CONTENU_MEDICAL`) en nommant le mot. La liste est une PROPOSITION, marquée [smsStatutMotsInterdits] : à valider par un médecin ;
///  * AUCUN NOM : la variable `{{nom}}` n'est JAMAIS remplacée dans un SMS (le relais ne doit pas voir un nom à côté d'un numéro) ; elle est retirée et la
///    ponctuation qui l'entourait resserrée. Le texte qui partira est montré tel quel avant l'envoi ;
///  * une variable inconnue ou sans valeur est un refus nommé (un patient ne doit jamais recevoir « {{rdv}} ») ;
///  * le numéro est ramené au format international (`+` et 8 à 15 chiffres) ; un numéro local reçoit l'indicatif du pays ([smsIndicatifDefaut], le Bénin).
library;

/// Longueur maximale d'un SMS composé (caractères) : la même borne que le schéma du relais (`App\Relais\Sms\FileSms`, `relais-sms.js`).
const int smsLongueurMax = 320;

/// Cinq tentatives d'envoi au plus, côté relais (ADR-0009) : affiché au poste, jamais réglé depuis le poste.
const int smsTentativesMax = 5;

/// L'indicatif téléphonique ajouté à un numéro saisi sans indicatif : le Bénin (+229).
const String smsIndicatifDefaut = '229';

/// L'interrupteur de la passerelle est FERMÉ par défaut : un flux de numéros personnels hors du poste est un acte que la clinique ouvre en connaissance de cause.
const bool smsActifDefaut = false;

/// Le statut de la liste des mots interdits, affiché tel quel à l'écran « Passerelle SMS ».
const String smsStatutMotsInterdits = 'Liste proposée, à valider par un médecin';

/// LES MOTS INTERDITS DANS UN SMS (proposition, À VALIDER PAR UN MÉDECIN). Écrits sans accent ni majuscule : le contrôle compare un texte ramené à la même
/// forme. Chaque entrée se reconnaît en DÉBUT de mot, suivie de trois lettres au plus (pluriels et féminins : « analyses », « séropositive »).
const List<String> smsMotsInterdits = [
  // diagnostic et maladies
  'diagnostic', 'maladie', 'pathologie', 'symptome', 'vih', 'sida', 'seropositi', 'paludisme', 'hepatite', 'tuberculose', 'cancer', 'tumeur', 'diabete',
  'hypertension', 'infection', 'ist', 'mst', 'syphilis', 'covid', 'depression', 'psychiatri', 'toxicomanie', 'alcoolisme',
  // santé de la femme
  'grossesse', 'enceinte', 'accouchement', 'avortement', 'ivg', 'fausse couche', 'contraception', 'planning familial', 'sterilet',
  // examens et résultats
  'depistage', 'analyse', 'resultat', 'examen', 'bilan sanguin', 'prelevement', 'echographie', 'radiographie', 'scanner', 'irm', 'biopsie',
  // soins
  'ordonnance', 'medicament', 'traitement', 'hospitalisation', 'chirurgie', 'chirurgical', 'motif de consultation', 'deces',
];

/// Les variables qu'un SMS peut porter. `{{nom}}` n'y figure pas : il est retiré, jamais remplacé.
const List<String> smsVariablesPermises = ['{{clinique}}', '{{telephone}}', '{{date}}', '{{rdv}}'];

/// Le modèle du message d'essai (« Tester l'envoi ») : la même composition, les mêmes contrôles.
const String smsModeleEssai = 'Message d’essai de la passerelle SMS de {{clinique}}. Merci de ne pas répondre.';

/// Un refus nommé : un code stable, un motif lisible, le geste qui corrige.
class SmsRefus {
  const SmsRefus(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
  @override
  String toString() => '$code — $motif';
}

/// Le résultat d'une composition : le numéro et le texte qui partiraient, ou le refus.
class SmsCompose {
  const SmsCompose({this.numero, this.texte, this.refus, this.nomRetire = false});
  final String? numero;
  final String? texte;
  final SmsRefus? refus;

  /// Vrai quand le modèle portait `{{nom}}` : l'écran dit que le nom n'est pas envoyé.
  final bool nomRetire;
  bool get ok => refus == null;
}

const Map<String, String> _sansAccent = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o', 'ó': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae', '’': "'",
};

/// Ramène un texte à la forme de comparaison : minuscules, sans accent.
String smsFormeComparaison(String texte) {
  final b = StringBuffer();
  for (final r in texte.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_sansAccent[c] ?? c);
  }
  return b.toString();
}

/// Les mots interdits présents dans [texte] (dans l'ordre de la liste), vide s'il n'y en a aucun.
List<String> smsMotsInterditsTrouves(String texte, {List<String> liste = smsMotsInterdits}) {
  final t = smsFormeComparaison(texte);
  return [
    for (final mot in liste)
      if (RegExp('(^|[^a-z0-9])${RegExp.escape(smsFormeComparaison(mot))}[a-z]{0,3}(\$|[^a-z0-9])').hasMatch(t)) mot,
  ];
}

/// Le numéro au format international (`+229…`), ou `null` s'il n'en est pas un. Espaces, points, tirets et parenthèses sont ignorés ; « 00 » vaut « + » ;
/// un numéro sans indicatif reçoit [indicatif].
String? smsNormaliserNumero(String brut, {String indicatif = smsIndicatifDefaut}) {
  var s = brut.trim().replaceAll(RegExp(r'[\s.\-()/]'), '');
  if (s.isEmpty) return null;
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  if (!s.startsWith('+')) s = '+$indicatif$s';
  return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(s) ? s : null;
}

/// Le numéro masqué du journal de la mère : l'indicatif et les deux derniers chiffres (« +229 •••••••• 01 »).
String smsMasquerNumero(String numero) {
  if (numero.length < 6) return '••••';
  final indic = numero.startsWith('+229') ? '+229' : numero.substring(0, 3);
  return '$indic ${'•' * (numero.length - indic.length - 2)} ${numero.substring(numero.length - 2)}';
}

/// CONTRÔLE d'un SMS déjà composé (le service de la mère le refait avant d'envoyer au relais) : numéro international, texte non vide et borné, aucune
/// variable restée, aucun mot interdit. `null` : conforme.
SmsRefus? smsControler({required String numero, required String texte}) {
  if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(numero)) {
    return const SmsRefus('SMS_NUMERO_INVALIDE', 'Le numéro n’est pas au format international (« + » puis 8 à 15 chiffres).', 'Corriger le numéro de téléphone.');
  }
  if (texte.trim().isEmpty) return const SmsRefus('SMS_TEXTE_VIDE', 'Le texte du SMS est vide.', 'Choisir un modèle de message qui porte un texte.');
  if (texte.runes.length > smsLongueurMax) {
    return SmsRefus('SMS_TROP_LONG', 'Le texte fait ${texte.runes.length} caractères : $smsLongueurMax au plus.', 'Raccourcir le modèle de message.');
  }
  if (RegExp(r'[\x00-\x09\x0B-\x1F\x7F]').hasMatch(texte)) {
    return const SmsRefus('SMS_CARACTERE_INTERDIT', 'Le texte porte un caractère de contrôle.', 'Retirer le caractère du modèle de message.');
  }
  final reste = RegExp(r'\{\{[^}]*\}\}').firstMatch(texte);
  if (reste != null) {
    return SmsRefus('SMS_VARIABLE_INCONNUE', 'Le texte porte encore la variable ${reste.group(0)} : un patient ne doit jamais la recevoir.',
        'Retirer la variable du modèle ou la remplacer par une variable permise (${smsVariablesPermises.join(', ')}).');
  }
  final interdits = smsMotsInterditsTrouves(texte);
  if (interdits.isNotEmpty) {
    return SmsRefus('SMS_CONTENU_MEDICAL', 'Le texte contient un mot interdit dans un SMS (« ${interdits.first} ») : un SMS ne porte aucun contenu médical.',
        'Un rappel dit le jour, l’heure et la clinique : retirer le mot du modèle de message.');
  }
  return null;
}

/// COMPOSE un SMS depuis le texte d'un modèle. `{{nom}}` est retiré (jamais remplacé) ; `{{clinique}}`, `{{telephone}}`, `{{date}}` et `{{rdv}}` sont remplacés ;
/// une variable sans valeur ou inconnue, un numéro invalide, un texte trop long ou porteur d'un mot interdit : refus nommé.
SmsCompose smsComposer({
  required String modele,
  required String numero,
  required String clinique,
  String telephone = '',
  String? date,
  String? rdv,
}) {
  final n = smsNormaliserNumero(numero);
  if (n == null) {
    return const SmsCompose(refus: SmsRefus('SMS_NUMERO_INVALIDE', 'Le numéro n’est pas un numéro de téléphone reconnu.', 'Saisir le numéro avec ou sans indicatif (+229).'));
  }
  final nomRetire = modele.contains('{{nom}}');
  var t = modele.replaceAll('{{nom}}', '');
  final valeurs = {'{{clinique}}': clinique, '{{telephone}}': telephone, '{{date}}': date, '{{rdv}}': rdv};
  for (final e in valeurs.entries) {
    if (!t.contains(e.key)) continue;
    final v = e.value;
    if (v == null || v.trim().isEmpty) {
      return SmsCompose(
          numero: n,
          refus: SmsRefus('SMS_VARIABLE_MANQUANTE', 'Le modèle porte ${e.key} mais aucune valeur n’est fournie.', 'Renseigner la valeur demandée avant de composer le SMS.'),
          nomRetire: nomRetire);
    }
    t = t.replaceAll(e.key, v.trim());
  }
  // Le nom retiré laisse « Bonjour , » : la ponctuation et les espaces se resserrent.
  // (La typographie française garde son espace avant « ? », « ! », « : » et « ; ».)
  t = t.replaceAllMapped(RegExp(r'[ \t]+([,.])'), (m) => m[1]!).replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceAll(RegExp(r'^[ \t,]+'), '').trim();
  final refus = smsControler(numero: n, texte: t);
  return SmsCompose(numero: n, texte: t, refus: refus, nomRetire: nomRetire);
}
