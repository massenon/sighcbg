// LA COMPTABILITÉ DU SOUS-LOT : pièces d'achat et de règlement fournisseur, 30 dépenses multi-lignes, validation des pièces d'août et de septembre,
// échéances fiscales de l'exercice 2026, règlements et relances des créances d'assureurs. RIEN n'est calculé ici : chaque écriture sort d'un moteur de
// `packages/domaine` (`cpaEcrituresDeSaisie`, `cpaEcrituresDepense`, `cpaValiderPiece`, `cfbGenEcheances`, `assReglerMere`), équilibrée par construction (RG-10),
// en brouillon ; la validation est un geste humain, rejoué ici pour août et septembre seulement.
//
// CE QUI RESTE VOLONTAIREMENT VIDE, AVEC SON MOTIF :
//  - `immobilisations` : aucun document de Baguidi ne donne la valeur ni la date d'acquisition d'un bien ; en inventer une ferait amortir au bilan un montant que
//    personne n'a arrêté. Le registre s'ouvre à la première acquisition réelle.
//  - `rapprochements`, `banques` (hors la caisse) : aucun compte bancaire n'a été remis, et le jeu n'invente pas un numéro de compte.
//  - `exercices` : l'exercice 2026 est ouvert SANS bilan d'ouverture ni liasse (aucune pièce du journal AN, aucune clôture) ; les écrans le disent.
//  - arrêtés de caisse : le modèle du poste n'a ni collection ni moteur pour les persister (l'état de caisse s'imprime à la demande depuis les factures du jour,
//    voir `m8-caisse`) ; il n'y a donc rien à écrire, ni jour « non arrêté » à représenter.
import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'contexte.dart';
import 'finance_caisse.dart';
import 'stock_base.dart';

class Comptabilite {
  Comptabilite(this.a, this.caisse);
  final Atelier a;
  final CaisseComptoir caisse;

  /// Les mois dont les pièces sont validées : août et septembre. Octobre et novembre restent en brouillon.
  static const List<String> moisValides = ['2026-08', '2026-09'];

  late final Map<String, String> _libelles = {for (final c in a.ctx.fiches('comptes')) '${c['num']}': '${c['libelle']}'};

  List<Fiche> _poser(List<Fiche> lignes, Fiche complement) {
    final out = <Fiche>[];
    for (final l in lignes) {
      final compte = '${l['compte']}';
      out.add(a.ajouter(
          'ecritures',
          {
            ...l,
            if (_libelles[compte] != null) 'compteLibelle': _libelles[compte],
            ...complement,
          },
          'ECR'));
    }
    return out;
  }

  // --- achats --------------------------------------------------------------------------------------------------------------------------------

  /// La facture d'un fournisseur au journal des achats : débit 601100 (achats de marchandises), crédit 401000 (fournisseurs) : les comptes de l'automatisation
  /// documentée « Réception d'une commande » (`cpaAutomatisations`). Brouillon. Rend les identifiants des lignes.
  List<Object?> poserFactureAchat(Fiche ff, String centre) {
    final m = d.nombreOuZero(ff['montantFacture']);
    final lignes = d.cpaEcrituresDeSaisie(
      date: '${ff['date']}',
      journal: 'ACH',
      libelle: 'Facture fournisseur ${ff['reference']} : ${ff['fournisseurNom']}',
      centreCout: centre,
      piece: '${ff['reference']}',
      lignes: [
        {'compte': '601100', 'debit': m, 'credit': 0},
        {'compte': '401000', 'debit': 0, 'credit': m},
      ],
      statut: 'brouillon',
      exercice: 2026,
      toutes: a.toutes('ecritures'),
    );
    d.cpaControlerEquilibre(lignes);
    final posees = _poser(lignes, {'pieceId': ff['id'], 'pieceNumero': ff['reference'], 'saisiPar': comptableStock});
    return [for (final p in posees) p['id']];
  }

