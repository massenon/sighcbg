import '../format/format_fr.dart' show nombre;
import 'cfb_regles.dart' show cfbLibelleCollection;

/// L'ARCHIVAGE DU JEU DE DÉMONSTRATION (décision D6 de la Direction, 09/11/2026 : « remise du jeu de démonstration : les ARCHIVER, les brouillons, etc. »).
///
/// RG-14 : suppression logique uniquement. Le geste par défaut de mise en production n'efface donc plus rien : chaque fiche ACTIVE d'une collection d'activité
/// passe à l'état archivé (`statut: 'archive'`, ancien statut gardé dans `statutAvantArchivage`), avec son motif, son acteur et sa date. Les fiches restent
/// consultables et restaurables depuis la Corbeille. Les brouillons sont archivés comme les autres : jamais validés au passage.
///
/// Ce fichier ne porte que les RÈGLES pures (motif, marques, brouillon, bilan, remise des échéances). Le geste vit côté poste (`cfbArchiverJeuDemo`).

/// Le motif porté par chaque fiche archivée par ce geste.
const cfbMotifArchivageJeuDemo = 'Jeu de démonstration, mise en production';

/// Le refus NOMMÉ d'un archivage : la bascule fermée, ou le motif manquant. `null` : le geste peut partir. Un refus muet ferait croire à une panne.
String? cfbRefusArchivage({required bool autorisee, required String motif}) {
  if (!autorisee) return 'Réinitialisation verrouillée : autoriser d’abord la réinitialisation des jeux de test, à l’onglet « Jeux de test ».';
  if (motif.trim().isEmpty) return 'Motif obligatoire : dire pourquoi le jeu de démonstration est archivé (journalisé, RG-12).';
  return null;
}

/// Le refus levé par le geste lui-même (le bouton ne protège rien tout seul).
class CfbRefusArchivage implements Exception {
  const CfbRefusArchivage(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

/// Les champs qui, valant `brouillon`, disent qu'une fiche n'a pas été validée : le statut des écritures et des comptes rendus, l'état d'un inventaire.
const cfbChampsBrouillon = <String>['statut', 'statutInv', 'etat'];

/// Vrai si la fiche est un BROUILLON : une pièce que personne n'a validée. Le bilan les compte à part, parce que c'est ce qu'on craint de voir validé au passage.
bool cfbEstBrouillon(Map<String, Object?> fiche) => cfbChampsBrouillon.any((c) => fiche[c] == 'brouillon');

/// Les marques d'archivage que le poste lit déjà (`cfbInfosArchivage`, fiche patient) : date, auteur, motif. Le STATUT, lui, est posé par la collection.
Map<String, Object?> cfbMarquesArchivage({required String motif, required String par, required DateTime le}) => {
      '_archiveLe': le.toIso8601String(),
      '_archivePar': par,
      '_motifArchivage': motif,
    };

/// Les champs de PAIEMENT d'une échéance fiscale : ce que la remise à « non payée » retire de la fiche.
const cfbChampsPaiementEcheance = <String>['paye', 'datePaiement', 'montant', 'moyen', 'reference', 'valideePar', 'observation'];

/// Une échéance qui porte un paiement de démonstration.
bool cfbEcheanceAPaiement(Map<String, Object?> f) => f['paye'] == true || f['datePaiement'] != null || f['reference'] != null;

/// LA REMISE D'UNE ÉCHÉANCE FISCALE À « NON PAYÉE » (décision de la Direction, 09/11/2026) : le paiement porté par le jeu de démonstration est une donnée
/// FICTIVE, pas une pièce comptable. Il est donc SUPPRIMÉ — champs de règlement remis à vide, `paiementsArchives` (trace des anciens archivages) retirée —
/// et n'est rangé nulle part ; le calendrier, dérivé d'un document, reste en service. Rend la fiche remise et le nombre de paiements fictifs retirés (celui de
/// la fiche, plus ceux d'une ancienne trace), ou `null` si l'échéance ne porte aucun paiement.
({Map<String, Object?> fiche, int retires})? cfbRetirerPaiementDemo(Map<String, Object?> f) {
  final anciens = (f['paiementsArchives'] as List?)?.length ?? 0;
  final porte = cfbEcheanceAPaiement(f);
  if (!porte && anciens == 0) return null;
  final fiche = {...f}..remove('paiementsArchives');
  if (porte) {
    for (final c in cfbChampsPaiementEcheance) {
      fiche.remove(c);
    }
    fiche['paye'] = false;
  }
  return (fiche: fiche, retires: (porte ? 1 : 0) + anciens);
}

/// Le bilan d'un archivage : par collection, le nombre de fiches archivées et, à part, celui des brouillons ; les paiements fictifs d'échéances retirés.
class CfbBilanArchivage {
  const CfbBilanArchivage({required this.parCollection, required this.brouillons, this.paiementsRetires = 0, this.motif = cfbMotifArchivageJeuDemo});
  final Map<String, int> parCollection;
  final Map<String, int> brouillons;
  final int paiementsRetires;
  final String motif;

  /// Les collections réellement touchées.
  List<String> get collections => [for (final e in parCollection.entries) if (e.value > 0) e.key];
  int get tables => collections.length;
  int get total => parCollection.values.fold(0, (a, b) => a + b);
  int get totalBrouillons => brouillons.values.fold(0, (a, b) => a + b);
}

/// « 83 table(s) archivée(s) — 9 520 fiches archivées, dont 648 brouillon(s). Aucune fiche n’est supprimée : tout se restaure depuis la Corbeille. »
/// Quand des paiements fictifs d'échéances ont été retirés, la phrase le DIT (c'est la seule suppression du geste).
String cfbToastArchivage(CfbBilanArchivage b) =>
    '${b.tables} table(s) archivée(s) — ${nombre(b.total)} fiches archivées, dont ${nombre(b.totalBrouillons)} brouillon(s). Aucune fiche n’est supprimée : tout se restaure depuis la Corbeille.'
    '${b.paiementsRetires > 0 ? ' ${nombre(b.paiementsRetires)} paiement(s) fictif(s) d’échéances fiscales supprimé(s) (donnée de démonstration, non rangée).' : ''}';

/// Le détail du bilan, une ligne par collection (nom, archivées, dont brouillons), de la plus fournie à la moins fournie.
List<String> cfbLignesBilanArchivage(CfbBilanArchivage b) {
  final noms = b.collections..sort((x, y) => b.parCollection[y]!.compareTo(b.parCollection[x]!) != 0 ? b.parCollection[y]!.compareTo(b.parCollection[x]!) : x.compareTo(y));
  return [
    for (final n in noms) '${cfbLibelleCollection(n).$2} : ${nombre(b.parCollection[n]!)} archivée(s)${(b.brouillons[n] ?? 0) > 0 ? ', dont ${nombre(b.brouillons[n]!)} brouillon(s)' : ''}',
  ];
}

/// Le message que la collection porte au journal (RG-12), une entrée par collection touchée.
Map<String, Object?> cfbApresArchivageCollection(int archivees, int brouillons, String motif) => {'archivees': archivees, 'brouillons': brouillons, 'motif': motif};
