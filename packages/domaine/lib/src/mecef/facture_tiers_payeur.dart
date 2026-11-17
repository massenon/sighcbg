/// LA FACTURE À UNE ENTREPRISE QUI PREND EN CHARGE UN PATIENT (Direction de Baguidi, 17/11/2026, point 2 de `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` § 10) : une vente normalisée
/// distincte de la facture du patient, adressée à un TIERS PAYEUR identifié par son IFU et son nom (un employeur, une convention). La facture du PATIENT reste ce qu'elle est : normalisée
/// sans acheteur ni AIB (`facture_patient.dart`) ; celle-ci est la seule pièce de la clinique qui porte un acheteur.
///
/// COMMENT LA PIÈCE SE RATTACHE (aucune seconde vérité) : elle naît d'une ligne du RELEVÉ de M9 — la ligne d'un souscripteur, d'une compagnie, sur une période (`assFillesMere`, la
/// fonction même de la facture mère et de la facture mensuelle). Son MONTANT est la part prise en charge de cette ligne (`AssFilleMere.assureur`), jamais une saisie ; elle porte les
/// NUMÉROS des factures patients qu'elle réclame (`piecesFilles`) et le rappel de sa ligne (compagnie, souscripteur, période). Une facture patient ne se réclame qu'UNE fois : si l'une
/// des filles figure déjà sur une autre facture à une entreprise ou sur une facture mère émise, l'émission est refusée en nommant la pièce.
///
/// Ce que le comptable DÉCIDE, et que rien ne présume : la SITUATION de l'acheteur au barème de l'AIB (jamais choisie d'office, même quand l'IFU suffirait à la déduire) ; le taux en
/// découle, lu au barème ARRÊTÉ en vigueur à la date (`acheteurNormaliseAuBareme`) — un taux non arrêté ne s'applique jamais. Le geste est réservé (`facture_tiers_emettre`).
///
/// Fonctions PURES : elles rendent la fiche à écrire ou un refus nommé (code, motif, geste) ; elles n'écrivent rien.
library;

import '../assurances/ass_regles.dart' show AssFilleMere;
import '../comptabilite/cpd_bareme_aib.dart' show CpdFiche;
import '../comptabilite/cpd_parametres_aib.dart' show CpdParametresAib;
import '../droits/gestes_reserves.dart';
import '../numerotation/numerotation.dart';
import 'acheteur_aib.dart';
import 'montants.dart';

/// La collection des factures à une entreprise (propre à M9). Elle voyage entre les postes (famille A de la mère, jamais vers un téléphone) mais ne s'ÉCRIT que sur la mère :
/// un fileul y dépose une DEMANDE (`facture_tiers_synchro.dart`).
const String colFacturesTiers = 'facturesTiers';

/// La série du référentiel `seriesNumerotation` qui numérote ces pièces (jamais le numéro des factures de la caisse).
const String serieFactureTiers = 'caisse.factures-tiers';

/// Le réglage des POSTES SIGNATAIRES de la pièce imprimée (rien en dur : les postes sont nommés par la clinique, leur titulaire est lu à l'organigramme).
const String factureTiersCleSignataires = 'factureTiers.signataires';

/// Le type porté par la pièce.
const String typeFactureTiersPayeur = 'tiers_payeur';

/// Un refus nommé : le code, ce qui est refusé, et le geste qui débloque.
class RefusTiersPayeur {
  const RefusTiersPayeur(this.code, this.motif, this.geste);
  final String code, motif, geste;
  Map<String, Object?> toJson() => {'ok': false, 'code': code, 'motif': motif, 'geste': geste};
}

/// Le verdict : la fiche à écrire, ou le refus.
class VerdictFactureTiers {
  const VerdictFactureTiers.ok(Map<String, Object?> this.fiche) : refus = null;
  const VerdictFactureTiers.refus(RefusTiersPayeur this.refus) : fiche = null;
  final Map<String, Object?>? fiche;
  final RefusTiersPayeur? refus;
  bool get ok => fiche != null;
}

