/// LA RETENUE D'AIB SUR UNE FACTURE FOURNISSEUR (M7 → M12) : ce que la clinique retient à la source et doit reverser à l'État.
///
/// Le taux ne s'écrit nulle part ici : il vient du barème daté par situation de l'acheteur (`cpd_bareme_aib.dart`), à la date de la facture : la catégorie
/// de la retenue EST une situation (le fournisseur a un IFU actif, n'en a pas, ou la facture est une prestation retenue par le payeur). Seule une version ARRÊTÉE s'applique ;
/// sans version arrêtée en vigueur, la retenue est REFUSÉE en disant pourquoi — jamais un taux « commode ». La retenue ne réécrit pas la pièce : elle
/// s'ajoute (la facture PORTE sa retenue) et se constate par UNE pièce comptable plate, en brouillon, contrôlée équilibrée (RG-10) :
/// débit du compte fournisseur (la dette envers le fournisseur diminue), crédit du compte 4478 (la dette envers l'État naît).
///
/// Le reversement se fait le 10 du mois suivant, reporté au jour ouvrable suivant s'il tombe un samedi ou un dimanche — jamais avancé.
library;

import 'cpc_echeances.dart';
import 'cpd_bareme_aib.dart';
import '../referentiels/versions_datees.dart';

/// Le compte fournisseur débité par la retenue.
const String cpdCompteFournisseurRetenue = '401000';

/// Le jour du mois suivant où l'AIB retenu se reverse.
const int cpdJourReversementAib = 10;

class RefusRetenueAib implements Exception {
  const RefusRetenueAib(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

/// Le résultat du calcul : la situation, le taux appliqué, la base, le montant (au franc) et le motif du taux.
class CpdRetenueAib {
  const CpdRetenueAib(
      {required this.situation, required this.taux, required this.base, required this.montant, required this.motif, required this.dateEffet, this.versionId});
  final String situation;
  final num taux;
  final num base;
  final int montant;
  final String motif;
  final String dateEffet;

  /// La version du barème sous laquelle la retenue a été calculée : une correction ultérieure du barème ne la réécrit pas.
  final String? versionId;

  Map<String, Object?> versFiche() =>
      {'situation': situation, 'taux': taux, 'base': base, 'montant': montant, 'motif': motif, 'dateEffet': dateEffet, if (versionId != null) 'versionId': versionId};
}

/// Calcule la retenue sur [base] pour la situation [situation] à [date]. Refuse (nommément) : base nulle ou négative, aucun taux arrêté en vigueur.
CpdRetenueAib cpdCalculerRetenueAib(Iterable<CpdFiche> bareme, String situation, num base, DateTime date, {Iterable<CpdFiche>? situations}) {
  if (base <= 0) throw const RefusRetenueAib('La base de la retenue doit être positive.');
  final r = cpdTauxAibALaDate(bareme, situation, date, situations: situations);
  final t = r.taux;
  if (t == null || r.version == null) throw RefusRetenueAib('Retenue impossible pour « $situation » : ${r.motif}');
  return CpdRetenueAib(
      situation: situation,
      versionId: r.version!['id'] == null ? null : '${r.version!['id']}',
      taux: t,
      base: base,
      montant: cpdMontantAib(base, t),
      motif: r.motif,
      dateEffet: isoJour(r.version!['dateEffet'] ?? date));
}

/// La date de reversement : le 10 du mois suivant la retenue, reporté au jour ouvrable suivant.
DateTime cpdEcheanceReversementAib(DateTime retenue) =>
    cpcJourOuvrableSuivant(DateTime(retenue.year, retenue.month + 1, cpdJourReversementAib));

/// Les deux lignes plates de la pièce de retenue (brouillon). L'équilibre est CONSTRUIT puis contrôlé (RG-10) : refus nommé sinon.
List<Map<String, Object?>> cpdEcrituresRetenueAib({
  required CpdRetenueAib retenue,
  required String numero,
  required String date,
  required String reference,
  required String fournisseur,
  required String pieceId,
  String compteFournisseur = cpdCompteFournisseurRetenue,
  String compteRetenu = cpdCompteAibRetenu,
}) {
  if (retenue.montant <= 0) throw const RefusRetenueAib('Une retenue nulle ne se constate pas.');
  final libelle = 'Retenue AIB ${retenue.taux} % — facture $reference — $fournisseur';
  final base = <String, Object?>{
    'numero': numero,
    'date': date,
    'journal': 'ACH',
    'journalLibelle': 'Journal des achats',
    'libelle': libelle,
    'pieceId': pieceId,
    'pieceNumero': reference,
    'origine': 'Automatique — Retenue AIB',
    'statut': 'brouillon',
  };
  final lignes = [
    {...base, 'compte': compteFournisseur, 'compteLibelle': 'Fournisseurs', 'debit': retenue.montant, 'credit': 0},
    {...base, 'compte': compteRetenu, 'compteLibelle': 'AIB retenu à reverser à l\'État', 'debit': 0, 'credit': retenue.montant},
  ];
  final d = lignes.fold<num>(0, (s, l) => s + (l['debit'] as num));
  final c = lignes.fold<num>(0, (s, l) => s + (l['credit'] as num));
  if (d != c) throw RefusRetenueAib('Écriture déséquilibrée (débit $d ≠ crédit $c) : retenue refusée (RG-10).');
  return lignes;
}

/// Le contrôle AVANT retenue : une facture ne porte qu'UNE retenue ; une facture archivée n'en reçoit pas.
String? cpdControlerRetenueFacture(Map<String, Object?> facture) {
  if ('${facture['statut'] ?? 'actif'}' != 'actif') return 'Une facture archivée ne reçoit pas de retenue.';
  if (facture['retenueAib'] is Map) return 'Cette facture porte déjà une retenue d\'AIB : la corriger se fait par une nouvelle pièce, jamais en la réécrivant.';
  return null;
}

/// Le registre des retenues : une ligne par facture retenue, avec la date de reversement, et les totaux par mois de retenue.
class CpdRegistreRetenues {
  const CpdRegistreRetenues({required this.lignes, required this.parMois, required this.total});
  final List<Map<String, Object?>> lignes;
  final Map<String, int> parMois;
  final int total;
}

CpdRegistreRetenues cpdRegistreRetenuesAib(Iterable<Map<String, Object?>> factures) {
  final lignes = <Map<String, Object?>>[];
  final parMois = <String, int>{};
  var total = 0;
  for (final f in factures) {
    if ('${f['statut'] ?? 'actif'}' != 'actif') continue;
    final r = f['retenueAib'];
    if (r is! Map) continue;
    final date = DateTime.tryParse('${r['date'] ?? f['date'] ?? ''}');
    final m = (r['montant'] as num?)?.round() ?? 0;
    final mois = date == null ? '—' : isoJour(date).substring(0, 7);
    parMois[mois] = (parMois[mois] ?? 0) + m;
    total += m;
    lignes.add({
      'reference': f['reference'],
      'fournisseur': f['fournisseurNom'],
      'date': date == null ? null : isoJour(date),
      'situation': r['situation'] ?? r['code'],
      'taux': r['taux'],
      'base': r['base'],
      'montant': m,
      'reversement': date == null ? null : isoJour(cpdEcheanceReversementAib(date)),
    });
  }
  lignes.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  return CpdRegistreRetenues(lignes: lignes, parMois: parMois, total: total);
}
