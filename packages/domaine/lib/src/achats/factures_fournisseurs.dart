/// Factures fournisseurs (M7) — `m7-factures-fournisseurs`. Règles rejouées sur `test/vecteurs/factures_fournisseurs.json` (écran piloté dans la
/// maquette, `build/vecteurs-m7-achats.js`, et `SIGH.bfr.calculer()` pour le poids sur le BFR).
///
/// « payée » et NON « soldée » : le registre, son filtre, son indicateur « Impayées » et la dette du BFR comptent sur `payee` (la fiche
/// proposait « soldée » à l'édition : une pièce éditée reparaissait dans les impayées — corrigé le 22/09/2026).
library;

import '../format/js.dart';
import 'fournisseurs_m7.dart' show FormulaireInvalide;

typedef FicheFacture = Map<String, Object?>;

const reglementPayee = 'payee';
const reglementPartielle = 'partielle';
const reglementImpayee = 'impayee';

/// Libellé et ton du badge de règlement (`succes`, `attention`, `danger`). Un statut hors de ces trois (« soldee », pièce de génération
/// antérieure) fait ÉCHOUER le rendu du tableau dans la maquette (écart E21) : ici, le statut est affiché tel quel.
const reglementsFournisseur = <String, (String, String)>{
  reglementPayee: ('Payée', 'succes'),
  reglementPartielle: ('Partielle', 'attention'),
  reglementImpayee: ('Impayée', 'danger'),
};

double _n(Object? v) => nombreOuZero(v);

/// LA définition de la dette fournisseur (décision de la Direction, Q13 du 15/11/2026) : la plus PRUDENTE — une pièce reste due tant qu'elle n'est ni `payee` NI `soldee`
/// (« payée » et « soldée » désignent la même chose selon l'écran par lequel la pièce est passée). Une seule définition, lue par TOUS : l'écran des factures fournisseurs,
/// le BFR, les tableaux de pilotage, l'assistant. Une pièce partiellement réglée compte pour son montant facturé entier.
const List<String> statutsDetteFournisseurSoldee = ['payee', 'soldee'];

/// MARQUAGE « à valider » : la Direction a arrêté la définition ; le Comptable doit encore la confirmer. Affiché partout où la dette est montrée.
const String detteFournisseurAValider =
    'Définition de la dette fournisseur : toute facture ni payée ni soldée, pour son montant facturé entier (la plus prudente). À valider par le Comptable.';

/// La pièce [r] pèse-t-elle encore sur la dette fournisseur ?
bool detteFournisseurOuverte(Map<String, Object?> r) => !statutsDetteFournisseurSoldee.contains('${r['statutPaiement'] ?? ''}');

/// Les quatre indicateurs de l'écran. « Impayées » somme le MONTANT FACTURÉ de toute pièce qui n'est pas `payee` — une pièce partiellement
/// réglée compte donc pour son montant entier.
class KpisFacturesFournisseurs {
  const KpisFacturesFournisseurs(
      {required this.total,
      required this.rapprochees,
      required this.anomalies,
      required this.impayees});
  final int total, rapprochees, anomalies;
  final double impayees;
}

KpisFacturesFournisseurs kpisFacturesFournisseurs(Iterable<FicheFacture> rows) {
  final l = rows.toList();
  return KpisFacturesFournisseurs(
    total: l.length,
    rapprochees: l.where((r) => r['statutRappro'] == 'rapproche').length,
    anomalies: l.where((r) => r['statutRappro'] == 'anomalie').length,
    impayees: l
        .where(detteFournisseurOuverte)
        .fold<double>(0, (a, r) => a + _n(r['montantFacture'])),
  );
}

/// Le bandeau d'alerte (absent sans anomalie). Texte brut de la maquette, balises retirées.
String? noteAnomalies(Iterable<FicheFacture> rows) {
  final n = rows.where((r) => r['statutRappro'] == 'anomalie').length;
  if (n == 0) return null;
  return '$n anomalie(s) de rapprochement détectée(s) : le montant facturé diffère du montant livré. Vérification requise avant règlement.';
}

/// Les dettes fournisseurs (BFR, écran, assistant) : montant facturé de toute pièce ni `payee` NI `soldee` — UNE définition depuis la décision Q13 (l'écran ne retirait que
/// `payee` : sur une pièce « soldee » les deux divergeaient, écart E21 ; E3140 les aligne).
double detteFournisseurs(Iterable<FicheFacture> rows) => rows
    .where(detteFournisseurOuverte)
    .fold<double>(0, (a, r) => a + _n(r['montantFacture']));

int nbDettesFournisseurs(Iterable<FicheFacture> rows) => rows.where(detteFournisseurOuverte).length;

/// Un écart nul se lit « Conforme » ; sinon le montant signé (`+` explicite au-dessus de zéro).
bool ecartConforme(FicheFacture r) => _n(r['ecart']) == 0;

/// Ce que « Modifier » écrit. Les noms de champs du formulaire de la maquette ne sont PAS ceux de la fiche (`numero` et `montant` au lieu de
/// `numeroFournisseur` et `montantFacture`) : ni le N° fournisseur ni le montant affichés ne changent, l'écart n'est pas recalculé, et le
/// formulaire OBLIGE à ressaisir un `numero` que la fiche ne porte pas. Écart E21 — porté fidèlement, à arbitrer.
///
/// [saisie] : `numero`, `date`, `fournisseur` (obligatoires), `montant` (nombre ou vide), `echeance`, `statutPaiement`.
FicheFacture patchEditionFacture(Map<String, Object?> saisie) {
  final manquants = [
    for (final k in const ['numero', 'date', 'fournisseur'])
      if ('${saisie[k] ?? ''}'.isEmpty) k
  ];
  if (manquants.isNotEmpty) throw FormulaireInvalide(manquants);
  return {
    'numero': saisie['numero'],
    'date': saisie['date'],
    'fournisseur': saisie['fournisseur'],
    'montant': num.tryParse('${saisie['montant'] ?? ''}'),
    'echeance': saisie['echeance'] ?? '',
    'statutPaiement': saisie['statutPaiement'] ?? '',
  };
}