/// Les numéros des factures patients déjà RÉCLAMÉES : par une facture à une entreprise ACTIVE ([facturesTiers]) ou par une facture mère ÉMISE ([facturesMere] actives). Le numéro de
/// chaque fille donne la pièce qui la réclame (pour nommer le refus). Une facture à une entreprise ENTIÈREMENT contre-passée par avoirs (`montantAvoirs` ≥ `montantTTC`) ne réclame
/// plus rien : ses filles sont libres, c'est la voie que le refus « Retirer la pièce qui les réclame par un avoir » annonce.
Map<String, String> fillesDejaReclamees({Iterable<Map<String, Object?>> facturesTiers = const [], Iterable<Map<String, Object?>> facturesMere = const []}) {
  final out = <String, String>{};
  for (final (nature, pieces) in [('une facture à une entreprise', facturesTiers), ('la facture mère', facturesMere)]) {
    for (final p in pieces) {
      if (p['statut'] == 'archive') continue;
      if (p['type'] == typeFactureTiersPayeur && _tout(p['montantAvoirs']) > 0 && _tout(p['montantAvoirs']) >= _tout(p['montantTTC'])) continue;
      for (final n in (p['piecesFilles'] as List? ?? const [])) {
        out.putIfAbsent('$n', () => '$nature ${p['numero'] ?? p['id'] ?? ''}'.trim());
      }
    }
  }
  return out;
}