  /// Le règlement d'une facture fournisseur : débit 401000, crédit 521000 (journal de banque, comme le règlement d'une facture mère). Brouillon.
  List<Object?> poserReglementFournisseur(Fiche ff, String date) {
    final m = d.nombreOuZero(ff['montantFacture']);
    final lignes = d.cpaEcrituresDeSaisie(
      date: date,
      journal: 'BQ',
      libelle: 'Règlement facture fournisseur ${ff['reference']} : ${ff['fournisseurNom']}',
      centreCout: 'direction',
      piece: '${ff['reference']}',
      lignes: [
        {'compte': '401000', 'debit': m, 'credit': 0},
        {'compte': '521000', 'debit': 0, 'credit': m},
      ],
      statut: 'brouillon',
      exercice: 2026,
      toutes: a.toutes('ecritures'),
    );
    d.cpaControlerEquilibre(lignes);
    final posees = _poser(lignes, {'pieceId': ff['id'], 'pieceNumero': ff['reference'], 'saisiPar': comptableCaisse});
    return [for (final p in posees) p['id']];
  }

  // --- dépenses ------------------------------------------------------------------------------------------------------------------------------

  /// Les lignes de dépense possibles : (libellé, compte de charge du plan de la clinique, plancher, plafond). Libellés génériques, aucun nom de société.
  static const Map<String, List<(String, String, int, int)>> _lignes = {
    'fonctionnement': [
      ('Papier et fournitures de bureau', '604700', 5000, 45000),
      ('Facture d’eau', '605100', 8000, 30000),
      ('Facture d’électricité', '605200', 45000, 160000),
      ('Carburant du groupe électrogène', '604200', 20000, 80000),
      ('Frais de téléphone et d’internet', '628100', 10000, 40000),
    ],
    'entretien': [
      ('Entretien des climatiseurs', '624200', 15000, 60000),
      ('Petite réparation de plomberie', '624100', 5000, 35000),
      ('Maintenance du matériel', '624300', 10000, 50000),
    ],
    'logistique': [
      ('Transport de marchandises', '616000', 5000, 30000),
      ('Déplacement pour approvisionnement', '618100', 5000, 25000),
    ],
    'medical': [
      ('Consommables achetés en dépannage', '604100', 10000, 60000),
    ],
    'personnel': [
      ('Prestation de nettoyage', '637100', 15000, 50000),
    ],
    'fiscal': [
      ('Droits de timbre', '646210', 1000, 8000),
      ('Frais bancaires', '631810', 2000, 12000),
      ('Patente et taxes annexes', '641200', 10000, 40000),
    ],
    'divers': [
      ('Fournitures diverses', '605000', 3000, 20000),
    ],
  };

  /// Trente dépenses de trésorerie directe (par la caisse), chacune de 2 à 4 lignes de libellés, dont quatre SANS justificatif (comptées et signalées).
  /// Une écriture plate par ligne et un crédit de trésorerie du total (`cpaEcrituresDepense`, RG-10 contrôlé avant écriture), brouillon.
  void depenses() {
    final t = a.t;
    final jours = a.ctx.joursOuvres();
    final dates = t.melanger(jours).take(30).toList()..sort((x, y) => x.compareTo(y));
    final sansRecu = {for (final i in t.melanger([for (var i = 0; i < 30; i++) i]).take(4)) i};
    final banque = a.ctx.fiches('banques').firstWhere((b) => b['id'] == 'BQ00');
    for (var i = 0; i < dates.length; i++) {
      final cat = t.pondere({'fonctionnement': 8, 'entretien': 5, 'logistique': 4, 'fiscal': 4, 'medical': 3, 'personnel': 3, 'divers': 3});
      final n = t.entre(2, 4);
      // Les lignes de SA catégorie d'abord ; si elle n'en a pas assez pour faire une pièce à plusieurs libellés, on complète par le fonctionnement courant.
      final propres = t.melanger(_lignes[cat]!);
      final choisies = propres.take(n).toList();
      if (choisies.length < n) {
        final complement = t.melanger([for (final l in _lignes['fonctionnement']!) if (!choisies.contains(l)) l]);
        choisies.addAll(complement.take(n - choisies.length));
      }
      final lignes = [
        for (final (libelle, compte, lo, hi) in choisies)
          {'libelle': libelle, 'compteCharge': compte, 'montant': (t.entre(lo, hi) / 50).round() * 50},
      ];
      final tot = d.cpaTotauxDepense('', lignes);
      final jour = Contexte.date(dates[i]);
      final saisiPar = i.isEven ? comptableCaisse : comptableStock;
      final dep = a.ajouter(
          'depenses',
          {
            'reference': d.cpaReferenceDepense(jour, a.toutes('depenses')),
            'date': jour,
            'lignes': tot.lignes,
            'montant': tot.montant,
            'libelle': tot.libelle,
            'compteCharge': tot.compteCharge,
            'compteTresorerie': 'BQ00',
            'categorie': cat,
            if (!sansRecu.contains(i)) 'justificatif': {'nom': 'recu-DEP-2026-${pad(i + 1, 4)}.jpg', 'type': 'image/jpeg'},
            'saisiPar': saisiPar,
            'saisiLe': jour,
            'fictif': true,
            'source': 'Dépense fictive de démonstration : libellés et montants d’attente',
          },
          'DEP',
          largeur: 4);
      final lignesEcr = d.cpaEcrituresDepense(dep, banque);
      final posees = _poser(lignesEcr, {'saisiPar': saisiPar});
      a.maj('depenses', dep['id'], {'ecritureId': posees.first['id'], 'ecritureIds': [for (final p in posees) p['id']]});
    }
  }

