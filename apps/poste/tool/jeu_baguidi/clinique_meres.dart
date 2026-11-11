// LES FACTURES MÈRES DU MOIS : chaque compagnie reçoit, au début du mois suivant, UNE pièce qui consolide ses souscripteurs (les six entreprises sont
// facturées au mois sur leurs salariés visités). Le moteur de rapprochement du domaine contrôle que trois totaux coïncident (souscripteurs, factures patients,
// détail ligne à ligne) : l'émission est refusée tant qu'ils divergent. Une facture mère n'est émise que pour un mois COMPLET.
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'clinique_base.dart';
import 'contexte.dart';

/// Planifie l'émission des factures mères d'août, de septembre et d'octobre, le 5 du mois suivant.
void planifierMeres(Jeu j) {
  const compagnies = [('NSIA', 'NSIA ASSURANCE'), ('SUNU', 'SUNU ASSURANCE'), ('SANLAM', 'SANLAM ASSURANCE')];
  for (final (mois, jourEmission) in [(8, DateTime.utc(2026, 9, 5, 15)), (9, DateTime.utc(2026, 10, 5, 15)), (10, DateTime.utc(2026, 11, 5, 15))]) {
    j.planifier(jourEmission, () {
      final debut = DateTime.utc(2026, mois, 1);
      final fin = DateTime.utc(2026, mois + 1, 1);
      final depuis = Contexte.date(debut);
      final duMois = [
        for (final f in j.ctx.collection('factures').actives)
          if ('${f['date']}'.compareTo(depuis) >= 0 && '${f['date']}'.compareTo(Contexte.date(fin)) < 0) f
      ];
      for (final (code, nom) in compagnies) {
        final filles = d.assFillesMere(duMois, code, nom, depuis);
        if (filles.isEmpty) continue;
        final rap = d.assRapprocher(filles);
        if (!rap.concorde) throw StateError('Facture mère $code $depuis : les trois totaux divergent : ${rap.ecarts}');
        final fiche = d.assEmettreMere(
          code: code,
          nom: nom,
          periode: 'mois',
          filles: filles,
          rap: rap,
          depuis: depuis,
          auj: j.horloge,
          nbExistantes: j.ctx.collection('facturesMere').toutes.length,
          emisePar: caissierDuJeu,
        );
        j.ajouter('facturesMere', {...fiche, 'fin': Contexte.date(fin.subtract(const Duration(days: 1)))}, 'FMR');
      }
    });
  }
}