num _tout(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

String _montant(num n) => n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// ÉMETTRE une facture à une entreprise : le refus nommé, ou la fiche à écrire. Ordre des contrôles : le geste ; la ligne du relevé ; les filles déjà réclamées ; l'acheteur (IFU et
/// nom, tous deux obligatoires pour un tiers payeur) ; la situation d'AIB CHOISIE ; le taux du barème arrêté ; les montants de la normalisation (entiers, total cohérent).
VerdictFactureTiers emettreFactureTiersPayeur({
  required String role,
  DroitsGestes? gestes,
  bool fileul = false,
  required Object? acheteurIfu,
  required Object? acheteurNom,
  required Object? situationChoisie,
  required String compagnieCode,
  required String compagnieNom,
  required String periode,
  required String periodeLibelle,
  required String depuis,
  required AssFilleMere? ligne,
  Iterable<Map<String, Object?>> facturesTiers = const [],
  Iterable<Map<String, Object?>> facturesMere = const [],
  required DateTime date,
  required Iterable<CpdFiche> situations,
  required Iterable<CpdFiche> versions,
  CpdParametresAib? parametres,
  num tauxTvaCourant = 0,
  required String auteur,
  String? note,
}) {
  VerdictFactureTiers non(String code, String motif, String geste) => VerdictFactureTiers.refus(RefusTiersPayeur(code, motif, geste));
  if (fileul) {
    return non('FILEUL_LECTURE_SEULE', 'Ce poste est un fileul : la facture à une entreprise s’émet depuis le poste mère, qui tient la numérotation et la normalisation.',
        'Émettre depuis le poste mère ; la pièce reviendra ici par la synchronisation.');
  }
  if (role.isEmpty || !(gestes ?? gestesOrigine()).peut(role, gesteFactureTiersEmettre)) {
    return non('TIERS_PAYEUR_RESERVE', 'Émettre une facture à une entreprise est un geste réservé (« Émettre une facture à une entreprise ») que votre rôle ne détient pas.',
        'Demander au comptable ou à la DAF, ou faire accorder le geste au rôle dans « Rôles et permissions › Gestes réservés ».');
  }
  if (ligne == null || ligne.factures.isEmpty) {
    return non('RELEVE_VIDE', 'Aucune ligne du relevé de M9 ne correspond : le souscripteur n’a aucune facture patient prise en charge sur la période.',
        'Choisir la compagnie, la période et le souscripteur dans le relevé ; la pièce ne se saisit pas à la main.');
  }
  final montant = ligne.assureur;
  if (!(montant > 0)) {
    return non('MONTANT_NUL', 'La part prise en charge de « ${ligne.souscripteur} » est nulle sur la période : il n’y a rien à facturer à l’entreprise.', 'Choisir une autre ligne du relevé.');
  }
  final numerosFilles = [for (final f in ligne.factures) '${f['numero'] ?? f['id']}'];
  final reclamees = fillesDejaReclamees(facturesTiers: facturesTiers, facturesMere: facturesMere);
  final deja = [for (final n in numerosFilles) if (reclamees.containsKey(n)) '$n (${reclamees[n]})'];
  if (deja.isNotEmpty) {
    return non('FILLE_DEJA_FACTUREE', 'Des factures patients de cette ligne sont déjà réclamées : ${deja.join(', ')}. Une facture patient ne se réclame qu’une fois.',
        'Retirer la pièce qui les réclame par un avoir, ou choisir une autre période.');
  }
  final ifu = '${acheteurIfu ?? ''}'.replaceAll(RegExp('[\\s  ]'), '');
  final nom = '${acheteurNom ?? ''}'.trim();
  if (ifu.isEmpty) {
    return non('IFU_ACHETEUR_REQUIS', 'L’IFU de l’entreprise est obligatoire : une facture à un tiers payeur identifie son acheteur.', 'Saisir l’IFU de l’entreprise (13 chiffres).');
  }
  if (nom.isEmpty) {
    return non('NOM_ACHETEUR_ABSENT', 'Le nom de l’entreprise est obligatoire : il accompagne son IFU sur la pièce normalisée.', 'Saisir le nom de l’entreprise qui porte cet IFU.');
  }
  final situation = '${situationChoisie ?? ''}'.trim();
  if (situation.isEmpty) {
    return non('AIB_SITUATION_A_CHOISIR', 'La situation de l’acheteur au barème de l’AIB n’est jamais présumée : le comptable la choisit.',
        'Choisir la situation de l’entreprise dans la liste du barème (Paramètres, « Acompte sur impôt (AIB) »).');
  }
  final ach = acheteurNormaliseAuBareme(ifu: ifu, nom: nom, situationChoisie: situation, date: date, situations: situations, versions: versions, parametres: parametres);
  if (ach.acheteur == null) {
    final r = ach.refus!;
    return non(r.code, r.motif, r.geste);
  }
  final designation = 'Prise en charge des soins — ${ligne.souscripteur} (${compagnieNom.isEmpty ? compagnieCode : compagnieNom}, $periodeLibelle)';
  final m = mecefMontants(
      lignes: [
        {'id': 'L001', 'designation': designation, 'quantite': 1, 'prixUnitaire': montant, 'montantBrut': montant, 'remise': 0, 'partAssureur': 0, 'partPersonnel': 0}
      ],
      totalAttendu: montant,
      aibTaux: ach.acheteur!.aibTaux,
      tauxTvaCourant: tauxTvaCourant);
  if (!m.ok) {
    final r = m.refus!;
    return non(r.code, r.motif, r.geste);
  }
  final mt = m.montants!;
  final numero = numeroSuivant(serieFactureTiers, date: date, existants: facturesTiers);
  return VerdictFactureTiers.ok({
    'numero': numero,
    'type': typeFactureTiersPayeur,
    'statut': 'actif',
    'date': _iso(date),
    'acheteurIfu': ifu,
    'acheteurNom': nom,
    'aibSituation': ach.acheteur!.aibSituation,
    'aibTaux': ach.acheteur!.aibTaux,
    'aibMotif': ach.aib.motif,
    'aibMontant': mt.aib,
    'montantTTC': mt.total,
    'montantHT': mt.ht,
    'tva': mt.tva,
    'netAPayer': mt.net,
    'baseMecef': mt.base,
    'designation': designation,
    'compagnieCode': compagnieCode,
    'compagnie': compagnieNom,
    'souscripteur': ligne.souscripteur,
    'periode': periode,
    'periodeLabel': periodeLibelle,
    'debut': depuis,
    'fin': _iso(date),
    'montantReleve': montant,
    'piecesFilles': numerosFilles,
    'nbFilles': numerosFilles.length,
    'statutMecef': 'en_attente',
    'emisePar': auteur,
    if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
  });
}

/// La phrase du rattachement, pour l'écran et la pièce : d'où vient le montant.
String rattachementFactureTiers(Map<String, Object?> f) =>
    'Part prise en charge de « ${f['souscripteur']} » au relevé de M9 (${f['compagnie'] ?? f['compagnieCode']}, ${f['periodeLabel'] ?? f['periode']}, du ${f['debut']} au ${f['fin']}) : '
    '${_montant((f['montantReleve'] as num?) ?? 0)} F sur ${f['nbFilles']} facture(s) patient (${((f['piecesFilles'] as List?) ?? const []).join(', ')}).';
