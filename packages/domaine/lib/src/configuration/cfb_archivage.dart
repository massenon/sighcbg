import '../format/format_fr.dart' show nombre;

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

/// La remise d'une échéance fiscale à « non payée » SANS perdre la trace : la fiche (le calendrier, dérivé d'un document, reste en service) repart sans
/// règlement ; le paiement de démonstration qu'elle portait est rangé, avec son motif, son acteur et sa date, dans `paiementsArchives`. Une échéance sans
/// paiement n'est pas touchée (rend `null`).
Map<String, Object?>? cfbRemettreEcheance(Map<String, Object?> f, {required String motif, required String par, required DateTime le}) {
  if (!cfbEcheanceAPaiement(f)) return null;
  final trace = <String, Object?>{
    for (final c in cfbChampsPaiementEcheance)
      if (f[c] != null) c: f[c],
    ...cfbMarquesArchivage(motif: motif, par: par, le: le),
    'statut': 'archive',
  };
  return {
    ...f,
    'paye': false,
    'datePaiement': null,
    'montant': null,
    'moyen': null,
    'reference': null,
    'valideePar': null,
    'paiementsArchives': [...((f['paiementsArchives'] as List?) ?? const []), trace],
  };
}

/// Le bilan d'un archivage : par collection, le nombre de fiches archivées et, à part, celui des brouillons ; les échéances remises à « non payée ».
class CfbBilanArchivage {
  const CfbBilanArchivage({required this.parCollection, required this.brouillons, this.echeancesRemises = 0, this.motif = cfbMotifArchivageJeuDemo});
  final Map<String, int> parCollection;
  final Map<String, int> brouillons;
  final int echeancesRemises;
  final String motif;

  /// Les collections réellement touchées.
  List<String> get collections => [for (final e in parCollection.entries) if (e.value > 0) e.key];
  int get tables => collections.length;
  int get total => parCollection.values.fold(0, (a, b) => a + b);
  int get totalBrouillons => brouillons.values.fold(0, (a, b) => a + b);
}

/// « 83 table(s) archivée(s) — 9 520 fiches archivées, dont 648 brouillon(s). Rien n’est supprimé : tout se restaure depuis la Corbeille. »
String cfbToastArchivage(CfbBilanArchivage b) =>
    '${b.tables} table(s) archivée(s) — ${nombre(b.total)} fiches archivées, dont ${nombre(b.totalBrouillons)} brouillon(s). Rien n’est supprimé : tout se restaure depuis la Corbeille.';

/// Le détail du bilan, une ligne par collection (nom, archivées, dont brouillons), de la plus fournie à la moins fournie.
List<String> cfbLignesBilanArchivage(CfbBilanArchivage b) {
  final noms = b.collections..sort((x, y) => b.parCollection[y]!.compareTo(b.parCollection[x]!) != 0 ? b.parCollection[y]!.compareTo(b.parCollection[x]!) : x.compareTo(y));
  return [
    for (final n in noms) '$n : ${nombre(b.parCollection[n]!)} archivée(s)${(b.brouillons[n] ?? 0) > 0 ? ', dont ${nombre(b.brouillons[n]!)} brouillon(s)' : ''}',
  ];
}

/// Le message que la collection porte au journal (RG-12), une entrée par collection touchée.
Map<String, Object?> cfbApresArchivageCollection(int archivees, int brouillons, String motif) => {'archivees': archivees, 'brouillons': brouillons, 'motif': motif};