  // --- validation ----------------------------------------------------------------------------------------------------------------------------

  /// Valide TOUTES les pièces d'août et de septembre (celles de la clinique, de la paie, des achats, des ventes, des dépenses, des règlements) ; octobre et
  /// novembre restent en brouillon. Une PIÈCE est l'ensemble des lignes de même numéro : elle se valide entière, RG-10 contrôlé sur l'ensemble AVANT
  /// (`cpaValiderPiece`). Son mois est celui de sa première ligne (un règlement partiel d'octobre ne dépiece pas une facture de septembre). La validation est
  /// posée par un comptable DIFFÉRENT de celui qui a saisi la pièce (séparation des tâches), le 5 du mois suivant. Rend le nombre de pièces validées.
  int validerAoutSeptembre() {
    var nb = 0;
    final vus = <String>{};
    for (final ligne in [...a.fiches('ecritures')]) {
      final numero = '${ligne['numero']}';
      if (!vus.add(numero)) continue;
      final piece = d.cpaPiece(a.fiches('ecritures'), numero);
      final debut = piece.map((l) => '${l['date']}').reduce((x, y) => x.compareTo(y) <= 0 ? x : y);
      if (!moisValides.contains(debut.substring(0, 7))) continue;
      final lignes = d.cpaValiderPiece(a.fiches('ecritures'), piece.firstWhere((l) => l['statut'] == 'brouillon'));
      final auteur = '${piece.first['saisiPar'] ?? (piece.first['origine'].toString().contains('Caisse') ? comptableCaisse : '')}';
      final valideur = auteur == comptableStock ? comptableCaisse : comptableStock;
      final mois = int.parse(debut.substring(5, 7));
      final valideLe = '2026-${pad(mois + 1, 2)}-05';
      for (final l in lignes) {
        a.maj('ecritures', l['id'], {'statut': 'validee', 'validePar': valideur, 'valideLe': valideLe});
      }
      nb++;
    }
    return nb;
  }

  // --- échéances fiscales --------------------------------------------------------------------------------------------------------------------

  /// L'exercice 2026 déroulé par le moteur depuis le calendrier du socle (CNSS au 15) : payées jusqu'aux déclarations de septembre (échues le 10 et le 12
  /// octobre), à l'exception d'UNE, la CNSS de septembre échue le 15 octobre, volontairement dépassée pour que l'alarme ait quelque chose à montrer. Les
  /// quittances ne portent AUCUN montant (aucun document ne donne les bases).
  void echeances() {
    final obligations = [for (final o in a.fiches('obligationsFiscales')) if (o['type'] == 'obligation') o];
    final gen = d.cfbGenEcheances(2026, obligationsFixes: obligations, aujourdhui: Contexte.maintenant, sansReglement: true);
    var i = 0;
    for (final e in gen) {
      final due = '${e['echeance']}';
      final enRetard = e['code'] == 'CNSS' && due == '2026-10-15';
      final payee = due.compareTo('2026-10-15') <= 0 && !enRetard;
      a.ajouter(
          'echeancesFiscales',
          {
            ...e,
            if (payee) ...{
              'paye': true,
              'datePaiement': due,
              'moyen': 'Virement bancaire',
              'reference': 'QUIT-${e['code']}-${due.substring(0, 7)}',
              'valideePar': (i++).isEven ? comptableStock : comptableCaisse,
            },
            'source': 'Calendrier de l’exercice 2026 (CNSS au 15) ; règlements de démonstration, montants non renseignés',
          },
          'ECH',
          largeur: 4);
    }
  }

