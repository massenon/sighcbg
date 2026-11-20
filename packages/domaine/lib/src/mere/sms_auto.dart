/// LES ENVOIS AUTOMATIQUES DE SMS (E5200, ECARTS E3680, ADR-0009) : le rappel la veille d'un rendez-vous et les vœux d'anniversaire.
///
/// Règles PURES, rejouables sans base ni relais ; le service de la mère (`PasserelleSms.executerAutomatiques`) y ajoute la lecture des fiches, la trace des dépôts et le dépôt.
///
///  * UNE FOIS PAR JOUR, à l'heure réglée (`sms.heureExecution`) : [smsAutoEstDu] dit si le tour du jour est dû — passé l'heure et pas encore fait aujourd'hui, donc rattrapé
///    si la mère était éteinte à l'heure dite ;
///  * UN ENVOI PAR PATIENT ET PAR OCCASION : la clé d'un envoi ([SmsAutoCandidat.cle]) est `rappel_rdv:<patient>:<jour du rendez-vous>` ou `anniversaire:<patient>:<année>` ; la mère
///    en garde la trace et ne dépose jamais deux fois la même clé, même si le tour est rejoué ;
///  * LE MESSAGE est un modèle neutre (jour, heure, clinique) : le nom est retiré, aucune donnée de santé, et le modèle doit être PROPOSABLE au SMS (`smsModeleProposable`) ;
///  * LE CONSENTEMENT du patient est exigé (`smsRefusConsentement`) : non renseigné ou refusé, rien ne part, et le refus est nommé dans le bilan ;
///  * le DÉLAI de rappel est réglé en heures (`sms.delaiRappelHeures`, 24 : « la veille ») ; il se ramène au JOUR du rendez-vous, parce qu'un tour par jour ne peut pas viser une heure.
library;

import '../consultation/ag_commun.dart' show agDate;
import '../format/format_fr.dart' show dateFR, iso;
import '../parametres/parametres_clinique.dart' show reglageBooleenA, seuilEntierA;
import 'sms.dart';
import 'sms_consentement.dart';

/// Les deux occasions automatiques (codes des clés de trace et du bilan).
const String smsOccasionRappelRdv = 'rappel_rdv';
const String smsOccasionAnniversaire = 'anniversaire';

/// Le modèle de message utilisé pour chaque occasion (code d'occasion de `modelesMessage`).
const Map<String, String> smsOccasionModele = {smsOccasionRappelRdv: 'rdv', smsOccasionAnniversaire: 'anniversaire'};

/// Les refus nommés propres aux envois automatiques (les refus de composition et de consentement gardent leurs codes).
const String smsAutoSansTelephone = 'SMS_AUTO_SANS_TELEPHONE';
const String smsAutoModeleAbsent = 'SMS_AUTO_MODELE_ABSENT';

/// Les réglages EN VIGUEUR un jour donné.
class SmsAutoReglage {
  const SmsAutoReglage({required this.rappelRdvActif, required this.voeuxAnniversaireActif, required this.heure, required this.delaiRappelHeures});
  final bool rappelRdvActif;
  final bool voeuxAnniversaireActif;

  /// L'heure locale (0 à 23) à partir de laquelle le tour du jour est dû.
  final int heure;
  final int delaiRappelHeures;
  bool get unEnvoiActif => rappelRdvActif || voeuxAnniversaireActif;
}

/// Les réglages en vigueur à [date] (AAAA-MM-JJ) : version datée, sinon défaut de la définition (bornes de la définition respectées). Les envois sont FERMÉS par défaut.
SmsAutoReglage smsAutoReglageA(Iterable<Map<String, Object?>> fichesParametres, String date) => SmsAutoReglage(
      rappelRdvActif: reglageBooleenA(fichesParametres, cleSmsRappelRdvActif, date),
      voeuxAnniversaireActif: reglageBooleenA(fichesParametres, cleSmsVoeuxAnniversaireActif, date),
      heure: seuilEntierA(fichesParametres, cleSmsHeureExecution, date),
      delaiRappelHeures: seuilEntierA(fichesParametres, cleSmsDelaiRappelHeures, date),
    );

/// Le tour du jour est-il DÛ ? Passé l'heure réglée, et pas déjà fait aujourd'hui ([dernierJour] : AAAA-MM-JJ du dernier tour achevé).
bool smsAutoEstDu(DateTime maintenant, SmsAutoReglage r, String? dernierJour) => r.unEnvoiActif && maintenant.hour >= r.heure && dernierJour != iso(maintenant);

/// Un envoi à faire.
class SmsAutoCandidat {
  const SmsAutoCandidat({required this.occasion, required this.cle, required this.patient, required this.jourOccasion, this.rdv});
  final String occasion;

  /// La clé d'idempotence : un seul envoi par patient et par occasion.
  final String cle;
  final Map<String, Object?> patient;

  /// Le jour de l'occasion (AAAA-MM-JJ) : celui du rendez-vous, ou le jour de l'anniversaire. Sert à purger les traces périmées.
  final String jourOccasion;

  /// « 18/11/2026 à 09h00 » (ou la date seule quand le rendez-vous n'a pas d'heure) ; seulement pour un rappel.
  final String? rdv;
}

bool _vrai(Object? v) => v != null && v != '' && v != 0 && v != false;

String _deuxChiffres(int n) => n.toString().padLeft(2, '0');

