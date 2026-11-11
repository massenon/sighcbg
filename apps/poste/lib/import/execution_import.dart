import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import '../shell/contexte_ecran.dart';
import 'droits_import.dart';
import 'fichier_import.dart';
import 'port_magasin.dart';
import 'selecteurs_import.dart';

/// Les gestes du module d'importation, UNE fois pour tous ses habillages (la page d'un jeu du module IMP, la fenêtre en trois étapes posée sur les écrans
/// métier) : les règles ne vivent pas dans une présentation.

PortMagasin portImport(ContexteEcran c) => PortMagasin(c.magasin, aujourdhui: () => c.aujourdhui, nomAgent: c.agent.nom);

/// Les choix de l'agent pour une analyse : « ignorer les existants » (ignoré tel quel sur un jeu qui ne l'autorise pas : le moteur refuse alors en le disant)
/// et les colonnes réservées que sa matrice lui accorde.
OptionsImport optionsImport(ContexteEcran c, JeuImport j, {bool ignorerExistants = false}) =>
    OptionsImport(ignorerExistants: ignorerExistants, colonnesAccordees: DroitsImport(c).colonnesAccordees(j));

/// Analyse COMPLÈTE d'un fichier choisi, sans rien écrire (hors la consignation d'un fichier REFUSÉ, qui est une trace et non une donnée métier). La borne de
/// taille du jeu est vérifiée avant toute lecture.
({AnalyseImport analyse, Fiche? lotRefuse}) verifierFichier(ContexteEcran c, JeuImport j, FichierChoisi f, {bool ignorerExistants = false}) {
  final port = portImport(c);
  final lu = lireFichierImport(f);
  final a = analyserFichier(j, lu.lignes, f.nom, port,
      motifIllisible: lu.motif,
      empreinte: importCrc32(f.octets),
      options: optionsImport(c, j, ignorerExistants: ignorerExistants),
      octets: f.octets.length,
      octetsMax: octetsMaxDe(c.magasin, j));
  return (analyse: a, lotRefuse: a.accepte ? null : consigner(j, a, port));
}
