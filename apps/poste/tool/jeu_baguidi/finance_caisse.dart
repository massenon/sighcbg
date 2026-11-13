// LA VENTE DE PHARMACIE AU COMPTOIR : une facture émise par le MOTEUR D'ÉMISSION (`emettreFacture`, la même décision que l'écran `m8-facturation`), réglée sur le
// champ, avec son écriture d'encaissement (`ecritureEncaissement`, RG-10 contrôlé avant écriture, brouillon). Aucune règle n'est écrite ici.
//
// CE QUE LE MODÈLE PERMET, ET CE QU'IL NE PERMET PAS : le moteur d'émission EXIGE une fiche patient (il lit son identifiant, son nom, sa couverture). La vraie
// fonction « client libre » (un nom saisi librement, sans fiche) n'existe pas encore : l'écran offre seulement l'option « opération détachée du dossier
// patient » (vente au comptoir). Le jeu n'invente donc pas une fiche patient par vente et n'en ajoute pas au répertoire (le sous-lot clinique en porte 120) :
// il passe au moteur UNE identité générique, « Client de comptoir (fictif) », EN MÉMOIRE, avec `dissocier: true`. La pièce naît sans code patient ni identifiant
// de dossier, porte `operationDissociee: true` et le nom générique. La fonction « client libre » reste à construire.
import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'clinique_base.dart' show champsNormalisation;
import 'stock_base.dart';

/// L'identité passée au moteur pour toute vente sans dossier : jamais insérée au répertoire des patients.
const Map<String, Object?> clientComptoir = {
  'id': null,
  'nom': 'Client de comptoir',
  'prenom': '(fictif)',
  'code': null,
  'assureur': null,
};

/// Une ligne de vente : le produit vendu (référence, désignation, prix de vente = prix d'achat, RG-02) et la quantité.
typedef LigneVente = ({String produitId, String designation, String nature, num prixVente, num quantite, num stockDetail});

class ResultatVente {
  const ResultatVente(this.facture, this.sorties);
  final Fiche facture;
  final List<d.SortieStock> sorties;
}

class CaisseComptoir {
  CaisseComptoir(this.a);
  final Atelier a;

  /// L'identifiant MECeF simulé : tiré d'une graine fixe PROPRE à ce sous-lot (loin de celle du sous-lot clinique), jamais de l'horloge.
  int _graineMecef = 70000;

  late final bool mecefActif = d.fermeturesEnVigueur(a.ctx.collection('modulesActifs').toutes).mecefEnService;

  late final Map<String, String> _libelles = {for (final c in a.ctx.fiches('comptes')) '${c['num']}': '${c['libelle']}'};

  /// Écrit les lignes d'écriture rendues par un moteur : identifiant, libellé du compte, brouillon.
  List<Fiche> poserEcritures(List<Map<String, Object?>> lignes, {Fiche complement = const {}}) {
    final posees = <Fiche>[];
    for (final e in lignes) {
      final compte = '${e['compte']}';
      posees.add(a.ajouter(
          'ecritures',
          {
            ...e,
            if (e['compteLibelle'] == null && _libelles[compte] != null) 'compteLibelle': _libelles[compte],
            'statut': 'brouillon',
            ...complement,
          },
          'ECR'));
    }
    return posees;
  }

  /// Contrôle le RG-03 d'une ligne AVANT émission, comme l'écran qui ajoute une prestation : le refus nomme le défaut, RIEN n'est écrit.
  /// Lève [d.RefusEmission].
  Map<String, Object?> ligne(LigneVente l, {num dejaSurLaFacture = 0}) => d.ligneSaisie(
        nature: l.nature,
        designation: l.designation,
        quantite: l.quantite,
        prixUnitaire: l.prixVente,
        produitId: l.produitId,
        stockDetail: l.stockDetail,
        dejaSurLaFacture: dejaSurLaFacture,
      );

  /// Émet et encaisse la vente. Les lignes ont déjà passé [ligne] (RG-03). Rend la pièce écrite et les sorties de stock à journaliser.
  ResultatVente vendre({required DateTime quand, required List<LigneVente> lignes, required String mode}) {
    final jour = jourDe(quand);
    final factures = a.toutes('factures');
    final r = d.emettreFacture(
      patient: {...clientComptoir},
      lignes: [for (final l in lignes) ligne(l)],
      dateRepartition: jour,
      dateFacture: jour,
      type: 'Pharmacie',
      mode: mode,
      rangDebut: d.rangSerieFactures(d.prefixeSerieFacture(proforma: false, dateFacture: jour), factures) - 1,
      // Une vente au comptoir se règle sur le champ, en totalité : le règlement saisi est la part du client.
      reglement: null,
      dissocier: true,
      mecefActif: mecefActif,
      produits: [
        for (final l in lignes) {'id': l.produitId, 'stockDetail': l.stockDetail, 'stock': l.stockDetail},
      ],
    );
    final piece = r.pieces.single;
    final fiche = {...piece}..remove('mecef');
    final ls = (piece['lignes'] as List).cast<Map<String, Object?>>();
    fiche['lignes'] = [
      for (final (i, l) in ls.indexed)
        {
          ...l,
          'id': 'L${pad(i + 1, 3)}',
          'statutPaiement': 'paye',
          'montantRegle': l['partPatient'],
          'payeLe': iso8601(quand),
          'payePar': comptableCaisse,
        }
    ];
    fiche['statut'] = 'actif';
    fiche['dernierReglement'] = {
      'date': iso8601(quand),
      'montant': piece['montantPaye'],
      'mode': mode,
      'lignes': [for (var i = 0; i < ls.length; i++) 'L${pad(i + 1, 3)}'],
      'encaissePar': comptableCaisse,
    };
    if (piece['mecef'] == true) fiche.addAll(champsNormalisation(fiche, d.numeroMecefSimule(++_graineMecef), quand, a.ctx));
    fiche['venteComptoir'] = true;
    fiche['source'] = 'Vente de pharmacie au comptoir, sans dossier patient (client générique fictif)';
    final ins = a.ajouter('factures', fiche, 'FAC');
    // L'encaissement : débit 571 de la part réglée, crédit 706 du total ; équilibré avant d'exister (RG-10), brouillon.
    final ecr = d.ecritureEncaissement(ins, d.nombreOuZero(ins['montantPaye']), jour, a.fiches('ecritures'));
    if (ecr.isEmpty) throw StateError('Écriture d\'encaissement refusée pour ${ins['numero']} (RG-10).');
    poserEcritures(ecr);
    return ResultatVente(ins, r.sorties);
  }
}
