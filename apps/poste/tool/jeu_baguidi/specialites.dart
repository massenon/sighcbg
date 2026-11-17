// SOUS-LOT « SPÉCIALITÉS » (PRD P0-12) : les quatorze fiches de la collection `specialites`, la fiche d'aptitude comme pièce certifiante (type TPC15), les
// conventions de visites de médecine du travail, et le rattachement des consultations de démonstration à leur spécialité.
//
// Il ne CRÉE aucune consultation : le sous-lot clinique a déjà posé 110 visites de médecine du travail et 30 consultations de médecins vacataires
// spécialistes (fictifs). Ce sous-lot ajoute seulement le champ `specialite` à celles qui en relèvent — c'est ce qui les fait paraître au hub, à l'agenda et
// aux statistiques de leur spécialité, et au dossier de leur patient. Les volumes du sous-lot clinique (200 consultations) ne bougent donc pas.
//
// Rien n'est inventé : les conventions sont celles des six entreprises fictives du socle (marquées `fictif: true`, source indiquée) ; aucun praticien n'est
// rattaché d'office à une spécialité (la fiche le dit : tous les médecins de la clinique peuvent consulter).
import 'package:sigh_domaine/sigh_domaine.dart';

import 'contexte.dart';

void generer(Contexte ctx) {
  final fiches = specFichesDeBase();
  for (final f in fiches) {
    ctx.ajouter('specialites', f);
  }

  // La fiche d'aptitude : pièce certifiante TPC15, tarifée par la grille MT-FAP.
  ctx.ajouter('typesPiece', {
    'id': mdtTypePiece.id,
    'sigle': mdtTypePiece.sigle,
    'libelle': mdtTypePiece.libelle,
    'direction': mdtTypePiece.direction,
    'tarifCode': mdtTypePiece.tarifCode,
    'statut': 'actif',
  });

  // Une convention de visites par entreprise cliente (les six du socle).
  var n = 0;
  for (final e in ctx.fiches('souscripteurs')) {
    if (e['categorie'] != 'entreprise') continue;
    n++;
    ctx.ajouter('conventionsVisites', {
      'id': 'CNV${n.toString().padLeft(3, '0')}',
      'statut': 'actif',
      'entrepriseId': e['id'],
      'entreprise': e['nom'],
      'dateDebut': e['dateDebut'] ?? '2026-08-01',
      'periodiciteMois': mdtPeriodiciteDefaut,
      'visitesAnnuellesPrevues': (e['effectif'] as num?)?.toInt() ?? 0,
      'observations': 'Convention fictive de démonstration : visites d’embauche, périodiques et de reprise de tout le personnel de l’entreprise.',
      'fictif': true,
      'source': 'Convention fictive de démonstration (médecine du travail)',
    });
  }

  // Le rattachement des consultations à leur spécialité : médecine du travail par le type de la visite, les autres par la spécialité du vacataire.
  final parSpecialite = {for (final p in ctx.fiches('prestataires')) '${p['nom']}': '${p['specialite'] ?? ''}'};
  final parLibelle = {for (final f in fiches) '${f['libelle']}': f};
  var rattachees = 0;
  ctx.remplacer('consultations', [
    for (final c in ctx.collection('consultations').toutes)
      () {
        final Map<String, Object?>? f = c['type'] == specTypeMedecineTravail
            ? fiches.firstWhere((x) => x['code'] == specCodeMedecineTravail)
            : parLibelle[parSpecialite['${c['medecin']}']];
        if (f == null) return c;
        rattachees++;
        return {...c, 'specialite': f['code'], 'specialiteLibelle': f['libelle']};
      }()
  ]);
  ctx.note('spécialités : ${fiches.length} fiches, $n conventions de visites, $rattachees consultations rattachées à leur spécialité');
}
