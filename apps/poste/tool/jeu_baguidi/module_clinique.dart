// SOUS-LOT « CLINIQUE M1 À M5 » : patients, consultations, dossiers, analyses, imagerie, hospitalisation et bloc, maternité, banque de sang, et la
// facturation de tout cela par les MOTEURS de `packages/domaine` (émission, encaissement, avoir, prise en charge RG-09, prescription).
//
// Le déroulé est chronologique (une file triée par date : les numéros de pièce suivent les jours). Chaque étape de planification tire dans le flux
// `clinique` de la graine fixe, dans un ordre fixe : mêmes entrées, mêmes octets. Rien n'est écrit à la main là où un moteur existe. Détail des volumes :
// voir `tool/README.md` et le rapport de génération (`ctx.notes`).
//
// Ce qui reste VOLONTAIREMENT vide (aucun écran de M1 à M5 n'a besoin de ces collections pour fonctionner, ou leur contenu relève d'un autre sous-lot) :
//  - `rendezvous`, `visites`, `antecedents`, `lits`, `chambres` : l'agenda lit `consultations`, les antécédents vivent sur le patient, le plan des lits est
//    une constante du domaine ;
//  - `couverturesAssurance` : aucun assuré n'a changé de compagnie dans la fenêtre (la fiche du dossier fait foi, RG-09 se lit à la date) ;
//  - `documentsPatient`, `clichesImagerie` : aucun fichier n'est livré avec le jeu (pas de PDF ni de cliché fictif) ;
//  - `dispensations`, `produits` : les ventes de pharmacie relèvent du sous-lot stock ; AUCUN médicament dans les factures de ce sous-lot.
import 'clinique_base.dart';
import 'clinique_hospi.dart';
import 'clinique_labo.dart';
import 'clinique_mater.dart';
import 'clinique_meres.dart';
import 'clinique_patients.dart';
import 'clinique_sang.dart';
import 'clinique_soins.dart';
import 'contexte.dart';

void generer(Contexte ctx) {
  final j = Jeu(ctx);
  poserGaranties(j);
  final pats = creerPatients(j);
  final exclus = <String>{};
  final nomsPris = {
    for (final p in ctx.fiches('patients')) '${p['nom']} ${p['prenom']}',
  };

  // La planification : l'ordre des appels est celui des tirages (ne pas le changer sans régénérer le jeu).
  final cesar = planifierMaternite(j, pats, exclus);
  planifierHospitalisation(j, pats, exclus);
  planifierBloc(j, pats, exclus, cesar);
  planifierSang(j, pats, exclus, nomsPris);
  final passages = planifierPassages(j, pats);
  for (final p in passages) {
    j.planifier(p.quand, () => executerPassage(j, p));
  }

  planifierMeres(j);

  j.derouler();

  // Après la caisse : le circuit du laboratoire et de l'imagerie, puis la clôture des dossiers dont tout est rendu.
  finaliserAnalyses(j);
  finaliserImagerie(j);
  cloturerDossiersRendus(j);

  // Les actes réalisés par chaque vacataire (M10) se lisent sur les consultations qu'il a tenues.
  final consultations = ctx.fiches('consultations');
  for (final pr in ctx.fiches('prestataires')) {
    final n = consultations.where((c) => c['medecin'] == pr['nom']).length;
    if (n > 0) j.maj('prestataires', pr['id'], {'actesRealises': n});
  }

  ctx.note('clinique : ${ctx.fiches('consultations').length} consultations, ${ctx.fiches('factures').length} factures, '
      '${ctx.fiches('demandesAnalyses').length} demandes d\'analyses, ${ctx.fiches('demandesImagerie').length} demandes d\'imagerie, '
      '${ctx.fiches('ecritures').length} lignes d\'écriture');
}