/// Le jour VISÉ par un rappel : le jour de `maintenant + délai`.
String smsAutoJourDuRappel(DateTime maintenant, int delaiHeures) => iso(maintenant.add(Duration(hours: delaiHeures)));

/// Les envois à faire AUJOURD'HUI, dans l'ordre : les rappels de rendez-vous puis les vœux, chacun seulement si son réglage est ouvert. Dédoublonnés par clé. Les fiches archivées
/// ne sont pas passées ici (la mère ne lit que les actives). Un rendez-vous sans dossier (personne non enregistrée) n'a pas de consentement : il n'est pas candidat.
List<SmsAutoCandidat> smsAutoCandidats({
  required Iterable<Map<String, Object?>> patients,
  required Iterable<Map<String, Object?>> rendezvous,
  required DateTime maintenant,
  required SmsAutoReglage reglage,
}) {
  final parId = {for (final p in patients) '${p['id']}': p};
  final vus = <String>{};
  final out = <SmsAutoCandidat>[];
  if (reglage.rappelRdvActif) {
    final cible = smsAutoJourDuRappel(maintenant, reglage.delaiRappelHeures);
    for (final r in rendezvous) {
      if (r['statut'] != 'planifiee' && r['statut'] != 'reporte') continue;
      if (r['nonPatient'] == true || !_vrai(r['patientId'])) continue;
      final d = agDate(r['date']);
      if (d == null || iso(d) != cible) continue;
      final p = parId['${r['patientId']}'];
      if (p == null) continue;
      final cle = '$smsOccasionRappelRdv:${p['id']}:$cible';
      if (!vus.add(cle)) continue;
      final avecHeure = RegExp(r'[T ]\d{2}:\d{2}').hasMatch('${r['date']}');
      out.add(SmsAutoCandidat(
          occasion: smsOccasionRappelRdv,
          cle: cle,
          patient: p,
          jourOccasion: cible,
          rdv: avecHeure ? '${dateFR(d)} à ${_deuxChiffres(d.hour)}h${_deuxChiffres(d.minute)}' : dateFR(d)));
    }
  }
  if (reglage.voeuxAnniversaireActif) {
    final auj = iso(maintenant);
    for (final p in patients) {
      final n = '${p['dateNaissance'] ?? ''}';
      if (n.length < 10) continue;
      var mmjj = n.substring(5, 10);
      // Né un 29 février : fêté le 28 février les années où il n'existe pas.
      final bissextile = DateTime(maintenant.year, 3, 0).day == 29;
      if (mmjj == '02-29' && !bissextile) mmjj = '02-28';
      if (auj.substring(5, 10) != mmjj) continue;
      final cle = '$smsOccasionAnniversaire:${p['id']}:${maintenant.year}';
      if (vus.add(cle)) out.add(SmsAutoCandidat(occasion: smsOccasionAnniversaire, cle: cle, patient: p, jourOccasion: auj));
    }
  }
  return out;
}

/// Le texte du premier modèle ACTIF de l'occasion qui soit PROPOSABLE au SMS ; `null` : aucun. Un modèle « Anniversaire » de la maquette qui dit « santé » est donc sauté au profit
/// du modèle neutre, sans qu'aucun texte ne soit réécrit en silence.
String? smsAutoModele(String occasion, Iterable<Map<String, Object?>> modeles) {
  final code = smsOccasionModele[occasion];
  for (final m in modeles) {
    if (m['occasion'] != code || m['actif'] == false || m['statut'] == 'archive') continue;
    final t = '${m['texte'] ?? ''}';
    if (t.trim().isNotEmpty && smsModeleProposable(occasion: m['occasion'], texte: t)) return t;
  }
  return null;
}

/// Un envoi préparé : le numéro et le texte qui partiraient, ou le refus nommé.
class SmsAutoPrepare {
  const SmsAutoPrepare(this.candidat, {this.numero, this.texte, this.refus});
  final SmsAutoCandidat candidat;
  final String? numero;
  final String? texte;
  final SmsRefus? refus;
  bool get ok => refus == null;
}

/// Prépare un envoi : consentement, numéro, modèle, composition (mêmes règles que la composition manuelle : nom retiré, mots interdits refusés).
SmsAutoPrepare smsAutoPreparer(SmsAutoCandidat c, {required Iterable<Map<String, Object?>> modeles, required String clinique, required String telephone}) {
  final consentement = smsRefusConsentement(c.patient);
  if (consentement != null) return SmsAutoPrepare(c, refus: consentement);
  final tel = '${c.patient['telephone'] ?? ''}'.trim();
  if (tel.isEmpty) {
    return SmsAutoPrepare(c, refus: const SmsRefus(smsAutoSansTelephone, 'Le dossier du patient ne porte aucun numéro de téléphone.', 'Renseigner le téléphone au dossier du patient.'));
  }
  final modele = smsAutoModele(c.occasion, modeles);
  if (modele == null) {
    return SmsAutoPrepare(c,
        refus: SmsRefus(smsAutoModeleAbsent, 'Aucun modèle de message actif et proposable par SMS pour l’occasion « ${smsOccasionModele[c.occasion]} ».',
            'Activer un modèle neutre à « Rappels & messages » (jour, heure, clinique ; aucun mot de santé).'));
  }
  final r = smsComposer(modele: modele, numero: tel, clinique: clinique, telephone: telephone, rdv: c.rdv, date: dateFR(DateTime.parse(c.jourOccasion)));
  return SmsAutoPrepare(c, numero: r.numero, texte: r.texte, refus: r.refus);
}