  // --- créances d'assureurs --------------------------------------------------------------------------------------------------------------------

  /// Les créances des assureurs sont les factures mères du sous-lot clinique (une par compagnie et par mois) : leur RÈGLEMENT passe par `assReglerMere` (une
  /// écriture de banque par règlement, brouillon, la ligne de règlement portée par la mère), leur RELANCE par une fiche `relances`. La suite de l'histoire :
  ///  - août, SUNU : réglée en totalité le 28/09 ; SANLAM : réglée à 60 % le 14/10, le reste est en retard ; NSIA : rien reçu, en retard (63 jours) ;
  ///  - septembre, SUNU : réglée en totalité le 04/11 ; NSIA et SANLAM en cours ; octobre : tout en cours.
  /// Trois relances aux deux compagnies en retard (niveau croissant), « en attente ».
  void creances() {
    final meres = a.fiches('facturesMere');
    Fiche mere(String code, String debut) => meres.firstWhere((m) => m['compagnieCode'] == code && m['debut'] == debut);

    void regler(Fiche m, String date, double part, String reference) {
      final montant = (d.nombreOuZero(m['montantReclame']) * part).roundToDouble();
      final res = d.assReglerMere(m,
          date: date, montant: montant, reference: reference, ecritures: a.toutes('ecritures'), utilisateur: comptableCaisse, horodatage: '${date}T09:00:00.000Z');
      final ids = <Object?>[];
      for (final e in res.ecritures) {
        ids.add(a.ajouter('ecritures', {...e, 'statut': 'brouillon', 'saisiPar': comptableCaisse}, 'ECR')['id']);
      }
      final reglements = [
        for (final x in (res.patch['reglements'] as List))
          if ((x as Map)['id'] == res.reglement['id']) {...x.cast<String, Object?>(), 'ecritureIds': ids} else x.cast<String, Object?>()
      ];
      a.maj('facturesMere', m['id'], {...res.patch, 'reglements': reglements});
    }

    regler(mere('SUNU', '2026-08-01'), '2026-09-28', 1, 'Virement SUNU, facture mère août 2026');
    regler(mere('SANLAM', '2026-08-01'), '2026-10-14', 0.6, 'Virement SANLAM, acompte sur facture mère août 2026');
    regler(mere('SUNU', '2026-09-01'), '2026-11-04', 1, 'Virement SUNU, facture mère septembre 2026');

    final assureurs = {for (final x in a.fiches('assureurs')) x['code']: x};
    void relance(String code, String periode, String date, String niveau, String canal, double montant, String observations) {
      a.ajouter(
          'relances',
          {
            'assureur': code,
            'assureurNom': '${assureurs[code]!['nom']}',
            'date': date,
            'periode': periode,
            'montant': montant,
            'niveau': niveau,
            'canal': canal,
            'observations': observations,
            'reference': d.assReferenceRelance(a.toutes('relances')),
            'statutRelance': 'en_attente',
            'fictif': true,
            'source': sourceDemo,
          },
          'REL',
          largeur: 4);
    }

    final nsia = a.parId('facturesMere', mere('NSIA', '2026-08-01')['id'])!;
    final sanlam = a.parId('facturesMere', mere('SANLAM', '2026-08-01')['id'])!;
    relance('NSIA', 'Août 2026', '2026-10-20', '1re relance', 'Courrier électronique', d.assResteDuMere(nsia), 'Facture mère émise le 05/09/2026, aucun règlement reçu.');
    relance('SANLAM', 'Août 2026', '2026-11-02', '1re relance', 'Courrier remis en main propre', d.assResteDuMere(sanlam), 'Acompte reçu le 14/10/2026 ; le solde reste dû.');
    relance('NSIA', 'Août 2026', '2026-11-04', '2e relance', 'Courrier recommandé', d.assResteDuMere(nsia), 'Sans réponse à la première relance du 20/10/2026.');
  }
}
