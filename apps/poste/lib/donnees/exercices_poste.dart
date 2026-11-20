import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// L'AMORÇAGE DES EXERCICES (au SOCLE, défaut PTA du 17/11/2026) : une fiche par année portée par le journal, l'horloge et la liasse déposée. La collection est lue par PLUSIEURS écrans (sélecteur de la
/// barre supérieure, plan de travail annuel, clôture, états financiers, paie, alertes) : l'amorcer depuis un seul écran laissait un poste neuf sans exercice, donc sans sélecteur, tant que cet écran
/// n'avait pas été ouvert. Le poste l'appelle au démarrage (`main.dart`), les écrans l'appellent encore (idempotent : une année déjà présente n'est jamais réinsérée ; les identifiants `EXO-AAAA` sont
/// déterministes, deux postes n'engendrent donc pas deux fiches pour la même année). À appeler AVANT le premier rendu : insérer pendant un rendu déclencherait les écouteurs en pleine construction.
void amorcerExercices(Magasin m, DateTime auj) {
  final col = m.collection('exercices');
  // Q29 (16/11/2026) : l'exercice SUIVANT s'ouvre d'avance à partir du mois réglé (décembre par défaut, réglable).
  final fiches = cpcExercicesAAmorcer(col.toutes, m.collection('ecritures').toutes, auj, moisOuvertureSuivant: moisOuvertureSuivantDe(m));
  for (final f in fiches) {
    col.inserer(f);
  }
  // La table PARAMÉTRABLE des comptes de résultat (131 bénéfice, 139 perte) : amorcée une fois, modifiable ensuite.
  final cr = m.collection('comptesResultat');
  if (cr.toutes.isEmpty) {
    for (final f in cpcComptesResultatDefaut) {
      cr.inserer({...f});
    }
  }
}


/// Le mois (1 à 12) à partir duquel l'exercice suivant s'ouvre d'avance : le RÉGLAGE DE CLINIQUE `exerciceOuvertureSuivantMois` ; décembre (`cpcMoisOuvertureSuivantDefaut`, la valeur de départ décidée par la
/// Direction) tant que personne ne l'a changé. Rien n'est écrit à la lecture : insérer pendant un rendu déclencherait les écouteurs en pleine construction ; la fiche naît au premier changement.
int moisOuvertureSuivantDe(Magasin m) => cpcMoisOuvertureSuivant(m.collection('reglages').parId(cpcCleMoisOuvertureSuivant)?['valeur']);
