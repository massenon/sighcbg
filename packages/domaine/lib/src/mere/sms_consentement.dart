/// LE CONSENTEMENT DU PATIENT AU SMS (E5201, ADR-0009, ECARTS E3681).
///
/// Un SMS part sur le téléphone d'un patient : il n'est envoyé qu'à celui qui l'a ACCEPTÉ. Le dossier porte trois champs — `consentementSms` (vrai : accepte, faux : refuse),
/// `consentementSmsLe` (l'instant du dernier changement) et `consentementSmsPar` (l'agent qui l'a consigné), les colonnes `consentement_sms*` du schéma. TROIS états et non
/// deux : un dossier d'avant ce champ, ou un patient qu'on n'a pas encore interrogé, est « NON RENSEIGNÉ » — jamais présumé consentant, et jamais confondu avec un refus.
/// Le champ vide n'existe donc pas comme valeur écrite : l'absence EST « non renseigné ».
///
///  * le formulaire patient (création et fiche) propose une liste « Accepte / Refuse » laissée vide tant que personne n'a répondu ; une modification qui ne touche pas à ce
///    champ le laisse intact (changer un quartier ne transforme pas « non renseigné » en refus) ;
///  * cocher ou décocher change la valeur ET date/signe le changement ; l'écriture passe par le journal d'audit du magasin (RG-12 : ancienne et nouvelle valeur) ;
///  * la composition d'un SMS depuis un patient sans consentement est REFUSÉE en le nommant, au poste puis par la mère, qui relit le dossier elle-même.
library;

import 'sms.dart' show SmsRefus;

/// Les trois états du consentement.
enum SmsConsentement { accepte, refuse, nonRenseigne }

/// Les valeurs du champ du formulaire (liste à deux choix ; vide : non renseigné).
const String smsChoixAccepte = 'oui';
const String smsChoixRefuse = 'non';

/// Le libellé affiché de chaque choix du formulaire.
const Map<String, String> smsLibellesChoixConsentement = {smsChoixAccepte: 'Accepte de recevoir des SMS', smsChoixRefuse: 'Refuse de recevoir des SMS'};

/// Le consentement d'un dossier. Accepte les formes qu'un champ peut avoir au magasin : booléen, ou texte « oui » / « non » (formulaire, import).
SmsConsentement smsConsentementDe(Map<String, Object?>? patient) {
  final v = patient?['consentementSms'];
  if (v == true || v == smsChoixAccepte || v == 'true') return SmsConsentement.accepte;
  if (v == false || v == smsChoixRefuse || v == 'false') return SmsConsentement.refuse;
  return SmsConsentement.nonRenseigne;
}

/// Le refus nommé quand le dossier ne permet pas d'écrire au patient par SMS ; `null` : le patient a accepté.
SmsRefus? smsRefusConsentement(Map<String, Object?>? patient) {
  if (patient == null) {
    return const SmsRefus('SMS_PATIENT_INCONNU', 'Aucun dossier patient ne correspond : le consentement au SMS ne peut pas être vérifié.', 'Choisir un patient du répertoire.');
  }
  switch (smsConsentementDe(patient)) {
    case SmsConsentement.accepte:
      return null;
    case SmsConsentement.refuse:
      return const SmsRefus('SMS_CONSENTEMENT_REFUSE', 'Le patient a refusé de recevoir des SMS.', 'Respecter ce refus : joindre le patient autrement, ou lui redemander et corriger « Consentement aux SMS » à son dossier.');
    case SmsConsentement.nonRenseigne:
      return const SmsRefus('SMS_CONSENTEMENT_ABSENT', 'Le consentement du patient aux SMS n’est pas renseigné : il n’est jamais présumé.', 'Demander au patient et renseigner « Consentement aux SMS » à son dossier (accueil).');
  }
}

/// Applique le consentement saisi au formulaire à la fiche à écrire. [saisie] porte `consentementSms` (choix du formulaire, booléen ou vide) ; [record] est la fiche avant
/// modification (`null` à la création) ; [maintenant] et [auteur] datent et signent un CHANGEMENT. Sans changement, la valeur, la date et l'auteur déjà consignés sont gardés tels
/// quels ; un champ laissé vide ne retire rien (retirer un consentement, c'est le REFUSER, ce qui se date et se signe).
Map<String, Object?> smsAppliquerConsentement(Map<String, Object?> saisie, Map<String, Object?>? record, DateTime maintenant, String auteur) {
  final v = {...saisie};
  final avant = smsConsentementDe(record);
  final demande = smsConsentementDe(v);
  v.remove('consentementSms');
  v.remove('consentementSmsLe');
  v.remove('consentementSmsPar');
  final etat = demande == SmsConsentement.nonRenseigne ? avant : demande;
  if (etat == SmsConsentement.nonRenseigne) return v;
  v['consentementSms'] = etat == SmsConsentement.accepte;
  if (etat == avant && record != null) {
    if (record['consentementSmsLe'] != null) v['consentementSmsLe'] = record['consentementSmsLe'];
    if (record['consentementSmsPar'] != null) v['consentementSmsPar'] = record['consentementSmsPar'];
  } else {
    v['consentementSmsLe'] = maintenant.toUtc().toIso8601String();
    v['consentementSmsPar'] = auteur;
  }
  return v;
}

/// La valeur du champ du formulaire pour une fiche (vide : non renseigné).
String smsChoixDeFiche(Map<String, Object?>? patient) => switch (smsConsentementDe(patient)) {
      SmsConsentement.accepte => smsChoixAccepte,
      SmsConsentement.refuse => smsChoixRefuse,
      SmsConsentement.nonRenseigne => '',
    };

/// Le libellé du consentement pour la fiche et l'état imprimé : l'état, puis QUAND et PAR QUI quand c'est consigné.
String smsLibelleConsentement(Map<String, Object?>? patient) {
  final etat = switch (smsConsentementDe(patient)) {
    SmsConsentement.accepte => 'Accepte les SMS',
    SmsConsentement.refuse => 'Refuse les SMS',
    SmsConsentement.nonRenseigne => 'Non renseigné',
  };
  final le = DateTime.tryParse('${patient?['consentementSmsLe'] ?? ''}')?.toLocal();
  final par = '${patient?['consentementSmsPar'] ?? ''}'.trim();
  if (le == null && par.isEmpty) return etat;
  final jour = le == null ? '' : ' le ${le.day.toString().padLeft(2, '0')}/${le.month.toString().padLeft(2, '0')}/${le.year}';
  return '$etat —$jour${par.isEmpty ? '' : ' (par $par)'}';
}
