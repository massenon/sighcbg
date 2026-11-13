/// LA MÉDECINE DU TRAVAIL — cœur de métier de la clinique, seule spécialité aux écrans propres : visites d'embauche, périodique et de reprise, fiche
/// d'aptitude, entreprises clientes et leurs salariés, conventions de visites. Règles pures, rejouées par `test/spec_travail_test.dart`.
///
/// Trois partis pris :
///  * l'ENTREPRISE CLIENTE est un souscripteur de catégorie « entreprise » (M9) et ses SALARIÉS sont les patients qui lui sont rattachés : une seconde
///    liste divergerait de la première au premier recrutement. Les écrans de médecine du travail en sont des VUES ;
///  * la FICHE D'APTITUDE est une pièce certifiante TARIFÉE par la caisse, comme les quatorze autres : elle réutilise `patFacturerPiece` (grille MT-FAP) ;
///  * la CONVENTION de visites est la seule donnée nouvelle : période, périodicité, nombre de visites prévues — l'entreprise ne s'y recopie pas.
library;

import '../format/format_fr.dart';
import '../patients/pat_pieces.dart' show PatTypePiece;
import '../referentiels/regles.dart' show joursEntre;

typedef FicheMdt = Map<String, Object?>;

/// Les trois visites réglementaires. `acte` et `codeTarif` renvoient au catalogue (actes MT01 à MT03, grille MT-EMB / MT-PER / MT-REP).
class MdtNature {
  const MdtNature(this.code, this.libelle, this.acte, this.codeTarif);
  final String code;
  final String libelle;
  final String acte;
  final String codeTarif;
}

const mdtNatures = <MdtNature>[
  MdtNature('embauche', 'Visite médicale d’embauche', 'MT01', 'MT-EMB'),
  MdtNature('periodique', 'Visite médicale périodique', 'MT02', 'MT-PER'),
  MdtNature('reprise', 'Visite médicale de reprise', 'MT03', 'MT-REP'),
];

MdtNature? mdtNature(Object? code) => mdtNatures.where((n) => n.code == code || n.libelle == code).firstOrNull;

/// Les avis d'aptitude. Les trois premiers sont ceux que porte le registre des visites ; l'inaptitude définitive les complète.
const mdtAptitudes = ['Apte', 'Apte avec aménagement de poste', 'Inapte temporaire', 'Inapte définitif'];

/// Périodicité des visites périodiques par défaut, en mois (la convention la fixe pour l'entreprise).
const mdtPeriodiciteDefaut = 12;

/// La fiche d'aptitude comme pièce certifiante (type TPC15 de `typesPiece`), tarifée par la caisse sur la grille MT-FAP. Elle porte le sigle FAP : aucune
/// des collisions de sigle des sources (CMA, CMD) n'est reproduite.
const mdtTypePiece = PatTypePiece('TPC15', 'FAP', 'Fiche d’aptitude (médecine du travail)', 'DM/DA', 'MT-FAP', null, null);

/// `valableJusqua` d'une fiche : douze mois après la visite, sauf inaptitude définitive (aucune validité : le salarié n'est pas apte à ce poste).
String? mdtValiditeFiche(DateTime visite, String aptitude) {
  if (aptitude == 'Inapte définitif') return null;
  return iso(DateTime(visite.year + 1, visite.month, visite.day));
}

/// `FA-0007/26` : la série annuelle des fiches d'aptitude (celle de l'année de la visite), archivées comprises — une fiche archivée garde son numéro.
String mdtReferenceFiche(Iterable<FicheMdt> consultations, DateTime date) {
  final aa = (date.year % 100).toString().padLeft(2, '0');
  var max = 0;
  for (final c in consultations) {
    final f = c['ficheAptitude'];
    final ref = f is Map ? '${f['reference']}' : '';
    final m = RegExp(r'^FA-(\d+)/(\d{2})$').firstMatch(ref);
    if (m != null && m.group(2) == aa) {
      final n = int.parse(m.group(1)!);
      if (n > max) max = n;
    }
  }
  return 'FA-${(max + 1).toString().padLeft(4, '0')}/$aa';
}

/// L'état d'un salarié au regard de ses visites. Trois réponses, et la dernière n'est pas un retard : un salarié JAMAIS vu attend sa visite d'embauche.
enum MdtEtat {
  aJour('a_jour', 'À jour'),
  aPlanifier('a_planifier', 'À planifier'),
  enRetard('en_retard', 'En retard'),
  jamaisVu('jamais_vu', 'Jamais vu');

  const MdtEtat(this.code, this.libelle);
  final String code;
  final String libelle;
}

({MdtEtat etat, String? echeance, int? jours}) mdtEtatSalarie(DateTime? derniereVisite, DateTime aujourdhui,
    {int periodiciteMois = mdtPeriodiciteDefaut, int preavisJours = 30}) {
  if (derniereVisite == null) return (etat: MdtEtat.jamaisVu, echeance: null, jours: null);
  final due = DateTime(derniereVisite.year, derniereVisite.month + periodiciteMois, derniereVisite.day);
  final jours = joursEntre(DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day), due);
  final etat = jours < 0 ? MdtEtat.enRetard : (jours <= preavisJours ? MdtEtat.aPlanifier : MdtEtat.aJour);
  return (etat: etat, echeance: iso(due), jours: jours);
}

/// Une convention est EN VIGUEUR à [jour] (`aaaa-mm-jj`) : non archivée, commencée, et soit sans fin (reconduction), soit non échue.
bool mdtConventionEnVigueur(FicheMdt conv, String jour) {
  if (conv['statut'] == 'archive') return false;
  final debut = '${conv['dateDebut'] ?? ''}';
  if (debut.isNotEmpty && debut.compareTo(jour) > 0) return false;
  final fin = '${conv['dateFin'] ?? ''}';
  return fin.isEmpty || fin.compareTo(jour) >= 0;
}

/// Le décompte d'une convention : visites PRÉVUES à l'année (convention) contre visites RÉALISÉES depuis le début de l'année [annee] pour l'entreprise.
({int prevues, int realisees, int reste}) mdtDecompteConvention(FicheMdt conv, Iterable<FicheMdt> consultations, int annee) {
  final prevues = (conv['visitesAnnuellesPrevues'] as num?)?.toInt() ?? 0;
  final realisees = [
    for (final c in consultations)
      if (c['statut'] == 'terminee' &&
          c['entrepriseId'] == conv['entrepriseId'] &&
          (c['type'] == 'Médecine du travail' || c['specialite'] == 'medecine-travail') &&
          '${c['date']}'.startsWith('$annee'))
        c
  ].length;
  return (prevues: prevues, realisees: realisees, reste: prevues > realisees ? prevues - realisees : 0);
}
